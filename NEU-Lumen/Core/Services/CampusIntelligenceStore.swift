import Foundation
import Observation

/// One generation at a time; no model output or source text is persisted.
@MainActor @Observable
final class CampusIntelligenceStore {
    struct Digest: Equatable {
        let identity: String
        let text: String
        let caption: String
    }
    var preferences: CampusIntelligencePreferences {
        didSet {
            guard preferences != oldValue else { return }
            if let data = try? JSONEncoder().encode(preferences) { defaults.set(data, forKey: Self.preferenceKey) }
            if !preferences.enabled { reset() }
            else { for feature in CampusIntelligenceFeature.allCases where !preferences.allows(feature) { clear(feature) } }
        }
    }
    private(set) var digests: [CampusIntelligenceFeature: Digest] = [:]
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let availability: () -> Bool
    @ObservationIgnored private let generate: @Sendable (CampusIntelligenceInput) async throws -> String
    @ObservationIgnored private var pending: [CampusIntelligenceFeature: CampusIntelligenceInput] = [:]
    @ObservationIgnored private var requested: [CampusIntelligenceFeature: String] = [:]
    @ObservationIgnored private var worker: Task<Void, Never>?
    private var generation = UUID()
    private static let preferenceKey = "lumen.intelligence.preferences.v1"

    init(defaults: UserDefaults = .standard, availability: @escaping () -> Bool = { AppleIntelligenceProvider.available },
         generate: @escaping @Sendable (CampusIntelligenceInput) async throws -> String = { try await AppleIntelligenceProvider.summarize($0) }) {
        self.defaults = defaults; self.availability = availability; self.generate = generate
        preferences = defaults.data(forKey: Self.preferenceKey).flatMap { try? JSONDecoder().decode(CampusIntelligencePreferences.self, from: $0) } ?? .init()
    }
    var available: Bool { availability() }
    func canUse(_ feature: CampusIntelligenceFeature) -> Bool { available && preferences.allows(feature) }
    func digest(for feature: CampusIntelligenceFeature) -> Digest? { canUse(feature) ? digests[feature] : nil }

    func reset() {
        generation = UUID(); worker?.cancel(); worker = nil
        pending.removeAll(); requested.removeAll(); digests = [:]
    }
    func cancelPending() {
        generation = UUID(); worker?.cancel(); worker = nil; pending.removeAll()
        requested = digests.mapValues(\.identity)
    }
    func clear(_ feature: CampusIntelligenceFeature) {
        pending[feature] = nil; requested[feature] = nil; digests[feature] = nil
    }
    func request(_ input: CampusIntelligenceInput?, for feature: CampusIntelligenceFeature) {
        guard let input, input.feature == feature, canUse(feature), !input.payload.isEmpty else { clear(feature); return }
        guard requested[feature] != input.identity else { return }
        requested[feature] = input.identity
        digests[feature] = nil
        pending[feature] = input
        guard worker == nil else { return }
        let epoch = generation
        worker = Task { [weak self] in
            guard let self else { return }
            defer { if self.generation == epoch { self.worker = nil } }
            while let feature = CampusIntelligenceFeature.allCases.first(where: { self.pending[$0] != nil }) {
                guard self.generation == epoch, !Task.isCancelled else { return }
                guard let input = self.pending.removeValue(forKey: feature), self.canUse(feature) else { continue }
                do {
                    let text = try await self.generate(input)
                    guard self.generation == epoch, !Task.isCancelled, self.canUse(feature), self.requested[feature] == input.identity else { continue }
                    guard !text.isEmpty, text.count <= 600 else { self.requested[feature] = nil; continue }
                    self.digests[feature] = Digest(identity: input.identity, text: text, caption: input.caption)
                } catch {
                    // Keep ordinary services available. A later refresh can retry this input.
                    if self.generation == epoch, self.requested[feature] == input.identity { self.requested[feature] = nil }
                }
            }
        }
    }
}

import Foundation
import Observation

/// A single ordered collection powers both Home and Services. Empty is intentional.
@MainActor @Observable
final class ServiceFavorites {
    private(set) var ids: [String] = []
    private var key: String?
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    func activate(account: String, apps: [PortalApp]) {
        key = account.isEmpty ? nil : "lumen.favorites." + account
        if let key, let saved = defaults.stringArray(forKey: key) {
            ids = saved.reduce(into: []) { if !$0.contains($1) { $0.append($1) } }
        } else {
            ids = Array(apps.prefix(8)).map(\.id)
        }
    }

    func apps(in catalog: [PortalApp]) -> [PortalApp] {
        ids.compactMap { id in catalog.first { $0.id == id } }
    }

    func contains(_ app: PortalApp) -> Bool { ids.contains(app.id) }

    func toggle(_ app: PortalApp) {
        if contains(app) { ids.removeAll { $0 == app.id } } else { ids.append(app.id) }
        persist()
    }

    func move(from offsets: IndexSet, to destination: Int) {
        let moving = offsets.sorted().map { ids[$0] }
        let target = destination - offsets.filter { $0 < destination }.count
        for index in offsets.sorted().reversed() { ids.remove(at: index) }
        ids.insert(contentsOf: moving, at: target)
        persist()
    }

    func remove(id: String) { ids.removeAll { $0 == id }; persist() }

    func reset(apps: [PortalApp]) { ids = Array(apps.prefix(8)).map(\.id); persist() }
    private func persist() { if let key { defaults.set(ids, forKey: key) } }
}

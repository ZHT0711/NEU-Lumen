import Foundation
#if canImport(WebKit)
import WebKit
#endif

/// Opaque WebKit profiles isolate both cookies and origin storage by campus account/platform.
/// Retiring the identifier first prevents a slow, still-open browser from restoring a logged-out profile.
@MainActor
struct LearningBrowserProfiles {
    let defaults: UserDefaults
    private let profilesKey = "lumen.learning.browserProfiles.v1"
    private let retiredKey = "lumen.learning.retiredBrowserProfiles.v1"

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    func identifier(account: String, platform: LearningPlatform) -> UUID? {
        guard !account.isEmpty, platform != .cg else { return nil }
        return identifier(account: account, key: platform.rawValue)
    }

    func identifier(account: String, service: NativeCampusService) -> UUID? {
        guard !account.isEmpty else { return nil }
        return identifier(account: account, key: "service." + service.rawValue)
    }

    private func identifier(account: String, key: String) -> UUID {
        var profiles = defaults.dictionary(forKey: profilesKey) as? [String: [String: String]] ?? [:]
        if let raw = profiles[account]?[key], let id = UUID(uuidString: raw) { return id }
        let id = UUID()
        profiles[account, default: [:]][key] = id.uuidString
        defaults.set(profiles, forKey: profilesKey)
        return id
    }

    func retire(account: String) {
        var profiles = defaults.dictionary(forKey: profilesKey) as? [String: [String: String]] ?? [:]
        let old = profiles.removeValue(forKey: account)?.values.map { $0 } ?? []
        defaults.set(profiles, forKey: profilesKey)
        defaults.set(Array(Set((defaults.stringArray(forKey: retiredKey) ?? []) + old)), forKey: retiredKey)
    }

    #if canImport(WebKit)
    @available(iOS 17.0, macOS 14.0, *)
    func cleanRetiredStores() async {
        for raw in defaults.stringArray(forKey: retiredKey) ?? [] {
            guard let id = UUID(uuidString: raw) else { continue }
            // Clear credentials even if an old WKWebView still owns this profile.
            await WKWebsiteDataStore(forIdentifier: id).removeData(
                ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: .distantPast)
            do {
                try await WKWebsiteDataStore.remove(forIdentifier: id)
                defaults.set((defaults.stringArray(forKey: retiredKey) ?? []).filter { $0 != raw }, forKey: retiredKey)
            } catch {
                // A live WKWebView can delay removal; retry on the next browser start.
            }
        }
    }
    #endif
}

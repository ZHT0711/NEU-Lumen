import Foundation
import Observation

@MainActor @Observable
final class SavedCampusNews {
    private(set) var items: [NewsItem] = []
    private let defaults: UserDefaults
    private var key: String?

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    func bind(account: String?) {
        let next = account.flatMap { $0.isEmpty ? nil : "lumen.news.saved.v1." + $0 }
        guard key != next else { return }
        key = next
        items = []
        guard let next, let data = defaults.data(forKey: next),
              let restored = try? JSONDecoder().decode([NewsItem].self, from: data) else { return }
        var seen = Set<String>()
        items = Array(restored.filter { seen.insert($0.id).inserted }.prefix(200))
    }

    func contains(_ item: NewsItem) -> Bool { items.contains { $0.id == item.id } }

    func toggle(_ item: NewsItem) {
        guard let key, let url = URL(string: item.url), ["http", "https"].contains(url.scheme ?? ""),
              url.user == nil, url.password == nil else { return }
        var next = items.filter { $0.id != item.id }
        if !contains(item) { next.insert(item, at: 0) }
        next = Array(next.prefix(200))
        guard let data = try? JSONEncoder().encode(next) else { return }
        defaults.set(data, forKey: key)
        items = next
    }
}

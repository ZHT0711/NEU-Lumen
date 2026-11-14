import Foundation

struct TodoItem { let id: String }
struct NetworkError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
    static func isCancellation(_ error: Error) -> Bool { error is CancellationError }
    static func from(_ error: Error) -> Self { Self(message: error.localizedDescription) }
}
@MainActor final class AffairsClient {
    var requests: [Int] = []
    var failPage: Int?
    var afterRead: (() -> Void)?
    var revision = 0
    func fetchTodos(page: Int, pageSize: Int) async throws -> [TodoItem] {
        requests.append(page)
        if page == failPage { failPage = nil; throw NetworkError(message: "interrupted") }
        let callback = afterRead; afterRead = nil; callback?()
        return (0..<pageSize).map { TodoItem(id: "\(revision)|\(page)|\($0)") }
    }
}
@MainActor final class SessionStore {
    enum Phase { case loggedIn, loggedOut }
    var phase: Phase = .loggedIn
    var requestEpoch = UUID()
    let client = AffairsClient()
    func persistWebSession() {}
}
@main struct AffairsTests {
    @MainActor static func main() async {
        let session = SessionStore(), store = NativeAffairsStore()
        await store.load(session: session, reset: true)
        await store.load(session: session, reset: false)
        precondition(store.items.count == 40 && session.client.requests == [1, 2])
        let original = store.items.map(\.id), updated = store.updatedAt
        session.client.revision = 1
        session.client.failPage = 2
        await store.load(session: session, reset: true)
        precondition(store.items.map(\.id) == original && store.updatedAt == updated && store.error != nil)
        await store.retry(session: session)
        precondition(store.items.count == 40 && store.items.allSatisfy { $0.id.hasPrefix("1|") })
        precondition(Array(session.client.requests.suffix(2)) == [1, 2] && store.error == nil)
        session.client.failPage = 3
        await store.load(session: session, reset: false)
        precondition(store.items.count == 40 && session.client.requests.last == 3)
        await store.retry(session: session)
        precondition(store.items.count == 60 && session.client.requests.last == 3)
        // Leaving and returning to the service does not reset the bound list.
        store.bind(to: session.requestEpoch)
        precondition(store.loaded && store.items.count == 60)
        session.client.afterRead = { session.requestEpoch = UUID() }
        await store.load(session: session, reset: true)
        precondition(store.items.count == 60, "a late result from the former identity is discarded")
        store.bind(to: session.requestEpoch)
        precondition(store.items.isEmpty && !store.loaded && store.updatedAt == nil)
        print("Native affairs: atomic multi-page refresh, exact retry page, same-account return and epoch isolation passed")
    }
}

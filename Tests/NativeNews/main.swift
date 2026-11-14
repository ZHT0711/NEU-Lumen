import Foundation

struct NewsChannel {
    let id: String
    let name: String
}

struct NewsItem {
    let id: String
}

struct NetworkError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

@MainActor
final class NewsClient {
    struct Request {
        let page: Int
        let channel: String
        let keyword: String
    }
    var requests: [Request] = []
    var failNext = false
    var afterFetch: (() -> Void)?

    func fetchNewsChannels() async throws -> [NewsChannel] {
        [NewsChannel(id: "news", name: "东大要闻"), NewsChannel(id: "campus", name: "校园生活")]
    }

    func fetchNews(pageSize: Int, channel: NewsChannel, page: Int, keyword: String) async throws -> [NewsItem] {
        requests.append(Request(page: page, channel: channel.id, keyword: keyword))
        if failNext { failNext = false; throw NetworkError(message: "连接中断") }
        let callback = afterFetch
        afterFetch = nil
        callback?()
        return (0..<pageSize).map { NewsItem(id: "\(channel.id)|\(keyword)|\(page)|\($0)") }
    }
}

@MainActor
final class SessionStore {
    enum Phase { case loggedIn, loggedOut }
    var phase: Phase = .loggedIn
    var requestEpoch = UUID()
    let client = NewsClient()
}

@main
struct NativeNewsTests {
    @MainActor
    static func main() async {
        let session = SessionStore()
        let store = NativeNewsStore()
        precondition(store.bind(to: session.requestEpoch))
        store.keyword = "校园"
        await store.load(session: session, reset: true)
        precondition(store.items.count == 30 && store.hasMore && store.hasLoaded)
        precondition(!store.bind(to: session.requestEpoch))
        precondition(store.keyword == "校园" && store.channelID == "news" && store.items.count == 30)
        await store.load(session: session, reset: false)
        precondition(store.items.count == 60 && session.client.requests.last?.page == 2)

        // A failed first-page refresh preserves the complete previous list and retries page one.
        let previousIDs = store.items.map(\.id)
        session.client.failNext = true
        await store.load(session: session, reset: true)
        precondition(store.items.map(\.id) == previousIDs && store.error != nil && store.hasMore)
        await store.retry(session: session)
        precondition(session.client.requests.last?.page == 1 && store.items.count == 30 && store.error == nil)

        // A failed next page retries that same page, without skipping or duplicating its rows.
        session.client.failNext = true
        await store.load(session: session, reset: false)
        precondition(store.items.count == 30 && session.client.requests.last?.page == 2)
        await store.retry(session: session)
        precondition(session.client.requests.last?.page == 2 && store.items.count == 60)
        precondition(Set(store.items.map(\.id)).count == 60)

        // Changed search criteria do not leave unrelated previous matches under the new filter.
        store.keyword = "图书馆"
        session.client.failNext = true
        await store.load(session: session, reset: true)
        precondition(store.items.isEmpty && !store.hasLoaded && store.error != nil)
        await store.retry(session: session)
        precondition(session.client.requests.last?.keyword == "图书馆" && store.items.count == 30)
        store.channelID = "campus"
        await store.load(session: session, reset: true)
        precondition(session.client.requests.last?.channel == "campus" && session.client.requests.last?.page == 1)
        precondition(store.items.allSatisfy { $0.id.hasPrefix("campus|") })

        // An account change drops the old response, and binding the new owner clears all old state.
        let beforeSwitch = store.items.map(\.id)
        session.client.afterFetch = { session.requestEpoch = UUID() }
        await store.load(session: session, reset: false)
        precondition(store.items.map(\.id) == beforeSwitch)
        precondition(store.bind(to: session.requestEpoch))
        precondition(store.items.isEmpty && store.channels.isEmpty && store.keyword.isEmpty && store.channelID.isEmpty)
        precondition(!store.hasLoaded && !store.busy && !store.hasMore && store.error == nil)
        print("Native news: retained searches, atomic refresh, exact failed-page retries and account isolation passed")
    }
}

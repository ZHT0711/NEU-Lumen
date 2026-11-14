import Foundation

struct NetworkError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
    static func isCancellation(_ error: Error) -> Bool { error is CancellationError }
    static func from(_ error: Error) -> Self { .init(message: error.localizedDescription) }
}

@MainActor
final class CampusReminderStore {
    static let shared = CampusReminderStore()
    func recordMail(account: String, messages: [NativeMailMessage], unread: Int?) async {}
}

@MainActor
final class MailTransaction {
    var current = true
    var busy = false
    var loadingWeb = false
    var hasMore = false
    var currentOperation: UUID?
    var subjectSearch = ""
    var advancedSearch = NativeMailSearch()
    var listedSearch = NativeMailSearch()
    var listedFolder = ""
    var loaded = false
    var folderID = "1"
    var nextStart = 0
    var messages: [NativeMailMessage] = []
    var folders: [NativeMailFolder] = []
    var error: String?
    var lastRefresh: Date?
    var ownerAccount = "SYNTH-A"
    var hasSearch: Bool { !advancedSearch.parameters.isEmpty || !subjectSearch.isEmpty }
    var total = 80
    var failedStart: Int?
    var starts: [Int] = []
    var onResponse: (() -> Void)?

    func execute(command: String, start: Int, includeFolders: Bool) async throws -> [String: Any] {
        starts.append(start)
        if failedStart == start { throw NetworkError(message: "合成连接中断") }
        let end = min(start + 20, total)
        let rows: [[String: Any]] = (start..<max(start, end)).map {
            ["id": "\(folderID)|\(subjectSearch)|\($0)", "subject": "合成邮件\($0)", "sender": "fixture@example.invalid"]
        }
        onResponse?()
        return ["messages": rows, "folderID": folderID, "nextStart": end, "hasMore": end < total,
                "folders": includeFolders ? [["id": folderID, "name": "合成文件夹", "total": total]] : []]
    }
    func persist() async {}

    // ACTUAL_REFRESH_METHOD
}

@main
struct NativeMailTests {
    @MainActor
    static func main() async {
        let store = MailTransaction()
        await store.refresh()
        await store.refresh(reset: false)
        await store.refresh(reset: false)
        precondition(store.messages.count == 60 && store.nextStart == 60 && store.hasMore)
        let original = store.messages
        await store.refresh()
        precondition(store.messages == original && store.nextStart == 60)
        precondition(Array(store.starts.suffix(3)) == [0, 20, 40], "refresh retains the whole loaded window")

        store.failedStart = 20
        await store.refresh()
        precondition(store.messages == original && store.nextStart == 60 && store.error != nil)
        store.failedStart = nil
        await store.refresh()
        precondition(store.messages == original && store.error == nil)

        store.failedStart = 0
        await store.refresh(advanced: NativeMailSearch(subject: "  课程通知  ", from: "  teacher@example.invalid  "))
        precondition(store.messages.isEmpty && !store.loaded && store.nextStart == 0 && store.error != nil)
        precondition(store.advancedSearch.subject == "课程通知" && store.advancedSearch.from == "teacher@example.invalid")
        store.failedStart = nil
        await store.refresh()
        precondition(store.messages.count == 20 && store.messages.allSatisfy { $0.id.contains("|课程通知|") })

        store.failedStart = 20
        await store.refresh(reset: false)
        precondition(store.messages.count == 20 && store.nextStart == 20)
        store.failedStart = nil
        await store.refresh(reset: false)
        precondition(store.messages.count == 40 && store.nextStart == 40 && store.error == nil)
        precondition(Set(store.messages.map(\.id)).count == 40)

        store.folderID = "7"
        await store.refresh()
        precondition(store.messages.count == 20 && store.messages.allSatisfy { $0.id.hasPrefix("7|") })
        store.total = 0
        await store.refresh(advanced: NativeMailSearch(subject: "没有结果"))
        precondition(store.messages.isEmpty && store.loaded && !store.hasMore && store.error == nil)

        store.total = 80
        store.onResponse = { store.current = false }
        await store.refresh(advanced: NativeMailSearch(subject: "旧账号迟到结果"))
        precondition(store.messages.isEmpty && !store.loaded, "changed owner never accepts a late list")
        print("Native mail: loaded-window refresh, atomic failed-page rollback, search normalization, exact pagination retries and owner isolation passed")
    }
}

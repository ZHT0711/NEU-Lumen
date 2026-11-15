import Foundation

struct SystemAgendaItem: Identifiable, Sendable {
    let id: String
    let title: String
    let date: Date
    let end: Date?
    let allDay: Bool
    let location: String
    let source: String
    let isReminder: Bool
    var eventID: String? = nil
}

struct SystemAgendaQuery: Hashable, Sendable {
    let account: String
    let start: Date
    let end: Date
    let events: Set<String>
    let reminders: Set<String>
    let excluded: Set<String>
    let timeZone: String
}

struct SystemAgendaReadResult: Sendable {
    var items: [SystemAgendaItem] = []
    var message: String?
}

/// Short-lived read cache. Account/selection changes invalidate both cached and in-flight results.
@MainActor
final class SystemAgendaLoader {
    typealias Reader = @Sendable (SystemAgendaQuery) async -> SystemAgendaReadResult
    private struct Entry {
        let result: SystemAgendaReadResult
        let date: Date
    }
    private struct Pending {
        let id = UUID()
        let task: Task<SystemAgendaReadResult, Never>
    }
    private let reader: Reader
    private let now: () -> Date
    private var saved: [SystemAgendaQuery: Entry] = [:]
    private var pending: [SystemAgendaQuery: Pending] = [:]
    private var generation = 0

    init(now: @escaping () -> Date = Date.init, reader: @escaping Reader) {
        self.now = now
        self.reader = reader
    }

    func invalidate() {
        generation &+= 1
        saved.removeAll()
        pending.values.forEach { $0.task.cancel() }
        pending.removeAll()
    }

    func load(_ query: SystemAgendaQuery, force: Bool = false) async -> SystemAgendaReadResult? {
        if !force, let entry = saved[query], now().timeIntervalSince(entry.date) < 60 { return entry.result }
        let epoch = generation
        let request: Pending
        if let existing = pending[query] { request = existing }
        else {
            let read = reader
            request = Pending(task: Task { await read(query) })
            pending[query] = request
        }
        let result = await request.task.value
        guard epoch == generation else { return nil }
        guard pending[query]?.id == request.id else { return result }
        pending[query] = nil
        // A failed read should be retried on the next visit.
        if result.message == nil {
            saved[query] = Entry(result: result, date: now())
            if saved.count > 8, let oldest = saved.min(by: { $0.value.date < $1.value.date })?.key {
                saved[oldest] = nil
            }
        }
        return result
    }
}

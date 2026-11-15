import Foundation
import EventKit
import CryptoKit
import Observation

/// Explicit week sync, scoped to our dedicated calendars and account marker.
/// Reading the system never changes the academic portal's source of truth.
@MainActor @Observable
final class SystemCalendarBridge {
    @ObservationIgnored let store = EKEventStore()
    private(set) var agenda: [SystemAgendaItem] = []
    private(set) var busy = false
    private(set) var message: String?
    private(set) var updatedAt: Date?
    private(set) var accountKey = ""
    var eventCalendarIDs: Set<String> = [] { didSet { if eventCalendarIDs != oldValue { invalidateAgenda() }; saveSelections() } }
    var reminderCalendarIDs: Set<String> = [] { didSet { if reminderCalendarIDs != oldValue { invalidateAgenda() }; saveSelections() } }
    private let defaults = UserDefaults.standard
    private var refreshID = UUID()
    @ObservationIgnored private var cachedExportIDs: Set<String>?
    @ObservationIgnored private let loader = SystemAgendaLoader { await SystemAgendaReader.read($0) }

    var eventsAllowed: Bool { EKEventStore.authorizationStatus(for: .event) == .fullAccess }
    var remindersAllowed: Bool { EKEventStore.authorizationStatus(for: .reminder) == .fullAccess }
    var eventCalendars: [EKCalendar] { availableCalendars(for: .event, allowed: eventsAllowed) }
    var reminderCalendars: [EKCalendar] { availableCalendars(for: .reminder, allowed: remindersAllowed) }

    func activate(account: String) {
        invalidateAgenda()
        accountKey = account.isEmpty ? "" : SHA256.hash(data: Data(account.utf8)).map { String(format: "%02x", $0) }.joined()
        let savedEvents = Set(defaults.stringArray(forKey: selectionKey("events")) ?? [])
        let savedReminders = Set(defaults.stringArray(forKey: selectionKey("reminders")) ?? [])
        eventCalendarIDs = savedEvents
        reminderCalendarIDs = savedReminders
        agenda = []
        updatedAt = nil
        message = nil
    }

    func requestAccess(events: Bool) async {
        do {
            let granted: Bool
            if events { granted = try await store.requestFullAccessToEvents() }
            else { granted = try await store.requestFullAccessToReminders() }
            message = granted ? "已连接，请选择要显示的日历或清单" : "未获授权，可在系统设置中开启访问权限"
        } catch { message = error.localizedDescription }
    }

    func invalidateAgenda() {
        refreshID = UUID()
        cachedExportIDs = nil
        loader.invalidate()
    }

    func refresh(start: Date, end: Date, force: Bool = false) async {
        let account = accountKey
        let requestID = UUID()
        refreshID = requestID
        let query = SystemAgendaQuery(account: account, start: start, end: end,
            events: eventsAllowed ? eventCalendarIDs : [], reminders: remindersAllowed ? reminderCalendarIDs : [],
            excluded: eventCalendarIDs.isEmpty && reminderCalendarIDs.isEmpty ? [] : exportCalendarIDs,
            timeZone: TimeZone.current.identifier)
        guard let result = await loader.load(query, force: force),
              account == accountKey, requestID == refreshID, !Task.isCancelled else { return }
        agenda = result.items
        message = result.message
        updatedAt = Date()
    }

    func event(for item: SystemAgendaItem) -> EKEvent? {
        guard eventsAllowed, let id = item.eventID else { return nil }
        let calendars = eventCalendars.filter { eventCalendarIDs.contains($0.calendarIdentifier) }
        guard !calendars.isEmpty else { return nil }
        let predicate = store.predicateForEvents(withStart: item.date.addingTimeInterval(-1),
            end: (item.end ?? item.date).addingTimeInterval(1), calendars: calendars)
        return store.events(matching: predicate).first { $0.eventIdentifier == id && $0.startDate == item.date }
    }

    func completeReminder(id: String) {
        guard remindersAllowed, let reminder = store.calendarItem(withIdentifier: id) as? EKReminder,
              !isOwned(reminder) else { return }
        do {
            reminder.isCompleted = true
            try store.save(reminder, commit: true)
            invalidateAgenda()
            agenda.removeAll { $0.id == id }
        } catch { message = error.localizedDescription }
    }

    /// Repeated sync updates by marker and removes only stale entries owned by us in this week.
    func sync(_ occurrences: [CourseOccurrence], start: Date, end: Date, events: Bool, reminders: Bool, alarmMinutes: Int) async {
        guard !busy, !accountKey.isEmpty else { return }
        guard events || reminders else { message = "请选择日历或提醒事项"; return }
        busy = true
        defer { busy = false; invalidateAgenda() }
        do {
            if events && !eventsAllowed { throw BridgeError.permission("日历") }
            if reminders && !remindersAllowed { throw BridgeError.permission("提醒事项") }
            let courses = occurrences.filter { $0.date >= start && $0.date < end }
            let desired = Set(courses.map { marker(for: $0).absoluteString })
            if events {
                let calendar = try exportCalendar(for: .event)
                let existing = store.events(matching: store.predicateForEvents(withStart: start, end: end, calendars: [calendar]))
                    .filter { isCurrentAccountItem($0) }
                for occurrence in courses {
                    let marker = marker(for: occurrence)
                    let event = existing.first { $0.url == marker } ?? EKEvent(eventStore: store)
                    event.calendar = calendar
                    event.url = marker
                    event.title = occurrence.slot.name
                    event.location = occurrence.slot.room
                    event.startDate = time(occurrence.date, minutes: occurrence.slot.startMinutes)
                    event.endDate = time(occurrence.date, minutes: occurrence.slot.endMinutes)
                    event.timeZone = Calendar.current.timeZone
                    event.notes = "由 NEU-Lumen 同步。学校调课后请重新同步此周。"
                    event.alarms = alarmMinutes < 0 ? [] : [EKAlarm(relativeOffset: -Double(alarmMinutes * 60))]
                    try store.save(event, span: .thisEvent, commit: false)
                }
                for event in existing where !desired.contains(event.url?.absoluteString ?? "") {
                    try store.remove(event, span: .thisEvent, commit: false)
                }
                try store.commit()
            }
            if reminders {
                let calendar = try exportCalendar(for: .reminder)
                let account = accountKey
                let existing = try await fetchReminders(in: [calendar]).filter { isCurrentAccountItem($0) }
                guard account == accountKey else { throw CancellationError() }
                for occurrence in courses {
                    let marker = marker(for: occurrence)
                    let reminder = existing.first { $0.url == marker } ?? EKReminder(eventStore: store)
                    reminder.calendar = calendar
                    reminder.url = marker
                    reminder.title = occurrence.slot.name
                    reminder.location = occurrence.slot.room
                    let date = time(occurrence.date, minutes: occurrence.slot.startMinutes)
                    reminder.dueDateComponents = Calendar.current.dateComponents([.calendar, .timeZone, .year, .month, .day, .hour, .minute], from: date)
                    reminder.notes = "由 NEU-Lumen 同步。完成状态在重复同步时保留。"
                    reminder.alarms = alarmMinutes < 0 ? [] : [EKAlarm(absoluteDate: date.addingTimeInterval(-Double(alarmMinutes * 60)))]
                    try store.save(reminder, commit: false)
                }
                for reminder in existing {
                    guard let components = reminder.dueDateComponents,
                          let date = components.date ?? Calendar.current.date(from: components),
                          date >= start && date < end, !desired.contains(reminder.url?.absoluteString ?? "") else { continue }
                    try store.remove(reminder, commit: false)
                }
                try store.commit()
            }
            message = "已同步 \(courses.count) 项；重复同步会更新本周内容。"
        } catch {
            store.reset()
            message = "同步未全部完成，可重试：" + error.localizedDescription
        }
    }

    private func fetchReminders(in calendars: [EKCalendar]) async throws -> [EKReminder] {
        try await withCheckedThrowingContinuation { continuation in
            store.fetchReminders(matching: store.predicateForReminders(in: calendars)) { reminders in
                if let reminders { continuation.resume(returning: reminders) }
                else { continuation.resume(throwing: BridgeError.read) }
            }
        }
    }

    private func marker(for occurrence: CourseOccurrence) -> URL {
        let hash = SHA256.hash(data: Data(occurrence.id.utf8)).map { String(format: "%02x", $0) }.joined()
        return URL(string: "lumen-course://\(accountKey)/\(hash)")!
    }

    private func isOwned(_ item: EKCalendarItem) -> Bool { item.url?.scheme == "lumen-course" }
    private func isCurrentAccountItem(_ item: EKCalendarItem) -> Bool { isOwned(item) && item.url?.host == accountKey }
    private func selectionKey(_ name: String) -> String { "lumen.system.\(accountKey).\(name)" }
    private func saveSelections() {
        guard !accountKey.isEmpty else { return }
        defaults.set(Array(eventCalendarIDs), forKey: selectionKey("events"))
        defaults.set(Array(reminderCalendarIDs), forKey: selectionKey("reminders"))
    }

    private var exportCalendarIDs: Set<String> {
        if let cachedExportIDs { return cachedExportIDs }
        let ids = Set(defaults.dictionaryRepresentation().filter { $0.key.hasPrefix("lumen.system.export.") }.values.compactMap { $0 as? String })
        cachedExportIDs = ids
        return ids
    }

    private func availableCalendars(for type: EKEntityType, allowed: Bool) -> [EKCalendar] {
        guard allowed else { return [] }
        let excluded = exportCalendarIDs
        return store.calendars(for: type).filter { !excluded.contains($0.calendarIdentifier) }
    }

    private func exportCalendar(for type: EKEntityType) throws -> EKCalendar {
        let key = "lumen.system.export.\(accountKey).\(type == .event ? "events" : "reminders")"
        if let id = defaults.string(forKey: key), let calendar = store.calendar(withIdentifier: id), calendar.allowsContentModifications { return calendar }
        let calendar = EKCalendar(for: type, eventStore: store)
        calendar.title = "NEU-Lumen 课表"
        let source = type == .event ? store.defaultCalendarForNewEvents?.source : store.defaultCalendarForNewReminders()?.source
        guard let source = source ?? store.sources.first(where: { $0.sourceType == .local }) else { throw BridgeError.source }
        calendar.source = source
        try store.saveCalendar(calendar, commit: true)
        defaults.set(calendar.calendarIdentifier, forKey: key)
        return calendar
    }

    private func time(_ date: Date, minutes: Int) -> Date {
        Calendar.current.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: date)!
    }

    private enum BridgeError: LocalizedError {
        case permission(String), source, read
        var errorDescription: String? {
            switch self {
            case .permission(let name): return "请先连接系统\(name)，允许完全访问"
            case .source: return "系统没有可写入的日历账户，请先在日历或提醒事项中添加账户"
            case .read: return "系统未返回提醒事项"
            }
        }
    }
}

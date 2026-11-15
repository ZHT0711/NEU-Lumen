import Foundation
import EventKit

enum SystemAgendaReader {
    /// Only value types cross the task boundary. Every EKObject belongs to this read's own store.
    static func read(_ query: SystemAgendaQuery) async -> SystemAgendaReadResult {
        guard !query.events.isEmpty || !query.reminders.isEmpty else { return SystemAgendaReadResult() }
        let task = Task.detached(priority: .userInitiated) {
            let store = EKEventStore()
            var result = SystemAgendaReadResult()
            let events = query.events.isEmpty ? [] : store.calendars(for: .event).filter {
                query.events.contains($0.calendarIdentifier) && !query.excluded.contains($0.calendarIdentifier)
            }
            if !events.isEmpty {
                let predicate = store.predicateForEvents(withStart: query.start, end: query.end, calendars: events)
                result.items = store.events(matching: predicate).compactMap { event in
                    guard event.url?.scheme != "lumen-course", let start = event.startDate else { return nil }
                    return SystemAgendaItem(id: "\(event.eventIdentifier ?? event.calendarItemIdentifier)|\(start.timeIntervalSince1970)",
                        title: event.title ?? "日历日程", date: start, end: event.endDate, allDay: event.isAllDay,
                        location: event.location ?? "", source: event.calendar.title, isReminder: false, eventID: event.eventIdentifier)
                }
            }
            guard !Task.isCancelled else { return result }
            let reminders = query.reminders.isEmpty ? [] : store.calendars(for: .reminder).filter {
                query.reminders.contains($0.calendarIdentifier) && !query.excluded.contains($0.calendarIdentifier)
            }
            if !reminders.isEmpty {
                let predicate = store.predicateForIncompleteReminders(withDueDateStarting: query.start, ending: query.end, calendars: reminders)
                let read: SystemAgendaReadResult = await withCheckedContinuation { continuation in
                    store.fetchReminders(matching: predicate) { [store] reminders in
                        // Keep the originating store alive until all reminder values have been copied.
                        _ = store
                        guard let reminders else {
                            continuation.resume(returning: SystemAgendaReadResult(message: "提醒事项读取失败，请稍后重试"))
                            return
                        }
                        let items = reminders.compactMap { reminder -> SystemAgendaItem? in
                            guard !reminder.isCompleted, reminder.url?.scheme != "lumen-course",
                                  let components = reminder.dueDateComponents,
                                  let date = components.date ?? Calendar.current.date(from: components),
                                  date >= query.start && date < query.end else { return nil }
                            return SystemAgendaItem(id: reminder.calendarItemIdentifier, title: reminder.title ?? "提醒事项",
                                date: date, end: nil, allDay: components.hour == nil, location: reminder.location ?? "",
                                source: reminder.calendar.title, isReminder: true)
                        }
                        continuation.resume(returning: SystemAgendaReadResult(items: items))
                    }
                }
                result.items += read.items
                result.message = read.message
            }
            result.items.sort { $0.date == $1.date ? $0.id < $1.id : $0.date < $1.date }
            return result
        }
        return await withTaskCancellationHandler(operation: { await task.value }, onCancel: { task.cancel() })
    }
}

import Foundation
import Observation

/// 本机自定义日程持久化（Application Support 下 JSON 文件，写入原子化）。
@MainActor
@Observable
final class PlannerEventStore {
    static let shared = PlannerEventStore()

    private(set) var revision = 0
    private(set) var events: [PlannerEvent] = [] { didSet { if events != oldValue { revision &+= 1 } } }

    private var fileURL: URL? {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("planner-events.json")
    }

    private init() {
        load()
    }

    func add(_ event: PlannerEvent) {
        events.append(event)
        persist()
    }

    func remove(id: String) {
        events.removeAll { $0.id == id }
        persist()
    }

    func restore(_ updated: [PlannerEvent]) throws {
        guard events != updated else { return }
        try write(updated)
        events = updated
    }

    /// 展开某一周（周日起 7 天）内的日程。
    func occurrences(inWeekStarting weekStart: Date) -> [CourseOccurrence] {
        let end = weekStart.addingTimeInterval(7 * 86400)
        return events.compactMap { event in
            guard let date = PortalDate.day(event.dateIso),
                  date >= weekStart && date < end else { return nil }
            return CourseOccurrence(date: date, slot: event.toSlot())
        }
    }

    func occurrences(onDay day: Date) -> [CourseOccurrence] {
        let cal = Calendar.current
        return events.compactMap { event in
            guard let date = PortalDate.day(event.dateIso),
                  cal.isDate(date, inSameDayAs: day) else { return nil }
            return CourseOccurrence(date: date, slot: event.toSlot())
        }
    }

    private func load() {
        guard let url = fileURL,
              let data = try? Data(contentsOf: url),
              let list = try? JSONDecoder().decode([PlannerEvent].self, from: data) else { return }
        events = list
    }

    private func persist() {
        // Preserve the existing best-effort write used by the in-app editor.
        try? write(events)
    }

    private func write(_ events: [PlannerEvent]) throws {
        guard let url = fileURL else { throw CocoaError(.fileNoSuchFile) }
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try JSONEncoder().encode(events)
        try data.write(to: url, options: .atomic)
    }
}

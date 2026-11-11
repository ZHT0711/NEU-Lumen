import Foundation

/// 一条课表事件（按周模板存放：weekday 1=周一 … 7=周日）。
struct CourseSlot: Hashable {
    var weekday: Int
    var startMinutes: Int
    var endMinutes: Int
    var name: String
    var room: String
    var teacher: String = ""
    /// kind: course=课程/考试 portal 事件, custom=自定义日程
    var kind: String = "course"
    /// 生效教学周范围（含两端）；0,0 表示不限。
    var weekStart: Int = 1
    var weekEnd: Int = 99
    /// kind=custom 时对应的本机日程 id。
    var eventID: String?

    func coversWeek(_ week: Int) -> Bool {
        weekStart == 0 || (week >= weekStart && week <= weekEnd)
    }

    var timeText: String {
        String(format: "%02d:%02d-%02d:%02d", startMinutes / 60, startMinutes % 60, endMinutes / 60, endMinutes % 60)
    }
}

/// 展开到具体某一天的事件。
struct CourseOccurrence: Identifiable, Hashable {
    let date: Date
    let slot: CourseSlot

    var id: String {
        "\(PortalDate.isoDay(date))|\(slot.startMinutes)|\(slot.endMinutes)|\(slot.teacher)|\(slot.name)|\(slot.room)|\(slot.kind)|\(slot.eventID ?? "")"
    }

    var isOngoing: Bool {
        let cal = Calendar.current
        guard cal.isDateInToday(date) else { return false }
        let minutes = cal.component(.hour, from: Date()) * 60 + cal.component(.minute, from: Date())
        return minutes >= slot.startMinutes && minutes < slot.endMinutes
    }
}

private struct CourseMergeKey: Hashable {
    let day: Date
    let name: String
    let room: String
    let teacher: String
    let kind: String
    let eventID: String?
}

extension Array where Element == CourseOccurrence {
    /// 先按日期和课程身份分组，再合并连续/重叠节次，避免整周课程互相打断。
    func mergeConsecutive() -> [CourseOccurrence] {
        func normalized(_ value: String) -> String {
            value.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.joined()
        }
        let calendar = Calendar.current
        let groups = Dictionary(grouping: self) { occurrence in
            CourseMergeKey(day: calendar.startOfDay(for: occurrence.date),
                name: normalized(occurrence.slot.name), room: normalized(occurrence.slot.room),
                teacher: normalized(occurrence.slot.teacher), kind: occurrence.slot.kind,
                eventID: occurrence.slot.kind == "custom" ? occurrence.slot.eventID : nil)
        }
        var result: [CourseOccurrence] = []
        for group in groups.values {
            var merged: [CourseOccurrence] = []
            for current in group.sorted(by: {
                $0.slot.startMinutes == $1.slot.startMinutes
                    ? $0.slot.endMinutes < $1.slot.endMinutes
                    : $0.slot.startMinutes < $1.slot.startMinutes
            }) {
                if let previous = merged.last,
                   current.slot.startMinutes <= previous.slot.endMinutes + 35 {
                    var slot = previous.slot
                    slot.endMinutes = Swift.max(slot.endMinutes, current.slot.endMinutes)
                    slot.weekStart = Swift.min(slot.weekStart, current.slot.weekStart)
                    slot.weekEnd = Swift.max(slot.weekEnd, current.slot.weekEnd)
                    merged[merged.count - 1] = CourseOccurrence(date: previous.date, slot: slot)
                } else {
                    merged.append(current)
                }
            }
            result.append(contentsOf: merged)
        }
        return result.sorted {
            let lhs = calendar.startOfDay(for: $0.date)
            let rhs = calendar.startOfDay(for: $1.date)
            if lhs != rhs { return lhs < rhs }
            if $0.slot.startMinutes != $1.slot.startMinutes { return $0.slot.startMinutes < $1.slot.startMinutes }
            return $0.id < $1.id
        }
    }
}

/// 同一事件只生成一个跨节次的块；冲突事件占独立列，均可点开。
struct TimetablePlacement: Identifiable {
    let occurrence: CourseOccurrence
    let firstPeriod: Int
    let lastPeriod: Int
    let lane: Int
    let laneCount: Int

    var id: String { occurrence.id }
    var periodCount: Int { lastPeriod - firstPeriod + 1 }

    static func layout(_ occurrences: [CourseOccurrence], on date: Date) -> [TimetablePlacement] {
        let calendar = Calendar.current
        // 合并按自然日分组；先筛选当天，避免七列各自重复合并整周。
        let daily = occurrences.filter { calendar.isDate($0.date, inSameDayAs: date) }.mergeConsecutive()
        var assigned: [(CourseOccurrence, Int, Int, Int)] = []
        var laneEnds: [Int] = []
        for occurrence in daily {
            let first = Semester.periodOf(startMinutes: occurrence.slot.startMinutes)
            let last = Swift.max(first, Semester.endPeriod(of: occurrence.slot.endMinutes))
            let lane = laneEnds.firstIndex { $0 < first } ?? laneEnds.count
            if lane == laneEnds.count { laneEnds.append(last) } else { laneEnds[lane] = last }
            assigned.append((occurrence, first, last, lane))
        }
        return assigned.map {
            TimetablePlacement(occurrence: $0.0, firstPeriod: $0.1, lastPeriod: $0.2,
                               lane: $0.3, laneCount: Swift.max(1, laneEnds.count))
        }
    }
}

/// 手动添加的日程（考试、事务、提醒…），落到具体某天，本机持久化。
struct PlannerEvent: Identifiable, Codable, Hashable {
    var id: String
    var name: String
    var dateIso: String
    var startMinutes: Int
    var endMinutes: Int
    var room: String
    var note: String
    var kind: String
    var deletable: Bool

    init(
        id: String = UUID().uuidString,
        name: String,
        dateIso: String,
        startMinutes: Int,
        endMinutes: Int,
        room: String = "",
        note: String = "",
        kind: String = "custom",
        deletable: Bool = true
    ) {
        self.id = id
        self.name = name
        self.dateIso = dateIso
        self.startMinutes = startMinutes
        self.endMinutes = endMinutes
        self.room = room
        self.note = note
        self.kind = kind
        self.deletable = deletable
    }

    /// 转成课表网格/时间轴可渲染的槽位。
    func toSlot() -> CourseSlot {
        let weekday = PortalDate.day(dateIso).map(Self.mondayBasedWeekday) ?? 1
        return CourseSlot(
            weekday: weekday,
            startMinutes: startMinutes,
            endMinutes: endMinutes,
            name: name,
            room: room.trimmingCharacters(in: .whitespaces).isEmpty ? "待定" : room.trimmingCharacters(in: .whitespaces),
            kind: kind,
            eventID: id
        )
    }

    static func mondayBasedWeekday(_ date: Date) -> Int {
        let swiftWeekday = Calendar.current.component(.weekday, from: date) // 1=周日
        return (swiftWeekday + 5) % 7 + 1 // 1=周一 … 7=周日
    }
}

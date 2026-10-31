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
        "\(PortalDate.isoDay(date))|\(slot.startMinutes)|\(slot.name)|\(slot.room)|\(slot.kind)|\(slot.eventID ?? "")"
    }

    var isOngoing: Bool {
        let cal = Calendar.current
        guard cal.isDateInToday(date) else { return false }
        let minutes = cal.component(.hour, from: Date()) * 60 + cal.component(.minute, from: Date())
        return minutes >= slot.startMinutes && minutes < slot.endMinutes
    }
}

extension Array where Element == CourseOccurrence {
    /// 合并同一天相邻且同名同地点的节次（如第 1 节与第 2 节合为 1-2 节），排序一次完成。
    func mergeConsecutive() -> [CourseOccurrence] {
        guard count > 1 else { return self }
        let sorted = sorted { $0.slot.startMinutes < $1.slot.startMinutes }
        var merged: [CourseOccurrence] = []
        for curr in sorted {
            guard let prev = merged.last else {
                merged.append(curr)
                continue
            }
            let cal = Calendar.current
            let sameDate = cal.isDate(prev.date, inSameDayAs: curr.date)
            let sameName = prev.slot.name.trimmingCharacters(in: .whitespaces) == curr.slot.name.trimmingCharacters(in: .whitespaces)
            let sameKind = prev.slot.kind == curr.slot.kind
            let sameRoom = prev.slot.room.trimmingCharacters(in: .whitespaces) == curr.slot.room.trimmingCharacters(in: .whitespaces)
            let gap = curr.slot.startMinutes - prev.slot.endMinutes
            if sameDate && sameName && sameKind && sameRoom && gap >= 0 && gap <= 35 {
                let combined = CourseSlot(
                    weekday: prev.slot.weekday,
                    startMinutes: prev.slot.startMinutes,
                    endMinutes: curr.slot.endMinutes,
                    name: prev.slot.name,
                    room: prev.slot.room,
                    teacher: prev.slot.teacher.isEmpty ? curr.slot.teacher : prev.slot.teacher,
                    kind: prev.slot.kind,
                    weekStart: min(prev.slot.weekStart, curr.slot.weekStart),
                    weekEnd: max(prev.slot.weekEnd, curr.slot.weekEnd),
                    eventID: prev.slot.eventID ?? curr.slot.eventID
                )
                merged[merged.count - 1] = CourseOccurrence(date: prev.date, slot: combined)
            } else {
                merged.append(curr)
            }
        }
        return merged
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

import Foundation

/// 2026-2027 学年第一学期模型 + 东北大学节次作息。
/// 锚点来自门户真实数据：第 1 教学周从 2026-08-30（周日）起。
enum Semester {
    static var week1Start: Date {
        Calendar.current.date(from: DateComponents(year: 2026, month: 8, day: 30))!
    }

    static let teachingWeeks = 16
    static let examWeeks = 2
    static let totalWeeks = teachingWeeks + examWeeks

    /// 该日期所在教学周序号（1 起；<1 或 >totalWeeks 即假期）。
    static func weekNumberOf(_ day: Date) -> Int {
        let cal = Calendar.current
        let start = cal.startOfDay(for: day)
        let dow = cal.component(.weekday, from: start) // 1=周日
        let sunday = cal.date(byAdding: .day, value: -(dow - 1), to: start)!
        let days = cal.dateComponents([.day], from: cal.startOfDay(for: week1Start), to: sunday).day ?? 0
        return days / 7 + 1
    }

    static func weekStart(of week: Int) -> Date {
        cal.date(byAdding: .day, value: 7 * (week - 1), to: cal.startOfDay(for: week1Start))!
    }

    /// 某天所在教学周的周日（门户周起始约定）。
    static func weekStart(forDay day: Date) -> Date {
        weekStart(of: weekNumberOf(day))
    }

    static func isExamWeek(_ week: Int) -> Bool {
        week > teachingWeeks && week <= totalWeeks
    }

    // 10 个小节：(开始分钟, 结束分钟)，来自门户课表真实时间（浑南上午）。
    static let periodStarts: [Int] = [510, 565, 630, 685, 840, 895, 960, 1015, 1110, 1165]
    static let periodEnds: [Int] = [555, 610, 675, 730, 885, 940, 1005, 1060, 1155, 1250]

    static func hm(_ minutes: Int) -> String {
        String(format: "%02d:%02d", minutes / 60, minutes % 60)
    }

    /// 分钟 → 所在小节序号（1...10）。
    static func periodOf(startMinutes: Int) -> Int {
        for (i, s) in periodStarts.enumerated() where startMinutes >= s && startMinutes < periodEnds[i] {
            return i + 1
        }
        return startMinutes < periodStarts[0] ? 1 : periodStarts.count
    }

    /// 结束时间落在某节结束时（如 12:10）→ 该节。
    static func endPeriod(of endMinutes: Int) -> Int {
        for (i, s) in periodStarts.enumerated() where endMinutes > s && endMinutes <= periodEnds[i] {
            return i + 1
        }
        return endMinutes < periodStarts[0] ? 1 : periodStarts.count
    }

    static func minutesNow() -> Int {
        let now = Date()
        return Calendar.current.component(.hour, from: now) * 60
            + Calendar.current.component(.minute, from: now)
    }

    private static let cal = Calendar.current
}

import Foundation
import Observation

struct SemesterConfiguration: Codable, Equatable {
    var name: String
    /// Civil date, not an absolute timestamp: changing time zones preserves the anchor day.
    var firstWeekSunday: String
    var teachingWeeks: Int
    var examWeeks: Int

    static let bundled = Self(name: "2026-2027 第一学期", firstWeekSunday: "2026-08-30", teachingWeeks: 16, examWeeks: 2)
    var totalWeeks: Int { teachingWeeks + examWeeks }

    func anchor(calendar: Calendar = .current) -> Date? {
        let parts = firstWeekSunday.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3, (2000...2100).contains(parts[0]), (1...12).contains(parts[1]),
              (1...31).contains(parts[2]), let date = calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2])),
              calendar.component(.year, from: date) == parts[0], calendar.component(.month, from: date) == parts[1],
              calendar.component(.day, from: date) == parts[2] else { return nil }
        return calendar.date(byAdding: .day, value: 1 - calendar.component(.weekday, from: date), to: calendar.startOfDay(for: date))
    }
    var isValid: Bool { !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && (1...40).contains(teachingWeeks) && (0...8).contains(examWeeks) && anchor() != nil }

    static func calibrated(name: String, firstWeekDay: Date, teachingWeeks: Int, examWeeks: Int, calendar: Calendar = .current) -> Self {
        let sunday = calendar.date(byAdding: .day, value: 1 - calendar.component(.weekday, from: firstWeekDay), to: calendar.startOfDay(for: firstWeekDay))!
        let p = calendar.dateComponents([.year, .month, .day], from: sunday)
        return Self(name: String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(60)),
                    firstWeekSunday: String(format: "%04d-%02d-%02d", p.year!, p.month!, p.day!),
                    teachingWeeks: teachingWeeks, examWeeks: examWeeks)
    }
}

/// Used from the main UI/repository. Reading configuration participates in Observation
/// so existing Semester facade users update without duplicating an anchor in each view.
@Observable
final class SemesterSettings {
    static let shared = SemesterSettings()
    private(set) var configuration = SemesterConfiguration.bundled
    private(set) var isCustomized = false
    private let defaults: UserDefaults
    private var account = ""

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }
    private var key: String { "lumen.semester." + account }

    func activate(account: String) {
        guard self.account != account else { return }
        self.account = account
        if !account.isEmpty, let data = defaults.data(forKey: key),
           let saved = try? JSONDecoder().decode(SemesterConfiguration.self, from: data), saved.isValid {
            configuration = saved
            isCustomized = true
        } else {
            configuration = .bundled
            isCustomized = false
        }
    }

    @discardableResult
    func save(_ value: SemesterConfiguration) -> Bool {
        guard !account.isEmpty, value.isValid, let data = try? JSONEncoder().encode(value) else { return false }
        defaults.set(data, forKey: key)
        configuration = value
        isCustomized = true
        return true
    }

    func reset() {
        if !account.isEmpty { defaults.removeObject(forKey: key) }
        configuration = .bundled
        isCustomized = false
    }
}

/// Teaching-week labels are configurable; portal requests still use civil weeks.
enum Semester {
    static var week1Start: Date { SemesterSettings.shared.configuration.anchor() ?? SemesterConfiguration.bundled.anchor()! }
    static var teachingWeeks: Int { SemesterSettings.shared.configuration.teachingWeeks }
    static var examWeeks: Int { SemesterSettings.shared.configuration.examWeeks }
    static var totalWeeks: Int { teachingWeeks + examWeeks }

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

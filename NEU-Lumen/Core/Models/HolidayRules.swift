import Foundation

struct HolidayYear: Codable {
    struct Day: Codable, Equatable {
        let name: String
        let date: String
        let isOffDay: Bool
    }
    let year: Int
    let days: [Day]

    static func decode(_ data: Data, year: Int) throws -> HolidayYear {
        let value = try JSONDecoder().decode(Self.self, from: data)
        guard value.year == year, !value.days.isEmpty, value.days.count < 100,
              Set(value.days.map(\.date)).count == value.days.count,
              value.days.allSatisfy({ day in
                  guard let date = PortalDate.day(day.date) else { return false }
                  return day.date.hasPrefix("\(year)-") && PortalDate.isoDay(date) == day.date && !day.name.isEmpty
              }) else { throw CocoaError(.coderReadCorrupt) }
        return value
    }

    // 2026 国办发明电〔2025〕7号。Future years are fetched, never extrapolated.
    static let bundled2026: HolidayYear = {
        let ranges: [(String, String, ClosedRange<Int>)] = [
            ("元旦", "01", 1...3), ("春节", "02", 15...23), ("清明节", "04", 4...6),
            ("劳动节", "05", 1...5), ("端午节", "06", 19...21), ("中秋节", "09", 25...27), ("国庆节", "10", 1...7)
        ]
        var days = ranges.flatMap { name, month, range in
            range.map { Day(name: name, date: String(format: "2026-%@-%02d", month, $0), isOffDay: true) }
        }
        days += ["01-04", "02-14", "02-28", "05-09", "09-20", "10-10"].map {
            Day(name: "调休补班", date: "2026-" + $0, isOffDay: false)
        }
        return HolidayYear(year: 2026, days: days)
    }()
}

enum SchoolDayOverride: String, Codable, CaseIterable {
    case normal, rest
    var title: String { self == .normal ? "按原课表上课" : "停课休息" }
}

enum HolidayRules {
    /// Replace only ordinary courses; the source is the raw portal date, not a recursively adjusted day.
    static func project(_ courses: [CourseOccurrence], from first: Date, to end: Date,
                        replacements: [String: String]) -> [CourseOccurrence] {
        var items = courses.filter {
            $0.date >= first && $0.date < end &&
                ($0.slot.kind != "course" || replacements[PortalDate.isoDay($0.date)] == nil)
        }
        for (target, source) in replacements {
            guard let date = PortalDate.day(target), date >= first, date < end else { continue }
            items += courses.filter { PortalDate.isoDay($0.date) == source && $0.slot.kind == "course" }.map {
                var slot = $0.slot
                slot.weekday = PlannerEvent.mondayBasedWeekday(date)
                return CourseOccurrence(date: date, slot: slot)
            }
        }
        return Array(Set(items))
    }

    static func apply(_ courses: [CourseOccurrence], enabled: Bool,
                      days: [String: HolidayYear.Day], overrides: [String: SchoolDayOverride]) -> [CourseOccurrence] {
        courses.filter { occurrence in
            // Exams and user-created events must never disappear on a public holiday.
            guard occurrence.slot.kind == "course" else { return true }
            let day = PortalDate.isoDay(occurrence.date)
            if let rule = overrides[day] { return rule == .normal }
            return !enabled || days[day]?.isOffDay != true
        }
    }
}

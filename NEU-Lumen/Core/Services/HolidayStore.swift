import Foundation
import Observation

@MainActor @Observable
final class HolidayStore {
    var enabled: Bool { didSet { defaults.set(enabled, forKey: "lumen.holidays.enabled") } }
    private(set) var days: [String: HolidayYear.Day] = [:]
    private(set) var overrides: [String: SchoolDayOverride] = [:]
    private(set) var replacementDates: [String: String] = [:]
    private(set) var status = ""
    private let defaults: UserDefaults
    private var overrideKey: String?
    private var attempted: Set<Int> = []
    private var knownYears: Set<Int> = [2026]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        enabled = defaults.object(forKey: "lumen.holidays.enabled") as? Bool ?? true
        merge(.bundled2026)
    }

    func activate(account: String) {
        overrideKey = account.isEmpty ? nil : "lumen.schoolDays." + account
        replacementDates = overrideKey.flatMap { defaults.dictionary(forKey: $0 + ".replacements") as? [String: String] } ?? [:]
        overrides = overrideKey.flatMap { defaults.data(forKey: $0) }
            .flatMap { try? JSONDecoder().decode([String: SchoolDayOverride].self, from: $0) } ?? [:]
    }

    func setReplacement(_ source: Date?, on target: Date) {
        replacementDates[PortalDate.isoDay(target)] = source.map(PortalDate.isoDay)
        if source != nil { setOverride(.normal, on: target) }
        if let overrideKey { defaults.set(replacementDates, forKey: overrideKey + ".replacements") }
    }

    func setOverride(_ rule: SchoolDayOverride?, on date: Date) {
        overrides[PortalDate.isoDay(date)] = rule
        if let overrideKey, let data = try? JSONEncoder().encode(overrides) { defaults.set(data, forKey: overrideKey) }
    }

    func label(on date: Date) -> String? {
        let key = PortalDate.isoDay(date)
        if let source = replacementDates[key] { return "补 \(source) 的课" }
        if let rule = overrides[key] { return "学校安排：" + rule.title }
        return days[key].map { $0.name + ($0.isOffDay ? " · 休" : " · 补班（以校方调课为准）") }
    }

    func apply(_ courses: [CourseOccurrence]) -> [CourseOccurrence] {
        HolidayRules.apply(courses, enabled: enabled, days: days, overrides: overrides)
    }

    func refresh(year: Int, force: Bool = false) async {
        let key = "lumen.holidays.\(year)"
        if let data = defaults.data(forKey: key), let cached = try? HolidayYear.decode(data, year: year) { merge(cached) }
        guard force || !attempted.contains(year) else { return }
        attempted.insert(year)
        do {
            var request = URLRequest(url: URL(string: "https://raw.githubusercontent.com/NateScarlet/holiday-cn/master/\(year).json")!)
            request.timeoutInterval = 12
            // No campus cookies or credentials are sent to the public holiday source.
            let configuration = URLSessionConfiguration.ephemeral
            configuration.httpCookieStorage = nil
            let session = URLSession(configuration: configuration)
            defer { session.finishTasksAndInvalidate() }
            let (data, response) = try await session.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw CocoaError(.fileReadUnknown) }
            let value = try HolidayYear.decode(data, year: year)
            merge(value)
            defaults.set(data, forKey: key)
            status = "\(year) 年节假日已更新"
        } catch {
            status = knownYears.contains(year) ? "\(year) 年使用本机节假日数据" : "\(year) 年安排尚未取得，保留原课表；可手动设置停课"
        }
    }

    private func merge(_ year: HolidayYear) {
        days = days.filter { !$0.key.hasPrefix("\(year.year)-") }
        for day in year.days { days[day.date] = day }
        knownYears.insert(year.year)
    }
}

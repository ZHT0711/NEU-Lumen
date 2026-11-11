import Foundation

/// Foundation-only policy shared by the repository and native regression tests.
/// No networking, account identifiers or ActivityKit payloads are stored here.
enum LiveActivityDataPolicy {
    static let accents = ["cyan", "blue", "green", "orange", "pink", "purple"]
    static let symbols = ["book.closed.fill", "creditcard.fill", "wifi", "bolt.fill", "checklist",
                          "calendar", "sparkles", "chart.bar.fill", "bell.fill", "heart.fill", "flag.fill"]
    static let destinations = ["course", "card", "settings", "learning", "profile"]

    static func accent(_ value: String) -> String { accents.contains(value) ? value : "cyan" }
    static func symbol(_ value: String) -> String { symbols.contains(value) ? value : "sparkles" }
    static func progress(_ value: Double?) -> Double? {
        guard let value, value.isFinite else { return nil }
        return min(1, max(0, value))
    }
    static func accountMatches(current: String?, loaded: String?, authenticated: Bool) -> Bool {
        authenticated && current?.isEmpty == false && current == loaded
    }

    /// Unlike teaching-week arithmetic, this works before the semester anchor too.
    static func portalWeekStart(for day: Date, calendar: Calendar = .current) -> Date {
        let start = calendar.startOfDay(for: day)
        return calendar.date(byAdding: .day, value: 1 - calendar.component(.weekday, from: start), to: start)!
    }

    static func money(_ value: Double?) -> String? {
        guard let value, value.isFinite else { return nil }
        return String(format: "¥%.2f", value)
    }
    static func dateText(_ date: Date, format: String, calendar: Calendar = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = format
        return formatter.string(from: date)
    }
    static func countdown(to date: Date, at now: Date) -> String {
        let interval = date.timeIntervalSince(now)
        guard interval.isFinite else { return "时间未读取" }
        if interval > 9999 * 86400 { return "超过9999天" }
        let minutes = max(0, Int(ceil(max(0, interval) / 60)))
        if minutes >= 1440 { return "\(minutes / 1440)天\((minutes % 1440) / 60)小时" }
        if minutes >= 60 { return "\(minutes / 60)小时\(minutes % 60)分" }
        return "\(minutes)分钟"
    }
}

enum LiveActivityTemplate {
    struct Variable: Identifiable, Sendable {
        let key: String
        let description: String
        var token: String { "{\(key)}" }
        var id: String { key }
    }
    static let variables: [Variable] = [
        .init(key: "course", description: "未来七天内进行中或下一项课程/手动日程"),
        .init(key: "room", description: "下一项课程/手动日程的地点"),
        .init(key: "start", description: "下一项开始日期与时间"),
        .init(key: "end", description: "下一项结束日期与时间"),
        .init(key: "card", description: "已同步的校园卡余额"),
        .init(key: "net", description: "已同步的校园网余额"),
        .init(key: "electric", description: "已读取的宿舍剩余电量（kWh）"),
        .init(key: "pending", description: "已读取的待完成作业数；部分读取带 +"),
        .init(key: "gpa", description: "当前或最近有成绩学期的 GPA"),
        .init(key: "week", description: "当前教学周（非教学周会明确标注）"),
        .init(key: "date", description: "本机当前日期 yyyy-MM-dd"),
        .init(key: "time", description: "本机当前时间 HH:mm")
    ]
    private static let pattern = try! NSRegularExpression(pattern: #"\{([a-z]+)\}"#)

    /// Single pass: replacement data is never interpreted as another template.
    /// Unknown tokens remain literal; known but missing data is explicitly unread.
    static func render(_ text: String, values: [String: String], limit: Int) -> String {
        let keys = Set(variables.map(\.key))
        var output = text
        for match in pattern.matches(in: text, range: NSRange(text.startIndex..., in: text)).reversed() {
            guard let keyRange = Range(match.range(at: 1), in: text),
                  let range = Range(match.range, in: output) else { continue }
            let key = String(text[keyRange])
            guard keys.contains(key) else { continue }
            let value = values[key].flatMap { $0.isEmpty ? nil : $0 } ?? "未读取"
            output.replaceSubrange(range, with: value)
        }
        return String(output.prefix(limit))
    }
}

struct LiveActivitySchedule {
    enum Availability: String { case notLoaded, empty, finished, upcoming, ongoing }
    struct Item {
        let occurrence: CourseOccurrence
        let start: Date
        let end: Date
        func isOngoing(at now: Date) -> Bool { start <= now && now < end }
        func progress(at now: Date) -> Double? {
            guard isOngoing(at: now) else { return nil }
            return LiveActivityDataPolicy.progress(now.timeIntervalSince(start) / end.timeIntervalSince(start))
        }
    }
    let items: [Item]
    let next: Item?
    let availability: Availability
    let portalLoaded: Bool
    let finishedCount: Int
    var isReady: Bool { availability != .notLoaded }
    var remainingCount: Int { items.count - finishedCount }

    /// An end clock earlier than the start clock represents an overnight event.
    /// Equal clocks and invalid slots are not fabricated into 24-hour events.
    static func interval(for occurrence: CourseOccurrence, calendar: Calendar = .current) -> Item? {
        let slot = occurrence.slot
        guard (0..<1440).contains(slot.startMinutes), (0...2880).contains(slot.endMinutes),
              slot.startMinutes != slot.endMinutes else { return nil }
        let day = calendar.startOfDay(for: occurrence.date)
        let endMinutes = slot.endMinutes < slot.startMinutes ? slot.endMinutes + 1440 : slot.endMinutes
        guard endMinutes - slot.startMinutes <= 1440,
              let start = calendar.date(byAdding: .minute, value: slot.startMinutes, to: day),
              let end = calendar.date(byAdding: .minute, value: endMinutes, to: day), start < end else { return nil }
        return Item(occurrence: occurrence, start: start, end: end)
    }

    static func snapshot(_ occurrences: [CourseOccurrence], from first: Date, to end: Date,
                         at now: Date, portalLoaded: Bool, calendar: Calendar = .current) -> Self {
        let items = occurrences.mergeConsecutive().compactMap { interval(for: $0, calendar: calendar) }
            .filter { $0.start < end && $0.end > first }
            .sorted { $0.start == $1.start ? $0.occurrence.id < $1.occurrence.id : $0.start < $1.start }
        let unfinished = items.filter { $0.end > now }
        // A currently running event wins even if another event starts later today.
        let next = unfinished.first { $0.isOngoing(at: now) } ?? unfinished.first
        let availability: Availability
        if let next { availability = next.isOngoing(at: now) ? .ongoing : .upcoming }
        else if !portalLoaded { availability = .notLoaded }
        else { availability = items.isEmpty ? .empty : .finished }
        return Self(items: items, next: next, availability: availability, portalLoaded: portalLoaded,
                    finishedCount: items.filter { $0.end <= now }.count)
    }
}

/// Counts only rows actually read by the existing learning bridges. Unread rows
/// and partial course syncs never turn into a fabricated zero pending count.
struct LiveActivityAssignments {
    struct Item {
        let id: String
        let title: String
        let platform: String
        let deadline: Date?
        let completed: Bool
    }
    let items: [Item]
    let hasLoadedData: Bool
    let hasUnreadData: Bool
    let loadedPlatformCount: Int
    var pending: [Item] { items.filter { !$0.completed } }
    var completedCount: Int { items.filter(\.completed).count }
    var pendingText: String? {
        guard hasLoadedData, !items.isEmpty || !hasUnreadData else { return nil }
        return "\(pending.count)" + (hasUnreadData ? "+" : "")
    }
    var progress: Double? {
        guard !hasUnreadData, !items.isEmpty else { return nil }
        return Double(completedCount) / Double(items.count)
    }
    func next(at now: Date) -> Item? {
        pending.sorted {
            if $0.deadline != $1.deadline { return ($0.deadline ?? .distantFuture) < ($1.deadline ?? .distantFuture) }
            return $0.id < $1.id
        }.first
    }
    func overdueCount(at now: Date) -> Int { pending.filter { $0.deadline.map { $0 < now } == true }.count }

    init(cg: CGAssignmentReport?, reports: [LearningPlatform: LearningAssignmentReport]) {
        var rows: [Item] = []
        var unread = false
        if let cg {
            unread = !cg.warnings.isEmpty
            for assignment in cg.assignments where !assignment.history {
                guard assignment.loaded, assignment.problemCount > 0,
                      assignment.problems.count >= assignment.problemCount else { unread = true; continue }
                rows.append(.init(id: "cg." + assignment.id, title: assignment.title, platform: LearningPlatform.cg.title,
                                  deadline: assignment.deadline, completed: assignment.isComplete))
            }
        }
        for platform in [LearningPlatform.mooc, .chaoxing] {
            guard let report = reports[platform] else { continue }
            unread = unread || !report.warnings.isEmpty
            let assignments = report.assignments.filter { platform != .mooc || ["作业", "测验"].contains($0.kind) }
            for course in report.courses where !report.refreshedCourseKeys.contains(course.key) {
                if !assignments.contains(where: { $0.courseKey == course.key }) { unread = true }
            }
            var seen = Set<String>()
            for assignment in assignments where seen.insert(assignment.id).inserted {
                guard assignment.completed || (!assignment.statusText.contains("待确认") && !assignment.statusText.contains("未读取")) else {
                    unread = true; continue
                }
                rows.append(.init(id: platform.rawValue + "." + assignment.id, title: assignment.title, platform: platform.title,
                                  deadline: assignment.deadline, completed: assignment.completed))
            }
        }
        items = rows
        loadedPlatformCount = (cg == nil ? 0 : 1) + [LearningPlatform.mooc, .chaoxing].filter { reports[$0] != nil }.count
        hasLoadedData = loadedPlatformCount > 0
        hasUnreadData = unread
    }
}

struct LiveActivityAcademic {
    let semester: GradeSemester?
    let scoredCount: Int
    let courseCount: Int
    let credits: Double?
    let gpa: Double?
    let weightedAverage: Double?
    var progress: Double? { courseCount > 0 ? Double(scoredCount) / Double(courseCount) : nil }

    /// Uses the same current/nonempty fallback as GradesView, without treating
    /// an unknown textual result (e.g. 缓考) or an empty report as a numeric 0 GPA.
    init(semesters: [GradeSemester]) {
        let selected = semesters.first { $0.current && !$0.courses.isEmpty }
            ?? semesters.first { !$0.courses.isEmpty }
            ?? semesters.first { $0.current } ?? semesters.first
        semester = selected
        courseCount = selected?.courses.count ?? 0
        func score(_ course: GradeCourse) -> Double? {
            if let value = course.score { return value.isFinite && (0...100).contains(value) ? value : nil }
            let value = course.scoreRaw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard ["优", "优秀", "良", "良好", "中", "中等", "及格", "合格", "不及格", "不合格"].contains(value) else { return nil }
            return course.scoreValue
        }
        let scored = (selected?.courses ?? []).compactMap { course -> (Double, Double)? in
            guard course.credit.isFinite, course.credit > 0, let value = score(course) else { return nil }
            return (value, course.credit)
        }
        scoredCount = scored.count
        let total = scored.reduce(0) { $0 + $1.1 }
        credits = total > 0 ? total : nil
        weightedAverage = total > 0 ? scored.reduce(0) { $0 + $1.0 * $1.1 } / total : nil
        gpa = total > 0 ? scored.reduce(0) { $0 + GradeSemester.gpaOf($1.0) * $1.1 } / total : nil
    }
}

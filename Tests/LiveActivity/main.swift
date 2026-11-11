import Foundation

// Native regression of the Foundation-only selection/template/statistics policy.
NSTimeZone.default = TimeZone(secondsFromGMT: 0)!
func utcCalendar() -> Calendar {
    var value = Calendar(identifier: .gregorian)
    value.timeZone = TimeZone(secondsFromGMT: 0)!
    return value
}
let calendar = utcCalendar()
func date(_ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
    utcCalendar().date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
}
func occurrence(_ day: Int, _ start: Int, _ end: Int, _ name: String = "示例课程", kind: String = "course", id: String? = nil) -> CourseOccurrence {
    CourseOccurrence(date: date(day), slot: CourseSlot(weekday: 3, startMinutes: start, endMinutes: end,
        name: name, room: "示例教室", kind: kind, eventID: id))
}

let night = date(11, 21, 49)
let tomorrow = occurrence(12, 630, 730, "明日课程")
let past = occurrence(11, 1110, 1250, "已结束课程")
let future = LiveActivitySchedule.snapshot([past, tomorrow], from: date(11), to: date(18), at: night, portalLoaded: true, calendar: calendar)
precondition(future.availability == .upcoming && future.next?.occurrence.slot.name == "明日课程")
precondition(future.finishedCount == 1 && future.remainingCount == 1)
precondition(future.next?.start == date(12, 10, 30))
precondition(future.next?.progress(at: night) == nil)

let manual = occurrence(12, 800, 830, "手动提醒", kind: "custom", id: "fixture-event")
let local = LiveActivitySchedule.snapshot([manual], from: date(11), to: date(18), at: night, portalLoaded: false, calendar: calendar)
precondition(local.isReady && local.availability == .upcoming && !local.portalLoaded)
let unread = LiveActivitySchedule.snapshot([], from: date(11), to: date(18), at: night, portalLoaded: false, calendar: calendar)
precondition(!unread.isReady && unread.availability == .notLoaded)
let empty = LiveActivitySchedule.snapshot([], from: date(11), to: date(18), at: night, portalLoaded: true, calendar: calendar)
precondition(empty.isReady && empty.availability == .empty)
let finished = LiveActivitySchedule.snapshot([past], from: date(11), to: date(18), at: night, portalLoaded: true, calendar: calendar)
precondition(finished.isReady && finished.availability == .finished && finished.next == nil)

let ongoing = occurrence(11, 600, 720, "进行中")
let after = occurrence(11, 750, 850, "稍后课程")
let running = LiveActivitySchedule.snapshot([after, ongoing], from: date(11), to: date(18), at: date(11, 11), portalLoaded: false, calendar: calendar)
precondition(running.next?.occurrence.slot.name == "进行中" && running.availability == .ongoing)
precondition(abs((running.next?.progress(at: date(11, 11)) ?? -1) - 0.5) < 0.000001)
let atEnd = LiveActivitySchedule.snapshot([ongoing, after], from: date(11), to: date(18), at: date(11, 12), portalLoaded: true, calendar: calendar)
precondition(atEnd.next?.occurrence.slot.name == "稍后课程" && atEnd.availability == .upcoming)
let midnight = LiveActivitySchedule.snapshot([occurrence(10, 1380, 60, "跨夜日程", kind: "custom", id: "night")],
    from: date(11), to: date(18), at: date(11, 0, 30), portalLoaded: false, calendar: calendar)
precondition(midnight.availability == .ongoing && midnight.next?.end == date(11, 1))
precondition(LiveActivitySchedule.interval(for: occurrence(11, 600, 600)) == nil)
precondition(LiveActivitySchedule.interval(for: occurrence(11, -1, 100)) == nil)
precondition(LiveActivitySchedule.interval(for: occurrence(11, 600, 2880)) == nil)
let beforeSemester = calendar.date(from: DateComponents(year: 2026, month: 1, day: 7))!
let sunday = LiveActivityDataPolicy.portalWeekStart(for: beforeSemester, calendar: calendar)
precondition(calendar.component(.weekday, from: sunday) == 1 && sunday <= beforeSemester)
print("Live activity schedule: future days, manual-only, unread/empty/finished, ongoing priority, exact end and overnight passed")

precondition(LiveActivityDataPolicy.accountMatches(current: "fixture-a", loaded: "fixture-a", authenticated: true))
precondition(!LiveActivityDataPolicy.accountMatches(current: "fixture-b", loaded: "fixture-a", authenticated: true))
precondition(!LiveActivityDataPolicy.accountMatches(current: "fixture-a", loaded: "fixture-a", authenticated: false))
precondition(!LiveActivityDataPolicy.accountMatches(current: "", loaded: "", authenticated: true))
precondition(LiveActivityDataPolicy.accent("invalid") == "cyan")
precondition(LiveActivityDataPolicy.symbol("invalid") == "sparkles")
precondition(LiveActivityDataPolicy.progress(.nan) == nil && LiveActivityDataPolicy.progress(.infinity) == nil)
precondition(LiveActivityDataPolicy.progress(-0.5) == 0 && LiveActivityDataPolicy.progress(4) == 1)
precondition(LiveActivityDataPolicy.money(0) == "¥0.00" && LiveActivityDataPolicy.money(.infinity) == nil)
let variables = ["course": "{card}", "card": "¥66.50"]
precondition(LiveActivityTemplate.render("{course} | {card}", values: variables, limit: 80) == "{card} | ¥66.50")
precondition(LiveActivityTemplate.render("{pending} {unknown}", values: [:], limit: 80) == "未读取 {unknown}")
precondition(LiveActivityTemplate.render("{course}", values: ["course": String(repeating: "😀", count: 100)], limit: 80).count == 80)
precondition(Set(LiveActivityTemplate.variables.map(\.key)) == Set(["course", "room", "start", "end", "card", "net", "electric", "pending", "gpa", "week", "date", "time"]))
print("Live activity template: fixed allowlist, missing versus zero, Unicode limit and one-pass substitutions passed")

let url = URL(string: "https://www.icourse163.org/")!
let course = LearningCourse(id: "fixture", termID: "term", title: "示例学习课程", url: url)
let assignments = [
    LearningAssignment(id: "one", courseKey: course.key, courseTitle: course.title, title: "未完成作业", kind: "作业", url: url,
        deadline: date(12, 23), deadlineText: "", statusText: "未提交", completed: false, scoreText: ""),
    LearningAssignment(id: "two", courseKey: course.key, courseTitle: course.title, title: "已完成测验", kind: "测验", url: url,
        deadline: nil, deadlineText: "", statusText: "已完成", completed: true, scoreText: "0")
]
let report = LearningAssignmentReport(courses: [course], assignments: assignments, warnings: [], refreshedCourseKeys: [course.key])
let summary = LiveActivityAssignments(cg: nil, reports: [.mooc: report])
precondition(summary.hasLoadedData && !summary.hasUnreadData && summary.pendingText == "1")
precondition(summary.next(at: night)?.title == "未完成作业" && summary.progress == 0.5)
precondition(summary.overdueCount(at: date(13)) == 1 && summary.loadedPlatformCount == 1)
let unknown = LearningAssignmentReport(courses: [course], assignments: [], warnings: [], refreshedCourseKeys: [])
precondition(LiveActivityAssignments(cg: nil, reports: [.mooc: unknown]).pendingText == nil)
let noTasks = LearningAssignmentReport(courses: [course], assignments: [], warnings: [], refreshedCourseKeys: [course.key])
precondition(LiveActivityAssignments(cg: nil, reports: [.mooc: noTasks]).pendingText == "0")
precondition(!LiveActivityAssignments(cg: nil, reports: [:]).hasLoadedData)
let incomplete = CGAssignment(id: "partial", title: "未读全题目的作业", url: nil, deadlineText: "", late: false,
    history: false, loaded: true, problems: [CGProblem(id: "p1", title: "题目", url: nil, statusText: "完全正确")], expectedProblemCount: 2)
let incompleteReport = CGAssignmentReport(assignments: [incomplete], warnings: [])
precondition(LiveActivityAssignments(cg: incompleteReport, reports: [:]).pendingText == nil)
print("Live activity assignments: loaded coverage, partial versus zero, pending, overdue and progress passed")

let math = GradeCourse(name: "数学", credit: 5, category: "必修", score: 92, scoreRaw: "")
let english = GradeCourse(name: "英语", credit: 3, category: "必修", score: 88, scoreRaw: "")
let known = GradeSemester(name: "已加载学期", termCode: "fixture", current: true, courses: [math, english])
let academic = LiveActivityAcademic(semesters: [known])
precondition(academic.scoredCount == 2 && academic.credits == 8 && academic.progress == 1)
precondition(abs((academic.weightedAverage ?? -1) - 90.5) < 0.000001)
precondition(abs((academic.gpa ?? -1) - 3.8875) < 0.000001)
let pendingGrade = GradeCourse(name: "未出分", credit: 3, category: "必修", score: nil, scoreRaw: "缓考")
let unknownAcademic = LiveActivityAcademic(semesters: [GradeSemester(name: "未出分学期", termCode: "other", current: true, courses: [pendingGrade])])
precondition(unknownAcademic.gpa == nil && unknownAcademic.weightedAverage == nil)
let zeroGrade = GradeCourse(name: "零分", credit: 3, category: "必修", score: 0, scoreRaw: "0")
precondition(LiveActivityAcademic(semesters: [GradeSemester(name: "真实零分", termCode: "zero", current: true, courses: [zeroGrade])]).gpa == 0)
precondition(LiveActivityAcademic(semesters: []).gpa == nil)
let emptyCurrent = GradeSemester(name: "空当前学期", termCode: "empty", current: true, courses: [])
precondition(LiveActivityAcademic(semesters: [emptyCurrent, known]).gpa == academic.gpa)
print("Live activity academic: current/nonempty fallback, GPA, weighted mean and unknown versus real zero passed")

@MainActor
func testConfigurationMigration() throws {
    let suite = "NEU-Lumen.LiveActivityTests." + UUID().uuidString
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let key = "lumen.dynamicIsland.configuration"
    let old: [String: Any] = ["enabled": false, "kind": "cardBalance", "customTitle": "旧标题", "customSubtitle": "旧副标题"]
    defaults.set(try JSONSerialization.data(withJSONObject: old), forKey: key)
    let store = DynamicIslandStore(defaults: defaults)
    precondition(!store.enabled && store.kind == .cardBalance && store.customTitle == "旧标题")
    precondition(store.accent == "cyan" && store.customIcon == "sparkles" && store.customValue.isEmpty)
    precondition(!store.customDeadlineEnabled && store.showProgress)
    precondition(DynamicIslandStore.ContentKind.allCases.count == 9)
    store.kind = .custom
    store.customTitle = String(repeating: "字", count: 200)
    store.customSubtitle = String(repeating: "字", count: 200)
    store.customValue = String(repeating: "值", count: 100)
    store.accent = "invalid"
    store.customIcon = "not-a-symbol"
    store.customDeadlineEnabled = true
    store.customDeadline = date(12, 18)
    let restored = DynamicIslandStore(defaults: defaults)
    precondition(restored.kind == .custom && !restored.enabled)
    precondition(restored.customTitle.count == 80 && restored.customSubtitle.count == 160 && restored.customValue.count == 32)
    precondition(restored.accent == "cyan" && restored.customIcon == "sparkles")
    precondition(restored.customDeadlineEnabled && restored.customDeadline == date(12, 18))
    restored.reset()
    let reset = DynamicIslandStore(defaults: defaults)
    precondition(reset.enabled && reset.kind == .nextCourse && !reset.customDeadlineEnabled && reset.customValue.isEmpty)
}
try testConfigurationMigration()
print("Live activity configuration: old four-field migration, limits, symbol/palette validation, countdown and reset passed")

import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

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
func testConfigurationMigration() async throws {
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
try await testConfigurationMigration()
print("Live activity configuration: old four-field migration, limits, symbol/palette validation, countdown and reset passed")

precondition(LiveActivityTemplate.dependencies(in: ["{course} {room} {unknown}", "{card} {card}"]) == Set(["course", "room", "card"]))
precondition(LiveActivityTemplate.dependencies(in: ["普通文字", "{{TIME}}", "{date}"]) == Set(["date"]))
func verifySemesterCalibration() {
    let suite = "NEU-Lumen.SemesterTests." + UUID().uuidString
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let settings = SemesterSettings(defaults: defaults)
    settings.activate(account: "fixture-a")
    let firstDay = calendar.date(from: DateComponents(year: 2027, month: 3, day: 1))!
    let spring = SemesterConfiguration.calibrated(name: "测试春季", firstWeekDay: firstDay,
        teachingWeeks: 18, examWeeks: 2, calendar: calendar)
    precondition(spring.firstWeekSunday == "2027-02-28" && spring.isValid && spring.totalWeeks == 20)
    precondition(settings.save(spring) && settings.configuration == spring)
    settings.activate(account: "fixture-b")
    precondition(settings.configuration == .bundled && !settings.isCustomized)
    settings.activate(account: "fixture-a")
    precondition(settings.configuration == spring)
    let restarted = SemesterSettings(defaults: defaults)
    restarted.activate(account: "fixture-a")
    precondition(restarted.configuration == spring)
    var invalid = spring
    invalid.firstWeekSunday = "2027-02-31"
    precondition(!invalid.isValid && !settings.save(invalid))
    invalid = spring
    invalid.teachingWeeks = 0
    precondition(!settings.save(invalid))
    settings.reset()
    precondition(settings.configuration == .bundled)
    print("Semester calibration: Sunday normalization, account isolation, restart, invalid dates and reset passed")
}
verifySemesterCalibration()

// BEGIN standalone presentation checks (also compiled by the Python runner).
let liveFixtureKinds = ["nextCourse", "cardBalance", "netBalance", "electricBalance", "assignments", "planner", "dayOverview", "academicOverview", "custom"]
func liveFixture(_ kind: String) -> LiveActivityContentState {
    LiveActivityContentState(title: "离线示例标题", subtitle: "示例来源上下文", value: "12",
        kind: kind, updatedAt: Date(timeIntervalSinceReferenceDate: 100), startDate: nil, endDate: nil,
        accent: "cyan", detailItems: [LiveActivityDetail(label: "示例标签", value: "真实字段的合成测试值")])
}
let liveEncoder = JSONEncoder()
let legacyData = Data(#"{"title":"旧活动","subtitle":"旧数据","value":"0","kind":"nextCourse","updatedAt":0,"startDate":100,"endDate":200,"countdownTitle":"距上课"}"#.utf8)
let legacyState = try JSONDecoder().decode(LiveActivityContentState.self, from: legacyData)
precondition(legacyState.detailItems == nil && legacyState.phase == nil && legacyState.countdownDate == Date(timeIntervalSinceReferenceDate: 100))
let legacyDetail = try JSONDecoder().decode(LiveActivityDetail.self, from: Data(#"{"label":"教室","value":"示例楼"}"#.utf8))
precondition(legacyDetail.isTimeSensitive == nil)
let family = "👨‍👩‍👧‍👦"
precondition(LiveActivityText.prefix(family + family, bytes: family.utf8.count + 1) == family)
precondition(LiveActivityText.detail("教师", " \n ") == nil && LiveActivityText.detail("地点", "待定") == nil)
let adversarialTexts = [String(repeating: "汉字😀", count: 800), String(repeating: "\"\\/", count: 1000),
    "a" + String(repeating: "\u{301}", count: 4000), String(repeating: family, count: 500),
    String(repeating: "\u{0}\u{1}\n\t", count: 800)]
var liveLargestPayload = 0
for kind in liveFixtureKinds {
    for text in adversarialTexts {
        var state = liveFixture(kind)
        state.title = text
        state.subtitle = text
        state.value = text
        state.secondaryValue = text
        state.kind = kind
        state.detailItems = (0..<20).map { LiveActivityDetail(label: String($0) + text, value: text, isTimeSensitive: true) }
        state.progress = .nan
        state.staleAfter = Date(timeIntervalSinceReferenceDate: .infinity)
        let bounded = state.boundedText()
        let data = try liveEncoder.encode(bounded)
        liveLargestPayload = max(liveLargestPayload, data.count)
        precondition(data.count <= LiveActivityContentState.payloadBudget)
        precondition((bounded.detailItems?.count ?? 0) <= LiveActivityContentState.maximumDetails)
        precondition(bounded.progress == nil && bounded.staleAfter == nil)
        let decoded = try JSONDecoder().decode(LiveActivityContentState.self, from: data)
        precondition(decoded == bounded)
        precondition(bounded.boundedText() == bounded)
    }
}
var invalidDates = liveFixture("custom")
invalidDates.updatedAt = Date(timeIntervalSinceReferenceDate: .nan)
invalidDates.startDate = Date(timeIntervalSinceReferenceDate: .infinity)
invalidDates.endDate = Date(timeIntervalSinceReferenceDate: -.infinity)
invalidDates.progress = 10
let safeDates = invalidDates.boundedText()
precondition(safeDates.updatedAt == .distantPast && safeDates.startDate == nil && safeDates.endDate == nil && safeDates.progress == 1)
let safeDateBytes = try liveEncoder.encode(safeDates).count
precondition(safeDateBytes <= 3200)
print("Live activity payload: nine sources, old JSON, detail migration, empty fields, Unicode/escaping/nonfinite values passed; maximum \(liveLargestPayload) bytes")

var timedState = liveFixture("nextCourse")
timedState.startDate = Date(timeIntervalSinceReferenceDate: 200)
timedState.endDate = Date(timeIntervalSinceReferenceDate: 300)
timedState.countdownTarget = "start"
timedState.secondaryValue = "即将开始"
timedState.phase = "upcoming"
timedState.detailItems = [LiveActivityDetail(label: "教师", value: "合成教师"),
    LiveActivityDetail(label: "后续", value: "合成下一项", isTimeSensitive: true)]
precondition(timedState.freshnessDeadline == timedState.startDate)
precondition(timedState.displaySecondary(isStale: true) == nil)
precondition(timedState.visibleDetails(isStale: true).map(\.label) == ["教师"])
precondition(timedState.displayValue(isStale: true) == "待更新")
timedState.updatedAt = Date(timeIntervalSinceReferenceDate: 220)
timedState.phase = "ongoing"
timedState.countdownTarget = "end"
precondition(timedState.freshnessDeadline == timedState.endDate)
timedState.staleAfter = Date(timeIntervalSinceReferenceDate: 250)
precondition(timedState.freshnessDeadline == timedState.staleAfter)
for kind in ["nextCourse", "planner", "dayOverview", "assignments"] {
    var finishedState = liveFixture(kind)
    finishedState.title = "已结束或已完成"
    finishedState.subtitle = "今天事项已结束"
    finishedState.phase = "finished"
    precondition(!finishedState.displayTitle(isStale: true).contains("已结束"))
    precondition(finishedState.displaySubtitle(isStale: true) == nil)
    precondition(finishedState.displayValue(isStale: true) == "待更新")
}
var plainCustom = liveFixture("custom")
precondition(plainCustom.freshnessDeadline == nil)
plainCustom.staleAfter = Date(timeIntervalSinceReferenceDate: 120)
precondition(plainCustom.freshnessDeadline == plainCustom.staleAfter)
for kind in liveFixtureKinds {
    var destination = liveFixture(kind)
    destination.destinationPath = "https://untrusted.invalid"
    precondition(destination.destination.scheme == "neulumen")
    precondition(!destination.destination.absoluteString.contains("untrusted"))
}
precondition(liveFixture("academicOverview").destination.absoluteString == "neulumen://activity/learning?section=grades")
print("Live activity freshness: start/end/custom boundaries, stale labels/counts and destination allowlist passed")
precondition(LiveActivityInlineSymbols.parts("地点 {sf:mappin.and.ellipse} A101") == [.text("地点 "), .symbol("mappin.and.ellipse"), .text(" A101")])
precondition(LiveActivityInlineSymbols.parts("{sf:not.allowed} {sf:bolt.fill}") == [.text("{sf:not.allowed} "), .symbol("bolt.fill")])
precondition(LiveActivityInlineSymbols.parts("{sf:https://example.invalid/x}") == [.text("{sf:https://example.invalid/x}")])
precondition(LiveActivityTemplate.dependencies(in: ["{sf:creditcard.fill} {card}"]) == ["card"])
print("Custom SF Symbols: whitelisted inline icons, literal unknown tokens and independent data variables passed")

for width in [CGFloat(220), 280, 330, 350, 370] {
    for labelWidth in [CGFloat(33), 60, 120, 240] {
        for timerWidth in [CGFloat(70), 108, 180, 360, 600] {
            let plan = LiveActivityLayoutMetrics.metricPlan(width: width,
                label: CGSize(width: labelWidth, height: 14), value: CGSize(width: timerWidth, height: 24))
            precondition(plan.size.width == width && plan.size.height > 0)
            for rect in [plan.label, plan.value] {
                precondition(rect.minX >= 0 && rect.minY >= 0 && rect.maxX <= width && rect.maxY <= plan.size.height)
            }
            precondition(!plan.label.intersects(plan.value))
            if !plan.stacked { precondition(plan.label.width == min(width, labelWidth)) }
            else { precondition(plan.value.width == width) }
        }
    }
}
precondition(LiveActivityLayoutMetrics.detailColumns(width: 330, accessibility: false) == 2)
precondition(LiveActivityLayoutMetrics.detailColumns(width: 370, accessibility: true) == 1)
precondition(LiveActivityLayoutMetrics.expandedContentHeight + LiveActivityLayoutMetrics.expandedReservedHeight == 160)
print("Live activity geometry: 100 real-policy width/label/timer plans are bounded, nonoverlapping; 100pt lower-region / 160pt full-island budget and accessibility reflow passed")
// END standalone presentation checks

let detailedCourse = CourseOccurrence(date: date(12), slot: CourseSlot(weekday: 4,
    startMinutes: 630, endMinutes: 730, name: "合成课程", room: "合成教室", teacher: "合成教师"))
let detailedSchedule = LiveActivitySchedule.snapshot([detailedCourse, occurrence(12, 840, 940, "合成后续")],
    from: date(12), to: date(13), at: date(12, 9), portalLoaded: true, calendar: calendar)
let courseDetails = detailedSchedule.expandedDetails(for: detailedSchedule.next!, at: date(12, 9), calendar: calendar)
precondition(courseDetails.contains { $0.label == "教师" && $0.value == "合成教师" })
precondition(courseDetails.contains { $0.label == "周节" && $0.value.contains("第3–4节") })
precondition(courseDetails.contains { $0.label == "当天" && $0.value.contains("2 项") })
precondition(courseDetails.contains { $0.label == "后续" && $0.isTimeSensitive == true })
let manualDetails = local.expandedDetails(for: local.next!, at: night, note: "合成备注", calendar: calendar)
precondition(manualDetails.contains { $0.label == "备注" && $0.value == "合成备注" })
precondition(!manualDetails.contains { $0.label == "教师" || $0.label == "周节" })
let irregular = LiveActivitySchedule.interval(for: occurrence(12, 613, 644))!
let irregularDetails = detailedSchedule.expandedDetails(for: irregular, at: date(12, 9), calendar: calendar)
precondition(!irregularDetails.contains { $0.label == "周节" && $0.value.contains("节") })
print("Live activity metadata: teacher/room/exact periods/day counts/next event, manual notes and non-fabricated periods passed")

// Real production portal-count constructor -> same fact rows used by Repository.
let missingNetCounts = NetUsageInfo.fromPortal(balance: 20, bytes: 1024, seconds: nil, times: nil)
precondition(!missingNetCounts.secondsFromPortal && !missingNetCounts.timesFromPortal)
precondition(!missingNetCounts.usageFacts.contains { $0.0 == "在线时长" || $0.0 == "本月连接" })
let zeroNetCounts = NetUsageInfo.fromPortal(balance: 20, bytes: 0, seconds: 0, times: 0)
precondition(zeroNetCounts.flowFromPortal && zeroNetCounts.secondsFromPortal && zeroNetCounts.timesFromPortal)
precondition(zeroNetCounts.usageFacts.contains { $0.0 == "在线时长" && $0.1 == "0小时0分" })
precondition(zeroNetCounts.usageFacts.contains { $0.0 == "本月连接" && $0.1 == "0 次" })
let partialNetCounts = NetUsageInfo.fromPortal(balance: 20, bytes: nil, seconds: 3600, times: nil)
precondition(!partialNetCounts.flowFromPortal && partialNetCounts.secondsFromPortal && !partialNetCounts.timesFromPortal)
precondition(partialNetCounts.usageFacts.contains { $0.0 == "在线时长" && $0.1 == "1小时0分" })
precondition(!partialNetCounts.usageFacts.contains { $0.0 == "本月连接" })
let invalidNetCounts = NetUsageInfo.fromPortal(balance: 20, bytes: -1, seconds: -1, times: -1)
precondition(!invalidNetCounts.flowFromPortal && !invalidNetCounts.secondsFromPortal && !invalidNetCounts.timesFromPortal)
precondition(!invalidNetCounts.usageFacts.contains { $0.0 == "在线时长" || $0.0 == "本月连接" })
precondition(Int64(exactly: Double.nan) == nil && Int64(exactly: Double.infinity) == nil && Int64(exactly: 1.5) == nil)
print("Network usage: production presence/fact path preserves missing, real zero, partial and invalid counters")

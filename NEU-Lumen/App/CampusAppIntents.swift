import AppIntents
import Foundation

enum CampusShortcutPage: String, AppEnum {
    case schedule, assignments, card, exams
    case academic, payment, vpn, affairs, mail, news, agenda, downloads, analysis, map, library, telephone

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "校园页面"
    static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .schedule: .init(title: "课表", synonyms: ["课程表", "今天的课表"]),
        .assignments: .init(title: "作业", synonyms: ["作业列表"]),
        .card: .init(title: "校园卡", synonyms: ["一卡通"]),
        .exams: .init(title: "考试安排", synonyms: ["考试页面"]),
        .academic: .init(title: "学业查询", synonyms: ["教务查询"]),
        .payment: .init(title: "缴费大厅", synonyms: ["生活缴费"]),
        .vpn: .init(title: "WebVPN", synonyms: ["校内资源"]),
        .affairs: "办事大厅",
        .mail: .init(title: "学校邮箱", synonyms: ["校园邮箱"]),
        .news: .init(title: "校园资讯", synonyms: ["校园新闻"]),
        .agenda: "校园日程",
        .downloads: "下载中心",
        .analysis: "成绩分析",
        .map: .init(title: "校园地图", synonyms: ["校园导航"]),
        .library: "图书馆",
        .telephone: .init(title: "校内电话簿", synonyms: ["校园电话簿"])
    ]

    var url: URL {
        let path = switch self {
        case .schedule: "course"
        case .assignments: "learning?section=assignments"
        case .card: "card"
        case .exams: "exams"
        case .academic, .payment, .vpn, .affairs, .mail, .news, .agenda, .downloads,
             .analysis, .map, .library, .telephone:
            "services?native=\(rawValue)"
        }
        return URL(string: "neulumen://activity/" + path)!
    }
}

struct OpenCampusPageIntent: OpenIntent {
    static let title: LocalizedStringResource = "打开校园页面"
    static let description = IntentDescription("在 NEU-Lumen 中打开课表、作业、考试、校园卡或任一原生校园服务。")

    @Parameter(title: "校园页面", requestValueDialog: "想打开哪个校园页面？")
    var target: CampusShortcutPage

    @Dependency private var environment: AppEnvironment

    static var parameterSummary: some ParameterSummary {
        Summary("打开 \(\.$target)")
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        try Task.checkCancellation()
        environment.pendingActivityURL = target.url
        return .result()
    }
}

enum CampusShortcutQuery: String, AppEnum {
    case nextCourse, today, assignments, exams

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "校园信息"
    static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .nextCourse: .init(title: "下一节课", synonyms: ["下节课", "下一节课程"]),
        .today: .init(title: "今日课表", synonyms: ["今天有哪些课", "今天的课表"]),
        .assignments: .init(title: "待交作业", synonyms: ["未完成作业", "任务截止时间"]),
        .exams: .init(title: "近期考试", synonyms: ["下一场考试", "考试时间"])
    ]
}

struct ReadCampusInformationIntent: AppIntent {
    static let title: LocalizedStringResource = "查询校园信息"
    static let description = IntentDescription("从当前账号已同步的数据查询课程、作业和考试。")
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresLocalDeviceAuthentication

    @Parameter(title: "校园信息", requestValueDialog: "想查询哪项校园信息？")
    var information: CampusShortcutQuery

    @Dependency private var environment: AppEnvironment

    static var parameterSummary: some ParameterSummary {
        Summary("查询 \(\.$information)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        try Task.checkCancellation()
        if environment.session.phase == .booting { throw CampusShortcutError.sync }
        guard environment.session.phase == .loggedIn else { throw CampusShortcutError.signIn }
        let repository = environment.repository
        guard repository.hasCurrentLiveActivityAccount else { throw CampusShortcutError.sync }

        // Main-actor reads stay in the verified account epoch and never restore,
        // switch, or refresh sessions on behalf of the calling system surface.
        let now = Date()
        let result: String
        switch information {
        case .nextCourse:
            guard let schedule = repository.campusWidgetSnapshot(now: now)?.schedule,
                  schedule.loadedDays.contains(CampusWidgetSnapshot.schoolCalendar.startOfDay(for: now)) else {
                throw CampusShortcutError.schedule
            }
            if let course = schedule.courses.first(where: { $0.start > now }) {
                result = "已同步课表中，下一节是\(Self.courseText(course, dateFormat: "M月d日 HH:mm"))。"
            } else {
                result = "已同步课表中暂无后续课程。"
            }
        case .today:
            let calendar = CampusWidgetSnapshot.schoolCalendar
            let day = calendar.startOfDay(for: now)
            guard let schedule = repository.campusWidgetSnapshot(now: now)?.schedule,
                  schedule.loadedDays.contains(day),
                  let tomorrow = calendar.date(byAdding: .day, value: 1, to: day) else {
                throw CampusShortcutError.schedule
            }
            let courses = schedule.courses.filter { $0.start < tomorrow && $0.end > day }
            if courses.isEmpty {
                result = "今天没有课程。"
            } else {
                let list = courses.prefix(5).map {
                    Self.courseText($0, dateFormat: $0.start < day ? "M月d日 HH:mm" : "HH:mm")
                }.joined(separator: "。")
                let more = courses.count > 5 ? "打开课表查看其余课程。" : ""
                result = "今天有 \(courses.count) 项课表安排。\(list)。\(more)"
            }
        case .assignments:
            guard let data = repository.campusWidgetSnapshot(now: now)?.assignments else {
                throw CampusShortcutError.assignments
            }
            result = Self.assignmentText(data, now: now)
        case .exams:
            guard let term = repository.academicTerms.first(where: \.current) ?? repository.academicTerms.first,
                  DataFreshness.isFresh(repository.academicExamsDate(term: term.code), for: CampusWidgetSnapshot.freshness, now: now) else {
                throw CampusShortcutError.exams
            }
            result = Self.examText(repository.academicExams(term: term.code), now: now)
        }
        return .result(value: result, dialog: "\(result)")
    }

    private static func courseText(_ course: CampusWidgetSnapshot.Course, dateFormat: String) -> String {
        let room = course.room.isEmpty ? "" : "，地点 \(course.room)"
        return "\(course.title)，\(dateText(course.start, format: dateFormat))\(room)"
    }

    private static func assignmentText(_ assignments: CampusWidgetSnapshot.Assignments, now: Date) -> String {
        let completeness = assignments.isPartial ? "部分平台未同步。" : ""
        guard assignments.pendingCount > 0 else {
            return "已同步平台中没有待交作业。\(completeness)"
        }
        let visible = assignments.items.prefix(3).map { item in
            guard let deadline = item.deadline else { return "\(item.title)，截止时间未读取" }
            let time = dateText(deadline, format: "M月d日 HH:mm")
            let status = deadline <= now ? "已截止" : "截止"
            return "\(item.title)，\(time)\(status)"
        }.joined(separator: "。")
        let summary = "已同步 \(assignments.pendingCount) 项待交作业。"
        return summary + (visible.isEmpty ? "" : visible + "。") + completeness
    }

    private static func examText(_ exams: [AcademicExam], now: Date) -> String {
        let next = exams.compactMap { exam -> (AcademicExam, Date)? in
            guard let start = exam.start, start >= now else { return nil }
            return (exam, start)
        }.min { $0.1 < $1.1 }
        let hasUnscheduled = exams.contains { $0.start == nil }
        guard let (exam, start) = next else {
            return hasUnscheduled ? "部分考试的具体时间待确认，请打开考试安排查看。" : "已同步的本学期考试中暂无后续安排。"
        }
        let location = exam.place.isEmpty ? "" : "，地点 \(exam.place)"
        let remainder = hasUnscheduled ? "另有考试时间待确认，请在考试安排中查看。" : ""
        return "下一场已确定时间的考试是\(exam.title)，\(dateText(start, format: "M月d日 HH:mm"))\(location)。\(remainder)"
    }

    private static func dateText(_ date: Date, format: String) -> String {
        LiveActivityDataPolicy.dateText(date, format: format, calendar: CampusWidgetSnapshot.schoolCalendar)
    }
}

struct CampusAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: OpenCampusPageIntent(), phrases: [
            "用 \(.applicationName) 打开\(\.$target)",
            "在 \(.applicationName) 打开校园页面"
        ], shortTitle: "打开校园页面", systemImageName: "arrow.up.forward.app")
        AppShortcut(intent: ReadCampusInformationIntent(), phrases: [
            "用 \(.applicationName) 查询\(\.$information)",
            "在 \(.applicationName) 查询校园信息"
        ], shortTitle: "查询校园信息", systemImageName: "list.bullet.rectangle")
    }
}

private enum CampusShortcutError: Error, CustomLocalizedStringResourceConvertible {
    case signIn, sync, schedule, assignments, exams

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .signIn: "请打开 NEU-Lumen 并登录校园账号。"
        case .sync: "请打开 NEU-Lumen 同步当前账号。"
        case .schedule: "请在 NEU-Lumen 中打开课表并同步。"
        case .assignments: "请在 NEU-Lumen 中打开作业页并同步。"
        case .exams: "请在 NEU-Lumen 中打开考试安排并同步。"
        }
    }
}

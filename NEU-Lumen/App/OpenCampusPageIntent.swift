import AppIntents
import Foundation

enum CampusShortcutPage: String, AppEnum {
    case schedule, todaySchedule, assignments, card, exams
    case academic, payment, vpn, affairs, mail, news, agenda, downloads, analysis, map, library, telephone

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "校园页面"
    static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .schedule: .init(title: "课表", synonyms: ["课程表"]),
        .todaySchedule: .init(title: "今日课表", synonyms: ["今天的课表"]),
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
        case .todaySchedule: "course?today=1"
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

/// OpenIntent runs in the foreground app. The extension needs the same intent declaration,
/// while only the app owns the state that applies the route.
@MainActor
final class CampusPageRouter {
    let open: @MainActor (URL) -> Void

    init(open: @escaping @MainActor (URL) -> Void) {
        self.open = open
    }
}

struct OpenCampusPageIntent: OpenIntent {
    static let title: LocalizedStringResource = "打开校园页面"
    static let description = IntentDescription("在 NEU-Lumen 中打开课表、作业、考试、校园卡或任一原生校园服务。")
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresLocalDeviceAuthentication

    @Parameter(title: "校园页面", requestValueDialog: "想打开哪个校园页面？")
    var target: CampusShortcutPage

    @Dependency private var router: CampusPageRouter

    init() {}

    init(target: CampusShortcutPage) {
        self.target = target
    }

    static var parameterSummary: some ParameterSummary {
        Summary("打开 \(\.$target)")
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        try Task.checkCancellation()
        router.open(target.url)
        return .result()
    }
}

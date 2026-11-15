import Foundation

enum CampusPaymentEntry {
    static let cardRecharge = URL(string: "https://pay.neu.edu.cn/scardrecharge51264Z006.html")!
    /// School project 414 / factory E039; never send electricity actions to the general portal.
    static let electricity = URL(string: "https://pay.neu.edu.cn/openPayElecPagesDbdx51414E039.html")!
    static func isElectricity(_ url: URL) -> Bool {
        url.scheme == "https" && url.host == "pay.neu.edu.cn" && url.path == electricity.path
    }
    static func resumableDestination(_ url: URL) -> URL? {
        [electricity, cardRecharge].first { $0 == url }
    }
}

enum HomeQuickServiceCount {
    static func normalized(_ value: Int) -> Int { value == 8 ? 8 : 4 }
}

enum NativeServicePosition {
    static func index(at x: Double, width: Double, count: Int) -> Int {
        guard x.isFinite, width.isFinite, width > 0, count > 0 else { return 0 }
        return min(count - 1, max(0, Int((min(width, max(0, x)) / width * Double(count)).rounded(.down))))
    }
}

/// Explicit native tools; this never rewrites PortalApp's school-provided destination.
enum NativeCampusService: String, CaseIterable, Identifiable, Codable, Hashable {
    case academic, payment, vpn, affairs, mail, news, agenda, downloads, analysis, map, library, telephone
    var id: String { rawValue }
    static let groups = ["学习与生活", "校园资源"]
    var group: String {
        switch self {
        case .academic, .payment, .affairs, .agenda, .analysis, .map: "学习与生活"
        case .mail, .news, .vpn, .downloads, .library, .telephone: "校园资源"
        }
    }
    var title: String {
        switch self {
        case .academic: "学业查询"
        case .payment: "缴费大厅"
        case .vpn: "WebVPN"
        case .affairs: "办事大厅"
        case .mail: "学校邮箱"
        case .news: "校园资讯"
        case .agenda: "校园日程"
        case .downloads: "下载中心"
        case .analysis: "成绩分析"
        case .map: "校园地图"
        case .library: "图书馆"
        case .telephone: "校内电话簿"
        }
    }
    var subtitle: String {
        switch self {
        case .academic: "课表、成绩、校历与培养计划"
        case .payment: "余额、用量、流水与校园缴费"
        case .vpn: "网络状态、认证与校内资源"
        case .affairs: "在办事项、处理进度与办事服务"
        case .mail: "文件夹、收件箱与邮件阅读"
        case .news: "资讯频道、搜索与往期新闻"
        case .agenda: "每日课程、本机日程与系统日历"
        case .downloads: "附件预览、分享与下载管理"
        case .analysis: "成绩分布、学期趋势与待公布记录"
        case .map: "校园地点、步行与 Pathly 楼内导航"
        case .library: "馆藏检索、借阅与图书续借"
        case .telephone: "部门、办公电话与办公地址"
        }
    }
    var symbol: String {
        switch self {
        case .academic: "graduationcap"
        case .payment: "creditcard"
        case .vpn: "network"
        case .affairs: "checklist"
        case .mail: "envelope"
        case .news: "newspaper"
        case .agenda: "calendar.badge.clock"
        case .downloads: "arrow.down.doc"
        case .analysis: "chart.bar.xaxis"
        case .map: "map"
        case .library: "books.vertical"
        case .telephone: "phone.bubble"
        }
    }
    var appID: String? {
        switch self { case .payment: "62"; case .affairs: "1"; case .mail: "121"; case .library: "21"; case .telephone: "91"; default: nil }
    }
    var fallbackURL: URL {
        let value: String
        switch self {
        case .academic: value = "https://jwxt.neu.edu.cn/jwapp/sys/homeapp/index.do"
        case .payment: value = "https://pay.neu.edu.cn/drCasLogin"
        case .vpn: value = "https://webvpn.neu.edu.cn/"
        case .affairs: value = "https://ehall.neu.edu.cn/db_portal/service_personal"
        case .mail: value = "https://mails.neu.edu.cn/coremail/cmcu_addon/dbdxsso.jsp"
        case .news: value = "https://neunews.neu.edu.cn/"
        case .agenda: value = "https://jwxt.neu.edu.cn/jwapp/sys/homeapp/index.do"
        case .analysis: value = "https://jwxt.neu.edu.cn/jwapp/sys/homeapp/index.do"
        case .map: value = "https://www.neu.edu.cn/zhxx1.htm"
        case .library: value = "https://portal.neu.edu.cn/tp_up/up/subgroup/gotoLibirarySystem"
        case .telephone: value = "https://plat.neu.edu.cn/telephone-directory/"
        case .downloads: value = "about:blank" // Local utility; never offers a school-page action.
        }
        return URL(string: value)!
    }
    func owns(host: String) -> Bool {
        switch self {
        case .academic: return host == "jwxt.neu.edu.cn"
        case .payment: return host == "pay.neu.edu.cn"
        case .vpn: return host == "webvpn.neu.edu.cn"
        case .affairs: return ["ehall.neu.edu.cn", "eone.neu.edu.cn"].contains(host)
        case .mail: return ["mails.neu.edu.cn", "mail.neu.edu.cn", "stu.neu.edu.cn", "imp.neu.edu.cn"].contains(host)
        case .news: return host == "neunews.neu.edu.cn"
        case .agenda: return host == "jwxt.neu.edu.cn"
        case .analysis: return host == "jwxt.neu.edu.cn"
        case .map: return false
        case .library: return ["portal.neu.edu.cn", "www.lib.neu.edu.cn", "lib.neu.edu.cn", "210.30.202.58"].contains(host)
        case .telephone: return host == "plat.neu.edu.cn"
        case .downloads: return false
        }
    }
    var hasSchoolPage: Bool { ![Self.downloads, .analysis, .map].contains(self) }
    func allowsNativeDocument(_ url: URL) -> Bool {
        guard url.user == nil, url.password == nil, let host = url.host?.lowercased(), owns(host: host) else { return false }
        if self == .library, url.scheme == "http", host == "210.30.202.58", url.port == 8991 {
            return url.path == "/F" || url.path.hasPrefix("/F/")
        }
        return url.scheme == "https" && (url.port == nil || url.port == 443)
    }

    func entryURL(apps: [PortalApp]) -> URL {
        for app in apps {
            guard let url = URL(string: app.entryUrl()), url.scheme == "https", url.user == nil, url.password == nil, url.port == nil || url.port == 443,
                  let host = url.host?.lowercased(), owns(host: host) else { continue }
            if appID == app.appId || app.name.localizedCaseInsensitiveContains(title) || self == .vpn { return url }
        }
        return fallbackURL
    }
}

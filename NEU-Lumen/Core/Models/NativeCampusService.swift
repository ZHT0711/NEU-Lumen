import Foundation

/// Explicit native tools; this never rewrites PortalApp's school-provided destination.
enum NativeCampusService: String, CaseIterable, Identifiable, Codable, Hashable {
    case academic, payment, vpn, affairs, mail
    var id: String { rawValue }
    var title: String {
        switch self {
        case .academic: "学业查询"
        case .payment: "缴费大厅"
        case .vpn: "WebVPN"
        case .affairs: "办事大厅"
        case .mail: "学校邮箱"
        }
    }
    var subtitle: String {
        switch self {
        case .academic: "课表、成绩、校历与培养计划"
        case .payment: "余额、用量、流水与校园缴费"
        case .vpn: "网络状态、认证与校内资源"
        case .affairs: "在办事项、处理进度与办事服务"
        case .mail: "文件夹、收件箱与邮件阅读"
        }
    }
    var symbol: String {
        switch self {
        case .academic: "graduationcap"
        case .payment: "creditcard"
        case .vpn: "network"
        case .affairs: "checklist"
        case .mail: "envelope"
        }
    }
    var appID: String? {
        switch self { case .payment: "62"; case .affairs: "1"; case .mail: "121"; default: nil }
    }
    var fallbackURL: URL {
        let value: String
        switch self {
        case .academic: value = "https://jwxt.neu.edu.cn/jwapp/sys/homeapp/index.do"
        case .payment: value = "https://pay.neu.edu.cn/drCasLogin"
        case .vpn: value = "https://webvpn.neu.edu.cn/"
        case .affairs: value = "https://ehall.neu.edu.cn/db_portal/service_personal"
        case .mail: value = "https://mails.neu.edu.cn/coremail/cmcu_addon/dbdxsso.jsp"
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
        }
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

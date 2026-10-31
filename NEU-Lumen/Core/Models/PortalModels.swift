import Foundation

/// 统一身份认证解析出的用户信息（来自门户首页 window.userInfoDSL）。
struct PortalUser: Equatable {
    let uid: String
    let name: String
    let sid: String
    let identity: String
    let department: String
    let email: String
    let avatarUrl: String

    static func fromInfoJson(_ j: [String: Any]) -> PortalUser {
        PortalUser(
            uid: j.str("uid"),
            name: j.str("name"),
            sid: j.str("xgh"),
            identity: j.str("identity"),
            department: j.str("depart"),
            email: j.str("email"),
            avatarUrl: j.str("avatar")
        )
    }
}

/// 校园资讯。
struct NewsItem: Identifiable, Hashable {
    let id: String
    let title: String
    let date: String
    let category: String
    let url: String
    let picUrl: String
}

/// 服务大厅里的门户应用。
struct PortalApp: Identifiable, Hashable {
    let name: String
    let appId: String
    let url: String
    let mobileUrl: String
    let iconUrl: String
    let desc: String
    let category: String
    let visits: Int

    var id: String { appId.isEmpty ? name : appId }

    /// 官方入口解析（与门户 Web 端一致）：移动端地址 → 应用地址 → mimipath 官方解析器。
    func entryUrl() -> String {
        if !mobileUrl.trimmingCharacters(in: .whitespaces).isEmpty { return withScheme(mobileUrl) }
        if !url.trimmingCharacters(in: .whitespaces).isEmpty { return withScheme(url) }
        if !appId.trimmingCharacters(in: .whitespaces).isEmpty {
            return "\(PortalClient.portalBase)/pages/mimipath/mimipath?appId=\(appId)"
        }
        return ""
    }
}

/// 办事动态（待办/在办事项）。
struct TodoItem: Identifiable, Hashable {
    let title: String
    let instance: String
    let node: String
    let percent: Int
    let time: String
    let url: String

    var id: String { "\(title)|\(instance)|\(time)" }
}

/// 首页数据条卡片（门户个人数据）。
struct DataCard: Identifiable, Hashable {
    let name: String
    let value: String

    var id: String { name }
}

/// 无协议地址补全：内网特征 → http，其余 → https。
func withScheme(_ raw: String) -> String {
    let u = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    if u.isEmpty { return u }
    if u.range(of: #"^[a-zA-Z][a-zA-Z0-9+.-]*://"#, options: .regularExpression) != nil { return u }
    let looksLikeIP = u.range(of: #"^\d{1,3}(\.\d{1,3}){3}"#, options: .regularExpression) != nil
    let firstSegment = u.split(separator: "/").first.map(String.init) ?? ""
    let hasPort = firstSegment.range(of: #":\d+"#, options: .regularExpression) != nil
    let intranet = looksLikeIP || hasPort || u.hasPrefix("10.")
    return (intranet ? "http://" : "https://") + u
}

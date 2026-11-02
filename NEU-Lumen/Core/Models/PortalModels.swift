import Foundation

/// 统一身份认证解析出的用户信息（来自门户首页 window.userInfoDSL）。
struct PortalUser: Equatable, Codable {
    let uid: String
    let name: String
    let sid: String
    let identity: String
    let department: String
    let email: String
    let avatarUrl: String

    static func fromInfoJson(_ j: [String: Any]) -> PortalUser {
        func value(_ key: String) -> String { j.str(key).trimmingCharacters(in: .whitespacesAndNewlines) }
        return PortalUser(
            uid: value("uid"),
            name: value("name"),
            sid: value("xgh"),
            identity: value("identity"),
            department: value("depart"),
            email: value("email"),
            avatarUrl: value("avatar")
        )
    }

    var hasProfile: Bool { !name.isEmpty || !sid.isEmpty }
    var hasCoreProfile: Bool { !name.isEmpty && !sid.isEmpty && !identity.isEmpty && !department.isEmpty }
    var displayName: String { name.isEmpty ? (sid.isEmpty ? "东大师生" : sid) : name }
    var identityDetails: String { [identity, department].filter { !$0.isEmpty }.joined(separator: " · ") }

    static let pending = PortalUser(uid: "", name: "", sid: "", identity: "", department: "", email: "", avatarUrl: "")

    func isSameAccount(as other: PortalUser) -> Bool {
        if !sid.isEmpty && !other.sid.isEmpty { return sid == other.sid }
        return !uid.isEmpty && !other.uid.isEmpty && uid == other.uid
    }

    func merging(_ newer: PortalUser) -> PortalUser {
        if (!uid.isEmpty && !newer.uid.isEmpty && uid != newer.uid)
            || (!sid.isEmpty && !newer.sid.isEmpty && sid != newer.sid) { return newer }
        func pick(_ old: String, _ next: String) -> String { next.isEmpty ? old : next }
        return PortalUser(uid: pick(uid, newer.uid), name: pick(name, newer.name), sid: pick(sid, newer.sid),
                          identity: pick(identity, newer.identity), department: pick(department, newer.department),
                          email: pick(email, newer.email), avatarUrl: pick(avatarUrl, newer.avatarUrl))
    }

    static func fromBrowserJSON(_ raw: String) -> PortalUser? {
        guard let data = raw.data(using: .utf8),
              let decoded = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) else { return nil }
        let object: [String: Any]?
        if let nested = decoded as? String, let nestedData = nested.data(using: .utf8) {
            object = (try? JSONSerialization.jsonObject(with: nestedData)) as? [String: Any]
        } else { object = decoded as? [String: Any] }
        guard let object else { return nil }
        let user = fromInfoJson(object)
        return user.hasProfile ? user : nil
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
struct PortalApp: Identifiable, Hashable, Codable {
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
    var destination: String = ""

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

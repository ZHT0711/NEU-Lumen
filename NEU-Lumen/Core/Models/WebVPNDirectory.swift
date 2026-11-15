import Foundation

enum WebVPNDirectoryError: LocalizedError, Equatable {
    case authentication, accountMismatch, invalidResponse
    var errorDescription: String? {
        switch self {
        case .authentication: "请完成学校 WebVPN 认证后刷新资源站点"
        case .accountMismatch: "WebVPN 与当前校园账号不一致，请重新认证"
        case .invalidResponse: "学校 WebVPN 目录返回异常，请稍后重试"
        }
    }
}

struct WebVPNResource: Identifiable, Hashable {
    let id: String
    let name: String
    let detail: String
    let originalURL: URL
    let gatewayURL: URL

    init?(json: [String: Any]) {
        let name = (json.str("name").isEmpty ? json.str("title") : json.str("name")).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, let original = URL(string: json.str("url")),
              ["http", "https"].contains(original.scheme?.lowercased() ?? ""),
              original.host != nil, original.user == nil, original.password == nil,
              let gateway = URL(string: json.str("redirect"), relativeTo: URL(string: "https://webvpn.neu.edu.cn/")!)?.absoluteURL,
              gateway.scheme == "https", gateway.host == "webvpn.neu.edu.cn",
              gateway.port == nil || gateway.port == 443, gateway.user == nil, gateway.password == nil,
              gateway.path.range(of: #"^/https?(?:-[0-9]+)?/[0-9a-f]+(?:/|$)"#, options: .regularExpression) != nil else { return nil }
        let rawID = json.str("id")
        // Query parameters can contain transient tokens; local preferences never store them.
        var identity = URLComponents(url: original, resolvingAgainstBaseURL: false)
        identity?.query = nil; identity?.fragment = nil
        id = rawID.isEmpty ? "recent:" + (identity?.string ?? original.host ?? name) : "resource:" + rawID
        self.name = String(name.prefix(180))
        detail = String((json.str("detail").isEmpty ? original.host ?? "" : json.str("detail")).prefix(300))
        originalURL = original
        gatewayURL = gateway
    }
}

struct WebVPNResourceGroup: Identifiable {
    let id: String
    let name: String
    let resources: [WebVPNResource]
}

struct WebVPNDirectory {
    let groups: [WebVPNResourceGroup]
    let recent: [WebVPNResource]
    var resources: [WebVPNResource] {
        var seen = Set<String>()
        return groups.flatMap(\.resources).filter { seen.insert($0.id).inserted }
    }

    static func validateIdentity(_ payload: Any, expected: String) throws {
        guard let value = payload as? [String: Any], let username = value["username"] as? String,
              !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw WebVPNDirectoryError.authentication }
        guard !expected.isEmpty, username.trimmingCharacters(in: .whitespacesAndNewlines) == expected.trimmingCharacters(in: .whitespacesAndNewlines) else {
            throw WebVPNDirectoryError.accountMismatch
        }
    }

    static func parse(groups payload: Any, recent recentPayload: Any) throws -> Self {
        guard let root = payload as? [String: Any], let rows = root["data"] as? [[String: Any]] else { throw WebVPNDirectoryError.invalidResponse }
        var groupIDs = Set<String>()
        let groups = rows.compactMap { row -> WebVPNResourceGroup? in
            guard row.str("type") != "bastion", let group = row["group"] as? [String: Any],
                  !group.str("group_name").isEmpty, let entries = row["resource"] as? [[String: Any]] else { return nil }
            let id = group.str("id")
            guard !id.isEmpty, groupIDs.insert(id).inserted else { return nil }
            var seen = Set<String>()
            return WebVPNResourceGroup(id: id, name: group.str("group_name"),
                resources: entries.compactMap(WebVPNResource.init).filter { seen.insert($0.id).inserted })
        }
        let entries = (recentPayload as? [String: Any])?["data"] as? [[String: Any]] ?? []
        var seen = Set<String>()
        let recent = entries.compactMap(WebVPNResource.init).filter { seen.insert($0.id).inserted }.prefix(20)
        return Self(groups: groups, recent: Array(recent))
    }
}

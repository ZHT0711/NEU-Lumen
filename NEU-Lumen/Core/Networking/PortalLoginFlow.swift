import Foundation

/// 浏览器登录必须把门户资料与真实 UA 连同 Cookie 一起交接。
struct WebLoginSession {
    let cookies: [HTTPCookie]
    let user: PortalUser?
    let userAgent: String
}

/// 网关首页不是一号通首页；先在浏览器中换票，再进入代理后的门户。
struct PortalLoginFlow {
    enum Action: Equatable {
        case wait
        case navigate(URL)
        case capture
    }

    private var gatewayAuthTried = false
    private var portalLandingTried = false

    static func isPersonalPortal(_ url: URL) -> Bool {
        guard url.scheme == "https" else { return false }
        if url.host == "personal.neu.edu.cn" {
            return url.path == "/portal" || url.path.hasPrefix("/portal/")
        }
        guard url.host == "webvpn.neu.edu.cn" else { return false }
        let prefix = URL(string: WebVPN.wrap(PortalClient.portalBase))!.path
        return url.path == prefix || url.path.hasPrefix(prefix + "/")
    }

    mutating func action(for url: URL) -> Action {
        guard url.scheme == "https", let host = url.host?.lowercased() else { return .wait }
        if Self.isPersonalPortal(url) { return .capture }
        guard host == "webvpn.neu.edu.cn" || host == "portal.neu.edu.cn" else { return .wait }
        if host == "webvpn.neu.edu.cn", !gatewayAuthTried {
            gatewayAuthTried = true
            return .navigate(URL(string: WebVPN.casService)!)
        }
        if !portalLandingTried {
            portalLandingTried = true
            let destination = gatewayAuthTried || host == "webvpn.neu.edu.cn"
                ? WebVPN.wrap(PortalClient.portalBase) : PortalClient.portalBase
            return .navigate(URL(string: destination)!)
        }
        // 学校仍返回网关拦截页时，交接已有会话，让 App 保留可用登录。
        return .capture
    }
}

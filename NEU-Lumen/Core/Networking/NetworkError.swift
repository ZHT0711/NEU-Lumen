import Foundation

/// 网络与业务错误。message 直接面向用户展示。
struct NetworkError: LocalizedError {
    let message: String
    var errorDescription: String? { message }

    /// 统一身份认证会话失效，需要重新登录。
    var isSessionExpired: Bool {
        message.contains("会话已失效")
            || message.contains("会话未能正常建立")
            || message.contains("登录信息已失效")
            || message.contains("请重新登录")
    }

    /// 把底层错误翻译成用户能看懂的提示。
    static func from(_ error: Error) -> NetworkError {
        if let e = error as? NetworkError { return e }
        if let urlError = error as? URLError {
            switch urlError.code {
            case .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed, .timedOut,
                 .networkConnectionLost, .notConnectedToInternet, .dataNotAllowed, .internationalRoamingOff:
                return NetworkError(message: "网络连接失败：请检查网络；校外访问部分校内系统可能需要校园网或 WebVPN")
            case .appTransportSecurityRequiresSecureConnection:
                return NetworkError(message: "系统安全策略拦截了不安全的连接")
            default:
                break
            }
        }
        return NetworkError(message: error.localizedDescription)
    }

    static func sessionExpired() -> NetworkError {
        NetworkError(message: "统一身份认证会话已失效，请重新登录")
    }
}

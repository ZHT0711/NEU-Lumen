import Foundation

/// 网络与业务错误。message 直接面向用户展示。
struct NetworkError: LocalizedError {
    let message: String
    var errorDescription: String? { message }

    /// 统一身份认证会话失效，需要重新登录。
    var isSessionExpired: Bool {
        message.contains("会话已失效") || message.contains("会话未能正常建立")
    }

    static func sessionExpired() -> NetworkError {
        NetworkError(message: "统一身份认证会话已失效，请重新登录")
    }
}

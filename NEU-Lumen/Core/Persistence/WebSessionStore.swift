import Foundation
import Security

/// 会话 Cookie 也可能没有 Expires；主动保存它们才能跨进程恢复网页登录。
/// 不修改学校给定的有效期，服务器明确要求重登时即清除快照。
struct SavedWebSession: Codable {
    struct Cookie: Codable {
        let name: String
        let value: String
        let domain: String
        let path: String
        let secure: Bool
        let httpOnly: Bool
        let expires: Date?

        init(_ cookie: HTTPCookie) {
            name = cookie.name; value = cookie.value; domain = cookie.domain
            path = cookie.path; secure = cookie.isSecure; httpOnly = cookie.isHTTPOnly
            expires = cookie.expiresDate
        }

        func restored(now: Date = Date()) -> HTTPCookie? {
            guard !value.isEmpty, expires.map({ $0 > now }) ?? true else { return nil }
            var properties: [HTTPCookiePropertyKey: Any] = [
                .name: name, .value: value, .domain: domain, .path: path,
            ]
            if secure { properties[.secure] = "TRUE" }
            if httpOnly { properties[HTTPCookiePropertyKey(rawValue: "HttpOnly")] = "TRUE" }
            if let expires { properties[.expires] = expires }
            return HTTPCookie(properties: properties)
        }
    }

    let user: PortalUser
    let userAgent: String
    let cookies: [Cookie]

    init(user: PortalUser, userAgent: String, cookies: [HTTPCookie]) {
        self.user = user; self.userAgent = userAgent
        self.cookies = cookies.map(Cookie.init)
    }

    func restoredCookies(now: Date = Date()) -> [HTTPCookie] {
        cookies.compactMap { $0.restored(now: now) }
    }
}

protocol WebSessionPersisting {
    func load() -> SavedWebSession?
    func save(_ session: SavedWebSession) throws
    func clear()
}

/// Cookie、UA、个人资料只进本机 Keychain，不写 UserDefaults 或项目文件。
struct KeychainWebSessionStore: WebSessionPersisting {
    var account = "active"

    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: "edu.neu.lumen.web-session",
         kSecAttrAccount as String: account]
    }

    func load() -> SavedWebSession? {
        var request = query
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(request as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return try? JSONDecoder().decode(SavedWebSession.self, from: data)
    }

    func save(_ session: SavedWebSession) throws {
        let data = try JSONEncoder().encode(session)
        let values: [String: Any] = [kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        var status = SecItemUpdate(query as CFDictionary, values as CFDictionary)
        if status == errSecItemNotFound {
            status = SecItemAdd(query.merging(values) { _, new in new } as CFDictionary, nil)
        }
        guard status == errSecSuccess else {
            throw NetworkError(message: "登录会话未能保存到本机钥匙串，重启后可能需要重新登录")
        }
    }

    func clear() { SecItemDelete(query as CFDictionary) }
}

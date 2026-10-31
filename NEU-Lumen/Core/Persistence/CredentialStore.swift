import Foundation
import Security

/// 统一身份认证凭据的本机安全存储（Keychain，Generic Password 双条目）。
enum CredentialStore {
    private static let service = "edu.neu.lumen.credentials"

    private static func baseQuery(_ account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    private static func set(_ account: String, _ value: String?) {
        SecItemDelete(baseQuery(account) as CFDictionary)
        guard let value, !value.isEmpty else { return }
        var attrs = baseQuery(account)
        attrs[kSecValueData as String] = Data(value.utf8)
        attrs[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(attrs as CFDictionary, nil)
    }

    private static func get(_ account: String) -> String? {
        var query = baseQuery(account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func save(username: String, password: String) {
        set("username", username)
        set("password", password)
    }

    static func load() -> (username: String, password: String)? {
        guard let username = get("username"), let password = get("password"),
              !username.isEmpty, !password.isEmpty else { return nil }
        return (username, password)
    }

    static func clear() {
        set("username", nil)
        set("password", nil)
    }

    static var hasPassword: Bool { get("password") != nil }
}

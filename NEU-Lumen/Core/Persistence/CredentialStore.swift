import Foundation
import Security

/// A username/password pair is one atomic Keychain record. Legacy two-item
/// records remain readable until the next successful save; never delete before update.
enum CredentialStore {
    private static let service = "edu.neu.lumen.credentials"
    private struct Record: Codable { let username: String; let password: String }

    private static func baseQuery(_ account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service, kSecAttrAccount as String: account]
    }

    private static func readData(_ account: String) -> (Data?, OSStatus) {
        var query = baseQuery(account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        return (status == errSecSuccess ? result as? Data : nil, status)
    }

    @discardableResult
    static func save(username: String, password: String) -> Bool {
        guard !username.isEmpty, !password.isEmpty,
              let data = try? JSONEncoder().encode(Record(username: username, password: password)) else { return false }
        let query = baseQuery("credentials-v2")
        let values: [String: Any] = [kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        var status = SecItemUpdate(query as CFDictionary, values as CFDictionary)
        if status == errSecItemNotFound {
            status = SecItemAdd(query.merging(values) { _, new in new } as CFDictionary, nil)
        }
        guard status == errSecSuccess else { return false }
        // The new complete record is durable before removing either legacy field.
        let usernameRemoved = remove("username")
        let passwordRemoved = remove("password")
        return usernameRemoved && passwordRemoved
    }

    static func load() -> (username: String, password: String)? {
        let (data, status) = readData("credentials-v2")
        if status == errSecSuccess {
            guard let data, let pair = try? JSONDecoder().decode(Record.self, from: data),
                  !pair.username.isEmpty, !pair.password.isEmpty else { return nil }
            return (pair.username, pair.password)
        }
        // A Keychain access failure is not permission to resurrect older credentials.
        guard status == errSecItemNotFound,
              let usernameData = readData("username").0, let passwordData = readData("password").0,
              let username = String(data: usernameData, encoding: .utf8),
              let password = String(data: passwordData, encoding: .utf8),
              !username.isEmpty, !password.isEmpty else { return nil }
        return (username, password)
    }

    private static func remove(_ account: String) -> Bool {
        let status = SecItemDelete(baseQuery(account) as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    @discardableResult
    static func clear() -> Bool {
        let pair = remove("credentials-v2")
        let username = remove("username")
        let password = remove("password")
        return pair && username && password
    }

    static var hasPassword: Bool { load() != nil }
}

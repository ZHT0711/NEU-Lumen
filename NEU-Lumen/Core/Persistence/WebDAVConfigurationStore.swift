import CryptoKit
import Foundation
import Security

/// Keep the WebDAV endpoint and credentials in one device-only record, separate from CAS credentials.
enum WebDAVConfigurationStore {
    private struct Record: Codable {
        let collectionURL: String
        let username: String
        let password: String
    }

    private enum StoreError: LocalizedError {
        case accountRequired, readFailed, saveFailed, clearFailed

        var errorDescription: String? {
            switch self {
            case .accountRequired: return "请先登录校园账号再配置 WebDAV。"
            case .readFailed: return "无法读取钥匙串中的 WebDAV 配置。"
            case .saveFailed: return "无法将 WebDAV 配置保存到钥匙串。"
            case .clearFailed: return "无法从钥匙串移除 WebDAV 配置。"
            }
        }
    }

    private static func query(for account: String) throws -> [String: Any] {
        guard !account.isEmpty else { throw StoreError.accountRequired }
        let fingerprint = SHA256.hash(data: Data(account.utf8)).map { String(format: "%02x", $0) }.joined()
        return [kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: "edu.neu.lumen.webdav-backup",
                kSecAttrAccount as String: "configuration-v1.\(fingerprint)"]
    }

    static func load(account: String) throws -> WebDAVConfiguration? {
        var query = try query(for: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data,
              let record = try? JSONDecoder().decode(Record.self, from: data),
              let configuration = try? WebDAVConfiguration(collectionURL: record.collectionURL,
                                                           username: record.username, password: record.password) else {
            throw StoreError.readFailed
        }
        return configuration
    }

    static func save(_ configuration: WebDAVConfiguration, account: String) throws {
        let query = try query(for: account)
        let record = Record(collectionURL: configuration.collectionURL.absoluteString,
                            username: configuration.username, password: configuration.password)
        guard let data = try? JSONEncoder().encode(record) else { throw StoreError.saveFailed }
        let changes: [String: Any] = [kSecValueData as String: data,
                                    kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
        var status = SecItemUpdate(query as CFDictionary, changes as CFDictionary)
        if status == errSecItemNotFound {
            status = SecItemAdd(query.merging(changes) { _, new in new } as CFDictionary, nil)
            if status == errSecDuplicateItem { status = SecItemUpdate(query as CFDictionary, changes as CFDictionary) }
        }
        guard status == errSecSuccess else { throw StoreError.saveFailed }
    }

    static func clear(account: String) throws {
        let query = try query(for: account)
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw StoreError.clearFailed }
    }
}

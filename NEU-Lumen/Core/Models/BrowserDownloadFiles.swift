import Foundation
import CryptoKit

/// Foundation-only disk boundary, shared by the app and offline macOS tests.
struct BrowserDownloadFiles {
    let root: URL
    private let manager = FileManager.default

    init(root: URL) { self.root = root }

    static func accountKey(_ account: String) -> String {
        SHA256.hash(data: Data(("NEU-Lumen.browser-downloads.v1\u{0}" + account).utf8))
            .map { String(format: "%02x", $0) }.joined()
    }

    func accountDirectory(_ key: String) throws -> URL {
        guard key.count == 64, key.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }) else {
            throw CocoaError(.fileReadInvalidFileName)
        }
        return root.appendingPathComponent(key, isDirectory: true)
    }

    func itemDirectory(_ id: UUID, account key: String) throws -> URL {
        try accountDirectory(key).appendingPathComponent(id.uuidString, isDirectory: true)
    }

    func fileURL(_ record: BrowserDownloadRecord, account key: String) throws -> URL {
        guard record.filename == BrowserDownloadNames.sanitize(record.filename) else {
            throw CocoaError(.fileReadInvalidFileName)
        }
        let directory = try itemDirectory(record.id, account: key)
        let url = directory.appendingPathComponent(record.filename, isDirectory: false)
        try rejectSymlink(root)
        try rejectSymlink(accountDirectory(key))
        try rejectSymlink(directory)
        try rejectSymlink(url)
        return url
    }

    func prepare(_ record: BrowserDownloadRecord, account key: String) throws -> URL {
        try secureDirectory(root)
        try secureDirectory(accountDirectory(key))
        let directory = try itemDirectory(record.id, account: key)
        // A UUID directory must be fresh; never overwrite an existing download.
        guard !manager.fileExists(atPath: directory.path) else { throw CocoaError(.fileWriteFileExists) }
        try secureDirectory(directory)
        return try fileURL(record, account: key)
    }

    func load(account key: String) throws -> BrowserDownloadManifest {
        let url = try accountDirectory(key).appendingPathComponent("manifest.json")
        try rejectSymlink(root)
        try rejectSymlink(accountDirectory(key))
        try rejectSymlink(url)
        guard manager.fileExists(atPath: url.path) else { return BrowserDownloadManifest(records: []) }
        return try BrowserDownloadManifest.decode(Data(contentsOf: url))
    }

    func save(_ records: [BrowserDownloadRecord], account key: String) throws {
        let data = try BrowserDownloadManifest(records: records).encoded()
        try secureDirectory(root)
        let directory = try accountDirectory(key)
        try secureDirectory(directory)
        let url = directory.appendingPathComponent("manifest.json")
        try rejectSymlink(url)
        #if os(iOS)
        try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        #else
        try data.write(to: url, options: .atomic)
        #endif
        try protect(url)
    }

    func remove(_ id: UUID, account key: String) throws {
        let directory = try itemDirectory(id, account: key)
        try rejectSymlink(root)
        try rejectSymlink(accountDirectory(key))
        try rejectSymlink(directory)
        if manager.fileExists(atPath: directory.path) { try manager.removeItem(at: directory) }
    }

    func finish(_ record: BrowserDownloadRecord, account key: String, requirePDF: Bool) throws -> Int64 {
        let url = try fileURL(record, account: key)
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard values.isRegularFile == true else { throw CocoaError(.fileReadCorruptFile) }
        if requirePDF {
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }
            guard try handle.read(upToCount: 5) == Data("%PDF-".utf8) else {
                throw BrowserDownloadValidationError.notPDF
            }
        }
        try protect(url)
        return Int64(values.fileSize ?? 0)
    }

    func protect(_ url: URL) throws {
        try manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        #if os(iOS)
        try manager.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
                                  ofItemAtPath: url.path)
        #endif
        var writable = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try writable.setResourceValues(values)
    }

    private func secureDirectory(_ url: URL) throws {
        try rejectSymlink(url)
        try manager.createDirectory(at: url, withIntermediateDirectories: true,
                                    attributes: [.posixPermissions: 0o700])
        #if os(iOS)
        try manager.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
                                  ofItemAtPath: url.path)
        #endif
        var writable = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try writable.setResourceValues(values)
    }

    private func rejectSymlink(_ url: URL) throws {
        let values = try? url.resourceValues(forKeys: [.isSymbolicLinkKey])
        if values?.isSymbolicLink == true { throw CocoaError(.fileReadNoPermission) }
    }
}

enum BrowserDownloadValidationError: Error { case notPDF }

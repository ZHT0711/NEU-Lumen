import Foundation
import CryptoKit

/// Account-scoped homework data. Authentication cookies are stored separately in Keychain.
struct AssignmentCacheStore {
    struct Snapshot: Codable {
        var cg: CGAssignmentReport?
        var cgUpdatedAt: Date?
        var reports: [LearningPlatform: LearningAssignmentReport]
        var updatedAt: [LearningPlatform: Date]
    }

    private let url: URL

    init(account: String) {
        let key = SHA256.hash(data: Data(account.utf8)).map { String(format: "%02x", $0) }.joined()
        url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Assignments", isDirectory: true).appendingPathComponent(key + ".json")
    }

    func load() -> Snapshot? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(Snapshot.self, from: data)
    }

    func save(_ snapshot: Snapshot) throws {
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var resource = directory
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try resource.setResourceValues(values)
        var options: Data.WritingOptions = [.atomic]
        #if os(iOS)
        options.insert(.completeFileProtectionUntilFirstUserAuthentication)
        #endif
        try JSONEncoder().encode(snapshot).write(to: url, options: options)
    }
}

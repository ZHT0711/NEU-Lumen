import Foundation
import CryptoKit

/// Only validated, query-stripped course snapshots; separate files for each account and selected plan.
struct AcademicPlanCacheStore {
    let account: String
    let planID: String
    var directory: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("NEU-Lumen/AcademicPlans", isDirectory: true)

    private var file: URL {
        let digest = SHA256.hash(data: Data((account + "\u{0}" + planID).utf8))
            .map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent(digest + ".json")
    }

    func load() -> AcademicPageSnapshot? {
        guard !account.isEmpty, !planID.isEmpty, let data = try? Data(contentsOf: file),
              let value = try? JSONDecoder().decode(AcademicPageSnapshot.self, from: data),
              value.account == account, value.planID == planID else { return nil }
        return value
    }

    func save(_ snapshot: AcademicPageSnapshot) throws {
        guard !account.isEmpty, !planID.isEmpty, snapshot.account == account, snapshot.planID == planID,
              snapshot.sourceURL.query == nil, snapshot.sourceURL.user == nil, snapshot.sourceURL.password == nil else {
            throw AcademicQueryError.accountMismatch
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var folder = directory
        var values = URLResourceValues(); values.isExcludedFromBackup = true
        try folder.setResourceValues(values)
        let data = try JSONEncoder().encode(snapshot)
        #if os(iOS)
        try data.write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        #else
        try data.write(to: file, options: .atomic)
        #endif
    }

    func clear() throws {
        if FileManager.default.fileExists(atPath: file.path) { try FileManager.default.removeItem(at: file) }
    }
}

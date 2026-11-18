import Foundation

/// Only the fields shown by the widgets cross the app group boundary.
struct CampusWidgetSnapshot: Codable, Equatable, Sendable {
    struct Course: Codable, Equatable, Identifiable, Sendable {
        let id: String
        let title: String
        let room: String
        let start: Date
        let end: Date
    }

    struct Schedule: Codable, Equatable, Sendable {
        let courses: [Course]
        let loadedDays: [Date]
        let expiresAt: Date
    }

    struct Assignment: Codable, Equatable, Identifiable, Sendable {
        let id: String
        let title: String
        let platform: String
        let deadline: Date?
    }

    struct Assignments: Codable, Equatable, Sendable {
        let pendingCount: Int
        let isPartial: Bool
        let items: [Assignment]
        let expiresAt: Date
    }

    let capturedAt: Date
    let schedule: Schedule?
    let assignments: Assignments?

    static let freshness: TimeInterval = 48 * 60 * 60
    private static let maximumBytes = 128 * 1024

    static var schoolCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return calendar
    }

    static var isSharingAvailable: Bool { fileURL != nil }

    private static var fileURL: URL? {
        #if os(iOS)
        let group = Bundle.main.object(forInfoDictionaryKey: "NEULumenWidgetAppGroup") as? String
            ?? "group.edu.neu.lumen.widgets"
        guard !group.isEmpty else { return nil }
        return FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group)?
            .appendingPathComponent("campus-widget-v1.json", isDirectory: false)
        #else
        return nil
        #endif
    }

    static func load() -> Self? {
        guard let fileURL else { return nil }
        return read(from: fileURL)
    }

    static func read(from url: URL) -> Self? {
        guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
              size <= maximumBytes,
              let data = try? Data(contentsOf: url), data.count <= maximumBytes else { return nil }
        return try? JSONDecoder().decode(Self.self, from: data)
    }

    /// Matching content keeps the original timestamp and does not spend a timeline reload.
    @discardableResult
    static func replace(_ snapshot: Self?) throws -> Bool {
        guard let fileURL else { return false }
        return try replace(snapshot, at: fileURL)
    }

    @discardableResult
    static func replace(_ snapshot: Self?, at url: URL) throws -> Bool {
        guard let snapshot, snapshot.schedule != nil || snapshot.assignments != nil else {
            do { try FileManager.default.removeItem(at: url); return true }
            catch let error as CocoaError where [.fileNoSuchFile, .fileReadNoSuchFile].contains(error.code) { return false }
        }
        if let old = read(from: url), old.schedule == snapshot.schedule, old.assignments == snapshot.assignments {
            return false
        }
        let data = try JSONEncoder().encode(snapshot)
        guard data.count <= maximumBytes else { throw CocoaError(.fileWriteOutOfSpace) }
        #if os(iOS)
        try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        #else
        try data.write(to: url, options: .atomic)
        #endif
        return true
    }
}

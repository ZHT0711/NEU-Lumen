import Foundation

struct PersonalBackup: Codable {
    let version: Int
    let savedAt: Date
    let settings: Settings
    let favoriteIDs: [String]
    let events: [PlannerEvent]

    struct Settings: Codable {
        let quickServiceCount: Int
        let campus: String?
        let semester: SemesterConfiguration?
        let smartHolidays: Bool
        let schoolDayOverrides: [String: SchoolDayOverride]
        let replacementDays: [String: String]
    }

    init(settings: Settings, favoriteIDs: [String], events: [PlannerEvent], savedAt: Date = Date()) {
        version = 1
        self.savedAt = savedAt
        self.settings = settings
        self.favoriteIDs = favoriteIDs
        self.events = events
    }

    static func decode(_ data: Data) throws -> Self {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        struct Header: Decodable { let version: Int }
        guard let header = try? decoder.decode(Header.self, from: data) else { throw BackupError.invalidFile }
        guard header.version == 1 else { throw BackupError.unsupportedVersion }
        guard let backup = try? decoder.decode(Self.self, from: data) else { throw BackupError.invalidFile }
        try backup.validate()
        return backup
    }

    func encoded() throws -> Data {
        try validate()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(self)
    }

    func mergingEvents(into local: [PlannerEvent]) -> [PlannerEvent] {
        let existing = Set(local.map(\.id))
        return local + events.filter { !existing.contains($0.id) }
    }

    private func validate() throws {
        guard [4, 8].contains(settings.quickServiceCount),
              settings.campus.map({ Campus(rawValue: $0) != nil }) ?? true,
              settings.semester?.isValid ?? true,
              Set(favoriteIDs).count == favoriteIDs.count,
              favoriteIDs.allSatisfy({ !$0.isEmpty }),
              Set(events.map(\.id)).count == events.count else { throw BackupError.invalidFile }

        let dates = Set(settings.schoolDayOverrides.keys).union(settings.replacementDays.keys)
            .union(settings.replacementDays.values).union(events.map(\.dateIso))
        guard dates.allSatisfy(Self.isValidDay),
              settings.replacementDays.allSatisfy({ target, source in
                  target != source && settings.schoolDayOverrides[target] == .normal
              }),
              events.allSatisfy({ event in
                  !event.id.isEmpty && !event.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                      && event.kind == "custom" && event.deletable
                      && (0..<1440).contains(event.startMinutes)
                      && ((event.startMinutes + 1)...1440).contains(event.endMinutes)
              }) else { throw BackupError.invalidFile }
    }

    private static func isValidDay(_ text: String) -> Bool {
        guard text.utf8.count == 10, let date = PortalDate.day(text) else { return false }
        return PortalDate.isoDay(date) == text
    }

    enum BackupError: LocalizedError {
        case invalidFile, unsupportedVersion, accountChanged, localWriteFailed

        var errorDescription: String? {
            switch self {
            case .invalidFile: "备份文件格式有误，或其中的设置与日程无效。"
            case .unsupportedVersion: "此备份由其他版本写入，请更新 NEU-Lumen 后重试。"
            case .accountChanged: "校园账号已变更。请重新打开 WebDAV 备份。"
            case .localWriteFailed: "日程未能写入本机。请检查存储空间后重试。"
            }
        }
    }
}

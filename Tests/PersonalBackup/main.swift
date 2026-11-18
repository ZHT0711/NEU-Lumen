import Foundation

func expectInvalid(_ operation: () throws -> Void) throws {
    do {
        try operation()
        preconditionFailure("Invalid personal backup was accepted")
    } catch PersonalBackup.BackupError.invalidFile {}
}

let settings = PersonalBackup.Settings(
    quickServiceCount: 8,
    campus: "hunnan",
    semester: .bundled,
    smartHolidays: false,
    schoolDayOverrides: ["2026-10-01": .normal, "2026-10-02": .rest],
    replacementDays: ["2026-10-01": "2026-09-28"]
)
let savedAt = Date(timeIntervalSince1970: 1_800_000_000)
let remoteOverlap = PlannerEvent(id: "shared", name: "远端标题", dateIso: "2026-11-24", startMinutes: 510, endMinutes: 555)
let remoteOnly = PlannerEvent(id: "remote", name: "远端新增", dateIso: "2026-11-27", startMinutes: 1439, endMinutes: 1440,
                              room: "活动室", note: "准备材料")
let original = PersonalBackup(settings: settings, favoriteIDs: ["service.2", "service.1"],
                              events: [remoteOverlap, remoteOnly], savedAt: savedAt)
let data = try original.encoded()
let restored = try PersonalBackup.decode(data)
precondition(restored.version == 1 && restored.savedAt == savedAt)
precondition(restored.settings.quickServiceCount == 8 && restored.settings.campus == "hunnan")
precondition(restored.settings.semester == .bundled && !restored.settings.smartHolidays)
precondition(restored.settings.schoolDayOverrides == settings.schoolDayOverrides)
precondition(restored.settings.replacementDays == settings.replacementDays)
precondition(restored.favoriteIDs == original.favoriteIDs && restored.events == original.events)
let reencoded = try restored.encoded()
precondition(data == reencoded, "Round-tripping should preserve the canonical backup")

let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
precondition(Set(json.keys) == ["version", "savedAt", "settings", "favoriteIDs", "events"])
let settingKeys = (json["settings"] as! [String: Any]).keys
precondition(Set(settingKeys) == ["quickServiceCount", "campus", "semester", "smartHolidays", "schoolDayOverrides", "replacementDays"])

var localOverlap = remoteOverlap
localOverlap.name = "保留本机改动"
var localOnly = remoteOverlap
localOnly.id = "local"
let merged = restored.mergingEvents(into: [localOverlap, localOnly])
precondition(merged == [localOverlap, localOnly, remoteOnly])
precondition(restored.mergingEvents(into: merged) == merged, "Repeated restore should not duplicate events")

let defaults = PersonalBackup.Settings(quickServiceCount: 4, campus: nil, semester: nil,
                                       smartHolidays: true, schoolDayOverrides: [:], replacementDays: [:])
let empty = try PersonalBackup(settings: defaults, favoriteIDs: [], events: []).encoded()
let emptyRoundTrip = try PersonalBackup.decode(empty)
precondition(emptyRoundTrip.favoriteIDs.isEmpty && emptyRoundTrip.events.isEmpty)
precondition(emptyRoundTrip.settings.campus == nil && emptyRoundTrip.settings.semester == nil)

do {
    _ = try PersonalBackup.decode(Data(#"{"version": 2}"#.utf8))
    preconditionFailure("A future backup version was accepted")
} catch PersonalBackup.BackupError.unsupportedVersion {}
try expectInvalid { _ = try PersonalBackup.decode(Data("not a backup".utf8)) }
try expectInvalid {
    _ = try PersonalBackup(settings: settings, favoriteIDs: ["service.1", "service.1"], events: []).encoded()
}
try expectInvalid {
    _ = try PersonalBackup(settings: settings, favoriteIDs: [], events: [remoteOverlap, remoteOverlap]).encoded()
}

for invalidEvent in [
    PlannerEvent(id: "badDate", name: "无效日期", dateIso: "2026-02-30", startMinutes: 510, endMinutes: 555),
    PlannerEvent(id: "badTime", name: "无效时间", dateIso: "2026-11-24", startMinutes: 610, endMinutes: 555),
    PlannerEvent(id: "overflow", name: "超界时间", dateIso: "2026-11-24", startMinutes: .max, endMinutes: .max),
    PlannerEvent(id: "emptyName", name: " \n", dateIso: "2026-11-24", startMinutes: 510, endMinutes: 555),
    PlannerEvent(id: "closed", name: "非自建日程", dateIso: "2026-11-24", startMinutes: 510, endMinutes: 555, deletable: false),
] {
    try expectInvalid { _ = try PersonalBackup(settings: settings, favoriteIDs: [], events: [invalidEvent]).encoded() }
}

var malformed = json
var changedSettings = json["settings"] as! [String: Any]
changedSettings["replacementDays"] = ["2026-10-02": "2026-09-28"]
malformed["settings"] = changedSettings
try expectInvalid { _ = try PersonalBackup.decode(JSONSerialization.data(withJSONObject: malformed)) }
var changedEvents = json["events"] as! [[String: Any]]
changedEvents[0]["kind"] = "exam"
malformed = json
malformed["events"] = changedEvents
try expectInvalid { _ = try PersonalBackup.decode(JSONSerialization.data(withJSONObject: malformed)) }

print("PASS: Personal backup versioning, payload fields, validation, round-trip and idempotent schedule merge")

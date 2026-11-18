import Foundation

func require(_ condition: Bool, _ message: String) {
    guard condition else { fatalError(message) }
}

func checkSharedFile() throws {
    let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: false)
    defer { try? FileManager.default.removeItem(at: temporary) }
    let file = temporary.appendingPathComponent("summary.json")

    let now = Date(timeIntervalSince1970: 1_797_635_820) // 2026-12-18 23:17 UTC
    let calendar = CampusWidgetSnapshot.schoolCalendar
    let schoolDay = calendar.startOfDay(for: now)
    require(calendar.component(.day, from: now) == 19, "Timetable follows university time across date boundaries")
    require(calendar.timeZone.secondsFromGMT(for: schoolDay) == 8 * 3600, "Campus civil day is UTC+8")
    require(!(try CampusWidgetSnapshot.replace(nil, at: file)), "Nothing to withdraw before opt-in")

    let classes = CampusWidgetSnapshot.Schedule(courses: [], loadedDays: [schoolDay], expiresAt: now.addingTimeInterval(60))
    let assignments = CampusWidgetSnapshot.Assignments(pendingCount: 1, isPartial: true, items: [
        .init(id: "assignment-0", title: "演示作业", platform: "演示平台", deadline: nil)
    ], expiresAt: now.addingTimeInterval(120))
    let snapshot = CampusWidgetSnapshot(capturedAt: now, schedule: classes, assignments: assignments)
    require(try CampusWidgetSnapshot.replace(snapshot, at: file), "First summary publishes")
    require(CampusWidgetSnapshot.read(from: file) == snapshot, "Valid snapshot round-trips")
    require(CampusWidgetSnapshot.read(from: file)?.schedule?.loadedDays == [schoolDay], "A known empty day remains distinct from unread data")

    let later = CampusWidgetSnapshot(capturedAt: now.addingTimeInterval(1), schedule: classes, assignments: assignments)
    require(!(try CampusWidgetSnapshot.replace(later, at: file)), "Identical data does not spend an extra timeline reload")
    require(CampusWidgetSnapshot.read(from: file)?.capturedAt == now, "Rewriting identical data does not claim new freshness")
    require(try CampusWidgetSnapshot.replace(.init(capturedAt: now, schedule: nil, assignments: assignments), at: file),
            "Loss of stale timetable data replaces the entire atomic file")
    require(CampusWidgetSnapshot.read(from: file)?.schedule == nil, "Unavailable timetable decodes as nil")

    try Data("invalid".utf8).write(to: file)
    require(CampusWidgetSnapshot.read(from: file) == nil, "Corrupted snapshots fail closed")
    require(try CampusWidgetSnapshot.replace(snapshot, at: file), "A valid summary replaces unreadable contents")
    require(try CampusWidgetSnapshot.replace(nil, at: file), "Opt-out or logout withdraws both sections")
    require(CampusWidgetSnapshot.read(from: file) == nil, "No personal data remains readable after withdrawal")
}

try checkSharedFile()
print("Campus widget snapshot checks passed")

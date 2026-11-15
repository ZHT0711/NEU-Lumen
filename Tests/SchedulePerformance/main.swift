import Foundation

enum PortalClient { static let portalBase = "https://personal.neu.edu.cn/portal" }

func day(_ value: String) -> Date { PortalDate.day(value)! }
let calendar = Calendar.current
let sunday = day("2026-09-27")
let first = day("2026-09-28")
let end = day("2026-10-05")
func item(_ date: Date, _ index: Int) -> CourseOccurrence {
    let start = Semester.periodStarts[index % 10]
    return CourseOccurrence(date: date, slot: CourseSlot(weekday: PlannerEvent.mondayBasedWeekday(date),
        startMinutes: start, endMinutes: start + 45, name: "课程\(index % 8)", room: "A\(index % 3)",
        teacher: "教师\(index % 2)", kind: index % 11 == 0 ? "exam" : "course"))
}

var raw: [Date: [CourseOccurrence]] = [:]
for week in -8..<10 {
    let start = calendar.date(byAdding: .day, value: week * 7, to: sunday)!
    raw[start] = (0..<7).flatMap { offset in
        (0..<24).map { item(calendar.date(byAdding: .day, value: offset, to: start)!, $0) }
    }
}
let all = raw.values.flatMap { $0 }
let mappings = [[:], ["2026-10-01": "2026-08-03"],
                ["2026-10-04": "2026-11-29", "2026-09-28": "2026-10-01"]]
for replacements in mappings {
    let weeks = ScheduleWeekSnapshot.portalWeeks(from: first, to: end, replacements: replacements)
    precondition(weeks.count <= 4, "Only target weeks and raw makeup source weeks are needed")
    let actual = HolidayRules.project(weeks.flatMap { raw[$0] ?? [] }, from: first, to: end, replacements: replacements).mergeConsecutive()
    let expected = HolidayRules.project(all, from: first, to: end, replacements: replacements).mergeConsecutive()
    precondition(actual == expected, "Narrowing the scan must preserve makeup and Sunday courses")
    let snapshot = ScheduleWeekSnapshot(sunday: sunday, occurrences: actual)
    precondition(snapshot.days.count == 7 && snapshot.days.first?.date == first && snapshot.days.last?.date == day("2026-10-04"))
    for column in snapshot.days {
        let legacy = TimetablePlacement.layout(expected, on: column.date)
        precondition(column.placements.map(\.occurrence) == legacy.map(\.occurrence))
        for (a, b) in zip(column.placements, legacy) {
            precondition(a.firstPeriod == b.firstPeriod && a.lastPeriod == b.lastPeriod && a.lane == b.lane && a.laneCount == b.laneCount)
        }
    }
}
let custom = PlannerEvent(id: "fixture", name: "日程", dateIso: "2026-09-28", startMinutes: 510, endMinutes: 555, room: "A101", note: "")
precondition(custom.toSlot() == custom.toSlot(on: first))

let cache = ScheduleWeekCache()
func key(_ offset: Int = 0, courses: Int = 1, holidays: Int = 1, planner: Int = 1, zone: String = "Asia/Shanghai") -> ScheduleWeekCache.Key {
    let date = calendar.date(byAdding: .day, value: offset * 7, to: sunday)!
    return .init(sunday: date, courses: [.init(sunday: date, revision: courses)], holidays: holidays, planner: planner, calendar: "gregorian", timeZone: zone)
}
var builds = 0
func build() -> ScheduleWeekSnapshot {
    builds += 1
    return ScheduleWeekSnapshot(sunday: sunday, occurrences: [])
}
_ = cache.value(for: key(), build: build)
for _ in 0..<1000 { _ = cache.value(for: key(), build: build) }
precondition(builds == 1, "Reopening a historical week must not recalculate layout")
for changed in [key(courses: 2), key(holidays: 2), key(planner: 2), key(zone: "UTC")] {
    _ = cache.value(for: changed, build: build)
}
precondition(builds == 5, "Course, holiday, planner and timezone changes must invalidate the snapshot")
cache.removeAll()
for offset in 0..<9 { _ = cache.value(for: key(offset), build: build) }
let beforeEviction = builds
_ = cache.value(for: key(), build: build)
precondition(builds == beforeEviction + 1, "Old projections are bounded to eight weeks")
cache.removeAll()
_ = cache.value(for: key(), build: build)
precondition(builds == beforeEviction + 2, "Account reset must clear snapshots")
print("PASS: bounded week scans, makeup/Sunday projection, identical layouts, revision invalidation, historical reuse and account reset")

// Optimized native microbenchmark of the previous redraw pipeline versus snapshot lookup.
// This measures data preparation, not device frame rate or a real account.
func milliseconds(_ operation: () -> Void) -> Double {
    let start = DispatchTime.now().uptimeNanoseconds
    operation()
    return Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
}
let benchmarkCache = ScheduleWeekCache()
func benchmarkReadKey() -> ScheduleWeekCache.Key {
    let start = calendar.date(byAdding: .day, value: 1, to: sunday)!
    let finish = calendar.date(byAdding: .day, value: 8, to: sunday)!
    let revisions = ScheduleWeekSnapshot.portalWeeks(from: start, to: finish, replacements: [:]).sorted().map {
        ScheduleWeekCache.WeekRevision(sunday: $0, revision: 1)
    }
    return .init(sunday: sunday, courses: revisions, holidays: 1, planner: 1,
        calendar: String(describing: calendar.identifier), timeZone: calendar.timeZone.identifier)
}
let benchmarkKey = benchmarkReadKey()
var checksum = 0
let iterations = 80
let legacyTime = milliseconds {
    for _ in 0..<iterations {
        let projected = HolidayRules.project(all, from: first, to: end, replacements: [:]).mergeConsecutive()
        for offset in 1...7 {
            checksum += TimetablePlacement.layout(projected, on: calendar.date(byAdding: .day, value: offset, to: sunday)!).count
        }
    }
}
let required = ScheduleWeekSnapshot.portalWeeks(from: first, to: end, replacements: [:])
let coldTime = milliseconds {
    _ = benchmarkCache.value(for: benchmarkKey) {
        ScheduleWeekSnapshot(sunday: sunday, occurrences: HolidayRules.project(required.flatMap { raw[$0] ?? [] }, from: first, to: end, replacements: [:]).mergeConsecutive())
    }
}
let warmTime = milliseconds {
    for _ in 0..<iterations {
        let value = benchmarkCache.value(for: benchmarkReadKey()) { preconditionFailure("Cache hit rebuilt the week") }
        checksum += value.days.reduce(0) { $0 + $1.placements.count }
    }
}
print(String(format: "BENCHMARK: %d cached weeks, %d raw rows; legacy %.3f ms/redraw, cold snapshot %.3f ms, warm snapshot %.6f ms/read; checksum %d",
    raw.count, all.count, legacyTime / Double(iterations), coldTime, warmTime / Double(iterations), checksum))

actor ReadGate {
    private(set) var calls = 0
    private var continuations: [CheckedContinuation<SystemAgendaReadResult, Never>] = []
    func read(_ query: SystemAgendaQuery) async -> SystemAgendaReadResult {
        calls += 1
        return await withCheckedContinuation { continuations.append($0) }
    }
    func finish(message: String? = nil) {
        let batch = continuations
        continuations.removeAll()
        for continuation in batch { continuation.resume(returning: SystemAgendaReadResult(message: message)) }
    }
}

func waitForCalls(_ gate: ReadGate, _ count: Int) async {
    for _ in 0..<1000 {
        if await gate.calls >= count { return }
        try? await Task.sleep(for: .milliseconds(1))
    }
    preconditionFailure("Reader never started")
}

@MainActor func testAgendaReads() async {
    let gate = ReadGate()
    var now = Date()
    let loader = SystemAgendaLoader(now: { now }, reader: { await gate.read($0) })
    func query(account: String = "a", events: Set<String> = ["one"]) -> SystemAgendaQuery {
        .init(account: account, start: first, end: end, events: events, reminders: [], excluded: [], timeZone: "Asia/Shanghai")
    }
    let initial = Task { await loader.load(query()) }
    await waitForCalls(gate, 1)
    let duplicate = Task { await loader.load(query()) }
    for _ in 0..<10 { await Task.yield() }
    let coalescedCalls = await gate.calls
    precondition(coalescedCalls == 1, "Concurrent reads of the same week must coalesce")
    // This main-actor code executes while the reader is suspended.
    await gate.finish()
    let initialResult = await initial.value
    let duplicateResult = await duplicate.value
    precondition(initialResult != nil && duplicateResult != nil)
    _ = await loader.load(query())
    let cachedCalls = await gate.calls
    precondition(cachedCalls == 1, "Tab revisit within 60 seconds must reuse the read")
    now = now.addingTimeInterval(61)
    let expired = Task { await loader.load(query()) }
    await waitForCalls(gate, 2)
    await gate.finish()
    _ = await expired.value
    let forced = Task { await loader.load(query(), force: true) }
    await waitForCalls(gate, 3)
    await gate.finish()
    _ = await forced.value
    let otherAccount = Task { await loader.load(query(account: "b")) }
    await waitForCalls(gate, 4)
    loader.invalidate()
    await gate.finish()
    let staleResult = await otherAccount.value
    precondition(staleResult == nil, "Logout/selection changes must reject in-flight results")
    let changed = Task { await loader.load(query(events: ["two"])) }
    await waitForCalls(gate, 5)
    await gate.finish(message: "fixture failure")
    let failure = await changed.value
    precondition(failure?.message != nil)
    let retry = Task { await loader.load(query(events: ["two"])) }
    await waitForCalls(gate, 6)
    await gate.finish()
    _ = await retry.value
    print("PASS: calendar read coalescing, TTL, manual refresh, selection/account invalidation, failure retry and main-actor responsiveness")
}
await testAgendaReads()

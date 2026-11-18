// App-only regression extension, appended to the disposable repository source by
// prepare_ui_validation.py. This file is never compiled into the downloadable IPA.
import UIKit

private actor ImageFixtureSource {
    private(set) var reads = 0

    func fetch(data: Data) async throws -> Data {
        reads += 1
        try await Task.sleep(for: .milliseconds(40))
        return data
    }
}

@MainActor
func verifyCampusImageCache() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    func makeCache() -> CampusImageCache {
        CampusImageCache(folder: "Images", maxPixels: 128, maxDownloadBytes: 100_000,
                         memoryBudget: 1_000_000, diskBudget: 1_000_000, cacheRoot: root)
    }
    let url = URL(string: "https://example.invalid/campus-icon.png")!
    let cache = makeCache()
    let source = ImageFixtureSource()
    let size = CGSize(width: 200, height: 150)
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    let icon = UIGraphicsImageRenderer(size: size, format: format).image { context in
        UIColor.blue.setFill()
        context.fill(CGRect(origin: .zero, size: size))
    }
    guard let data = icon.pngData() else { throw NetworkError(message: "Could not generate fixture image") }

    async let first = cache.image(at: url) { _ in try await source.fetch(data: data) }
    async let second = cache.image(at: url) { _ in try await source.fetch(data: data) }
    let (a, b) = await (first, second)
    guard let a, a === b, a.cgImage?.width == 128, a.cgImage?.height == 96,
          await source.reads == 1 else {
        throw NetworkError(message: "Service icon was not downsampled or fetched once")
    }
    let memory = await cache.image(at: url) { _ in throw URLError(.notConnectedToInternet) }
    let disk = await makeCache().image(at: url) { _ in throw URLError(.notConnectedToInternet) }
    guard memory === a, disk?.cgImage?.width == 128 else {
        throw NetworkError(message: "Service icon cache missed in memory or after reopening disk cache")
    }
    let otherURL = URL(string: "https://example.invalid/campus-icon.png?v=2")!
    let invalid = await cache.image(at: otherURL) { _ in Data("not an image".utf8) }
    let retry = await cache.image(at: otherURL) { _ in try await source.fetch(data: data) }
    guard invalid == nil, retry != nil, await source.reads == 2 else {
        throw NetworkError(message: "Invalid image was cached or the updated URL reused stale content")
    }
}

extension PortalRepository {
    func verifyDataReliability() async throws {
        func require(_ condition: Bool, _ message: String) throws {
            if !condition { throw NetworkError(message: message) }
        }
        let savedGeneration = accountGeneration
        defer { accountGeneration = savedGeneration }
        var attempts = 0
        do {
            _ = try await withRecovery { () async throws -> Int in
                attempts += 1
                self.accountGeneration = UUID()
                return 42
            }
            throw NetworkError(message: "Old account's successful first response accepted")
        } catch is CancellationError { }
        try require(attempts == 1, "Stale successful response retried")
        accountGeneration = savedGeneration
        let cancelled = Task { @MainActor in
            try await self.withRecovery { () async throws -> Int in
                withUnsafeCurrentTask { $0?.cancel() }
                return 42
            }
        }
        do {
            _ = try await cancelled.value
            throw NetworkError(message: "Cancelled successful operation accepted")
        } catch is CancellationError { }
        var gradeAttempts = 0
        do {
            _ = try await withRecovery(retryInterruptedRequest: false) { () async throws -> Int in
                gradeAttempts += 1
                throw URLError(.cancelled)
            }
            throw NetworkError(message: "Grade cancellation accepted as partial report")
        } catch let error as URLError where error.code == .cancelled { }
        try require(gradeAttempts == 1, "Cancelled grade query was replayed")
        let savedCache = weekCache, savedStates = weekStates
        defer { weekCache = savedCache; weekStates = savedStates }
        weekCache = [:]
        weekStates = [:]
        let sunday = LiveActivityDataPolicy.portalWeekStart(for: Date())
        let nextSunday = Calendar.current.date(byAdding: .day, value: 7, to: sunday)!
        weekStates[sunday] = .failed("fixture first week")
        weekStates[nextSunday] = .loaded
        weekCache[nextSunday] = []
        try require(displayWeekState(starting: sunday) == .failed("fixture first week"), "Second week's success hid first week's error")
        try require(!displayWeekIsLoaded(starting: sunday), "Incomplete schedule enabled calendar export")
        weekStates[sunday] = .loaded
        weekCache[sunday] = []
        weekStates[nextSunday] = .failed("fixture second week")
        try require(displayWeekState(starting: sunday) == .failed("fixture second week"), "First week's success hid second week's error")
    }

    func verifyActivityBoundaries() throws {
        func require(_ condition: Bool, _ message: String) throws {
            if !condition { throw NetworkError(message: message) }
        }
        let suite = "NEULumen.ActivityBoundaries." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = DynamicIslandStore(defaults: defaults)
        store.kind = .custom
        store.customTitle = "纯文字"
        store.customSubtitle = "不依赖动态数据"
        let now = Date()
        try require(liveActivityState(store: store, now: now)?.staleAfter == nil, "Plain text unexpectedly expires")
        store.customSubtitle = "{time}"
        guard let clock = liveActivityState(store: store, now: now), let expires = clock.staleAfter else {
            throw NetworkError(message: "Clock variable did not carry an expiration")
        }
        try require(expires > now && expires <= now.addingTimeInterval(60), "Clock survives its minute boundary")
        let savedCard = cardUpdatedAt
        defer { cardUpdatedAt = savedCard }
        cardUpdatedAt = now.addingTimeInterval(-3600)
        store.customSubtitle = "{card}"
        try require(liveActivityState(store: store, now: now)?.staleAfter == now.addingTimeInterval(-1800), "Wallet template hides stale cache")
        let family = "👨‍👩‍👧‍👦"
        store.customTitle = String(repeating: family, count: 80)
        store.customSubtitle = String(repeating: family, count: 160)
        store.customValue = String(repeating: family, count: 32)
        guard let state = liveActivityState(store: store, now: now) else { throw NetworkError(message: "Custom account missing") }
        let data = try JSONEncoder().encode(state)
        try require(data.count <= 3200 && !state.title.isEmpty, "ZWJ text exceeded encoded payload budget")
        let roundTrip = try JSONDecoder().decode(NEULumenActivityAttributes.ContentState.self, from: data)
        try require(roundTrip == state, "Limited Unicode payload does not round-trip")
        var target = state
        target.startDate = now.addingTimeInterval(60)
        target.endDate = now.addingTimeInterval(3600)
        target.countdownTitle = "本地化文案变化"
        target.countdownTarget = "start"
        try require(target.countdownDate == target.startDate, "Countdown depends on translated label")
        target.countdownTarget = "end"
        try require(target.countdownDate == target.endDate, "End countdown target changed")
        var escaped = state
        escaped.subtitle = String(repeating: "\\\"", count: 1600)
        escaped.progress = .nan
        let bounded = escaped.boundedText()
        let boundedBytes = try JSONEncoder().encode(bounded).count
        try require(boundedBytes <= 3200 && bounded.progress == nil, "Escaped text or NaN escaped payload budget")
    }
}

// Inject into the simulator-only generated validation app, never the release target.
import Foundation
import WebKit

@MainActor
func verifyBrowserDownloads(browser: PortalBrowser, client: PortalClient, base: URL) async throws {
    let store = BrowserDownloadStore.shared
    store.activate(account: "download-fixture-A")
    // Synthetic accounts only; clear previous fixture records so checks are repeatable.
    for record in store.records { store.delete(record.id) }
    defer { browser.close() }
    let index = base.appendingPathComponent("dl/index")
    func require(_ ok: Bool, _ message: String) throws {
        if !ok { throw NetworkError(message: "Download validation: " + message) }
    }
    func wait(_ predicate: () -> Bool) async throws {
        for _ in 0..<400 {
            if predicate() { return }
            try await Task.sleep(for: .milliseconds(50))
        }
        throw NetworkError(message: "Download fixture timed out")
    }
    func loadIndex() async throws {
        browser.webView.load(URLRequest(url: index))
        try await wait { browser.webView.url?.path == "/dl/index" && browser.title == "Download fixture" && !browser.isLoading }
    }
    func click(_ id: String) async throws {
        _ = try await browser.webView.evaluateJavaScript("document.getElementById('\(id)').click()")
    }
    func newRecord(after old: Set<UUID>, state: BrowserDownloadRecord.State) async throws -> BrowserDownloadRecord {
        try await wait { store.records.contains { !old.contains($0.id) && $0.state == state } }
        return store.records.first { !old.contains($0.id) && $0.state == state }!
    }
    func bytes(_ record: BrowserDownloadRecord) throws -> Data {
        guard let url = store.previewURL(for: record.id) else { throw NetworkError(message: "Missing completed fixture") }
        return try Data(contentsOf: url)
    }
    await browser.start(index, client: client)
    try await wait { browser.title == "Download fixture" && !browser.isLoading }
    let (pdf, _) = try await URLSession.shared.data(from: base.appendingPathComponent("dl/reference"))
    var before = Set(store.records.map(\.id))
    try await click("attachment")
    let attachment = try await newRecord(after: before, state: .completed)
    try require(try bytes(attachment) == Data("NEU-Lumen original attachment".utf8), "attachment response bytes")
    try require(browser.error == nil, "download must not overlay page error")

    try await loadIndex()
    try await click("inline")
    try await wait { browser.isCurrentPDF && !browser.isLoading && browser.webView.url?.path == "/dl/document" }
    try require(browser.webView.url?.pathExtension.isEmpty == true, "extensionless PDF MIME detection")
    before = Set(store.records.map(\.id))
    browser.downloadCurrentFile()
    let original = try await newRecord(after: before, state: .completed)
    try require(try bytes(original) == pdf, "exact original PDF bytes, WebKit cookie + original Referer")
    try require(original.kind == .original, "original vs generated PDF label")

    try await loadIndex()
    before = Set(store.records.map(\.id))
    try await click("same1")
    let same1 = try await newRecord(after: before, state: .completed)
    before = Set(store.records.map(\.id))
    try await click("same2")
    let same2 = try await newRecord(after: before, state: .completed)
    try require(same1.filename == same2.filename && store.previewURL(for: same1.id) != store.previewURL(for: same2.id), "same name UUID isolation")
    try require(try bytes(same1) == Data("same-1".utf8) && bytes(same2) == Data("same-2".utf8), "both same-name files retained")
    for id in ["blobPDF", "dataPDF"] {
        before = Set(store.records.map(\.id))
        try await click(id)
        let result = try await newRecord(after: before, state: .completed)
        try require(try bytes(result) == pdf, "\(id) stays inside WebKit")
    }

    before = Set(store.records.map(\.id))
    try await click("slow")
    let slow = try await newRecord(after: before, state: .downloading)
    try await wait { (store.records.first { $0.id == slow.id }?.receivedBytes ?? 0) > 0 }
    store.cancel(slow.id)
    try require(store.records.first { $0.id == slow.id }?.state == .cancelled, "cancel terminal state")
    before = Set(store.records.map(\.id))
    try await click("broken")
    _ = try await newRecord(after: before, state: .failed)
    try require(browser.error == nil, "transfer failure doesn't replace current page")

    try await loadIndex()
    _ = try await browser.webView.evaluateJavaScript("document.getElementById('post').submit()")
    try await wait { browser.isCurrentPDF && !browser.isLoading && browser.webView.url?.path == "/dl/post" }
    before = Set(store.records.map(\.id))
    browser.downloadCurrentFile()
    try require(browser.showsDownloadNotice && browser.downloadNotice.contains("POST"), "POST must show safe prompt")
    try require(Set(store.records.map(\.id)) == before, "POST must not start a GET download")
    let (stats, _) = try await URLSession.shared.data(from: base.appendingPathComponent("dl/stats"))
    let counts = try JSONSerialization.jsonObject(with: stats) as! [String: Int]
    try require(counts["post_get"] == 0, "server saw no POST-as-GET replay")
    try await loadIndex()
    before = Set(store.records.map(\.id))
    _ = try await browser.webView.evaluateJavaScript("document.getElementById('postAttachment').submit()")
    let posted = try await newRecord(after: before, state: .completed)
    try require(try bytes(posted) == pdf, "POST attachment uses existing response")

    // Expire only a synthetic cookie AFTER displaying the PDF. A 200 HTML login must be rejected.
    try await loadIndex()
    try await click("inline")
    try await wait { browser.isCurrentPDF && !browser.isLoading }
    for cookie in await browser.webView.configuration.websiteDataStore.httpCookieStore.allCookies() where cookie.name == "dl-fixture" {
        await browser.webView.configuration.websiteDataStore.httpCookieStore.deleteCookie(cookie)
    }
    before = Set(store.records.map(\.id))
    browser.downloadCurrentFile()
    let rejected = try await newRecord(after: before, state: .failed)
    try require(rejected.failure == .notPDF && store.previewURL(for: rejected.id) == nil, "HTML login isn't stored as a PDF")

    // Real WKDownload ownership survives browser-controller release (no background promise).
    var closing: PortalBrowser? = PortalBrowser()
    await closing!.start(index, client: client)
    try await wait { closing?.title == "Download fixture" && closing?.isLoading == false }
    before = Set(store.records.map(\.id))
    store.start(URLRequest(url: base.appendingPathComponent("dl/slow")), in: closing!.webView, scope: store.scope, requirePDF: false)
    closing!.close()
    closing = nil
    let survived = try await newRecord(after: before, state: .completed)
    try require(survived.receivedBytes == 4 * 1024 * 1024, "download survives browser close")

    // Switch accounts while WebKit callbacks are still in flight; old identity must not reappear.
    before = Set(store.records.map(\.id))
    let oldScope = store.scope
    store.start(URLRequest(url: base.appendingPathComponent("dl/slow")), in: browser.webView, scope: oldScope, requirePDF: false)
    _ = try await newRecord(after: before, state: .downloading)
    store.activate(account: "download-fixture-B")
    try require(store.records.isEmpty && !store.accepts(oldScope), "A -> B hides A and invalidates tokens")
    try await Task.sleep(for: .milliseconds(600))
    try require(store.records.isEmpty, "late A callbacks cannot mutate B")
    store.activate(account: nil)
    try require(store.records.isEmpty && store.accountKey == nil, "logout clears visible records")
    store.activate(account: "download-fixture-A")
    try require(store.records.contains { $0.id == original.id && $0.state == .completed }, "A completed private files survive")
    try require(try bytes(original) == pdf, "A original bytes still intact after B/logout")
    try require(store.records.contains { $0.state == .interrupted }, "old in-flight record is interrupted")

    store.activate(account: "download-fixture-A", epoch: UUID())
    let loginScope = store.scope
    store.activate(account: "download-fixture-A")
    try require(store.scope == loginScope, "omitted epoch must preserve the active login")
    store.start(URLRequest(url: base.appendingPathComponent("dl/slow")), in: browser.webView, scope: loginScope, requirePDF: false)
    try await wait { store.records.contains { $0.state == .downloading && $0.receivedBytes > 0 } }
    store.activate(account: "download-fixture-A", epoch: UUID())
    try require(!store.accepts(loginScope) && store.activeCount == 0, "same-account login epoch cancels old downloads")
    try await Task.sleep(for: .milliseconds(600))
    try require(store.activeCount == 0, "late same-account callbacks cannot revive old login")

    // Fresh store + manifest is deterministic restart recovery; separately kill/relaunch below.
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("download-restart-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: root) }
    let disk = BrowserDownloadFiles(root: root)
    let key = BrowserDownloadFiles.accountKey("restart-fixture")
    let partial = BrowserDownloadRecord(filename: "partial.bin")
    let partialURL = try disk.prepare(partial, account: key)
    try Data("incomplete".utf8).write(to: partialURL)
    try disk.save([partial], account: key)
    let restored = BrowserDownloadStore(root: root)
    restored.activate(account: "restart-fixture")
    try require(restored.records.first?.state == .interrupted, "fresh store interrupts unfinished manifest")
    try require(!FileManager.default.fileExists(atPath: partialURL.path), "restart removes partial bytes")
    print("PASS: real WKDownload attachments, inline extensionless PDF/cookie/Referer/raw bytes, POST, blob/data, duplicate filenames, cancellation, failure, close, account switch, logout, restart recovery")
}

// Call in TWO separate simulator launches. Terminate the first process immediately
// after the external runner observes the READY marker (before /dl/slow completes).
@MainActor
func verifyBrowserDownloadProcessRestart(save: Bool, base: URL, marker: URL) async throws {
    let store = BrowserDownloadStore.shared
    store.activate(account: "download-process-restart-fixture")
    if save {
        for record in store.records { store.delete(record.id) }
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        let webView = WKWebView(frame: .zero, configuration: config)
        store.start(URLRequest(url: base.appendingPathComponent("dl/attachment")), in: webView, scope: store.scope, requirePDF: false)
        for _ in 0..<240 {
            if store.records.contains(where: { $0.state == .completed }) { break }
            try await Task.sleep(for: .milliseconds(25))
        }
        guard store.records.contains(where: { $0.state == .completed }) else { throw NetworkError(message: "Restart seed failed") }
        var slow = URLComponents(url: base.appendingPathComponent("dl/slow"), resolvingAgainstBaseURL: false)!
        slow.queryItems = [URLQueryItem(name: "long", value: "1")]
        store.start(URLRequest(url: slow.url!), in: webView, scope: store.scope, requirePDF: false)
        for _ in 0..<240 {
            if store.records.contains(where: { $0.state == .downloading && $0.receivedBytes > 0 }) {
                try "READY: terminate process now".write(to: marker, atomically: true, encoding: .utf8)
                return
            }
            try await Task.sleep(for: .milliseconds(25))
        }
        throw NetworkError(message: "Restart seed did not enter active transfer")
    } else {
        guard store.records.contains(where: { $0.state == .interrupted }),
              !store.records.contains(where: { $0.state == .downloading }),
              let complete = store.records.first(where: { $0.state == .completed }),
              let url = store.previewURL(for: complete.id),
              try Data(contentsOf: url) == Data("NEU-Lumen original attachment".utf8) else {
            throw NetworkError(message: "Process restart did not preserve completed / interrupt active")
        }
        try "PASS: real process restart completed bytes + interrupted transfer".write(to: marker, atomically: true, encoding: .utf8)
    }
}

/// Screenshot seeding uses real localhost WKDownloads, not hand-written list records.
/// This file is copied ONLY into the disposable simulator target; all identities/data are synthetic.
@MainActor
func seedBrowserDownloadScreenshot(browser: PortalBrowser, client: PortalClient, base: URL) async throws {
    let store = BrowserDownloadStore.shared
    for record in store.records { store.delete(record.id) }
    func wait(_ condition: () -> Bool) async throws {
        for _ in 0..<400 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(50))
        }
        throw NetworkError(message: "Synthetic download screenshot seed timed out")
    }
    let index = base.appendingPathComponent("dl/index")
    await browser.start(index, client: client)
    try await wait { browser.title == "Download fixture" && !browser.isLoading }
    let scope = store.scope
    for endpoint in ["dl/attachment", "dl/document"] {
        let before = Set(store.records.map(\.id))
        var request = URLRequest(url: base.appendingPathComponent(endpoint))
        request.setValue(index.absoluteString, forHTTPHeaderField: "Referer")
        store.start(request, in: browser.webView, scope: scope, requirePDF: endpoint == "dl/document")
        try await wait { store.records.contains { !before.contains($0.id) && $0.state == .completed } }
    }
    let beforeCancel = Set(store.records.map(\.id))
    store.start(URLRequest(url: base.appendingPathComponent("dl/slow")), in: browser.webView, scope: scope, requirePDF: false)
    try await wait { store.records.contains { !beforeCancel.contains($0.id) && $0.state == .downloading && $0.receivedBytes > 0 } }
    if let record = store.records.first(where: { !beforeCancel.contains($0.id) && $0.state == .downloading }) { store.cancel(record.id) }
    store.start(URLRequest(url: base.appendingPathComponent("dl/broken")), in: browser.webView, scope: scope, requirePDF: false)
    try await wait { store.records.contains { $0.state == .failed } }
    var slow = URLComponents(url: base.appendingPathComponent("dl/slow"), resolvingAgainstBaseURL: false)!
    slow.queryItems = [URLQueryItem(name: "long", value: "1")]
    store.start(URLRequest(url: slow.url!), in: browser.webView, scope: scope, requirePDF: false)
    try await wait { store.records.contains { $0.state == .downloading && $0.receivedBytes > 0 } }
    guard store.records.contains(where: { $0.state == .completed }),
          store.records.contains(where: { $0.state == .cancelled }),
          store.records.contains(where: { $0.state == .failed }) else {
        throw NetworkError(message: "Synthetic download screenshot lacks required states")
    }
}

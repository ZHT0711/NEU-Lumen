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
    var stage = "initial page"
    func require(_ ok: Bool, _ message: String) throws {
        if !ok { throw NetworkError(message: "Download validation: " + message) }
    }
    func wait(_ predicate: () -> Bool) async throws {
        for _ in 0..<400 {
            if predicate() { return }
            try await Task.sleep(for: .milliseconds(50))
        }
        let states = store.records.map { "\($0.filename):\($0.state.rawValue):\($0.failure?.rawValue ?? "none")" }.joined(separator: ", ")
        throw NetworkError(message: "Download fixture timed out at \(stage); page=\(browser.webView.url?.scheme ?? "nil"); loading=\(browser.isLoading); pdf=\(browser.isCurrentPDF); records=[\(states)]; notice=\(browser.downloadNotice)")
    }
    func loadIndex() async throws {
        browser.webView.load(URLRequest(url: index))
        try await wait { browser.webView.url?.path == "/dl/index" && browser.title == "Download fixture" && !browser.isLoading }
    }
    func click(_ id: String) async throws {
        _ = try await browser.webView.evaluateJavaScript("document.getElementById('\(id)').click()")
    }
    func newRecord(after old: Set<UUID>, state: BrowserDownloadRecord.State) async throws -> BrowserDownloadRecord {
        try await wait { store.records.contains { !old.contains($0.id) && ($0.state == state || $0.state == .failed) } }
        guard let record = store.records.first(where: { !old.contains($0.id) && $0.state == state }) else {
            let failure = store.records.first { !old.contains($0.id) }?.failure?.rawValue ?? "unknown"
            throw NetworkError(message: "Download validation failed at \(stage): \(failure)")
        }
        return record
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
        // Exercise the user-facing "download current original file" path.
        // A nested element.click() from injected JS is not a trusted user gesture
        // in every WebKit version and can suppress automatic download navigation.
        stage = id + " inline document"
        try await loadIndex()
        guard let text = try await browser.webView.evaluateJavaScript("document.getElementById('\(id)').href") as? String,
              let url = URL(string: text), ["blob", "data"].contains(url.scheme ?? "") else {
            throw NetworkError(message: "Invalid synthetic \(id) link")
        }
        browser.webView.load(URLRequest(url: url))
        try await wait { browser.isCurrentPDF && !browser.isLoading && browser.webView.url?.scheme == url.scheme }
        stage = id + " original download"
        before = Set(store.records.map(\.id))
        browser.downloadCurrentFile()
        let result = try await newRecord(after: before, state: .completed)
        try require(try bytes(result) == pdf, "\(id) original bytes stay inside WebKit")
    }
    stage = "slow transfer and cancellation"
    try await loadIndex()

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


/// Executes the shipped form/order bridge in an actual isolated WebKit world.
@MainActor
func verifyNativeServiceDocument(browser: PortalBrowser, base: URL) async throws {
    let web = browser.webView
    let oldFrame = web.frame
    web.frame = CGRect(x: 0, y: 0, width: 390, height: 700)
    defer { web.frame = oldFrame }
    let html = #"""
    <!doctype html><meta charset="utf-8"><title>Synthetic service document</title>
    <form onsubmit="event.preventDefault(); window.syntheticActivations=(window.syntheticActivations||0)+1">
    <input type="hidden" name="csrf" value="SYNTH-CSRF">
    <label>申请理由<input name="reason" required></label>
    <label>说明<textarea name="note">合成说明</textarea></label>
    <label>项目<select name="item"><option value="one">合成项目一</option><option value="two">合成项目二</option></select></label>
    <fieldset><legend>领取方式</legend><label><input type="radio" name="delivery" value="online">线上</label><label><input type="radio" name="delivery" value="desk">窗口</label></fieldset>
    <label><input type="checkbox" name="agreement" required>确认合成条款</label>
    <button type="submit">提交合成申请</button></form>
    <table><thead><tr><th>订单</th><th>金额</th><th>状态</th><th>操作</th></tr></thead>
    <tbody><tr><td>SYNTH-ORDER</td><td id="amount">12.34</td><td>学校待确认</td><td><button onclick="window.syntheticOrders=(window.syntheticOrders||0)+1">查看合成订单</button></td></tr></tbody></table>
    <script>window.syntheticActivations=0;window.syntheticOrders=0;</script>
    """#
    web.loadHTMLString(html, baseURL: base.appendingPathComponent("service-document"))
    for _ in 0..<200 {
        if web.title == "Synthetic service document" && !web.isLoading { break }
        try await Task.sleep(for: .milliseconds(50))
    }
    let world = WKContentWorld.world(name: "NEULumen.ServiceDocument")
    func require(_ value: Bool, _ message: String) throws {
        if !value { throw NetworkError(message: "Native service document: " + message) }
    }
    func call(_ command: String, token: String = "", action: String = "", values: [String: String] = [:]) async throws -> [String: Any] {
        let raw = try await web.callAsyncJavaScript(NativeServiceDocument.bridge,
            arguments: ["command": command, "token": token, "actionID": action, "values": values], in: nil, contentWorld: world)
        guard let result = raw as? [String: Any] else { throw NetworkError(message: "Missing service bridge result") }
        return result
    }
    func read() async throws -> NativeServiceDocument {
        let raw = try await call("read")
        let data = try JSONSerialization.data(withJSONObject: raw)
        return try JSONDecoder().decode(NativeServiceDocument.self, from: data)
    }
    var snapshot = try await read()
    try require(snapshot.fields.count == 5 && snapshot.tables.first?.rows.first?.contains("SYNTH-ORDER") == true, "native controls and original order cells")
    try require(!snapshot.fields.contains(where: { $0.label == "csrf" }), "hidden CSRF stays in school document")
    guard let submit = snapshot.actions.first(where: { $0.title == "提交合成申请" }) else { throw NetworkError(message: "Missing school submit control") }
    var result = try await call("act", token: snapshot.token, action: submit.id)
    try require(result["error"] as? String == "validation", "required fields must stop activation")
    snapshot = try await read()
    var values = Dictionary(uniqueKeysWithValues: snapshot.fields.map { ($0.id, $0.value) })
    for field in snapshot.fields {
        if field.label == "申请理由" { values[field.id] = "合成申请理由" }
        if field.kind == "checkbox" { values[field.id] = "true" }
        if field.kind == "radio" { values[field.id] = "online" }
        if field.kind == "select" { values[field.id] = "two" }
    }
    result = try await call("act", token: snapshot.token, action: submit.id, values: values)
    try require(result["activated"] as? Bool == true, "single explicit school handler activation")
    var facts = try await web.evaluateJavaScript("[window.syntheticActivations,document.querySelector('[name=csrf]').value,document.querySelector('[name=item]').value,document.querySelector('[name=delivery]:checked').value]") as? [Any]
    try require(facts?[0] as? Int == 1 && facts?[1] as? String == "SYNTH-CSRF" && facts?[2] as? String == "two" && facts?[3] as? String == "online", "handlers, CSRF, select and radio values")
    result = try await call("act", token: snapshot.token, action: submit.id, values: values)
    try require(result["error"] as? String == "stale", "consumed snapshot blocks duplicate actions")
    snapshot = try await read()
    guard let order = snapshot.actions.first(where: { $0.title == "查看合成订单" }) else { throw NetworkError(message: "Missing order action") }
    _ = try await web.evaluateJavaScript("document.getElementById('amount').textContent='99.00'")
    result = try await call("act", token: snapshot.token, action: order.id)
    try require(result["error"] as? String == "stale", "changed order amount invalidates confirmation")
    snapshot = try await read()
    _ = try await web.evaluateJavaScript("document.querySelector('[name=csrf]').value='SYNTH-ROTATED'")
    result = try await call("act", token: snapshot.token, action: order.id)
    try require(result["error"] as? String == "stale", "changed hidden order/form token invalidates confirmation")
    snapshot = try await read()
    guard let note = snapshot.fields.first(where: { $0.kind == "textarea" }) else { throw NetworkError(message: "Missing text area") }
    result = try await call("fill", token: snapshot.token, values: [note.id: "继续在学校页面填写"])
    try require(result["filled"] as? Bool == true, "transfer edited values to original webpage")
    facts = try await web.evaluateJavaScript("[window.syntheticActivations,document.querySelector('[name=note]').value]") as? [Any]
    try require(facts?[0] as? Int == 1 && facts?[1] as? String == "继续在学校页面填写", "fill never resubmits form")
    snapshot = try await read()
    _ = try await web.evaluateJavaScript("location.hash='synthetic-new-step'")
    result = try await call("act", token: snapshot.token, action: order.id)
    try require(result["error"] as? String == "stale", "SPA navigation invalidates old document")
    print("PASS: isolated WebKit native forms/orders, required validation, hidden tokens, select/radio/checkbox editing, original handlers, one-shot actions, changed amount/token/navigation and webpage continuation")
}

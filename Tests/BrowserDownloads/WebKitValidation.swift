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
    try require(!browser.reloadReadOnlyDocument(), "automatic code refresh must not replay a POST document")
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
    try await verifyRetainedBrowserReads(client: client, base: base)
    print("PASS: real WKDownload attachments, inline extensionless PDF/cookie/Referer/raw bytes, POST, blob/data, duplicate filenames, cancellation, failure, close, account switch, logout, restart recovery")
}

@MainActor
private func verifyRetainedBrowserReads(client: PortalClient, base: URL) async throws {
    let retained = PortalBrowser()
    defer { retained.close() }
    func require(_ condition: Bool, _ message: String) throws {
        if !condition { throw NetworkError(message: "Retained payment browser: " + message) }
    }
    func wait(_ condition: () -> Bool) async throws {
        for _ in 0..<400 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(25))
        }
        throw NetworkError(message: "Retained payment document did not reach the expected loading state")
    }
    func counts() async throws -> [String: Int] {
        let (data, _) = try await URLSession.shared.data(from: base.appendingPathComponent("dl/stats"))
        return try JSONDecoder().decode([String: Int].self, from: data)
    }
    let get = base.appendingPathComponent("dl/resume-get")
    let early = PortalBrowser()
    defer { early.close() }
    await early.start(get, client: client)
    early.close() // Before WebKit necessarily delivers its first navigation callback.
    try await Task.sleep(for: .milliseconds(80))
    await early.start(get, client: client)
    try await wait { early.title == "Resumable GET fixture" && !early.webView.isLoading && !early.isLoading }
    early.close()
    await retained.start(get, client: client)
    try await wait { retained.title == "Resumable GET fixture" && retained.webView.isLoading }
    retained.close()
    try await Task.sleep(for: .milliseconds(80))
    await retained.start(get, client: client)
    try await wait { retained.title == "Resumable GET fixture" && !retained.webView.isLoading && !retained.isLoading }
    let complete = try await retained.webView.evaluateJavaScript("!!document.getElementById('complete')") as? Bool
    try require(complete == true, "closing the first GET mid-load must resume and finish when reopened")
    let first = try await counts()
    try require((first["resume_get"] ?? 0) >= 2, "the interrupted GET was requested again")
    _ = try await retained.webView.evaluateJavaScript("document.getElementById('retained-draft').value='SYNTH-UNSUBMITTED-EDIT'")
    retained.close()
    await retained.start(get, client: client)
    try await Task.sleep(for: .milliseconds(100))
    let saved = try await retained.webView.evaluateJavaScript("document.getElementById('retained-draft').value") as? String
    let reopened = try await counts()
    try require(saved == "SYNTH-UNSUBMITTED-EDIT" && reopened["resume_get"] == first["resume_get"], "completed form reentry preserves edits without another request")

    var post = URLRequest(url: base.appendingPathComponent("dl/resume-post"))
    post.httpMethod = "POST"
    post.httpBody = Data("synthetic=only".utf8)
    post.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
    retained.webView.load(post)
    try await wait { retained.title == "Interrupted POST fixture" && retained.webView.isLoading }
    retained.close()
    try await Task.sleep(for: .milliseconds(80))
    await retained.start(get, client: client)
    try await Task.sleep(for: .milliseconds(150))
    let final = try await counts()
    try require(final["resume_post"] == 1 && final["resume_post_get"] == 0, "interrupted POST must never be replayed or converted to GET")
    print("PASS: retained browser interrupted GET recovery, completed form draft preservation and no POST replay")
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
    _ = try await web.evaluateJavaScript("document.querySelector('form').action='/changed-synthetic-destination'")
    result = try await call("act", token: snapshot.token, action: submit.id)
    try require(result["error"] as? String == "stale", "changed form destination invalidates confirmation")
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
    _ = try await web.evaluateJavaScript("document.body.insertAdjacentHTML('beforeend', '<div id=projects><a onclick=\"window.syntheticProjects=(window.syntheticProjects||0)+1\"><p>合成缴费项目</p></a></div>')")
    result = try await call("watch")
    try require(result["changed"] as? Bool == true, "AJAX project list is detected")
    snapshot = try await read()
    guard let project = snapshot.actions.first(where: { $0.title == "合成缴费项目" }) else { throw NetworkError(message: "Missing onclick-only school payment project") }
    result = try await call("watch")
    try require(result["changed"] as? Bool == false, "background observation preserves the current action snapshot")
    result = try await call("act", token: snapshot.token, action: project.id)
    try require(result["activated"] as? Bool == true, "onclick-only payment project works")
    let projectCount = try await web.evaluateJavaScript("window.syntheticProjects") as? Int
    try require(projectCount == 1, "school payment project handler executes once")
    _ = try await web.evaluateJavaScript("document.body.insertAdjacentHTML('beforeend', '<input type=button value=合成教务查询 onclick=\"window.academicClicks=(window.academicClicks||0)+1\"><div role=grid aria-label=合成考试><div role=row><span role=columnheader>课程</span><span role=columnheader>地点</span></div><div role=row><span role=gridcell>合成高数</span><span role=gridcell>A101</span></div></div>')")
    snapshot = try await read()
    try require(snapshot.tables.contains { $0.headers == ["课程", "地点"] && $0.rows == [["合成高数", "A101"]] }, "academic ARIA grid uses visible column headers and cells")
    guard let academic = snapshot.actions.first(where: { $0.title == "合成教务查询" }) else { throw NetworkError(message: "Missing school input button") }
    result = try await call("act", token: snapshot.token, action: academic.id)
    try require(result["activated"] as? Bool == true, "school input-button query is usable")
    let academicClicks = try await web.evaluateJavaScript("window.academicClicks") as? Int
    try require(academicClicks == 1, "academic handler executes exactly once")
    let classroomHTML = #"""
    <!doctype html><meta charset="utf-8"><title>Synthetic empty classroom</title>
    <label>校区<select id="campus" onchange="document.getElementById('building').innerHTML=this.value==='north'?'<option value=n1>合成北区一号楼</option>':'<option value=s1>合成南区一号楼</option>'"><option value="north">合成北校区</option><option value="south">合成南校区</option></select></label>
    <label>教学楼<select id="building"><option value="n1">合成北区一号楼</option></select></label>
    <label>查询日期<input id="day" type="date" value="2026-11-14"></label>
    <label>节次<select id="periods" multiple><option value="1">第一节</option><option value="2">第二节</option><option value="3" disabled>停用节次</option></select></label>
    <div class="bh-form-item"><label class="bh-form-label">教室类型</label><div id="classroomType" class="jqx-dropdownlist" role="combobox" aria-controls="classroomChoices" onclick="document.getElementById('classroomChoices').hidden=false"><div id="dropdownlistContentclassroomType">请选择教室类型</div></div></div>
    <div id="classroomChoices" hidden><div role="option" data-value="normal" onclick="document.getElementById('dropdownlistContentclassroomType').textContent=this.textContent;this.parentNode.hidden=true">合成普通教室</div><div role="option" data-value="lab" aria-disabled="true">合成停用教室</div></div>
    <button onclick="window.classroomQueries=(window.classroomQueries||0)+1;document.getElementById('result').textContent=document.getElementById('building').value">查询</button>
    <table><thead><tr><th>空闲教室</th></tr></thead><tbody><tr><td id="result">尚未查询</td></tr></tbody></table>
    """#
    web.loadHTMLString(classroomHTML, baseURL: base.appendingPathComponent("synthetic-classrooms"))
    for _ in 0..<200 {
        if web.title == "Synthetic empty classroom" && !web.isLoading { break }
        try await Task.sleep(for: .milliseconds(50))
    }
    snapshot = try await read()
    guard let campus = snapshot.fields.first(where: { $0.label == "校区" }) else { throw NetworkError(message: "Missing classroom campus") }
    result = try await call("change", token: snapshot.token, action: campus.id, values: [campus.id: "south"])
    try require(result["filled"] as? Bool == true, "native SELECT changes use school dependent-field handler")
    snapshot = try await read()
    try require(snapshot.fields.first(where: { $0.label == "教学楼" })?.options.first?.value == "s1", "campus change refreshes building options")
    try require(snapshot.fields.first(where: { $0.label == "查询日期" })?.kind == "date", "school date is presented as a native date field")
    guard let periods = snapshot.fields.first(where: { $0.label == "节次" }) else { throw NetworkError(message: "Missing classroom periods") }
    result = try await call("change", token: snapshot.token, action: periods.id, values: [periods.id: #"["1","2"]"#])
    try require(result["filled"] as? Bool == true, "native multi-select preserves every selected teaching period")
    snapshot = try await read()
    guard let choice = snapshot.fields.first(where: { $0.kind == "choice" }) else { throw NetworkError(message: "Missing school custom selector") }
    try require(choice.label == "教室类型" && choice.options.isEmpty, "closed custom selector retains school label without guessing options")
    result = try await call("open", token: snapshot.token, action: choice.id)
    try require(result["opened"] as? Bool == true, "explicitly open custom selector through school handler")
    snapshot = try await read()
    guard let opened = snapshot.fields.first(where: { $0.kind == "choice" }) else { throw NetworkError(message: "Missing opened selector") }
    try require(opened.options.map(\.value) == ["normal"], "only rendered enabled options are offered")
    result = try await call("change", token: snapshot.token, action: opened.id, values: [opened.id: "forged"])
    try require(result["error"] as? String == "format", "unoffered custom choice cannot be injected")
    result = try await call("change", token: snapshot.token, action: opened.id, values: [opened.id: "normal"])
    try require(result["filled"] as? Bool == true, "school custom option remains operable from isolated world")
    result = try await call("change", token: snapshot.token, action: opened.id, values: [opened.id: "normal"])
    try require(result["error"] as? String == "stale", "custom option action remains one-shot")
    snapshot = try await read()
    try require(snapshot.fields.first(where: { $0.kind == "choice" })?.value == "合成普通教室", "selected custom choice is read back from school state")
    guard let query = snapshot.actions.first(where: { $0.title == "查询" }) else { throw NetworkError(message: "Missing classroom query") }
    try require(query.query == true, "read-only classroom query does not need a business confirmation sheet")
    result = try await call("act", token: snapshot.token, action: query.id)
    try require(result["activated"] as? Bool == true, "classroom query executes once after linked controls update")
    snapshot = try await read()
    try require(snapshot.tables.first?.rows.first == ["s1"], "classroom results remain available to native reader")
    _ = try await web.evaluateJavaScript(#"""
    document.getElementById('campus').onchange=()=>setTimeout(()=>{document.getElementById('building').innerHTML='<option value="late">合成延迟楼栋</option>';},400);
    document.body.insertAdjacentHTML('beforeend','<label>关键词<input id="classroomKeyword" value=""></label><button type="submit">100</button><nav class="pagination"><button>2</button></nav><div role="checkbox" aria-label="选择合成教室" aria-checked="false" onclick="this.setAttribute(\'aria-checked\',this.getAttribute(\'aria-checked\')!==\'true\')">合成教室行</div>');
    """#)
    snapshot = try await read()
    let keywordKey = snapshot.fields.first(where: { $0.label == "关键词" })?.key
    guard let changedCampus = snapshot.fields.first(where: { $0.label == "校区" }) else { throw NetworkError(message: "Missing linked campus") }
    result = try await call("change", token: snapshot.token, action: changedCampus.id, values: [changedCampus.id: "north"])
    try require(result["filled"] as? Bool == true, "async dependent query starts from school handler")
    _ = try await read()
    try await Task.sleep(for: .milliseconds(550))
    result = try await call("watch")
    try require(result["changed"] as? Bool == true, "late AJAX options are observed after first read")
    snapshot = try await read()
    try require(snapshot.fields.first(where: { $0.label == "教学楼" })?.options.first?.value == "late", "late building choices become available")
    try require(keywordKey != nil && snapshot.fields.first(where: { $0.label == "关键词" })?.key == keywordKey, "stable field keys allow unsubmitted drafts to survive linked refresh")
    try require(snapshot.actions.first(where: { $0.title == "100" })?.query == false && snapshot.actions.first(where: { $0.title == "2" })?.query == true, "numeric amounts never bypass confirmation while pager numbers remain queries")
    guard let rowChoice = snapshot.fields.first(where: { $0.label == "选择合成教室" }) else { throw NetworkError(message: "Missing school ARIA row selector") }
    result = try await call("change", token: snapshot.token, action: rowChoice.id, values: [rowChoice.id: "true"])
    try require(result["filled"] as? Bool == true, "school custom row checkbox uses its own handler")
    snapshot = try await read()
    try require(snapshot.fields.first(where: { $0.label == "选择合成教室" })?.value == "true", "custom checkbox state reads back")
    // Structure mirrors the observed EMAP-FQ/jqxGrid controls, with synthetic data only.
    let emapHTML = #"""
    <!doctype html><meta charset="utf-8"><title>Synthetic EMAP classroom</title>
    <style>[role=combobox]{display:inline-block;min-width:150px;min-height:30px} .jqx-grid{margin-top:20px}td,[role=columnheader]{padding:8px}a{display:inline-block;padding:8px;cursor:pointer}</style>
    <article><div id="synthetic-search" class="emap-FQ-container">
      <div class="emap-FQ-filter-group"><div class="emap-FQ-label">学校校区</div><div class="emap-FQ-input-warp">
        <div id="jqxWidgetSynthetic" role="combobox" class="jqx-widget jqx-dropdownlist-state-normal" data-name="XXXQDM" data-caption="学校校区" aria-owns="listBoxjqxWidgetSynthetic">
          <div id="dropdownlistContentjqxWidgetSynthetic">请选择...</div><input type="hidden" value="">
          <div id="listBoxjqxWidgetSynthetic" hidden><div id="filterinnerListBoxjqxWidgetSynthetic"><input placeholder="请查找"></div>
            <div role="option" id="synthetic-campus-a" aria-selected="false"><span class="chkbox"></span>合成甲校区</div>
            <div role="option" id="synthetic-campus-b" aria-selected="false"><span class="chkbox"></span>合成乙校区</div>
          </div>
        </div>
      </div></div>
      <div class="emap-FQ-filter-group"><div class="emap-FQ-label">教学楼</div><select data-name="JXLDM" data-caption="教学楼" id="synthetic-building"><option value="">请先选择校区</option></select></div>
      <div class="emap-FQ-filter-group"><div class="emap-FQ-label">教室名称</div><input data-name="JASMC" data-caption="教室名称" id="synthetic-keyword" oninput="document.getElementById('synthetic-summary').textContent=this.value"></div>
      <div class="emap-FQ-filter-group"><div class="emap-FQ-label">空闲日期</div><div xtype="date-local" data-name="KXRQ" data-caption="空闲日期" class="bhtc-input-group"><input bh-form-role="dateTimeInput" type="text" value="2026-11-14"></div></div>
      <span id="synthetic-summary"></span><a class="bh-btn bh-btn-primary" emap-role="FQ-search-btn">搜索</a>
      <a class="bh-btn" data-action="synthetic-write">合成申请</a>
    </div>
    <div id="synthetic-grid" role="grid" class="jqx-grid"><div id="columntablesynthetic-grid"><div role="columnheader">教室名称</div><div role="columnheader">空闲时间</div></div>
      <div><table id="tablesynthetic-grid"><tbody><tr role="row"><td role="gridcell">尚未查询</td><td role="gridcell">未知</td></tr></tbody></table></div>
      <div class="jqx-grid-pager"><div class="bh-pager">
        <a pager-flag="home"><i></i></a><a pager-flag="prev"><i></i></a><a pager-flag="next"><i></i></a><a pager-flag="end"><i></i></a>
        <span class="bh-pager-num">1-10 总记录数 20</span><span class="bh-pager-no">总页数 2</span><input pager-flag="gotoPage" value="1">
      </div></div>
    </div></article>
    <script>
    window.syntheticQueries=0;window.syntheticWrites=0;
    const campus=document.getElementById('jqxWidgetSynthetic'),popup=document.getElementById('listBoxjqxWidgetSynthetic');
    campus.addEventListener('click',event=>{
      if(event.target.closest('[role=option]') || event.target.matches('input'))return;
      popup.hidden=!popup.hidden;
      if(popup.hidden)campus.dispatchEvent(new Event('close'));
    });
    for(const option of popup.querySelectorAll('[role=option]'))option.addEventListener('click',()=>{
      option.setAttribute('aria-selected',option.getAttribute('aria-selected')!=='true');
      const selected=Array.from(popup.querySelectorAll('[aria-selected=true]'));
      document.getElementById('dropdownlistContentjqxWidgetSynthetic').textContent=selected.map(x=>x.textContent).join('、')||'请选择...';
      campus.querySelector('input[type=hidden]').value=selected.map(x=>x.id).join(',');
    });
    popup.querySelector('input').addEventListener('keyup',event=>{
      for(const option of popup.querySelectorAll('[role=option]'))option.hidden=!option.textContent.includes(event.target.value);
    });
    campus.addEventListener('close',()=>setTimeout(()=>{
      document.getElementById('synthetic-building').innerHTML='<option value="synthetic-building-a">合成教学楼</option>';
    },400));
    document.querySelector('[emap-role=FQ-search-btn]').addEventListener('click',()=>{
      window.syntheticQueries++;
      document.querySelector('#tablesynthetic-grid tbody').innerHTML='<tr role="row"><td role="gridcell">合成A101</td><td role="gridcell">08:30-10:10</td></tr>';
    });
    document.querySelector('[data-action=synthetic-write]').addEventListener('click',()=>window.syntheticWrites++);
    for(const action of document.querySelectorAll('a[pager-flag]'))action.addEventListener('click',()=>{
      document.querySelector('.bh-pager-num').textContent='11-20 总记录数 20';
      document.querySelector('[pager-flag=gotoPage]').value='2';
      document.querySelector('#tablesynthetic-grid tbody').innerHTML='<tr role="row"><td role="gridcell">合成B201</td><td role="gridcell">10:30-12:10</td></tr>';
    });
    document.querySelector('[pager-flag=gotoPage]').addEventListener('keyup',event=>{
      if(event.keyCode===13)document.querySelector('.bh-pager-num').textContent='跳转到第'+event.target.value+'页';
    });
    </script>
    """#
    let emapURL = URL(string: "/jwapp/sys/kxjas/*default/index.do#/kxjscxxs", relativeTo: base)!
    web.loadHTMLString(emapHTML, baseURL: emapURL)
    for _ in 0..<200 {
        if web.title == "Synthetic EMAP classroom" && !web.isLoading { break }
        try await Task.sleep(for: .milliseconds(50))
    }
    snapshot = try await read()
    guard let schoolCampus = snapshot.fields.first(where: { $0.label == "学校校区" }),
          let schoolDate = snapshot.fields.first(where: { $0.label == "空闲日期" }) else { throw NetworkError(message: "Missing EMAP data-caption labels") }
    try require(schoolDate.kind == "date", "EMAP date wrapper labels its otherwise unnamed inner input")
    try require(snapshot.tables.first?.headers == ["教室名称", "空闲时间"], "jqxGrid outer header DIVs label the inner HTML table")
    try require(Set(snapshot.actions.filter { $0.query == true }.map(\.title)).isSuperset(of: ["搜索", "首页", "上一页", "下一页", "末页"]), "delegated EMAP search and icon-only pager anchors are native actions")
    try require(snapshot.fields.contains(where: { $0.label == "跳转页码" && $0.commit == "page" }), "school page jump input has a meaningful label")
    result = try await call("open", token: snapshot.token, action: schoolCampus.id)
    try require(result["opened"] as? Bool == true, "open real-shape EMAP dropdown")
    snapshot = try await read()
    guard let multiCampus = snapshot.fields.first(where: { $0.label == "学校校区" }) else { throw NetworkError(message: "Missing EMAP campus choices") }
    try require(multiCampus.expanded == true && multiCampus.multiple == true && multiCampus.search != nil && multiCampus.options.count == 2, "EMAP multi-select exposes selected state, filtering and explicit completion")
    result = try await call("change", token: snapshot.token, action: multiCampus.id, values: [multiCampus.id: "synthetic-campus-a"])
    try require(result["filled"] as? Bool == true, "select EMAP campus using school handlers")
    snapshot = try await read()
    guard let selectedCampus = snapshot.fields.first(where: { $0.label == "学校校区" }) else { throw NetworkError(message: "Missing selected EMAP campus") }
    try require(selectedCampus.options.first(where: { $0.value == "synthetic-campus-a" })?.selected == true && selectedCampus.expanded == true, "multi-select stays open and reads checked options")
    result = try await call("filter", token: snapshot.token, action: selectedCampus.id, values: [selectedCampus.id: "甲"])
    try require(result["filtered"] as? Bool == true, "native option search uses school's filter input")
    snapshot = try await read()
    guard let filteredCampus = snapshot.fields.first(where: { $0.label == "学校校区" }) else { throw NetworkError(message: "Missing filtered EMAP campus") }
    try require(filteredCampus.options.count == 1 && filteredCampus.options.first?.title == "合成甲校区", "native options follow school-filtered rendered choices")
    result = try await call("close", token: snapshot.token, action: filteredCampus.id)
    try require(result["closed"] as? Bool == true, "complete EMAP multi-selection through school close event")
    _ = try await read()
    try await Task.sleep(for: .milliseconds(550))
    result = try await call("watch")
    try require(result["changed"] as? Bool == true, "school close-triggered building response is observed")
    snapshot = try await read()
    try require(snapshot.fields.first(where: { $0.label == "教学楼" })?.options.first?.value == "synthetic-building-a", "close-triggered dependent building appears natively")
    guard let schoolQuery = snapshot.actions.first(where: { $0.title == "搜索" }),
          let schoolKeyword = snapshot.fields.first(where: { $0.label == "教室名称" }) else { throw NetworkError(message: "Missing EMAP query") }
    result = try await call("act", token: snapshot.token, action: schoolQuery.id, values: [schoolKeyword.id: "合成"])
    try require(result["activated"] as? Bool == true, "query accepts user edits even when school live filter summary changes")
    snapshot = try await read()
    try require(snapshot.tables.first?.rows.first == ["合成A101", "08:30-10:10"], "EMAP search result retains its real column labels")
    guard let nextPage = snapshot.actions.first(where: { $0.title == "下一页" }) else { throw NetworkError(message: "Missing semantic school pager") }
    result = try await call("act", token: snapshot.token, action: nextPage.id)
    try require(result["activated"] as? Bool == true, "semantic pager still clicks the original school icon anchor")
    snapshot = try await read()
    try require(snapshot.tables.first?.rows.first?.first == "合成B201" && snapshot.notices.contains("11-20 总记录数 20"), "EMAP next-page result and record range read back")
    guard let pageNumber = snapshot.fields.first(where: { $0.commit == "page" }) else { throw NetworkError(message: "Missing page jump") }
    result = try await call("change", token: snapshot.token, action: pageNumber.id, values: [pageNumber.id: "1"])
    try require(result["filled"] as? Bool == true, "native page jump updates school field and Enter handler")
    snapshot = try await read()
    try require(snapshot.notices.contains("跳转到第1页"), "school page-jump key handler runs")
    let draftIdentity = snapshot.draftIdentity
    try require(draftIdentity?.isEmpty == false, "draft identity is an opaque nonempty token")
    snapshot = try await read()
    try require(snapshot.draftIdentity == draftIdentity, "unchanged documents and hidden state preserve the draft identity")
    _ = try await web.evaluateJavaScript("document.querySelector('input[type=hidden]').value='SYNTH-CHANGED-ORDER'")
    result = try await call("watch")
    try require(result["changed"] as? Bool == true, "hidden-only order changes are observable without exposing their values")
    snapshot = try await read()
    try require(snapshot.draftIdentity != draftIdentity, "hidden order value changes invalidate native drafts")
    let rotatedIdentity = snapshot.draftIdentity
    _ = try await web.evaluateJavaScript("document.querySelector('input[type=hidden]').replaceWith(document.querySelector('input[type=hidden]').cloneNode(true))")
    snapshot = try await read()
    try require(snapshot.draftIdentity != rotatedIdentity, "replaced hidden nodes invalidate drafts even when their value is unchanged")
    _ = try await web.evaluateJavaScript(#"""
    document.body.insertAdjacentHTML('beforeend','<div data-name="RANGE"><input id="range-start" type="date" value="2026-11-14"><input id="range-end" type="date" value="2026-11-15"></div><div id="unnamed-range" data-name="UNNAMED" data-caption="日期区间"><input type="date" value="2026-11-14"><input type="date" value="2026-11-15"></div><input data-name="STABLE" data-caption="合成控件" id="jqxWidgetabc123" value="合成值">');
    """#)
    snapshot = try await read()
    guard let rangeStart = snapshot.fields.first(where: { $0.key?.hasSuffix(":RANGE:range-start") == true }),
          let rangeEnd = snapshot.fields.first(where: { $0.key?.hasSuffix(":RANGE:range-end") == true }) else { throw NetworkError(message: "Missing compound date range controls") }
    try require(rangeStart.key != rangeEnd.key, "shared data-name never aliases distinct date controls")
    result = try await call("change", token: snapshot.token, action: rangeEnd.id, values: [rangeEnd.id: "2026-11-20"])
    try require(result["filled"] as? Bool == true, "native end-date editing targets its own field")
    var rangeValues = try await web.evaluateJavaScript("[document.getElementById('range-start').value,document.getElementById('range-end').value]") as? [String]
    try require(rangeValues == ["2026-11-14", "2026-11-20"], "editing the end date leaves the start date unchanged")
    snapshot = try await read()
    let unnamed = snapshot.fields.filter { $0.key?.contains(":UNNAMED:") == true }
    try require(unnamed.count == 2 && Set(unnamed.compactMap(\.key)).count == 2, "unnamed compound inputs use distinct stable group ordinals")
    result = try await call("change", token: snapshot.token, action: unnamed[1].id, values: [unnamed[1].id: "2026-11-21"])
    try require(result["filled"] as? Bool == true, "unnamed second control remains individually editable")
    rangeValues = try await web.evaluateJavaScript("Array.from(document.querySelectorAll('#unnamed-range input')).map(el=>el.value)") as? [String]
    try require(rangeValues == ["2026-11-14", "2026-11-21"], "unnamed end-date editing does not change its sibling")
    snapshot = try await read()
    let stableKey = snapshot.fields.first(where: { $0.label == "合成控件" })?.key
    _ = try await web.evaluateJavaScript("document.getElementById('jqxWidgetabc123').id='jqxWidgetdef456'")
    snapshot = try await read()
    try require(stableKey != nil && snapshot.fields.first(where: { $0.label == "合成控件" })?.key == stableKey, "random jqxWidget ID regeneration preserves the semantic field identity")
    let counts = try await web.evaluateJavaScript("[window.syntheticQueries,window.syntheticWrites]") as? [Int]
    try require(counts == [1, 0], "EMAP read-only validation never invokes a business write")
    print("PASS: isolated WebKit native forms/orders, required validation, hidden tokens, select/radio/checkbox editing, original handlers, one-shot actions, changed amount/token/navigation and webpage continuation")
}

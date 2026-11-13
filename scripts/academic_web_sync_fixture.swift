// Disposable Debug simulator fixture only. Uses the PRODUCTION browser configuration,
// AcademicPageReader script, decoder, shared content world and repository apply guard.
// Navigation is localhost test plumbing, NOT evidence of school authentication.
import UIKit
import WebKit

@MainActor
private final class AcademicFixtureNavigation: NSObject, WKNavigationDelegate {
    var finished = false
    var failure: Error?
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { finished = true }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { failure = error }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { failure = error }
}

@MainActor
private enum AcademicWebSyncFixture {
    struct Result {
        let raw: [String: Any]
        let pageWorld: [String: Any]?
        let requests: Int
        let source: URL
    }
    static func require(_ condition: Bool, _ message: String) throws {
        if !condition { throw NetworkError(message: message) }
    }
    static func read(mode: String, account: String) async throws -> Result {
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first else {
            throw NetworkError(message: "No simulator scene for actual WebKit academic check")
        }
        let original = scene.windows.first(where: \.isKeyWindow)
        let browser = AcademicReadOnlyBrowser()
        let web = browser.webView
        try require(!web.configuration.websiteDataStore.isPersistent, "Academic browser unexpectedly persists website data")
        let navigation = AcademicFixtureNavigation()
        web.navigationDelegate = navigation // Only replace navigation plumbing for synthetic localhost.
        let window = UIWindow(windowScene: scene)
        window.frame = scene.coordinateSpace.bounds
        let controller = UIViewController()
        controller.view.backgroundColor = .systemBackground
        window.rootViewController = controller
        web.frame = CGRect(x: 0, y: 60, width: 350, height: 600)
        controller.view.addSubview(web)
        window.makeKeyAndVisible()
        defer { browser.close(); window.isHidden = true; original?.makeKeyAndVisible() }
        let identifier = UUID().uuidString
        var components = URLComponents(string: "http://127.0.0.1:8787/jwapp/sys/synthetic/identity.html")!
        components.queryItems = [URLQueryItem(name: "id", value: identifier),
            URLQueryItem(name: "mode", value: mode), URLQueryItem(name: "account", value: account)]
        let source = components.url!
        web.load(URLRequest(url: source))
        for _ in 0..<200 {
            if let failure = navigation.failure { throw failure }
            if navigation.finished { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        try require(navigation.finished, "Synthetic academic page did not finish loading")
        try await Task.sleep(for: .milliseconds(100))
        let arguments: [String: Any] = ["rootURL": "http://127.0.0.1:8787/jwapp/sys/homeapp/", "expectedAccount": account]
        var pageWorld: [String: Any]?
        if mode == "spoof" {
            pageWorld = try await web.callAsyncJavaScript(AcademicPageReader.browserScript,
                arguments: arguments, in: nil, contentWorld: .page) as? [String: Any]
            try require(pageWorld?["account"] as? String == account,
                        "Negative control did not demonstrate unsafe page-world identity spoof")
        }
        guard let raw = try await web.callAsyncJavaScript(AcademicPageReader.browserScript,
            arguments: arguments, in: nil, contentWorld: AcademicReadOnlyBrowser.readerWorld) as? [String: Any] else {
            throw NetworkError(message: "Production isolated reader returned no structured result")
        }
        if mode == "spoof" {
            let calls = try await web.evaluateJavaScript("window.__academicSpoofFetchCalls") as? Int
            try require(calls == 2, "Isolated reader called the untrusted page fetch")
        }
        let evidence = URL(string: "http://127.0.0.1:8787/academic-fixture/evidence?id=" + identifier)!
        let (bytes, response) = try await URLSession.shared.data(from: evidence)
        try require((response as? HTTPURLResponse)?.statusCode == 200, "Missing local identity request evidence")
        let map = try JSONSerialization.jsonObject(with: bytes) as? [String: Any]
        guard let requests = map?["requests"] as? Int else { throw NetworkError(message: "Invalid identity request count") }
        return Result(raw: raw, pageWorld: pageWorld, requests: requests, source: source)
    }
    static func isPreserved(_ repo: PortalRepository, _ snapshot: AcademicPageSnapshot) -> Bool {
        guard let current = repo.academicPageSnapshot else { return false }
        return current.account == snapshot.account && current.title == snapshot.title
            && current.sourceURL == snapshot.sourceURL && current.courses == snapshot.courses
            && current.recognizedTables == snapshot.recognizedTables && current.updatedAt == snapshot.updatedAt
    }
}

@MainActor
func runAcademicWebSyncChecks(_ environment: AppEnvironment) async {
    let output = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("academic-web-sync-checks.txt")
    do {
        let repo = environment.repository
        await repo.ensureLoadedForCurrentUser()
        guard let context = repo.academicRequestContext else { throw NetworkError(message: "Missing synthetic account context") }
        let same = try await AcademicWebSyncFixture.read(mode: "same", account: context.account)
        let snapshot = try AcademicPageReader.decode(same.raw, expectedAccount: context.account, expectedSourceURL: same.source)
        try AcademicWebSyncFixture.require(same.requests == 2 && snapshot.courses.count == 1,
                                          "Same-account reader did not verify both real HTTP identities")
        try repo.applyAcademicPageSnapshot(snapshot, context: context)
        try AcademicWebSyncFixture.require(AcademicWebSyncFixture.isPreserved(repo, snapshot), "Same-account snapshot was not applied")
        var lines = ["PASS: actual nonPersistent WebKit; production named-content-world reader/decoder and repository apply; synthetic localhost only",
                     "CASE: same-account",
                     "IDENTITY: {\"case\":\"same-account\",\"requests\":\(same.requests),\"accepted\":true}"]
        for (mode, name, count) in [("wrong", "wrong-account", 1), ("spoof", "spoofed-page-world", 1),
                                   ("change", "identity-changes-between-checks", 2)] {
            let result = try await AcademicWebSyncFixture.read(mode: mode, account: context.account)
            try AcademicWebSyncFixture.require(result.raw["error"] as? String == "identity" && result.requests == count,
                                              "Actual isolated reader failed identity rejection for " + name)
            do {
                _ = try AcademicPageReader.decode(result.raw, expectedAccount: context.account, expectedSourceURL: result.source)
                throw NetworkError(message: "Identity mismatch reached a native snapshot")
            } catch AcademicQueryError.accountMismatch { }
            try AcademicWebSyncFixture.require(AcademicWebSyncFixture.isPreserved(repo, snapshot),
                                              "Rejected identity replaced the previous account snapshot")
            if mode == "spoof" {
                try AcademicWebSyncFixture.require(result.pageWorld?["account"] as? String == context.account,
                                                  "Missing unsafe-world negative control")
                lines.append("NEGATIVE-CONTROL: unsafe-page-world-spoof-accepted")
            }
            lines.append("CASE: " + name)
            lines.append("IDENTITY: {\"case\":\"\(name)\",\"requests\":\(result.requests),\"accepted\":false}")
        }
        // Real production epoch change: old native snapshot cannot be written after logout/login.
        environment.session.logout()
        environment.session.seedScreenshotSession()
        await repo.ensureLoadedForCurrentUser()
        try AcademicWebSyncFixture.require(repo.academicRequestContext != context && repo.academicPageSnapshot == nil,
                                          "Account epoch reset left an old academic snapshot visible")
        do {
            try repo.applyAcademicPageSnapshot(snapshot, context: context)
            throw NetworkError(message: "Stale account context applied an academic snapshot")
        } catch AcademicQueryError.accountMismatch { }
        try AcademicWebSyncFixture.require(repo.academicPageSnapshot == nil, "Stale apply wrote academic data into the new epoch")
        lines.append("CASE: account-epoch-rejects-old-snapshot")
        try lines.joined(separator: "\n").write(to: output, atomically: true, encoding: .utf8)
    } catch {
        try? ("FAIL: " + error.localizedDescription).write(to: output, atomically: true, encoding: .utf8)
    }
}

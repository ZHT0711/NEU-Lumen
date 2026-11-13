// Simulator-only integration tests; synthetic localhost storage and platform cookies.
import Foundation
import WebKit

@MainActor
func verifyLearningProcessRestart(save: Bool, base: URL) async throws {
    let defaults = UserDefaults(suiteName: "learning-browser-restart-fixture")!
    let profiles = LearningBrowserProfiles(defaults: defaults)
    let account = "learning-browser-restart-A"
    let vault = KeychainWebSessionStore(account: "learning." + account)
    if save {
        profiles.retire(account: account)
        profiles.retire(account: "learning-browser-restart-B")
        vault.clear()
        await profiles.cleanRetiredStores()
    }
    let session = SessionStore(defaults: defaults)
    session.seedLearningValidationSession(account: account)
    func require(_ value: Bool, _ message: String) throws {
        if !value { throw NetworkError(message: "Learning persistence: " + message) }
    }
    func open(_ session: SessionStore, _ platform: LearningPlatform) async throws -> PortalBrowser {
        let browser = PortalBrowser()
        await browser.start(platform.entryURL, client: session.client, session: session)
        try require(browser.webView.configuration.websiteDataStore.identifier == session.learningBrowserIdentifier(for: platform),
                    "Production browser did not select its account/platform profile")
        browser.webView.stopLoading()
        browser.webView.load(URLRequest(url: base.appendingPathComponent("second.html")))
        for _ in 0..<200 {
            if browser.webView.url?.host == "127.0.0.1", browser.title == "第二页", !browser.isLoading { return browser }
            try await Task.sleep(for: .milliseconds(50))
        }
        throw NetworkError(message: "Learning persistence localhost page timed out")
    }
    func storage(_ browser: PortalBrowser, write: String?) async throws -> [String: String] {
        let result = try await browser.webView.callAsyncJavaScript(#"""
        const db = await new Promise((resolve, reject) => {
            const r = indexedDB.open('learning-fixture', 1);
            r.onupgradeneeded = () => r.result.createObjectStore('tokens');
            r.onsuccess = () => resolve(r.result); r.onerror = () => reject(r.error);
        });
        try {
            if (write) {
                localStorage.setItem('learning-token', write);
                await new Promise((resolve, reject) => {
                    const tx = db.transaction('tokens', 'readwrite');
                    tx.objectStore('tokens').put(write, 'token');
                    tx.oncomplete = () => resolve(); tx.onerror = () => reject(tx.error);
                });
            }
            const token = await new Promise((resolve, reject) => {
                const r = db.transaction('tokens').objectStore('tokens').get('token');
                r.onsuccess = () => resolve(r.result || ''); r.onerror = () => reject(r.error);
            });
            return {local: localStorage.getItem('learning-token') || '', indexed: token};
        } finally { db.close(); }
        """#, arguments: ["write": write ?? ""], in: nil, contentWorld: .page)
        return result as? [String: String] ?? [:]
    }
    for platform in [LearningPlatform.mooc, .chaoxing] {
        let marker = "fixture-" + platform.rawValue
        var browser: PortalBrowser? = try await open(session, platform)
        let cookieStore = browser!.webView.configuration.websiteDataStore.httpCookieStore
        if save {
            let cookie = HTTPCookie(properties: [.name: platform == .mooc ? "NTESSTUDYSI" : "_uid",
                .value: marker, .domain: platform == .mooc ? ".icourse163.org" : ".chaoxing.com",
                .path: "/", .secure: "TRUE"])!
            await cookieStore.setCookie(cookie)
        }
        let result = try await storage(browser!, write: save ? marker : nil)
        try require(result["local"] == marker && result["indexed"] == marker,
                    "\(platform.rawValue) localStorage/IndexedDB did not survive process restart")
        let cookies = await cookieStore.allCookies()
        try require(cookies.contains { platform.ownsCookie($0) && $0.value == marker },
                    "\(platform.rawValue) session cookie was not restored from Keychain")
        try require(!cookies.contains { $0.domain.contains("neu.edu.cn") }, "Portal cookies leaked into durable learning profile")
        await browser!.saveSession()
        browser!.close()
        browser = nil
    }
    if !save {
        let other = SessionStore(defaults: defaults)
        other.seedLearningValidationSession(account: "learning-browser-restart-B")
        let isolated = try await open(other, .mooc)
        let empty = try await storage(isolated, write: nil)
        try require(empty["local"] == "" && empty["indexed"] == "", "A second campus account saw the first account's storage")
        let isolatedCookies = await isolated.webView.configuration.websiteDataStore.httpCookieStore.allCookies()
        try require(!isolatedCookies.contains { $0.value == "fixture-mooc" }, "A second campus account saw the first account's cookies")
        isolated.close()
        let old = session.learningBrowserIdentifier(for: .mooc)
        session.logout()
        try require(vault.load() == nil, "Logout did not clear learning Keychain snapshot")
        session.seedLearningValidationSession(account: account)
        try require(old != session.learningBrowserIdentifier(for: .mooc), "Logout reused the retired WebKit identifier")
        let fresh = try await open(session, .mooc)
        let cleared = try await storage(fresh, write: nil)
        try require(cleared["local"] == "" && cleared["indexed"] == "", "Logout resurrected old origin storage")
        fresh.close()
        session.logout()
        other.logout()
        await profiles.cleanRetiredStores()
    }
}

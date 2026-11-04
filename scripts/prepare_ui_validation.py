"""Create a disposable simulator fixture; fixture code never enters the IPA."""
from pathlib import Path
import shutil
import sys

root = Path(__file__).resolve().parents[1]
destination = Path(sys.argv[1]).resolve()
destination.mkdir(parents=True, exist_ok=True)
for name in ["NEU-Lumen", "NEU-Lumen.xcodeproj"]:
    shutil.copytree(root / name, destination / name, dirs_exist_ok=True)
repository = destination / "NEU-Lumen/Core/Services/PortalRepository.swift"
with repository.open("a", encoding="utf-8") as stream:
    stream.write(r'''

// Only in the disposable UI validation copy.
extension PortalRepository {
    func seedUIValidation() {
        loadedForSID = ""
        user = DemoData.user
        dataCards = DemoData.dataCards
        apps = DemoData.apps
        favorites.activate(account: "", apps: apps)
        news = DemoData.news.enumerated().map { index, item in
            NewsItem(id: item.id, title: item.title, date: item.date, category: item.category,
                url: "http://127.0.0.1:8787/article.html?id=\(index)", picUrl: "")
        }
        hotSearch = DemoData.hotSearch
        homeState = .loaded
        gradesCache = [GradeSemester(name: "2026–2027 秋季学期", termCode: "fixture", current: true,
            courses: [GradeCourse(name: "高等数学", credit: 5, category: "必修", score: 92, scoreRaw: ""),
                      GradeCourse(name: "大学英语", credit: 3, category: "必修", score: 88, scoreRaw: "")])]
        gradesState = .loaded
        let start = Semester.weekStart(forDay: Date())
        var items: [CourseOccurrence] = []
        for day in [1, 2, 4] {
            let date = Calendar.current.date(byAdding: .day, value: day, to: start)!
            for period in 0..<4 {
                items.append(CourseOccurrence(date: date, slot: CourseSlot(weekday: day,
                    startMinutes: Semester.periodStarts[period], endMinutes: Semester.periodEnds[period],
                    name: day == 2 ? "程序设计基础" : "高等数学", room: "浑南 A101")))
            }
        }
        weekCache[start] = items
        weekState = .loaded
    }
}
''')
(destination / "NEU-Lumen/App/NEULumenApp.swift").write_text(r'''
import SwiftUI
import WebKit

@main
struct UIValidationApp: App {
    @State private var environment = AppEnvironment()
    var body: some Scene {
        WindowGroup { UIValidationRoot().environment(environment).tint(AppTheme.accent) }
    }
}

struct UIValidationRoot: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var ready = false
    @State private var testBrowser = PortalBrowser()
    private var screen: String {
        ProcessInfo.processInfo.arguments.first { $0.hasPrefix("--screen=") }?.replacingOccurrences(of: "--screen=", with: "") ?? "home"
    }
    var body: some View {
        Group {
            if ready {
                switch screen {
                case "schedule": ScheduleView()
                case "services": ServicesView()
                case "profile": ProfileView()
                case "favorites": FavoritesEditor()
                case "holidays": ScheduleSettingsSheet()
                case "calendar": SystemCalendarSheet(sunday: Semester.weekStart(forDay: Date()))
                case "grades": GradesView()
                case "browser":
                    TabView {
                        NavigationStack { PortalWebViewScreen(url: URL(string: "http://127.0.0.1:8787/index.html")!) }
                            .tabItem { Label("浏览器", systemImage: "globe") }
                    }
                default: MainTabView()
                }
            } else { ProgressView() }
        }
        .overlay(alignment: .bottomTrailing) {
            if ProcessInfo.processInfo.arguments.contains("--browser-checks") {
                PortalWebView(browser: testBrowser).frame(width: 1, height: 1).opacity(0.01)
            }
        }
        .task {
            if ProcessInfo.processInfo.arguments.contains("--session-save-check") {
                runSessionPersistenceCheck(save: true)
                return
            }
            if ProcessInfo.processInfo.arguments.contains("--session-restore-check") {
                runSessionPersistenceCheck(save: false)
                return
            }
            environment.repository.seedUIValidation()
            ready = true
            if ProcessInfo.processInfo.arguments.contains("--browser-checks") {
                await runBrowserChecks(testBrowser, client: environment.session.client)
            }
        }
    }
}

@MainActor
func runSessionPersistenceCheck(save: Bool) {
    let output = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        .appendingPathComponent(save ? "session-save.txt" : "session-restore.txt")
    let vault = KeychainWebSessionStore()
    do {
        if save {
            let cookie = HTTPCookie(properties: [.name:"wengine_vpn_ticket", .value:"restart-fixture",
                .domain:"webvpn.neu.edu.cn", .path:"/https/fixture/portal", .secure:"TRUE",
                HTTPCookiePropertyKey(rawValue:"HttpOnly"):"TRUE"])!
            try vault.save(SavedWebSession(user: DemoData.user, userAgent: "Fixture WebKit", cookies: [cookie]))
        } else {
            guard let saved = vault.load(), saved.user == DemoData.user, saved.userAgent == "Fixture WebKit",
                  let cookie = saved.restoredCookies().first, cookie.value == "restart-fixture",
                  cookie.path == "/https/fixture/portal", cookie.isSecure, cookie.isHTTPOnly else {
                throw NetworkError(message: "Saved browser session did not survive process restart")
            }
            vault.clear()
            guard vault.load() == nil else { throw NetworkError(message: "Session logout cleanup failed") }
        }
        try "PASS: Keychain session \(save ? "save" : "restore after process restart and clear")".write(to: output, atomically: true, encoding: .utf8)
    } catch {
        try? ("FAIL: " + error.localizedDescription).write(to: output, atomically: true, encoding: .utf8)
    }
}

@MainActor
func runBrowserChecks(_ browser: PortalBrowser, client: PortalClient) async {
    let output = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("browser-checks.txt")
    func waitFor(_ condition: () -> Bool) async throws {
        for _ in 0..<240 {
            if condition() { return }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        throw NetworkError(message: "Browser check timed out, title=\(browser.title), error=\(browser.error ?? "none")")
    }
    do {
        let scrollActivity = TabBarScrollActivity()
        scrollActivity.moved(by: 20)
        guard scrollActivity.direction == .down else { throw NetworkError(message: "Downward tab minimization failed") }
        scrollActivity.moved(by: -20)
        guard scrollActivity.direction == .up else { throw NetworkError(message: "Upward tab minimization failed") }
        // A held finger can pause without producing a new scroll phase.
        try await Task.sleep(for: .milliseconds(800))
        guard scrollActivity.direction == nil else { throw NetworkError(message: "Paused scroll did not restore tabs") }
        scrollActivity.moved(by: 20)
        scrollActivity.ended()
        try await Task.sleep(for: .milliseconds(500))
        guard scrollActivity.direction == nil else { throw NetworkError(message: "Idle scroll did not restore tabs") }
        scrollActivity.moved(by: 20)
        scrollActivity.ended()
        try await Task.sleep(for: .milliseconds(250))
        scrollActivity.moved(by: -20)
        try await Task.sleep(for: .milliseconds(200))
        guard scrollActivity.direction == .up else { throw NetworkError(message: "Cancelled restore interrupted a new scroll") }
        scrollActivity.restore()
        scrollActivity.moved(by: 0.1)
        guard scrollActivity.direction == nil else { throw NetworkError(message: "Tab scroll jitter or reset failed") }
        for key in ["NSLocationWhenInUseUsageDescription", "NSCameraUsageDescription", "NSMicrophoneUsageDescription", "NSMotionUsageDescription"] {
            guard let purpose = Bundle.main.object(forInfoDictionaryKey: key) as? String, !purpose.isEmpty else {
                throw NetworkError(message: "Missing web permission purpose: \(key)")
            }
        }
        await browser.start(URL(string: "http://127.0.0.1:8787/index.html")!, client: client)
        try await waitFor { browser.title == "校园网页功能验证" && !browser.isLoading }
        guard browser.webView.findInteraction != nil else { throw NetworkError(message: "Find unavailable") }
        let geolocation = try await browser.webView.evaluateJavaScript("window.isSecureContext && typeof navigator.geolocation.getCurrentPosition === 'function' && typeof navigator.geolocation.watchPosition === 'function'") as? Bool
        guard geolocation == true else { throw NetworkError(message: "Web geolocation API unavailable") }
        let userAgent = try await browser.webView.evaluateJavaScript("navigator.userAgent") as? String
        guard userAgent == (client.browserUserAgent ?? HTTPClient.userAgent) else { throw NetworkError(message: "Browser and HTTP session UA mismatch") }
        _ = try await browser.webView.evaluateJavaScript("document.getElementById('popup').click()")
        try await waitFor { browser.title == "第二页" && browser.canGoBack }
        browser.webView.goBack()
        try await waitFor { browser.title == "校园网页功能验证" && browser.canGoForward }
        browser.webView.goForward()
        try await waitFor { browser.title == "第二页" }
        browser.toggleDesktop()
        try await waitFor { !browser.isLoading && browser.title == "第二页" }
        browser.webView.pageZoom = 1.3
        guard abs(browser.webView.pageZoom - 1.3) < 0.01 else { throw NetworkError(message: "Zoom failed") }
        await browser.exportPDF()
        guard let pdf = browser.sharedFile?.url, (try Data(contentsOf: pdf)).starts(with: Data("%PDF".utf8)) else {
            throw NetworkError(message: "PDF export failed")
        }
        browser.sharedFile = nil
        browser.goToEntry()
        try await waitFor { browser.title == "校园网页功能验证" && !browser.isLoading }
        _ = try await browser.webView.evaluateJavaScript("document.getElementById('download').click()")
        try await waitFor { browser.sharedFile != nil }
        guard let download = browser.sharedFile?.url,
              try String(contentsOf: download, encoding: .utf8) == "NEU-Lumen download fixture" else {
            throw NetworkError(message: "Download contents failed")
        }
        let cardBridge = CardWebBridge(baseURL: URL(string: "http://127.0.0.1:8787")!, entryURL: URL(string: "http://127.0.0.1:8787/card-login.html")!)
        let balance = try await cardBridge.balance(client: client)
        guard balance.balance == 66.5 && balance.subsidy == 7.5 else { throw NetworkError(message: "WebKit card balance incorrect") }
        let statement = try await cardBridge.bills(client: client, year: 2026, month: 10)
        guard statement.bills.count == 2 && !statement.truncated else { throw NetworkError(message: "WebKit card statement/paging incorrect") }
        let thumbnail = await client.fetchNewsThumbnail(NewsItem(id: "thumbnail", title: "测试", date: "", category: "", url: "http://127.0.0.1:8787/article.html", picUrl: ""))
        guard let thumbnail, UIImage(data: thumbnail) != nil else { throw NetworkError(message: "Article first image not decoded") }
        try "PASS: tab scroll directions, pause/idle restore, cancelled restore, reset/jitter, web permission purposes, geolocation API, WebKit card SSO, real balance, ASP.NET hidden state, bill query/pagination, article first image, page load, session UA, find, target-blank, back, forward, desktop, zoom, PDF, entry, download".write(to: output, atomically: true, encoding: .utf8)
    } catch {
        try? ("FAIL: " + error.localizedDescription).write(to: output, atomically: true, encoding: .utf8)
    }
}
''', encoding="utf-8")
fixtures = destination / "fixtures"
fixtures.mkdir(exist_ok=True)
(fixtures / "index.html").write_text('''<!doctype html><html lang="zh"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>校园网页功能验证</title><style>body{font:17px -apple-system;padding:24px;color:#213060;background:#f3f5fb}h1{font-size:28px}a{display:block;background:white;border-radius:16px;padding:18px;margin:14px 0;color:#3553a2;text-decoration:none}small{color:#6d7487}</style><small>NEU · 校园浏览器</small><h1>更顺手的校园网页</h1><p>查找、缩放、分享和下载，都在手边。</p><a id="popup" target="_blank" href="second.html">打开新窗口链接 ↗</a><a id="download" download="campus-guide.txt" href="download.txt">下载校园指南 ↓</a><p>下方工具栏提供前进、后退、刷新与分享。</p></html>''', encoding="utf-8")
(fixtures / "second.html").write_text('<meta charset="utf-8"><title>第二页</title><h1>导航成功</h1>', encoding="utf-8")
(fixtures / "download.txt").write_text("NEU-Lumen download fixture", encoding="utf-8")

shutil.copyfile(root / "NEU-Lumen/Assets.xcassets/NEULogo.imageset/logo.png", fixtures / "article-first.png")
(fixtures / "article.html").write_text('<html><header><img src="/missing-logo.png"></header><div class="wp_articlecontent"><p>正文</p><img src="article-first.png"></div></html>', encoding="utf-8")
(fixtures / "card-login.html").write_text('<html><form action="/selfsearch/SSOLogin.aspx" method="post"><input name="username" value="fixture"><input name="timestamp" value="123"><input name="auid" value="signed"></form><script>document.forms[0].submit()</script></html>', encoding="utf-8")

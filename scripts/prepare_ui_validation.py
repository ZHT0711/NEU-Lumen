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
    func verifyRequestRecovery() async throws {
        var attempts = 0
        let value = try await withRecovery { () async throws -> Int in
            attempts += 1
            if attempts == 1 { throw CancellationError() }
            return 42
        }
        guard value == 42, attempts == 2 else { throw NetworkError(message: "Interrupted card request was not retried") }

        var cancelledAttempts = 0
        let cancelled = Task { @MainActor in
            try await self.withRecovery { () async throws -> Int in
                cancelledAttempts += 1
                withUnsafeCurrentTask { $0?.cancel() }
                throw CancellationError()
            }
        }
        do {
            _ = try await cancelled.value
            throw NetworkError(message: "Cancelled view task returned success")
        } catch is CancellationError { }
        guard cancelledAttempts == 1 else { throw NetworkError(message: "Cancelled view task was replayed") }

        let savedGeneration = accountGeneration
        defer { accountGeneration = savedGeneration }
        var staleAttempts = 0
        do {
            _ = try await withRecovery { () async throws -> Int in
                staleAttempts += 1
                self.accountGeneration = UUID()
                throw CancellationError()
            }
            throw NetworkError(message: "Old account request returned success")
        } catch is CancellationError { }
        guard staleAttempts == 1 else { throw NetworkError(message: "Old account request was replayed") }
    }

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
        cgReport = CGAssignmentReport(assignments: [CGAssignment(id: "fixture", title: "第 3 次课后作业",
            url: nil, deadlineText: "2026-11-10 23:59:59", late: false, history: false, loaded: true,
            problems: [CGProblem(id: "fixture.1", title: "分支与循环", url: nil, statusText: "完全正确"),
                       CGProblem(id: "fixture.2", title: "数组练习", url: nil, statusText: "还未提交")])], warnings: [])
        cgState = .loaded
        cgUpdatedAt = Date()
        campusOverride = .hunnan
        for platform in [LearningPlatform.mooc, .chaoxing] {
            let url = platform.entryURL
            let course = LearningCourse(id: platform.rawValue, termID: "fixture", title: "程序设计基础", url: url,
                progress: platform == .chaoxing ? LearningCourseProgress(completed: 28, total: 40) : nil,
                deadline: platform == .chaoxing ? Date().addingTimeInterval(30 * 86400) : nil)
            assignmentReports[platform] = LearningAssignmentReport(courses: [course], assignments: [
                LearningAssignment(id: "task.1", courseKey: course.key, courseTitle: course.title, title: "第 5 周作业", kind: "作业",
                    url: url, deadline: Date().addingTimeInterval(86400), deadlineText: "", statusText: "未提交", completed: false, scoreText: ""),
                LearningAssignment(id: "task.2", courseKey: course.key, courseTitle: course.title, title: "第 4 周测验", kind: "测验",
                    url: url, deadline: nil, deadlineText: "", statusText: "已完成", completed: true, scoreText: "10 / 10")
            ], warnings: [], refreshedCourseKeys: [course.key])
            if platform == .mooc {
                assignmentReports[platform]?.courses.append(LearningCourse(id: "empty", termID: "fixture", title: "只有课程信息", url: url))
            }
            assignmentSections[platform] = assignmentReports[platform]?.sections(for: platform)
            assignmentStates[platform] = .loaded
        }
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
import AppIntents

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
                case "grades", "mooc", "chaoxing": GradesView()
                case "card": NavigationStack { CardView() }
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
            if screen == "home-nanhu" { environment.repository.setCampusOverride(.nanhu) }
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
    let learningVault = KeychainWebSessionStore(account: "learning.restart-fixture")
    let cache = AssignmentCacheStore(account: "restart-fixture")
    do {
        if save {
            let cookie = HTTPCookie(properties: [.name:"wengine_vpn_ticket", .value:"restart-fixture",
                .domain:"webvpn.neu.edu.cn", .path:"/https/fixture/portal", .secure:"TRUE",
                HTTPCookiePropertyKey(rawValue:"HttpOnly"):"TRUE"])!
            try vault.save(SavedWebSession(user: DemoData.user, userAgent: "Fixture WebKit", cookies: [cookie]))
            let learningCookie = HTTPCookie(properties: [.name: "NTESSTUDYSI", .value: "learning-fixture",
                .domain: ".icourse163.org", .path: "/", .secure: "TRUE"])!
            try learningVault.save(SavedWebSession(user: DemoData.user, userAgent: "Fixture WebKit", cookies: [learningCookie]))
            let course = LearningCourse(id: "fixture", termID: "1", title: "缓存课程", url: LearningPlatform.mooc.entryURL)
            let row = LearningAssignment(id: "fixture-task", courseKey: course.key, courseTitle: course.title,
                title: "缓存作业", kind: "作业", url: course.url, deadline: nil, deadlineText: "",
                statusText: "已提交", completed: true, scoreText: "")
            let report = LearningAssignmentReport(courses: [course], assignments: [row], warnings: [],
                refreshedCourseKeys: [course.key], accountKey: "fixture")
            try cache.save(.init(cg: nil, cgUpdatedAt: nil, reports: [.mooc: report], updatedAt: [.mooc: Date()]))
        } else {
            guard let saved = vault.load(), saved.user == DemoData.user, saved.userAgent == "Fixture WebKit",
                  let cookie = saved.restoredCookies().first, cookie.value == "restart-fixture",
                  cookie.path == "/https/fixture/portal", cookie.isSecure, cookie.isHTTPOnly else {
                throw NetworkError(message: "Saved browser session did not survive process restart")
            }
            guard learningVault.load()?.restoredCookies().first?.value == "learning-fixture",
                  cache.load()?.reports[.mooc]?.assignments.first?.completed == true,
                  AssignmentCacheStore(account: "different-restart-fixture").load() == nil else {
                throw NetworkError(message: "Learning session or account-scoped homework cache did not survive restart")
            }
            learningVault.clear()
            vault.clear()
            guard vault.load() == nil else { throw NetworkError(message: "Session logout cleanup failed") }
        }
        try "PASS: Keychain portal/learning sessions and account-scoped homework cache \(save ? "save" : "restore after process restart and clear")".write(to: output, atomically: true, encoding: .utf8)
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
        let evening = Calendar.current.date(bySettingHour: 21, minute: 0, second: 0, of: Date())!
        let morning = Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: Date())!
        guard AppTheme.daylightSymbol(at: evening) == "moon.stars.fill", AppTheme.daylightSymbol(at: morning) == "sun.max.fill" else {
            throw NetworkError(message: "Day/night launch symbol incorrect")
        }
        let requestRepository = PortalRepository(session: SessionStore(client: client))
        try await requestRepository.verifyRequestRecovery()
        let scrollActivity = TabBarScrollActivity()
        scrollActivity.moved(by: 20)
        guard scrollActivity.direction == .down else { throw NetworkError(message: "Downward tab minimization failed") }
        scrollActivity.moved(by: -20)
        guard scrollActivity.direction == .up else { throw NetworkError(message: "Upward tab minimization failed") }
        // A held finger can pause without producing a new scroll phase.
        try await waitFor { scrollActivity.direction == nil }
        guard scrollActivity.direction == nil else { throw NetworkError(message: "Paused scroll did not restore tabs") }
        scrollActivity.moved(by: 20)
        scrollActivity.ended()
        try await waitFor { scrollActivity.direction == nil }
        guard scrollActivity.direction == nil else { throw NetworkError(message: "Idle scroll did not restore tabs") }
        scrollActivity.moved(by: 20)
        scrollActivity.ended()
        scrollActivity.moved(by: -20)
        await Task.yield()
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
        browser.webView.load(URLRequest(url: URL(string: "http://127.0.0.1:8787/balance-labels.html")!))
        try await waitFor { browser.title == "Visible wallet" && !browser.isLoading }
        let visibleBalance = try await browser.syncCardBalance()
        guard visibleBalance.balance == 32.10 && visibleBalance.subsidy == 0 && visibleBalance.status == "正常卡" else {
            throw NetworkError(message: "Visible website wallet was not synchronized")
        }
        let cardBridge = CardWebBridge(baseURL: URL(string: "http://127.0.0.1:8787")!, entryURL: URL(string: "http://127.0.0.1:8787/card-login.html")!)
        let cardStore = WKWebsiteDataStore.nonPersistent()
        cardBridge.use(store: cardStore)
        let balance = try await cardBridge.balance(client: client)
        guard balance.balance == 66.5 && balance.subsidy == 7.5 else { throw NetworkError(message: "WebKit card balance incorrect") }
        let refreshed = try await cardBridge.balance(client: client)
        guard refreshed.balance == balance.balance else { throw NetworkError(message: "Card refresh lost its authenticated session") }
        let statement = try await cardBridge.bills(client: client, year: 2026, month: 10)
        guard statement.bills.count == 2 && !statement.truncated,
              statement.bills.allSatisfy({ $0.amount == -5 && $0.station == "一食堂" && $0.time != nil }) else {
            throw NetworkError(message: "WebKit card GB2312 decoding, header columns or stateful paging incorrect")
        }
        for mode in ["repeat-bills", "unknown-bills", "empty-bills"] {
            let cookie = HTTPCookie(properties: [.name: mode, .value: "1", .domain: "127.0.0.1", .path: "/"])!
            await cardStore.httpCookieStore.setCookie(cookie)
            do {
                let result = try await cardBridge.bills(client: client, year: 2026, month: 10)
                guard mode == "empty-bills", result.bills.isEmpty else {
                    throw NetworkError(message: "Invalid card response was accepted as a statement")
                }
            } catch {
                let message = NetworkError.from(error).message
                guard (mode == "repeat-bills" && message.contains("翻页未推进"))
                    || (mode == "unknown-bills" && message.contains("结构未识别")) else { throw error }
            }
            await cardStore.httpCookieStore.deleteCookie(cookie)
        }
        let hiddenWallet = HTTPCookie(properties: [.name: "hide-wallet", .value: "1", .domain: "127.0.0.1", .path: "/"])!
        await cardStore.httpCookieStore.setCookie(hiddenWallet)
        let withoutWallet = try await cardBridge.bills(client: client, year: 2026, month: 10)
        guard withoutWallet.bills.count == 2 else { throw NetworkError(message: "Bills depended on wallet field parsing") }
        await cardStore.httpCookieStore.deleteCookie(hiddenWallet)
        let adopted = CardWebBridge(baseURL: URL(string: "http://127.0.0.1:8787")!, entryURL: URL(string: "http://127.0.0.1:8787/card-login.html")!)
        adopted.use(store: cardStore, currentURL: URL(string: "http://127.0.0.1:8787/selfsearch/User/ConsumeInfo.aspx")!)
        let adoptedBalance = try await adopted.balance(client: client)
        guard adoptedBalance.balance == 66.5 else { throw NetworkError(message: "Adopted website session was replaced by SSO") }
        browser.webView.load(URLRequest(url: URL(string: "http://127.0.0.1:8787/assignment/")!))
        try await waitFor { browser.title == "CG 作业" && !browser.isLoading }
        let cg = try await browser.syncCGAssignments()
        guard cg.assignments.count == 3, cg.warnings.count == 1,
              let first = cg.assignments.first(where: { $0.id == "1" }), first.completedCount == 1,
              first.problems[1].status == .notSubmitted, first.deadlineText == "2026-11-10 23:59:59",
              let second = cg.assignments.first(where: { $0.id == "2" }), second.late,
              second.problems.map(\.status) == [.needsWork, .submitted],
              cg.assignments.first(where: { $0.id == "3" })?.loaded == false else {
            let summary = cg.assignments.map { "\($0.id)=\($0.problems.map(\.status)) deadline=\($0.deadlineText)" }.joined(separator: "; ")
            throw NetworkError(message: "CG assignment enumeration, deadlines, status or partial failure incorrect: \(summary), warnings=\(cg.warnings)")
        }
        let proxied = try await browser.webView.callAsyncJavaScript(CGAssignmentReport.browserScript,
            arguments: ["rootURL": "http://127.0.0.1:8787/http/fixture/assignment/", "originalRootURL": "http://neucsecg.neu.edu.cn/assignment/"], in: nil, contentWorld: .page)
        let proxiedCG = try CGAssignmentReport.decode(proxied ?? [:])
        guard proxiedCG.assignments.count == 3,
              proxiedCG.assignments.first(where: { $0.id == "2" })?.problems.count == 2 else {
            throw NetworkError(message: "CG gateway root-relative or relative links failed")
        }
        let moocCourse = ["id": "NEU-1", "termID": "1", "title": "测试课程", "url": "https://www.icourse163.org/mooc/learn/NEU-1/assessments?tid=1"]
        let moocData: [String: Any] = ["chapters": [["id": 1, "lessons": [], "homeworks": [
            ["id": 1, "name": "第一周作业", "contentType": 3, "deadline": 1893456000000, "usedTryCount": 1],
            ["id": 2, "name": "第一周测验", "contentType": 2, "deadline": 1893456000000]
        ]]]]
        let moocJSON = String(data: try JSONSerialization.data(withJSONObject: moocData), encoding: .utf8)!
        let moocRaw = try await browser.webView.callAsyncJavaScript(MOOCScripts.readCourse,
            arguments: ["html": "<html></html>", "responses": [["raw": moocJSON, "termID": "1"]], "course": moocCourse], in: nil, contentWorld: .page)
        guard let moocPayload = moocRaw as? [String: Any], moocPayload["recognized"] as? Bool == true else {
            throw NetworkError(message: "MOOC outline was not recognized")
        }
        let moocRows = try LearningAssignmentReport.decodeRows(moocPayload["assignments"] ?? [], platform: .mooc)
        guard moocRows.count == 2, moocRows[0].completed, !moocRows[1].completed, moocRows[0].deadline != nil,
              moocRows[0].url.path.hasSuffix("/assessments") else { throw NetworkError(message: "MOOC fields or destination incorrect") }
        let cxHTML = """
        <html><ul class="work-list"><li data="https://mooc1.chaoxing.com/mooc-ans/mooc2/work/task?workId=1"><p class="overHidden2">未交作业</p><p class="status">未交</p><div class="time notOver">剩余90小时37分钟</div></li>
        <li data="https://mooc1.chaoxing.com/mooc-ans/mooc2/work/task?workId=2"><p class="overHidden2">待批阅作业</p><p class="status">待批阅</p></li></ul><div id="page"><li>1</li><li>3</li></div></html>
        """
        let cxRaw = try await browser.webView.callAsyncJavaScript(ChaoxingAssignments.pageScript,
            arguments: ["html": cxHTML, "pageURL": "https://mooc1.chaoxing.com/mooc-ans/mooc2/work/list", "courseKey": "1.1", "courseTitle": "测试课程"], in: nil, contentWorld: .page)
        guard let cxPayload = cxRaw as? [String: Any], cxPayload["pages"] as? Int == 3 else { throw NetworkError(message: "Chaoxing pagination incorrect") }
        let cxRows = try LearningAssignmentReport.decodeRows(cxPayload["assignments"] ?? [], platform: .chaoxing)
        guard cxRows.count == 2, !cxRows[0].completed, cxRows[1].completed, cxRows[0].deadline != nil,
              cxRows[1].deadline == nil else { throw NetworkError(message: "Chaoxing status or deadline incorrect") }
        browser.webView.load(URLRequest(url: URL(string: "http://127.0.0.1:8787/home.htm")!))
        try await waitFor { browser.title == "MOOC courses" && !browser.isLoading }
        try await verifyMOOCCourseCards(source: browser.webView)
        try await verifyMOOCAllCourses(source: browser.webView)
        browser.webView.load(URLRequest(url: URL(string: "http://127.0.0.1:8787/card-menu.html")!))
        try await waitFor { browser.title == "Card menu" && !browser.isLoading }
        try await browser.openCardQuery("交易汇总信息")
        try await waitFor { browser.title == "Card summary" && !browser.isLoading }
        let thumbnail = await client.fetchNewsThumbnail(NewsItem(id: "thumbnail", title: "测试", date: "", category: "", url: "http://127.0.0.1:8787/article.html", picUrl: ""))
        guard let thumbnail, UIImage(data: thumbnail) != nil else { throw NetworkError(message: "Article first image not decoded") }
        try "PASS: CG legacy/AI-panel problems and gateway URLs, MOOC assignment fields and one-click multi-page MOOC/SPOC sync, Chaoxing pagination/status/deadlines, day/night launch symbols, interrupted request retry, real cancellation and account isolation, visible wallet synchronization, live input properties and iframe wallet, bills without wallet fields, tab scroll directions, pause/idle restore, cancelled restore, reset/jitter, web permission purposes, geolocation API, WebKit card SSO, required Referer, authenticated refresh and adopted session, real balance, ASP.NET hidden state, bill query/pagination, article first image, page load, session UA, find, target-blank, back, forward, desktop, zoom, PDF, entry, download".write(to: output, atomically: true, encoding: .utf8)
    } catch {
        try? ("FAIL: " + error.localizedDescription).write(to: output, atomically: true, encoding: .utf8)
    }
}
''', encoding="utf-8")
fixtures = destination / "fixtures"
fixtures.mkdir(exist_ok=True)
(fixtures / "index.html").write_text('''<!doctype html><html lang="zh"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>校园网页功能验证</title><style>body{font:17px -apple-system;padding:24px;color:#213060;background:#f3f5fb}h1{font-size:28px}a{display:block;background:white;border-radius:16px;padding:18px;margin:14px 0;color:#3553a2;text-decoration:none}small{color:#6d7487}</style><small>NEU · 校园浏览器</small><h1>更顺手的校园网页</h1><p>查找、缩放、分享和下载，都在手边。</p><a id="popup" target="_blank" href="second.html">打开新窗口链接 ↗</a><a id="download" download="campus-guide.txt" href="download.txt">下载校园指南 ↓</a><p>下方工具栏提供前进、后退、刷新与分享。</p></html>''', encoding="utf-8")
(fixtures / "second.html").write_text('<meta charset="utf-8"><title>第二页</title><h1>导航成功</h1>', encoding="utf-8")
(fixtures / "balance-labels.html").write_text('<meta charset="utf-8"><title>Visible wallet</title><div>卡状态：正常卡</div><div>主钱包余额：32.10元</div><div>补助余额：0元</div>', encoding="utf-8")
(fixtures / "card-menu.html").write_text('<title>Card menu</title><iframe src="card-links.html"></iframe>', encoding="utf-8")
(fixtures / "card-links.html").write_text('<meta charset="utf-8"><a target="_top" href="card-summary.html">交易汇总信息</a>', encoding="utf-8")
(fixtures / "card-summary.html").write_text('<meta charset="utf-8"><title>Card summary</title><p>汇总查询已打开</p>', encoding="utf-8")
(fixtures / "download.txt").write_text("NEU-Lumen download fixture", encoding="utf-8")
(fixtures / "home.htm").write_text('''<meta charset="utf-8"><title>MOOC courses</title><div id="j-coursewrap">
<a onclick="window.open('/mooc/learn/NEU-1/assessments?tid=42')"><img alt="课程一"></a>
<a onclick="location.href='/spoc/learn/NEU-2?tid=43'"><img alt="课程二"></a></div>''', encoding="utf-8")

shutil.copyfile(root / "NEU-Lumen/Assets.xcassets/NEULogo.imageset/logo.png", fixtures / "article-first.png")
(fixtures / "article.html").write_text('<html><header><img src="/missing-logo.png"></header><div class="wp_articlecontent"><p>正文</p><img src="article-first.png"></div></html>', encoding="utf-8")
(fixtures / "card-login.html").write_text('<html><form action="/selfsearch/SSOLogin.aspx" method="post"><input name="username" value="fixture"><input name="timestamp" value="123"><input name="auid" value="signed"></form><script>document.forms[0].submit()</script></html>', encoding="utf-8")

grades_source = destination / "NEU-Lumen/Features/Grades/GradesView.swift"
grades_source.write_text(grades_source.read_text(encoding="utf-8").replace(
    '@State private var platform = LearningPlatform.cg',
    '@State private var platform = ProcessInfo.processInfo.arguments.contains("--screen=mooc") ? LearningPlatform.mooc : ProcessInfo.processInfo.arguments.contains("--screen=chaoxing") ? .chaoxing : .cg'
), encoding="utf-8")

platform_source = destination / "NEU-Lumen/Core/Models/LearningAssignments.swift"
platform_source.write_text(platform_source.read_text(encoding="utf-8").replace(
    'return host == "www.icourse163.org" || host == "icourse163.org"',
    'return host == "127.0.0.1" || host == "www.icourse163.org" || host == "icourse163.org"'
), encoding="utf-8")
reader_source = destination / "NEU-Lumen/Core/Networking/LearningWebReader.swift"
with reader_source.open("a", encoding="utf-8") as stream:
    stream.write(r'''

@MainActor
func verifyMOOCCourseCards(source: WKWebView) async throws {
    let courses = try await MOOCCourseNavigator(source: source).discover()
    guard courses.count == 2, courses[0].id == "NEU-1", courses[0].termID == "42",
          courses[1].id == "NEU-2", courses[1].termID == "43", courses[1].activeTermID == "99" else {
        throw NetworkError(message: "MOOC no-href card discovery or target-blank navigation incorrect")
    }
}


final class LearningFixtureProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "www.icourse163.org" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}
    override func startLoading() {
        do {
            let url = request.url!
            let payload: String
            if url.path.contains("getMyLearnedCoursePanelList") {
                var body = request.httpBody ?? Data()
                if body.isEmpty, let stream = request.httpBodyStream {
                    stream.open()
                    defer { stream.close() }
                    var buffer = [UInt8](repeating: 0, count: 4096)
                    while stream.hasBytesAvailable {
                        let count = stream.read(&buffer, maxLength: buffer.count)
                        if count <= 0 { break }
                        body.append(contentsOf: buffer.prefix(count))
                    }
                }
                guard let fields = try JSONSerialization.jsonObject(with: body) as? [String: Int],
                      fields["type"] == 30, fields["psize"] == 50,
                      let page = fields["p"], let type = fields["courseType"] else {
                    throw NetworkError(message: "Incorrect course-list request")
                }
                let ids = type == 1 ? (page == 1 ? Array(1...50) : [51]) : [52]
                let courses: [[String: Any]] = ids.map { id in
                    ["id": id, "name": "课程 \(id)", "mode": type == 1 ? 0 : 20,
                     "schoolPanel": ["shortName": "NEU"], "termPanel": ["id": id + 100]]
                }
                payload = String(data: try JSONSerialization.data(withJSONObject: ["code": 0,
                    "result": ["result": courses, "pagination": ["totleCount": type == 1 ? 51 : 1]]]), encoding: .utf8)!
            } else if url.path.contains("courseBean.") {
                payload = #"{"result":{"id":99,"name":"软件测试课程","endTime":1794326399000,"chapters":[{"id":1,"name":"作业与测验章节","endTime":1794326399000,"lessons":[],"homeworks":[{"id":1,"name":"极限简答作业","contentType":3,"test":{"userSubmitStatus":1}},{"id":2,"name":"单元测验","contentType":2,"test":{"usedTryCount":1}},{"id":3,"name":"考试","contentType":6,"test":{"userSubmitStatus":1}}]}]}}"#
            } else if url.path.contains("/learn/") {
                payload = "<html><title>课程</title></html>"
            } else {
                throw NetworkError(message: "Unexpected learning fixture URL")
            }
            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json; charset=utf-8"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(payload.utf8))
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
}

@MainActor
func verifyMOOCAllCourses(source: WKWebView) async throws {
    let cookie = HTTPCookie(properties: [.name: "NTESSTUDYSI", .value: "fixture-learning", .domain: ".icourse163.org", .path: "/", .secure: "TRUE"])!
    await source.configuration.websiteDataStore.httpCookieStore.setCookie(cookie)
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [LearningFixtureProtocol.self]
    let report = try await LearningWebReader(webView: source, configuration: configuration).read(.mooc)
    guard report.courses.count == 52, report.refreshedCourseKeys.count == 52,
          report.assignments.count == 104, report.assignments.allSatisfy(\.completed),
          report.assignments.allSatisfy({ ["作业", "测验"].contains($0.kind) }), report.warnings.isEmpty,
          report.courses.last?.url.path == "/spoc/learn/NEU-52" else {
        throw NetworkError(message: "One-click sync did not read all paginated MOOC and SPOC courses")
    }
}
''')

browser_source = destination / "NEU-Lumen/Features/Web/PortalWebView.swift"
browser_source.write_text(browser_source.read_text(encoding="utf-8").replace(
    'guard original.host == "ecard.neu.edu.cn" else {',
    'guard ["ecard.neu.edu.cn", "127.0.0.1"].contains(original.host ?? "") else {'
).replace(
    'guard original.host == "neucsecg.neu.edu.cn" else {',
    'guard ["neucsecg.neu.edu.cn", "127.0.0.1"].contains(original.host ?? "") else {'
), encoding="utf-8")

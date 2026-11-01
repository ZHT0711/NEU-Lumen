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
        news = DemoData.news
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
                case "grades": GradesView()
                case "browser":
                    NavigationStack { PortalWebViewScreen(url: URL(string: "http://127.0.0.1:8787/index.html")!) }
                default: HomeView(selection: .constant(.home))
                }
            } else { ProgressView() }
        }
        .overlay(alignment: .bottomTrailing) {
            if ProcessInfo.processInfo.arguments.contains("--browser-checks") {
                PortalWebView(browser: testBrowser).frame(width: 1, height: 1).opacity(0.01)
            }
        }
        .task {
            environment.repository.seedUIValidation()
            ready = true
            if ProcessInfo.processInfo.arguments.contains("--browser-checks") {
                await runBrowserChecks(testBrowser, client: environment.session.client)
            }
        }
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
        await browser.start(URL(string: "http://127.0.0.1:8787/index.html")!, client: client)
        try await waitFor { browser.title == "校园网页功能验证" && !browser.isLoading }
        guard browser.webView.findInteraction != nil else { throw NetworkError(message: "Find unavailable") }
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
        try "PASS: page load, find, target-blank, back, forward, desktop, zoom, PDF, entry, download".write(to: output, atomically: true, encoding: .utf8)
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

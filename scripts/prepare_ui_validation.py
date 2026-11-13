"""Create a disposable simulator fixture; fixture code never enters the IPA."""
from pathlib import Path
import shutil
import sys

from ui_layout_fixture import inject as inject_measured_ui

root = Path(__file__).resolve().parents[1]
destination = Path(sys.argv[1]).resolve()
# Reject all paths inside/above the Release source tree, including symlink aliases.
if destination == root or root in destination.parents or destination in root.parents:
    raise RuntimeError("UI fixture destination must be outside the production repository")
destination.mkdir(parents=True, exist_ok=True)
for name in ["NEU-Lumen", "NEU-LumenLiveActivity", "NEU-Lumen.xcodeproj"]:
    shutil.copytree(root / name, destination / name, dirs_exist_ok=True)
inject_measured_ui(root, destination)
demo_source = destination / "NEU-Lumen/Core/Services/DemoData.swift"
demo_source.write_text(demo_source.read_text(encoding="utf-8").replace(
    'department: "计算机科学与工程学院"', 'department: "未来技术学院"'
), encoding="utf-8")
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
        loadedForSID = session.user?.sid.isEmpty == false ? session.user!.sid : (session.user?.uid ?? "")
        loadedForEpoch = session.requestEpoch
        // Synthetic screenshot-only source values; never uploaded or used by the Release IPA.
        user = DemoData.user
        dataCards = DemoData.dataCards
        apps = DemoData.apps
        appsLoaded = true
        favorites.activate(account: loadedForSID ?? "", apps: apps)
        cardBalance = CardBalance(balance: 66.50, subsidy: 7.50, status: "正常卡")
        cardState = .loaded
        cardUpdatedAt = Date()
        netInfo = NetUsageInfo(balance: 25.00, monthBytes: 3 * 1024 * 1024 * 1024,
            monthSeconds: 7200, monthTimes: 12, flowFromPortal: true)
        netState = .loaded
        electricInfo = ElectricInfo(unbound: true, remainKwh: nil, roomNo: nil, roomLabel: nil, lastReadAt: nil)
        electricState = .loaded
        cardBills = [
            CardBill(time: Date(), timeText: "09:00", subject: "餐费", amount: -8.50, fee: 0, balanceAfter: 66.50, station: "第一食堂"),
            CardBill(time: Date().addingTimeInterval(-86400), timeText: "12:10", subject: "餐费", amount: -12.00, fee: 0, balanceAfter: 75.00, station: "第二食堂")
        ]
        billsCache["\(billsYear)-\(billsMonth)"] = cardBills
        billsState = .loaded
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
        if !items.contains(where: { Calendar.current.isDateInToday($0.date) }) {
            items.append(CourseOccurrence(date: Date(), slot: CourseSlot(weekday: PlannerEvent.mondayBasedWeekday(Date()),
                startMinutes: 600, endMinutes: 695, name: "合成课程：程序设计基础", room: "合成教室 A101")))
        }
        weekCache[start] = items
        weekCache[Calendar.current.date(byAdding: .day, value: 7, to: start)!] = []
        weekCache[Calendar.current.date(byAdding: .day, value: -7, to: start)!] = []
        for key in weekCache.keys { weekStates[key] = .loaded }
        weekState = .loaded
        gradesUpdatedAt = Date()
        netUpdatedAt = Date()
        electricUpdatedAt = Date()
    }

    func verifyLiveActivityPublication() throws {
        try verifyActivityBoundaries()
        func require(_ condition: Bool, _ message: String) throws {
            if !condition { throw NetworkError(message: message) }
        }
        let suite = "live-activity-publication." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = DynamicIslandStore(defaults: defaults)
        let now = Date()
        for kind in DynamicIslandStore.ContentKind.allCases {
            store.kind = kind
            store.accent = "purple"
            guard let state = liveActivityState(store: store, now: now) else {
                throw NetworkError(message: "Seeded source has no payload: " + kind.rawValue)
            }
            try require(state.kind == kind.rawValue && state.accent == "purple", "Source/style mapping changed")
            try require(state.destination.scheme == "neulumen", "Source has an unsafe deep link")
            try require(try JSONEncoder().encode(state).count < 4096, "Activity payload exceeds system size budget")
        }
        let savedAccount = loadedForSID
        loadedForSID = "another-fixture-account"
        store.kind = .custom
        try require(liveActivityState(store: store, now: now) == nil, "Old account data leaked into custom activity")
        loadedForSID = savedAccount
        let savedBalance = cardBalance
        cardBalance = CardBalance(balance: 0, subsidy: 0, status: "正常卡")
        store.kind = .cardBalance
        try require(liveActivityState(store: store, now: now)?.value == "¥0.00", "Real zero balance became unread")
        cardBalance = savedBalance
        let savedWeeks = weekCache
        weekCache = [:]
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: now)!
        let event = PlannerEvent(name: "Fixture future manual", dateIso: PortalDate.isoDay(tomorrow), startMinutes: 600, endMinutes: 660)
        planner.add(event)
        defer { planner.remove(id: event.id); weekCache = savedWeeks; loadedForSID = savedAccount; cardBalance = savedBalance }
        for kind in [DynamicIslandStore.ContentKind.nextCourse, .planner] {
            store.kind = kind
            try require(liveActivityState(store: store, now: now)?.title == event.name, "Future manual event depends on remote timetable cache")
        }
        store.kind = .custom
        store.customTitle = "{course}"
        store.customSubtitle = "余额 {card} · 未读取电量 {electric}"
        store.customValue = "{pending}"
        store.customIcon = "bell.fill"
        store.customDeadlineEnabled = true
        store.customDeadline = now.addingTimeInterval(3600)
        let custom = liveActivityState(store: store, now: now)
        try require(custom?.title == event.name && custom?.symbol == "bell.fill", "Custom variables/icon were not applied")
        try require(custom?.endDate == store.customDeadline && custom?.countdownTitle == "距截止", "Custom target countdown lost its date")
    }
}
''')
# Parent-supplied reliability checks are private-access extensions in this disposable file only.
with repository.open("a", encoding="utf-8") as stream:
    stream.write("\n" + (root / "scripts/repository_validation.swift").read_text(encoding="utf-8") + "\n")
# Screenshot-only fixture routing: never replace real app networking in the IPA,
# and leave browser/session/ActivityKit integration checks on their real code paths.
fixture_source = repository.read_text(encoding="utf-8")
for signature in [
    'func loadCardOverview(force: Bool = false) async {',
    'func loadDisplayWeek(starting sunday: Date, force: Bool = false) async {',
    'func refreshHome(force: Bool = false) async {',
    'func loadCardBalance(force: Bool = false) async {',
    'func loadNetInfo(force: Bool = false) async {',
    'func loadElectric(force: Bool = false) async {',
]:
    if fixture_source.count(signature) != 1:
        raise RuntimeError(f"Screenshot fixture hook changed: {signature}")
    fixture_source = fixture_source.replace(signature, signature + '''
        if ProcessInfo.processInfo.arguments.contains(where: { $0.hasPrefix("--screen=") }) { return }
''')
repository.write_text(fixture_source, encoding="utf-8")
session_source = destination / "NEU-Lumen/Core/Services/SessionStore.swift"
with session_source.open("a", encoding="utf-8") as stream:
    stream.write('''
// Only in the disposable simulator screenshot copy; no authentication or persistence.
extension SessionStore {
    func seedLearningValidationSession(account: String) {
        user = PortalUser(uid: account, name: "Fixture", sid: account, identity: "", department: "", email: "", avatarUrl: "")
        phase = .loggedIn
    }

    func seedScreenshotSession() {
        user = DemoData.user
        phase = .loggedIn
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
                case "services-art": NavigationStack {
                    ScrollView { NativeServicesCarousel(services: NativeCampusService.allCases, searching: true) { _ in }.padding() }
                        .background(Color(.systemGroupedBackground)).navigationTitle("原生服务")
                        .nativeUIFixtureCaption("本次构建原生卡面 · 八项校园主题简笔画")
                }
                case "profile": ProfileView()
                case "favorites": FavoritesEditor()
                case "holidays": ScheduleSettingsSheet()
                case "calendar": SystemCalendarSheet(sunday: Semester.weekStart(forDay: Date()))
                case "grades", "mooc", "chaoxing": GradesView()
                case "card": NavigationStack { CardView() }
                case "live-activity", "live-activity-custom": NavigationStack { LiveActivitySettingsView() }
                case "academic-center": NavigationStack { AcademicCenterView().nativeUIFixtureCaption("模拟器合成学业查询 · 非真实账号数据") }
                case "academic-calendar": NavigationStack { AcademicCalendarView().nativeUIFixtureCaption("模拟器合成校历与周次 · 非学校实际安排") }
                case "academic-plan": NavigationStack { PersonalAcademicProgramDetail(program: PersonalAcademicProgram(id: "SYNTH-PROGRAM", name: "合成个人培养方案 · UI 验证", minimumCredits: "154", facts: [])).nativeUIFixtureCaption("模拟器合成培养方案 · 非真实修读记录") }
                case "native-payment": NavigationStack { NativeServiceHost(initial: .payment).nativeUIFixtureCaption("模拟器合成缴费账户 · 非真实账单") }
                case "native-vpn": NavigationStack { NativeServiceHost(initial: .vpn).nativeUIFixtureCaption("模拟器合成网络状态 · 非实际认证") }
                case "native-affairs": NavigationStack { NativeServiceHost(initial: .affairs).nativeUIFixtureCaption("模拟器合成办事进度 · 非真实申请") }
                case "native-mail": NavigationStack { NativeServiceHost(initial: .mail).nativeUIFixtureCaption("模拟器合成邮箱 · 非真实邮件") }
                case "native-news": NavigationStack { NativeServiceHost(initial: .news).nativeUIFixtureCaption("模拟器合成资讯 · 非学校实际新闻") }
                case "native-agenda": NavigationStack { NativeServiceHost(initial: .agenda).nativeUIFixtureCaption("模拟器合成日程 · 非真实课程安排") }
                case "native-downloads": NavigationStack { NativeServiceHost(initial: .downloads).nativeUIFixtureCaption("模拟器合成下载 · 非真实账号文件") }
                case let token where token.hasPrefix("live-expanded-"):
                    LiveActivityExpandedPreview(token: String(token.dropFirst("live-expanded-".count)))
                case "downloads":
                    BrowserDownloadsView(store: BrowserDownloadStore.shared)
                        .safeAreaInset(edge: .bottom) {
                            Text("模拟器演示下载 · 非真实账号数据")
                                .font(.caption).foregroundStyle(.secondary).padding(6)
                                .frame(maxWidth: .infinity).background(.regularMaterial)
                        }
                case "browser":
                    TabView {
                        NavigationStack { PortalWebViewScreen(url: URL(string: "http://127.0.0.1:8787/index.html")!) }
                            .tabItem { Label("浏览器", systemImage: "globe") }
                    }
                default: MainTabView()
                }
            } else { ProgressView() }
        }
        .background {
            if ready {
                LiveActivityCoordinator()
                BrowserDownloadCoordinator()
                Color.clear.task {
                    guard ProcessInfo.processInfo.arguments.contains(where: { $0.hasPrefix("--screen=") }) else { return }
                    do {
                        try await Task.sleep(for: .milliseconds(750))
                        let marker = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                            .appendingPathComponent("screen-ready.txt")
                        try ("PASS: screenshot page mounted " + screen).write(to: marker, atomically: true, encoding: .utf8)
                    } catch { }
                }
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if ProcessInfo.processInfo.arguments.contains("--browser-checks") ||
                ProcessInfo.processInfo.arguments.contains("--download-checks") || screen == "downloads" || screen == "native-downloads" {
                PortalWebView(browser: testBrowser).frame(width: 1, height: 1).opacity(0.01)
            }
        }
        .task {
            let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let downloadBase = URL(string: "http://127.0.0.1:8787")!
            if let arg = ProcessInfo.processInfo.arguments.first(where: { $0.hasPrefix("--system-island=") }) {
                await prepareSystemIsland(kind: String(arg.dropFirst("--system-island=".count)), manager: environment.liveActivityManager)
                return
            }

            if ProcessInfo.processInfo.arguments.contains("--academic-web-sync-checks") {
                environment.session.seedScreenshotSession()
                await runAcademicWebSyncChecks(environment)
                return
            }
            if ProcessInfo.processInfo.arguments.contains("--live-activity-layout-checks") {
                await runLiveActivityLayoutChecks()
                return
            }
            if ProcessInfo.processInfo.arguments.contains("--learning-save-check") ||
                ProcessInfo.processInfo.arguments.contains("--learning-restore-check") {
                let save = ProcessInfo.processInfo.arguments.contains("--learning-save-check")
                let output = documents.appendingPathComponent(save ? "learning-save.txt" : "learning-restore.txt")
                do {
                    try await verifyLearningProcessRestart(save: save, base: downloadBase)
                    try "PASS: MOOC/Chaoxing localStorage, IndexedDB and session cookies across process restart; account/platform isolation and logout rotation".write(to: output, atomically: true, encoding: .utf8)
                } catch { try? ("FAIL: " + error.localizedDescription).write(to: output, atomically: true, encoding: .utf8) }
                return
            }
            if ProcessInfo.processInfo.arguments.contains("--download-checks") {
                let output = documents.appendingPathComponent("download-checks.txt")
                do {
                    try await verifyBrowserDownloads(browser: testBrowser, client: environment.session.client, base: downloadBase)
                    try await verifyNativeServiceDocument(browser: testBrowser, base: downloadBase)
                    try "PASS: real WKDownload original PDF bytes, cookies/Referer, POST safety, blob/data, duplicate names, progress, cancel/failure, browser close, account isolation and manifest recovery".write(to: output, atomically: true, encoding: .utf8)
                } catch {
                    try? ("FAIL: " + error.localizedDescription).write(to: output, atomically: true, encoding: .utf8)
                }
                return
            }
            if ProcessInfo.processInfo.arguments.contains("--download-save-check") ||
                ProcessInfo.processInfo.arguments.contains("--download-restore-check") {
                let save = ProcessInfo.processInfo.arguments.contains("--download-save-check")
                let output = documents.appendingPathComponent(save ? "download-save.txt" : "download-restore.txt")
                do { try await verifyBrowserDownloadProcessRestart(save: save, base: downloadBase, marker: output) }
                catch { try? ("FAIL: " + error.localizedDescription).write(to: output, atomically: true, encoding: .utf8) }
                return
            }
            if ProcessInfo.processInfo.arguments.contains("--session-save-check") {
                runSessionPersistenceCheck(save: true)
                return
            }
            if ProcessInfo.processInfo.arguments.contains("--session-restore-check") {
                runSessionPersistenceCheck(save: false)
                return
            }
            if ProcessInfo.processInfo.arguments.contains("--live-activity-data-checks") {
                environment.session.seedScreenshotSession()
                environment.repository.seedUIValidation()
                let output = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                    .appendingPathComponent("live-activity-data-checks.txt")
                do {
                    try environment.repository.verifyLiveActivityPublication()
                    try "PASS: activity boundary checks, nine real repository payloads, 4KB budget, account isolation, zero balance, future manual without portal cache and custom target/templates".write(to: output, atomically: true, encoding: .utf8)
                } catch {
                    try? ("FAIL: " + error.localizedDescription).write(to: output, atomically: true, encoding: .utf8)
                }
                return
            }
            if ProcessInfo.processInfo.arguments.contains(where: { $0.hasPrefix("--screen=") }) {
                environment.session.seedScreenshotSession()
                let user = DemoData.user
                BrowserDownloadStore.shared.activate(account: user.sid.isEmpty ? user.uid : user.sid,
                                                     epoch: environment.session.requestEpoch)
                environment.dynamicIslandStore.kind = screen == "live-activity-custom" ? .custom : .nextCourse
            }
            environment.repository.seedUIValidation()
            if screen.hasPrefix("academic-") || screen.hasPrefix("native-") {
                do { try await seedAcademicUIValidation(environment) }
                catch {
                    try? ("FAIL: " + error.localizedDescription).write(to: documents.appendingPathComponent(screen + "-screenshot.txt"), atomically: true, encoding: .utf8)
                    return
                }
            }
            if screen == "live-activity-custom" {
                environment.dynamicIslandStore.customTitle = "{course}"
                environment.dynamicIslandStore.customSubtitle = "卡 {card} · 网 {net}"
                environment.dynamicIslandStore.customValue = "{week}"
                environment.dynamicIslandStore.customIcon = "bell.fill"
                environment.dynamicIslandStore.accent = "purple"
                environment.dynamicIslandStore.customDeadlineEnabled = true
                environment.dynamicIslandStore.customDeadline = Date().addingTimeInterval(3600)
            }
            if screen == "home-nanhu" { environment.repository.setCampusOverride(.nanhu) }
            if screen == "downloads" || screen == "native-downloads" {
                // Only synthetic localhost responses enter this disposable simulator container.
                let user = DemoData.user
                BrowserDownloadStore.shared.activate(account: user.sid.isEmpty ? user.uid : user.sid)
                let output = documents.appendingPathComponent("download-screenshot.txt")
                do {
                    try await seedBrowserDownloadScreenshot(browser: testBrowser, client: environment.session.client, base: downloadBase)
                    ready = true
                    try "PASS: real WKDownload synthetic screenshot has active, complete, cancelled and failed rows; no campus account data".write(to: output, atomically: true, encoding: .utf8)
                } catch { try? ("FAIL: " + error.localizedDescription).write(to: output, atomically: true, encoding: .utf8) }
                return
            }
            ready = true
            await writeNativeUIValidationMarker(screen: screen, environment: environment)
            if ProcessInfo.processInfo.arguments.contains("--live-activity-checks") {
                await runLiveActivityChecks(environment.liveActivityManager)
            }
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
        try await requestRepository.verifyDataReliability()
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
        let downloads = BrowserDownloadStore.shared
        let fixtureUser = DemoData.user
        downloads.activate(account: fixtureUser.sid.isEmpty ? fixtureUser.uid : fixtureUser.sid)
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
        let priorExports = Set(downloads.records.map(\.id))
        await browser.exportPDF()
        guard let exported = downloads.records.first(where: {
            !priorExports.contains($0.id) && $0.kind == .webpagePDF && $0.state == .completed
        }), let pdf = downloads.previewURL(for: exported.id),
            (try Data(contentsOf: pdf)).starts(with: Data("%PDF-".utf8)) else {
            throw NetworkError(message: "Persisted webpage PDF export failed")
        }
        browser.showsDownloads = false
        browser.goToEntry()
        try await waitFor { browser.title == "校园网页功能验证" && !browser.isLoading }
        let priorFiles = Set(downloads.records.map(\.id))
        _ = try await browser.webView.evaluateJavaScript("document.getElementById('download').click()")
        try await waitFor { downloads.records.contains { !priorFiles.contains($0.id) && $0.state == .completed } }
        guard let item = downloads.records.first(where: { !priorFiles.contains($0.id) && $0.state == .completed }),
              let download = downloads.previewURL(for: item.id),
              try String(contentsOf: download, encoding: .utf8) == "NEU-Lumen download fixture" else {
            throw NetworkError(message: "Persisted original download contents failed")
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
# Real WebKit download checks live outside the Release source tree.
shutil.copyfile(root / "Tests/BrowserDownloads/WebKitValidation.swift",
                destination / "NEU-Lumen/App/BrowserDownloadValidation.swift")
shutil.copyfile(root / "Tests/Learning/PersistenceValidation.swift",
                destination / "NEU-Lumen/App/LearningPersistenceValidation.swift")
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
).replace(
    '@State private var section = "作业"',
    '@State private var section = ProcessInfo.processInfo.arguments.contains("--screen=grades") ? "成绩" : "作业"'
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

manager_source = destination / 'NEU-Lumen/Core/Services/DynamicIslandActivityManager.swift'
with manager_source.open('a', encoding='utf-8') as stream:
    stream.write(r'''

extension DynamicIslandActivityManager {
    func settleForValidation() async throws {
        for _ in 0..<200 {
            if worker == nil { return }
            try await Task.sleep(for: .milliseconds(50))
        }
        throw NetworkError(message: "ActivityKit operations did not settle")
    }
}
''')

(destination / 'NEU-Lumen/App/LiveActivityValidation.swift').write_text(r'''
import ActivityKit
import SwiftUI

@MainActor
func runLiveActivityChecks(_ manager: DynamicIslandActivityManager) async {
    let output = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("live-activity-checks.txt")
    func require(_ condition: Bool, _ message: String) throws {
        if !condition { throw NetworkError(message: message) }
    }
    func waitFor(_ condition: () -> Bool, _ message: String) async throws {
        for _ in 0..<200 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(50))
        }
        throw NetworkError(message: message)
    }
    func active() -> [Activity<NEULumenActivityAttributes>] {
        Activity<NEULumenActivityAttributes>.activities.filter {
            $0.activityState == .active || $0.activityState == .stale
        }
    }
    do {
        for _ in 0..<100 {
            if UIApplication.shared.applicationState == .active { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        try require(UIApplication.shared.applicationState == .active, "Fixture is not foreground")
        try require(ActivityAuthorizationInfo().areActivitiesEnabled, "Simulator disabled Live Activities")
        let legacy = try JSONDecoder().decode(NEULumenActivityAttributes.self,
            from: Data(#"{"campus":"浑南校区"}"#.utf8))
        try require(legacy.accountID == nil, "Legacy activity attributes failed to decode")
        let legacyState = try JSONDecoder().decode(NEULumenActivityAttributes.ContentState.self,
            from: Data(#"{"title":"旧配置","subtitle":"","value":"","kind":"custom","updatedAt":0}"#.utf8))
        try require(legacyState.endDate == nil && legacyState.symbol == "sparkles", "Legacy state failed to decode")
        try require(legacyState.accent == nil && legacyState.symbolName == nil && legacyState.secondaryValue == nil && legacyState.progress == nil,
            "Legacy content did not decode optional new fields")

        var request = DynamicIslandActivityManager.Request(enabled: true, accountID: "fixture-a",
            campus: "浑南校区", state: .init(title: "原生实时活动", subtitle: "ActivityKit 生命周期验证",
            value: "", kind: "custom", updatedAt: .distantPast), isForeground: true,
            refreshDate: Date(), contentKind: "custom")
        manager.synchronize(request)
        try await manager.settleForValidation()
        try await waitFor({ manager.isRunning && active().count == 1 },
            "Native start failed: \(manager.status) \(manager.lastError ?? "")")
        let firstID = active()[0].id
        request.state?.title = "已更新的原生实时活动"
        manager.synchronize(request)
        try await manager.settleForValidation()
        try await waitFor({ active().first?.id == firstID && active().first?.content.state.title == request.state?.title },
            "Native update did not propagate: id=\(active().first?.id ?? "none"), title=\(active().first?.content.state.title ?? "none")")

        request.state?.accent = "pink"
        request.state?.symbolName = "heart.fill"
        request.state?.secondaryValue = "附加信息"
        request.state?.progress = 0.5
        let customTarget = Date().addingTimeInterval(3600)
        request.state?.endDate = customTarget
        request.state?.countdownTitle = "距截止"
        manager.synchronize(request)
        try await manager.settleForValidation()
        try await waitFor({ active().first?.content.state.accent == "pink" && active().first?.content.state.symbol == "heart.fill" },
            "Native theme/icon update did not reach ActivityKit")
        try require(abs((active().first?.content.staleDate ?? .distantPast).timeIntervalSince(customTarget)) < 1,
            "Custom countdown did not expire at its target")

        request.enabled = false
        manager.synchronize(request)
        try await manager.settleForValidation()
        try await waitFor({ !manager.isRunning && active().isEmpty }, "Disabling left an activity running")
        request.enabled = true
        request.isForeground = false
        manager.synchronize(request)
        try await manager.settleForValidation()
        try require(active().isEmpty, "Started an activity in the background")
        request.isForeground = true
        manager.synchronize(request)
        try await manager.settleForValidation()
        try await waitFor({ active().count == 1 }, "Foreground resume did not start an activity")

        request.accountID = "fixture-b"
        request.state?.title = "另一个账号的实时活动"
        manager.synchronize(request)
        try await manager.settleForValidation()
        try await waitFor({ active().count == 1 && active().first?.attributes.accountID == "fixture-b" },
            "Account switch kept the previous account's activity")
        let dismissed = active()[0]
        await dismissed.end(nil, dismissalPolicy: .immediate)
        for _ in 0..<100 {
            if !manager.isRunning { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        try require(!manager.isRunning, "System end was not observed")
        manager.synchronize(request)
        try await manager.settleForValidation()
        try require(active().isEmpty, "A dismissed activity was automatically recreated")
        manager.restart()
        try await manager.settleForValidation()
        try await waitFor({ active().count == 1 }, "Explicit restart failed")

        let restored = DynamicIslandActivityManager()
        let restoredID = active()[0].id
        var loading = request
        loading.state = nil
        loading.contentReady = false
        restored.synchronize(loading)
        try await restored.settleForValidation()
        try require(active().count == 1 && active()[0].id == restoredID,
            "Loading account data discarded or duplicated the restored activity")
        restored.synchronize(request)
        try await restored.settleForValidation()
        try require(active().first?.id == restoredID, "Restore created a duplicate")
        request.accountID = nil
        restored.synchronize(request)
        try await restored.settleForValidation()
        try await waitFor({ active().isEmpty }, "Logout left account content visible")

        // Leave a real course activity visible for a system screenshot.
        request.accountID = "fixture-preview"
        request.state = .init(title: "程序设计基础", subtitle: "浑南 A101", value: "09:00",
            kind: "nextCourse", updatedAt: .distantPast,
            startDate: Date().addingTimeInterval(-600), endDate: Date().addingTimeInterval(2400))
        manager.synchronize(request)
        try await manager.settleForValidation()
        try await waitFor({ active().count == 1 }, "Preview activity failed to start")
        try "PASS: native ActivityKit start, update, disable, foreground, account isolation, dismissal, restart, restore, logout; id=\(active()[0].id)"
            .write(to: output, atomically: true, encoding: .utf8)
    } catch {
        try? ("FAIL: " + error.localizedDescription).write(to: output, atomically: true, encoding: .utf8)
    }
}
''', encoding='utf-8')

shutil.copyfile(root / "scripts/system_island_fixture.swift", destination / "NEU-Lumen/App/SystemIslandValidation.swift")

# Explicitly synthetic service fixtures, applied only to this disposable Debug copy.
def service_fixture(relative, signature, insertion, extension=''):
    path = destination / relative
    source = path.read_text(encoding='utf-8')
    if source.count(signature) != 1:
        raise RuntimeError(f'Native service fixture hook changed: {signature}')
    path.write_text(source.replace(signature, signature + insertion) + extension, encoding='utf-8')

service_fixture('NEU-Lumen/Features/Academic/PersonalAcademicProgramView.swift',
                'func load(session: SessionStore, program: PersonalAcademicProgram? = nil) async {', r'''
        if ProcessInfo.processInfo.arguments.contains("--screen=academic-plan") {
            let sample = PersonalAcademicProgram(id: "SYNTH-PROGRAM", name: "合成个人培养方案 · UI 验证", minimumCredits: "154", facts: [])
            programs = [sample]
            tree = AcademicProgramTree(program: sample, nodes: [
                AcademicProgramNode(id: sample.id, parentID: nil, name: sample.name, minimumCredits: "154", minimumGroups: nil, kind: "培养方案", inherited: false, referenced: false, mustPass: false),
                AcademicProgramNode(id: "SYNTH-PLATFORM", parentID: sample.id, name: "合成通识教育平台", minimumCredits: "48", minimumGroups: "2", kind: "平台", inherited: false, referenced: false, mustPass: false),
                AcademicProgramNode(id: "SYNTH-GROUP-A", parentID: "SYNTH-PLATFORM", name: "合成公共基础课组", minimumCredits: "24", minimumGroups: nil, kind: "课组", inherited: false, referenced: true, mustPass: true),
                AcademicProgramNode(id: "SYNTH-GROUP-B", parentID: "SYNTH-PLATFORM", name: "合成人文素养课组", minimumCredits: "8", minimumGroups: nil, kind: "课组", inherited: false, referenced: false, mustPass: false)])
            loading = false; error = nil; return
        }
''')
# Open the actual native detail diagram in this screenshot-only copy.
program_view = destination / 'NEU-Lumen/Features/Academic/PersonalAcademicProgramView.swift'
program_source = program_view.read_text(encoding='utf-8').replace('private struct PersonalAcademicProgramDetail:', 'struct PersonalAcademicProgramDetail:')
program_view.write_text(program_source, encoding='utf-8')

service_fixture('NEU-Lumen/Features/Services/NativeNewsView.swift',
                'func load(session: SessionStore, reset: Bool) async {', r'''
        if ProcessInfo.processInfo.arguments.contains("--screen=native-news") {
            channels = [NewsChannel(id: "synthetic", name: "合成校园资讯")]; channelID = "synthetic"
            items = [NewsItem(id: "SYNTH-N-1", title: "合成资讯：校园科技文化节活动预告", date: "2026-11-14", category: "合成校园资讯", url: "http://127.0.0.1:8787/article.html", picUrl: ""),
                     NewsItem(id: "SYNTH-N-2", title: "合成资讯：图书馆阅读活动与开放安排", date: "2026-11-13", category: "合成校园资讯", url: "http://127.0.0.1:8787/article.html", picUrl: "")]
            busy = false; hasMore = false; return
        }
''')
service_fixture('NEU-Lumen/Core/Services/NativeMailStore.swift',
                'func connect(session: SessionStore, apps: [PortalApp], server: URL? = nil) async {', r'''
        if ProcessInfo.processInfo.arguments.contains("--screen=native-mail") { seedServiceScreenshot(); return }
''', r'''
extension NativeMailStore {
    func seedServiceScreenshot() {
        email = "synthetic@stu.neu.edu.cn"
        folders = [NativeMailFolder(id: "1", name: "收件箱", total: 3, unread: 1),
                   NativeMailFolder(id: "2", name: "已发送", total: 1, unread: 0)]
        messages = [NativeMailMessage(id: "SYNTH-M-1", subject: "合成通知：图书馆预约提醒", sender: "合成图书馆通知", dateText: "今天 09:00", unread: true),
                    NativeMailMessage(id: "SYNTH-M-2", subject: "合成邮件：本周校园活动", sender: "合成校园服务", dateText: "昨天 15:30", unread: false)]
        loaded = true; loadingWeb = false; busy = false; hasMore = false
    }
}
''')
service_fixture('NEU-Lumen/Features/Services/NativeCampusPages.swift',
                'private func check(force: Bool) async {', r'''
        if ProcessInfo.processInfo.arguments.contains("--screen=native-vpn") {
            campus = false; ticket = true; checkedAt = Date(); return
        }
''')
service_fixture('NEU-Lumen/Features/Services/NativeCampusPages.swift',
                'func load(session: SessionStore, reset: Bool) async {', r'''
        if ProcessInfo.processInfo.arguments.contains("--screen=native-affairs") {
            items = [TodoItem(title: "合成申请：在读证明", instance: "合成办事流水 SYNTH-001", node: "合成节点：审核中", percent: 50, time: "今天 09:00", url: "https://ehall.neu.edu.cn/"),
                     TodoItem(title: "合成申请：场地预约", instance: "合成办事流水 SYNTH-002", node: "合成节点：待受理", percent: 0, time: "昨天 16:00", url: "https://ehall.neu.edu.cn/")]
            loaded = true; hasMore = false; loading = false; return
        }
''')

import Foundation
import Observation

/// 业务仓储：视图只读这里。网络集中在 PortalClient，状态集中在这里。
/// 性能策略：
/// - 周课表按教学周缓存（weekCache），同周切换不重复打教务；
/// - 首页各接口并行拉取（async let），单接口失败不阻塞其它区块；
/// - 成绩整表缓存，仅手动/下拉强制刷新；
/// - 会话过期自动静默重登并重试一次。
@MainActor
@Observable
final class PortalRepository {
    let planner = PlannerEventStore.shared
    let favorites = ServiceFavorites()
    let holidays = HolidayStore()
    let systemCalendar = SystemCalendarBridge()
    let cardWebBridge = CardWebBridge()
    private var cardUsesWebKit = false
    private var cardBalanceRevision = UUID()
    private(set) var newsThumbnails: [String: Data] = [:]
    private var loadingNewsThumbnails: Set<String> = []
    private(set) var newsRevision = 0

    private let session: SessionStore

    private(set) var user: PortalUser?
    private(set) var dataCards: [DataCard] = []
    private(set) var apps: [PortalApp] = []
    private(set) var news: [NewsItem] = []
    private(set) var todos: [TodoItem] = []
    private(set) var hotSearch: [String] = []
    private(set) var homeState: LoadState = .idle
    private(set) var usedOfflineFallback = false

    private var weekCache: [Date: [CourseOccurrence]] = [:]
    private var loadingWeeks: Set<Date> = []
    private(set) var weekState: LoadState = .idle

    private var gradesCache: [GradeSemester]?
    private var gradeRequestID = 0
    private(set) var gradesState: LoadState = .idle
    private(set) var gradesWarning: String?
    private(set) var cgReport: CGAssignmentReport?
    private(set) var cgState: LoadState = .idle
    private(set) var cgUpdatedAt: Date?
    private var cgRequestID = UUID()
    private var cgBrowser: PortalBrowser?
    private(set) var assignmentReports: [LearningPlatform: LearningAssignmentReport] = [:]
    private(set) var assignmentSections: [LearningPlatform: [LearningAssignmentSection]] = [:]
    private(set) var assignmentCacheWarning: String?
    private(set) var assignmentStates: [LearningPlatform: LoadState] = [:]
    private(set) var assignmentUpdatedAt: [LearningPlatform: Date] = [:]
    private var assignmentRequests: [LearningPlatform: UUID] = [:]
    private var assignmentBrowsers: [LearningPlatform: PortalBrowser] = [:]
    private(set) var campusOverride: Campus?
    var suggestedCampus: Campus? { Campus.inferred(from: session.user?.department ?? "") }
    var campus: Campus { campusOverride ?? suggestedCampus ?? .nanhu }

    func setCampusOverride(_ value: Campus?) {
        campusOverride = value
        if let account = loadedForSID, !account.isEmpty {
            UserDefaults.standard.set(value?.rawValue, forKey: "lumen.campus." + account)
        }
    }

    // MARK: 一卡通 / 网费 / 电费

    private(set) var cardBalance: CardBalance?
    private(set) var cardState: LoadState = .idle
    private(set) var cardWarning: String?
    private(set) var cardUpdatedAt: Date?
    private(set) var billsYear: Int = Calendar.current.component(.year, from: Date())
    private(set) var billsMonth: Int = Calendar.current.component(.month, from: Date())
    private(set) var cardBills: [CardBill] = []
    private(set) var billTruncated = false
    private(set) var billsState: LoadState = .idle
    private var billsCache: [String: [CardBill]] = [:]
    private var truncatedCache: [String: Bool] = [:]
    private var billsRequestID = UUID()
    private(set) var netInfo: NetUsageInfo?
    private(set) var netState: LoadState = .idle
    private(set) var electricInfo: ElectricInfo?
    private(set) var electricState: LoadState = .idle

    private static let monthFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM"
        return f
    }()

    /// 电费房间码（宿舍 3 位 + 寝室 4 位，本机保存）。
    var electricRoomCode: String {
        get { UserDefaults.standard.string(forKey: "lumen.electric.room") ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: "lumen.electric.room") }
    }

    private var monthKey: String { Self.monthFormatter.string(from: Calendar.current.date(from: DateComponents(year: billsYear, month: billsMonth))!) }

    private var accountGeneration = UUID()
    private var loadedForSID: String?
    private var appsLoaded = false
    private var appsLoading = false

    init(session: SessionStore) {
        self.session = session
    }

    var ecodeEntryURL: URL { ServiceCatalog(apps: apps).ecodeURL }

    // MARK: - 会话恢复

    /// 登录用户变化时清空缓存，避免串号。
    func ensureLoadedForCurrentUser() async {
        let sid = session.user?.sid.isEmpty == false ? session.user!.sid : (session.user?.uid ?? "")
        guard loadedForSID != sid else { return }
        accountGeneration = UUID()
        campusOverride = UserDefaults.standard.string(forKey: "lumen.campus." + sid).flatMap(Campus.init(rawValue:))
        cardWebBridge.reset()
        cardUsesWebKit = false
        newsThumbnails = [:]
        loadingNewsThumbnails = []
        dataCards = []
        apps = ServiceCatalog.merging([DemoData.apps, cachedApps()])
        appsLoaded = false
        news = []
        todos = []
        hotSearch = []
        weekCache.removeAll()
        loadingWeeks.removeAll()
        gradesCache = nil
        gradeRequestID += 1
        gradesWarning = nil
        cgRequestID = UUID()
        cgBrowser?.webView.stopLoading()
        cgBrowser = nil
        cgReport = nil
        cgState = .idle
        cgUpdatedAt = nil
        assignmentRequests = [:]
        for browser in assignmentBrowsers.values { browser.webView.stopLoading() }
        assignmentBrowsers = [:]
        assignmentReports = [:]
        assignmentSections = [:]
        assignmentCacheWarning = nil
        assignmentStates = [:]
        assignmentUpdatedAt = [:]
        cardBalance = nil
        cardWarning = nil
        cardUpdatedAt = nil
        cardBills = []
        billsCache.removeAll()
        truncatedCache.removeAll()
        netInfo = nil
        electricInfo = nil
        cardState = .idle
        billsState = .idle
        netState = .idle
        electricState = .idle
        homeState = .idle
        weekState = .idle
        gradesState = .idle
        usedOfflineFallback = false
        user = session.user
        favorites.activate(account: sid, apps: apps)
        holidays.activate(account: sid)
        systemCalendar.activate(account: sid)
        loadedForSID = sid
        if !sid.isEmpty, let cached = AssignmentCacheStore(account: sid).load() {
            cgReport = cached.cg
            cgUpdatedAt = cached.cgUpdatedAt
            if cached.cg != nil { cgState = .loaded }
            assignmentReports = cached.reports
            assignmentUpdatedAt = cached.updatedAt
            for (platform, report) in cached.reports {
                assignmentSections[platform] = report.sections(for: platform)
                assignmentStates[platform] = .loaded
            }
        }
    }

    /// 会话过期 → 静默重登 → 重试一次。
    private func withRecovery<T>(_ operation: () async throws -> T) async throws -> T {
        let generation = accountGeneration
        let account = session.user
        func checkRequest() throws {
            try Task.checkCancellation()
            let sameAccount = account.map { previous in
                session.user.map { previous.isSameAccount(as: $0) } ?? false
            } ?? (session.user == nil)
            guard generation == accountGeneration, sameAccount else { throw CancellationError() }
        }
        await session.waitForRecovery()
        do {
            try checkRequest()
            return try await operation()
        } catch {
            try checkRequest()
            if NetworkError.isCancellation(error) {
                await session.waitForRecovery()
                try checkRequest()
                return try await operation()
            }
            if let e = error as? NetworkError, e.isSessionExpired {
                guard await session.silentRelogin() else { throw e }
                try checkRequest()
                user = session.user
                return try await operation()
            }
            throw error
        }
    }

    /// 单接口拉取，失败返回 nil（由调用方决定是否回退演示数据）。
    private func run<T>(_ operation: () async throws -> T) async -> T? {
        do {
            return try await withRecovery(operation)
        } catch {
            return nil
        }
    }

    // MARK: - 首页

    func refreshHome() async {
        if homeState == .loading { return }
        homeState = .loading
        usedOfflineFallback = false
        let client = session.client

        async let cards = run { try await client.fetchDataCards() }
        async let appList = run { try await client.fetchApps() }
        async let newsList = run { try await client.fetchNews() }
        async let todoList = run { try await client.fetchTodos() }
        async let hot = run { try await client.fetchHotSearch() }

        let (cardsValue, appsValue, newsValue, todoValue, hotValue) =
            await (cards, appList, newsList, todoList, hot)

        var anySuccess = false
        if let v = cardsValue {
            dataCards = v
            anySuccess = true
        } else if dataCards.isEmpty {
            dataCards = []
        }
        if let v = appsValue, !v.isEmpty {
            apps = ServiceCatalog.merging([DemoData.apps, cachedApps(), apps, v])
            saveAppsCache()
            appsLoaded = true
            anySuccess = true
        } else if apps.isEmpty {
            apps = ServiceCatalog.merging([DemoData.apps, cachedApps()])
        }
        if let v = newsValue, !v.isEmpty {
            news = v
            newsRevision += 1
            newsThumbnails = newsThumbnails.filter { !$0.value.isEmpty }
            anySuccess = true
        } else if news.isEmpty {
            news = DemoData.news
        }
        if let v = todoValue {
            todos = v
        }
        if let v = hotValue, !v.isEmpty {
            hotSearch = v
        } else if hotSearch.isEmpty {
            hotSearch = DemoData.hotSearch
        }

        user = session.user
        usedOfflineFallback = !anySuccess
        homeState = anySuccess ? .loaded : .failed("门户接口不可用，正在展示离线演示数据")
    }

    func dataCardURL(_ card: DataCard) -> URL {
        if let url = PortalLink.resolve(card.destination) { return url }
        if card.name.contains("卡") && (card.name.contains("余额") || card.name.contains("补助")) { return URL(string: PortalClient.serviceCard)! }
        let terms: [String]
        if card.name.contains("图书") || card.name.contains("借阅") { terms = ["图书馆"] }
        else if card.name.contains("网费") || card.name.contains("流量") { terms = ["网络计费", "网费"] }
        else if card.name.contains("电费") { terms = ["缴费", "电费"] }
        else if card.name.contains("成绩") || card.name.contains("学分") || card.name.contains("绩点") { terms = ["教务系统（新）", "教务系统"] }
        else { terms = [card.name] }
        if let app = apps.first(where: { app in terms.contains { app.name.contains($0) } }), let url = PortalLink.resolve(app.entryUrl()) { return url }
        return URL(string: PortalClient.portalBase)!
    }

    func loadNewsThumbnail(_ item: NewsItem) async {
        guard newsThumbnails[item.id] == nil, !loadingNewsThumbnails.contains(item.id) else { return }
        let generation = accountGeneration
        loadingNewsThumbnails.insert(item.id)
        defer { if generation == accountGeneration { loadingNewsThumbnails.remove(item.id) } }
        let data = await session.client.fetchNewsThumbnail(item)
        guard generation == accountGeneration, !Task.isCancelled else { return }
        newsThumbnails[item.id] = data ?? Data()
    }

    func applyCardBalance(_ balance: CardBalance) {
        cardBalanceRevision = UUID()
        cardUsesWebKit = true
        cardBalance = balance
        cardState = .loaded
        cardWarning = nil
        cardUpdatedAt = Date()
        session.persistWebSession()
    }

    private func cardBalanceWithWebRecovery() async throws -> CardBalance {
        if cardUsesWebKit { return try await cardWebBridge.balance(client: session.client) }
        do { return try await session.client.fetchCardBalance() }
        catch {
            if NetworkError.isCancellation(error) || Task.isCancelled { throw CancellationError() }
            let balance = try await cardWebBridge.balance(client: session.client)
            cardUsesWebKit = true
            return balance
        }
    }

    /// 服务大厅按需加载应用列表（避免冷启动时重复请求）。
    func loadAppsIfNeeded() async {
        guard !appsLoaded, !appsLoading else { return }
        appsLoading = true
        defer { appsLoading = false }
        if let v = await run({ try await session.client.fetchApps() }), !v.isEmpty {
            apps = ServiceCatalog.merging([DemoData.apps, cachedApps(), v])
            saveAppsCache()
            appsLoaded = true
        } else {
            apps = ServiceCatalog.merging([DemoData.apps, cachedApps()])
        }
    }

    /// 服务入口按账号缓存；短公开列表、网络错误不能抹掉完整目录。
    private var appsCacheKey: String? {
        guard let user = session.user else { return nil }
        let account = user.sid.isEmpty ? user.uid : user.sid
        return account.isEmpty ? nil : "lumen.apps." + account
    }

    private func cachedApps() -> [PortalApp] {
        guard let key = appsCacheKey, let data = UserDefaults.standard.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([PortalApp].self, from: data)) ?? []
    }

    private func saveAppsCache() {
        guard let key = appsCacheKey, let data = try? JSONEncoder().encode(apps) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    func loadHotSearchIfNeeded() async {
        guard hotSearch.isEmpty else { return }
        if let v = await run({ try await session.client.fetchHotSearch() }), !v.isEmpty {
            hotSearch = v
        } else {
            hotSearch = DemoData.hotSearch
        }
    }

    // MARK: - 课表

    /// 拉取某天所在教学周；命中缓存直接返回，不重复请求教务。
    /// 同一周已有在途加载时等待其完成，避免快速翻周时请求被吞掉。
    func loadWeek(containing date: Date, force: Bool = false) async {
        let generation = accountGeneration
        let weekStart = Semester.weekStart(forDay: date)
        if !force, weekCache[weekStart] != nil {
            weekState = .loaded
            return
        }
        if !force, loadingWeeks.contains(weekStart) {
            while loadingWeeks.contains(weekStart) {
                guard generation == accountGeneration, !Task.isCancelled else { return }
                try? await Task.sleep(nanoseconds: 120_000_000)
                if weekCache[weekStart] != nil { break }
            }
            if weekCache[weekStart] != nil {
                weekState = .loaded
                return
            }
        }
        if !force, weekCache[weekStart] != nil {
            weekState = .loaded
            return
        }
        loadingWeeks.insert(weekStart)
        weekState = .loading
        defer { if generation == accountGeneration { loadingWeeks.remove(weekStart) } }
        do {
            let list = try await withRecovery {
                try await self.session.client.fetchWeek(anyDayInWeek: date)
            }
            guard generation == accountGeneration else { return }
            weekCache[weekStart] = list
            weekState = .loaded
        } catch {
            guard generation == accountGeneration else { return }
            // 有缓存就继续用缓存，无缓存才报错
            if weekCache[weekStart] == nil {
                weekState = .failed(NetworkError.from(error).message)
            } else {
                weekState = .loaded
            }
        }
    }

    /// 某教学周（周日开始）的门户事件；无缓存返回 nil。
    func portalOccurrences(weekStarting weekStart: Date) -> [CourseOccurrence]? {
        weekCache[weekStart].map { holidays.apply($0) }
    }

    func loadDisplayWeek(starting sunday: Date, force: Bool = false) async {
        await ensureLoadedForCurrentUser()
        let generation = accountGeneration
        await loadWeek(containing: sunday, force: force)
        guard generation == accountGeneration, !Task.isCancelled else { return }
        let nextSunday = Calendar.current.date(byAdding: .day, value: 7, to: sunday)!
        await loadWeek(containing: nextSunday, force: force)
        guard generation == accountGeneration, !Task.isCancelled else { return }
        let first = Calendar.current.date(byAdding: .day, value: 1, to: sunday)!
        let end = Calendar.current.date(byAdding: .day, value: 8, to: sunday)!
        for (target, source) in holidays.replacementDates {
            guard let targetDate = PortalDate.day(target), targetDate >= first, targetDate < end,
                  let sourceDate = PortalDate.day(source) else { continue }
            let sourceWeek = Semester.weekStart(forDay: sourceDate)
            if sourceWeek != sunday && sourceWeek != nextSunday {
                await loadWeek(containing: sourceDate, force: force)
            }
        }
        for year in Set([sunday, nextSunday].map { Calendar.current.component(.year, from: $0) }) {
            await holidays.refresh(year: year)
        }
    }

    func displayWeekOccurrences(starting sunday: Date) -> [CourseOccurrence] {
        let cal = Calendar.current
        let first = cal.date(byAdding: .day, value: 1, to: sunday)!
        let end = cal.date(byAdding: .day, value: 8, to: sunday)!
        let portal = effectivePortalOccurrences(from: first, to: end)
        let custom = planner.events.compactMap { event -> CourseOccurrence? in
            guard let date = PortalDate.day(event.dateIso) else { return nil }
            return CourseOccurrence(date: date, slot: event.toSlot())
        }
        return (portal + custom).filter { $0.date >= first && $0.date < end }.mergeConsecutive()
    }

    func displayWeekIsLoaded(starting sunday: Date) -> Bool {
        let next = Calendar.current.date(byAdding: .day, value: 7, to: sunday)!
        let first = Calendar.current.date(byAdding: .day, value: 1, to: sunday)!
        let end = Calendar.current.date(byAdding: .day, value: 8, to: sunday)!
        let replacementsLoaded = holidays.replacementDates.allSatisfy { target, source in
            guard let date = PortalDate.day(target), date >= first && date < end,
                  let sourceDate = PortalDate.day(source) else { return true }
            return weekCache[Semester.weekStart(forDay: sourceDate)] != nil
        }
        return weekCache[sunday] != nil && weekCache[next] != nil && replacementsLoaded
    }

    private func effectivePortalOccurrences(from first: Date, to end: Date) -> [CourseOccurrence] {
        holidays.apply(HolidayRules.project(weekCache.values.flatMap { $0 }, from: first, to: end,
            replacements: holidays.replacementDates))
    }

    /// 今日时间轴：门户周缓存 ∩ 今天 + 本机日程，合并相邻节次。
    func todayTimeline() -> [CourseOccurrence] {
        let today = Calendar.current.startOfDay(for: Date())
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: today)!
        let portal = effectivePortalOccurrences(from: today, to: tomorrow)
        return (portal + planner.occurrences(onDay: today)).mergeConsecutive()
    }

    /// 下一节未结束的课程。
    func nextCourse() -> CourseOccurrence? {
        let now = Semester.minutesNow()
        return todayTimeline().first { $0.slot.endMinutes > now }
    }

    // MARK: - 成绩

    var cgEntryURL: URL {
        let entry = apps.first { $0.name.contains("CG实验") }?.entryUrl() ?? "http://neucsecg.neu.edu.cn"
        if let url = URL(string: entry), (WebVPN.unwrap(url) ?? url).host == "neucsecg.neu.edu.cn" { return url }
        return URL(string: "http://neucsecg.neu.edu.cn")!
    }

    func loadCGAssignments(force: Bool = false) async {
        await ensureLoadedForCurrentUser()
        if cgState == .loading || (!force && cgReport != nil) { return }
        cgState = .loading
        let generation = accountGeneration
        let request = UUID()
        cgRequestID = request
        do {
            let report = try await withRecovery {
                let browser = PortalBrowser()
                self.cgBrowser = browser
                await browser.start(self.cgEntryURL, client: self.session.client, session: self.session)
                return try await browser.syncCGAssignments()
            }
            guard generation == accountGeneration, request == cgRequestID else { return }
            applyCGReport(report)
        } catch {
            guard generation == accountGeneration, request == cgRequestID else { return }
            cgState = NetworkError.isCancellation(error) ? .idle : .failed(NetworkError.from(error).message)
        }
        cgBrowser = nil
    }

    func applyCGReport(_ report: CGAssignmentReport) {
        cgRequestID = UUID()
        cgBrowser?.webView.stopLoading()
        cgBrowser = nil
        cgReport = report
        cgState = .loaded
        cgUpdatedAt = Date()
        saveAssignmentCache()
        session.persistWebSession()
    }

    func loadAssignments(_ platform: LearningPlatform, force: Bool = false) async {
        if platform == .cg { await loadCGAssignments(force: force); return }
        await ensureLoadedForCurrentUser()
        if assignmentStates[platform] == .loading || (!force && assignmentReports[platform] != nil) { return }
        let generation = accountGeneration
        let request = UUID()
        assignmentRequests[platform] = request
        assignmentStates[platform] = .loading
        let browser = PortalBrowser()
        assignmentBrowsers[platform] = browser
        do {
            await browser.start(platform.entryURL, client: session.client, session: session)
            let report = try await browser.syncAssignments(platform, previous: assignmentReports[platform])
            guard accountGeneration == generation, assignmentRequests[platform] == request else { return }
            applyAssignments(report, platform: platform)
        } catch {
            guard accountGeneration == generation, assignmentRequests[platform] == request else { return }
            assignmentStates[platform] = NetworkError.isCancellation(error) ? .idle : .failed(NetworkError.from(error).message)
            assignmentBrowsers[platform] = nil
        }
    }

    func applyAssignments(_ report: LearningAssignmentReport, platform: LearningPlatform) {
        assignmentRequests[platform] = UUID()
        assignmentBrowsers[platform]?.webView.stopLoading()
        assignmentBrowsers[platform] = nil
        assignmentReports[platform] = report.merging(assignmentReports[platform])
        assignmentSections[platform] = assignmentReports[platform]?.sections(for: platform)
        assignmentStates[platform] = .loaded
        assignmentUpdatedAt[platform] = Date()
        saveAssignmentCache()
        session.persistWebSession()
    }

    private func saveAssignmentCache() {
        guard let account = loadedForSID, !account.isEmpty else { return }
        do {
            try AssignmentCacheStore(account: account).save(.init(cg: cgReport, cgUpdatedAt: cgUpdatedAt,
                reports: assignmentReports, updatedAt: assignmentUpdatedAt))
            assignmentCacheWarning = nil
        } catch { assignmentCacheWarning = "本机作业缓存未能保存，重启后请重新同步。" }
    }

    var grades: [GradeSemester] {
        gradesCache ?? []
    }

    func loadGrades(force: Bool = false) async {
        if !force, gradesCache != nil {
            gradesState = .loaded
            return
        }
        if gradesState == .loading { return }
        gradesState = .loading
        let requestID = gradeRequestID
        do {
            let list = try await withRecovery {
                try await self.session.client.fetchJwxtGrades()
            }
            guard requestID == gradeRequestID else { return }
            applyGradeReport(list)
        } catch {
            guard requestID == gradeRequestID else { return }
            if gradesCache?.isEmpty == false {
                gradesWarning = "本次同步失败，保留上次结果：" + NetworkError.from(error).message
                gradesState = .loaded
            } else {
                gradesState = .failed(NetworkError.from(error).message)
            }
        }
    }

    func applyGradeReport(_ report: GradeReport) {
        gradeRequestID += 1
        gradesCache = report.semesters
        gradesWarning = report.failedTerms.isEmpty ? nil : "部分学期未能同步：" + report.failedTerms.joined(separator: "、")
        gradesState = .loaded
    }

    // MARK: - 一卡通 / 网费 / 电费

    /// 一卡通总览：余额、网费、电费并行拉取（校内直连，校外自动走 WebVPN）。
    private func cardResult<T>(_ operation: () async throws -> T) async -> Result<T, Error> {
        do { return .success(try await withRecovery(operation)) }
        catch { return .failure(error) }
    }

    func loadCardOverview() async {
        await ensureLoadedForCurrentUser()
        if cardState == .loading { return }
        cardState = .loading
        cardWarning = nil
        netState = .loading
        electricState = .loading
        let client = session.client
        let generation = accountGeneration
        let balanceRevision = cardBalanceRevision
        // 与泥洞一致，先固定这一轮的校内/校外路由，再并发取业务数据。
        await client.prepareAccess()
        async let fetchedCard = cardResult { try await self.cardBalanceWithWebRecovery() }
        async let fetchedNet = cardResult { try await client.fetchNetInfo(sid: session.user?.sid ?? "") }
        async let fetchedElectric = cardResult { try await client.fetchElectric(room: electricRoomCode) }
        let (card, net, elec) = await (fetchedCard, fetchedNet, fetchedElectric)
        guard generation == accountGeneration else { return }
        session.persistWebSession()
        if balanceRevision == cardBalanceRevision {
            switch card {
            case .success(let value):
                cardBalance = value
                cardUpdatedAt = Date()
                cardState = .loaded
            case .failure(let error):
                if NetworkError.isCancellation(error) {
                    cardState = cardBalance == nil ? .idle : .loaded
                } else if cardBalance != nil {
                    cardWarning = "本次同步失败，显示上次真实结果：" + NetworkError.from(error).message
                    cardState = .loaded
                } else { cardState = .failed(NetworkError.from(error).message) }
            }
        }
        switch net {
        case .success(let value): netInfo = value; netState = .loaded
        case .failure(let error):
            if NetworkError.isCancellation(error) { netState = netInfo == nil ? .idle : .loaded }
            else { netState = netInfo == nil ? .failed(NetworkError.from(error).message) : .loaded }
        }
        switch elec {
        case .success(let value): electricInfo = value; electricState = .loaded
        case .failure(let error):
            if NetworkError.isCancellation(error) { electricState = electricInfo == nil ? .idle : .loaded }
            else { electricState = electricInfo == nil ? .failed(NetworkError.from(error).message) : .loaded }
        }
    }

    /// 拉取某自然月流水（历史月落缓存，不再自动刷新）。
    func loadBills(year: Int, month: Int, force: Bool = false) async {
        await ensureLoadedForCurrentUser()
        if !force, billsState == .loading, billsYear == year, billsMonth == month { return }
        let requestID = UUID()
        billsRequestID = requestID
        billsYear = year
        billsMonth = month
        let key = "\(year)-\(month)"
        if !force, let cached = billsCache[key] {
            cardBills = cached
            billTruncated = truncatedCache[key] ?? false
            billsState = .loaded
            return
        }
        billsState = .loading
        let generation = accountGeneration
        do {
            let result = try await withRecovery {
                if self.cardUsesWebKit { return try await self.cardWebBridge.bills(client: self.session.client, year: year, month: month) }
                do { return try await self.session.client.fetchCardBills(year: year, month: month) }
                catch {
                    if NetworkError.isCancellation(error) || Task.isCancelled { throw CancellationError() }
                    let statement = try await self.cardWebBridge.bills(client: self.session.client, year: year, month: month)
                    self.cardUsesWebKit = true
                    return statement
                }
            }
            guard generation == accountGeneration, requestID == billsRequestID else { return }
            session.persistWebSession()
            billsCache[key] = result.bills
            truncatedCache[key] = result.truncated
            cardBills = result.bills
            billTruncated = result.truncated
            billsState = .loaded
        } catch {
            guard generation == accountGeneration, requestID == billsRequestID else { return }
            if NetworkError.isCancellation(error) {
                billsState = billsCache[key] == nil ? .idle : .loaded
            } else if billsCache[key] == nil {
                billsState = .failed(NetworkError.from(error).message)
            } else {
                billsState = .loaded
            }
        }
    }

    /// 前后翻月（跨年自动进位）。
    func shiftBillsMonth(_ delta: Int) async {
        var month = billsMonth + delta
        var year = billsYear
        if month < 1 { month = 12; year -= 1 }
        if month > 12 { month = 1; year += 1 }
        await loadBills(year: year, month: month)
    }

    /// 按自然日聚合当前月流水（无流水日补 0，柱数 = 当月天数）。
    func daySpends() -> [CardDaySpend] {
        let cal = Calendar.current
        var buckets: [Date: (spend: Double, recharge: Double, count: Int)] = [:]
        for bill in cardBills {
            guard let time = bill.time else { continue }
            let day = cal.startOfDay(for: time)
            var bucket = buckets[day] ?? (0, 0, 0)
            if bill.amount < 0 {
                bucket.spend += -bill.amount
                bucket.count += 1
            } else if bill.amount > 0 {
                bucket.recharge += bill.amount
            }
            buckets[day] = bucket
        }
        guard let monthDate = cal.date(from: DateComponents(year: billsYear, month: billsMonth)),
              let dayCount = cal.range(of: .day, in: .month, for: monthDate)?.count else { return [] }
        var out: [CardDaySpend] = []
        out.reserveCapacity(dayCount)
        for day in 1...dayCount {
            guard let date = cal.date(from: DateComponents(year: billsYear, month: billsMonth, day: day)) else { continue }
            let bucket = buckets[cal.startOfDay(for: date)] ?? (0, 0, 0)
            out.append(CardDaySpend(date: date, spend: bucket.spend, recharge: bucket.recharge, count: bucket.count))
        }
        return out
    }

    /// 当月消费合计。
    var monthSpendTotal: Double {
        daySpends().reduce(0) { $0 + $1.spend }
    }

    /// 首页一卡通入口卡片的摘要。
    var cardSummaryText: String? {
        guard let balance = cardBalance else { return nil }
        return String(format: "%.2f", balance.balance)
    }
}

/// 组合根：App 根部创建并注入。
@MainActor
@Observable
final class AppEnvironment {
    let session: SessionStore
    let repository: PortalRepository
    let dynamicIslandStore: DynamicIslandStore

    init() {
        let store = SessionStore()
        self.session = store
        self.repository = PortalRepository(session: store)
        self.dynamicIslandStore = DynamicIslandStore()
    }
}

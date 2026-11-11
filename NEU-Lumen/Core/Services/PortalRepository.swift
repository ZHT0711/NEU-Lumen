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
    private(set) var gradesUpdatedAt: Date?
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
    private(set) var netUpdatedAt: Date?
    private(set) var electricInfo: ElectricInfo?
    private(set) var electricState: LoadState = .idle
    private(set) var electricUpdatedAt: Date?

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
    private var currentAccountKey: String? {
        guard let user = session.user else { return nil }
        let key = user.sid.isEmpty ? user.uid : user.sid
        return key.isEmpty ? nil : key
    }
    private var hasCurrentLiveActivityAccount: Bool {
        LiveActivityDataPolicy.accountMatches(current: currentAccountKey, loaded: loadedForSID,
                                             authenticated: session.phase == .loggedIn)
    }
    private var appsLoaded = false
    private var appsLoading = false

    init(session: SessionStore) {
        self.session = session
    }

    var ecodeEntryURL: URL { ServiceCatalog(apps: apps).ecodeURL }

    // MARK: - 会话恢复

    /// 登录用户变化时清空缓存，避免串号。
    func ensureLoadedForCurrentUser() async {
        let sid = currentAccountKey ?? ""
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
        gradesUpdatedAt = nil
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
        netUpdatedAt = nil
        electricInfo = nil
        electricUpdatedAt = nil
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
                let value = try await operation()
                try checkRequest()
                return value
            }
            if let e = error as? NetworkError, e.isSessionExpired {
                guard await session.silentRelogin() else { throw e }
                try checkRequest()
                user = session.user
                let value = try await operation()
                try checkRequest()
                return value
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
        await ensureLoadedForCurrentUser()
        guard hasCurrentLiveActivityAccount else { return }
        let generation = accountGeneration
        let weekStart = LiveActivityDataPolicy.portalWeekStart(for: date)
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
            let sourceWeek = LiveActivityDataPolicy.portalWeekStart(for: sourceDate)
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
            return weekCache[LiveActivityDataPolicy.portalWeekStart(for: sourceDate)] != nil
        }
        return weekCache[sunday] != nil && weekCache[next] != nil && replacementsLoaded
    }

    private func effectivePortalOccurrences(from first: Date, to end: Date) -> [CourseOccurrence] {
        holidays.apply(HolidayRules.project(weekCache.values.flatMap { $0 }, from: first, to: end,
            replacements: holidays.replacementDates))
    }

    /// 今日时间轴包含跨午夜仍进行中的事项，和课表页使用同一调休/本机数据。
    func todayTimeline(now: Date = Date()) -> [CourseOccurrence] {
        guard hasCurrentLiveActivityAccount else { return [] }
        return activitySchedule(now: now, dayOnly: true).items.map(\.occurrence)
    }

    /// 不再只看今天：从当前时刻选未来七个自然日内最早未结束的事项。
    /// 本机手动课程/日程不需要门户周缓存；正在进行的事项优先。
    func nextCourse(now: Date = Date()) -> CourseOccurrence? {
        guard hasCurrentLiveActivityAccount else { return nil }
        return activitySchedule(now: now).next?.occurrence
    }

    private func activityRange(now: Date, dayOnly: Bool) -> (first: Date, end: Date) {
        let cal = Calendar.current
        let first = cal.startOfDay(for: now)
        return (first, cal.date(byAdding: .day, value: dayOnly ? 1 : 7, to: first)!)
    }

    private func localOccurrences(from first: Date, to end: Date) -> [CourseOccurrence] {
        planner.events.compactMap { event in
            guard let date = PortalDate.day(event.dateIso), date >= first && date < end else { return nil }
            return CourseOccurrence(date: date, slot: event.toSlot())
        }
    }

    private func portalRangeIsLoaded(from first: Date, to end: Date) -> Bool {
        let cal = Calendar.current
        var day = cal.startOfDay(for: first)
        while day < end {
            guard weekCache[LiveActivityDataPolicy.portalWeekStart(for: day)] != nil else { return false }
            if let source = holidays.replacementDates[PortalDate.isoDay(day)], let sourceDate = PortalDate.day(source),
               weekCache[LiveActivityDataPolicy.portalWeekStart(for: sourceDate)] == nil { return false }
            day = cal.date(byAdding: .day, value: 1, to: day)!
        }
        return true
    }

    private func activitySchedule(now: Date, dayOnly: Bool = false, localOnly: Bool = false) -> LiveActivitySchedule {
        let range = activityRange(now: now, dayOnly: dayOnly)
        // Yesterday is needed only to retain an overnight event intersecting today.
        let sourceFirst = Calendar.current.date(byAdding: .day, value: -1, to: range.first)!
        let portal = localOnly ? [] : effectivePortalOccurrences(from: sourceFirst, to: range.end)
        return LiveActivitySchedule.snapshot(portal + localOccurrences(from: sourceFirst, to: range.end),
            from: range.first, to: range.end, at: now,
            portalLoaded: localOnly || portalRangeIsLoaded(from: sourceFirst, to: range.end))
    }

    /// 全局协调器只在登录/前台/类别切换/跨日准备所选来源；分钟 tick 只渲染缓存。
    /// 自定义变量和作业只读当前账号现有缓存，不暗中登录三方平台。
    func prepareLiveActivityData(for store: DynamicIslandStore, force: Bool = false) async {
        await ensureLoadedForCurrentUser()
        guard hasCurrentLiveActivityAccount, store.enabled else { return }
        let generation = accountGeneration
        switch store.kind {
        case .nextCourse, .dayOverview:
            let now = Date()
            let range = activityRange(now: now, dayOnly: store.kind == .dayOverview)
            let first = Calendar.current.date(byAdding: .day, value: -1, to: range.first)!
            var weeks = Set<Date>()
            var day = first
            while day < range.end {
                weeks.insert(LiveActivityDataPolicy.portalWeekStart(for: day))
                if let source = holidays.replacementDates[PortalDate.isoDay(day)], let date = PortalDate.day(source) {
                    weeks.insert(LiveActivityDataPolicy.portalWeekStart(for: date))
                }
                day = Calendar.current.date(byAdding: .day, value: 1, to: day)!
            }
            for week in weeks.sorted() {
                await loadWeek(containing: week, force: force)
                guard generation == accountGeneration, hasCurrentLiveActivityAccount, !Task.isCancelled else { return }
            }
        case .cardBalance:
            if force || cardBalance == nil { await loadCardOverview() }
        case .netBalance:
            if force || netInfo == nil { await loadCardOverview() }
        case .electricBalance:
            if force || electricInfo == nil { await loadCardOverview() }
        case .academicOverview:
            await loadGrades(force: force)
        case .planner, .assignments, .custom:
            // PlannerEventStore loads synchronously. AssignmentCacheStore was
            // restored by ensureLoadedForCurrentUser; missing templates stay unread.
            break
        }
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
        await ensureLoadedForCurrentUser()
        guard hasCurrentLiveActivityAccount else { return }
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
        gradesUpdatedAt = Date()
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
        case .success(let value): netInfo = value; netUpdatedAt = Date(); netState = .loaded
        case .failure(let error):
            if NetworkError.isCancellation(error) { netState = netInfo == nil ? .idle : .loaded }
            else { netState = netInfo == nil ? .failed(NetworkError.from(error).message) : .loaded }
        }
        switch elec {
        case .success(let value): electricInfo = value; electricUpdatedAt = Date(); electricState = .loaded
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

    func liveActivityDataIsReady(for kind: DynamicIslandStore.ContentKind, now: Date = Date()) -> Bool {
        guard hasCurrentLiveActivityAccount else { return false }
        switch kind {
        case .nextCourse: return activitySchedule(now: now).isReady
        case .cardBalance: return cardBalance != nil && cardUpdatedAt != nil
        case .netBalance: return netInfo != nil
        case .electricBalance: return electricInfo != nil
        case .assignments: return activityAssignments.hasLoadedData
        case .planner, .custom: return true
        case .dayOverview:
            let schedule = activitySchedule(now: now, dayOnly: true)
            return schedule.portalLoaded || !schedule.items.isEmpty
        case .academicOverview: return gradesCache != nil
        }
    }

    /// A nil state means unread, never an already loaded empty timetable.
    /// The coordinator can retain an existing Activity while contentReady is false.
    func liveActivityDataStatus(for kind: DynamicIslandStore.ContentKind, now: Date = Date()) -> String {
        guard hasCurrentLiveActivityAccount else { return "等待当前账号登录与缓存加载" }
        func sourceStatus(_ state: LoadState, ready: Bool) -> String {
            if ready { return "已读取当前账号数据" }
            switch state {
            case .loading: return "正在读取"
            case .failed(let message): return "未读取：" + message
            default: return "未读取，请同步所选来源"
            }
        }
        switch kind {
        case .nextCourse, .planner:
            let local = kind == .planner
            let schedule = activitySchedule(now: now, localOnly: local)
            switch schedule.availability {
            case .notLoaded: return sourceStatus(weekState, ready: false)
            case .empty: return local ? "未来七天暂无个人日程" : "未来七天暂无课程或日程"
            case .finished: return local ? "范围内个人日程全部已结束" : "范围内课程与日程全部已结束"
            case .upcoming, .ongoing:
                return schedule.portalLoaded ? "已读取当前账号事项" : "已有可用事项；门户课表尚未完整读取"
            }
        case .cardBalance: return sourceStatus(cardState, ready: cardBalance != nil)
        case .netBalance: return sourceStatus(netState, ready: netInfo != nil)
        case .electricBalance:
            if electricInfo?.unbound == true { return "已读取：尚未绑定宿舍" }
            return sourceStatus(electricState, ready: electricInfo != nil)
        case .assignments:
            let assignments = activityAssignments
            guard assignments.hasLoadedData else { return "作业未读取，请在学习页登录所需平台并同步" }
            return "已读取 \(assignments.loadedPlatformCount) 个平台；仅汇总已同步作业" + (assignments.hasUnreadData ? "（部分未读取）" : "")
        case .dayOverview:
            let schedule = activitySchedule(now: now, dayOnly: true)
            if !schedule.portalLoaded { return schedule.items.isEmpty ? sourceStatus(weekState, ready: false) : "已读取日程；门户课表尚未完整读取" }
            return schedule.items.isEmpty ? "今天暂无课程或日程" : schedule.remainingCount == 0 ? "今天的事项全部已结束" : "已读取今日课表与日程"
        case .academicOverview: return sourceStatus(gradesState, ready: gradesCache != nil)
        case .custom: return "只读当前账号已加载缓存；缺失变量显示未读取"
        }
    }

    private var activityAssignments: LiveActivityAssignments {
        LiveActivityAssignments(cg: cgReport, reports: assignmentReports)
    }

    private func activityTemplateValues(now: Date) -> [String: String] {
        var values = ["date": LiveActivityDataPolicy.dateText(now, format: "yyyy-MM-dd"),
                      "time": LiveActivityDataPolicy.dateText(now, format: "HH:mm")]
        let week = Semester.weekNumberOf(now)
        values["week"] = (1...Semester.totalWeeks).contains(week) ? "第\(week)周" : "非教学周"
        let schedule = activitySchedule(now: now)
        if let next = schedule.next {
            values["course"] = next.occurrence.slot.name
            values["room"] = next.occurrence.slot.room
            values["start"] = LiveActivityDataPolicy.dateText(next.start, format: "MM-dd HH:mm")
            values["end"] = LiveActivityDataPolicy.dateText(next.end, format: "MM-dd HH:mm")
        } else if schedule.isReady {
            values["course"] = schedule.availability == .empty ? "无课程或日程" : "全部已结束"
        }
        values["card"] = LiveActivityDataPolicy.money(cardBalance?.balance)
        values["net"] = LiveActivityDataPolicy.money(netInfo?.balance)
        if let electric = electricInfo {
            if electric.unbound { values["electric"] = "未绑定" }
            else if let kwh = electric.remainKwh, kwh.isFinite { values["electric"] = String(format: "%.1f kWh", kwh) }
        }
        values["pending"] = activityAssignments.pendingText
        if gradesCache != nil, let gpa = LiveActivityAcademic(semesters: grades).gpa {
            values["gpa"] = String(format: "%.2f", gpa)
        }
        return values
    }

    /// Pure publication from current-account caches. nil is reserved for unread sources.
    func liveActivityState(store: DynamicIslandStore, now: Date = Date()) -> NEULumenActivityAttributes.ContentState? {
        guard hasCurrentLiveActivityAccount else { return nil }
        func content(_ title: String, subtitle: String, value: String,
                     updatedAt: Date = .distantPast, start: Date? = nil, end: Date? = nil,
                     symbol: String? = nil, secondary: String? = nil, progress: Double? = nil,
                     countdown: String? = nil, destination: String = "settings") -> NEULumenActivityAttributes.ContentState {
            .init(title: String(title.prefix(80)), subtitle: String(subtitle.prefix(160)),
                  value: String(value.prefix(32)), kind: store.kind.rawValue, updatedAt: updatedAt,
                  startDate: start, endDate: end, accent: LiveActivityDataPolicy.accent(store.accent),
                  symbolName: LiveActivityDataPolicy.symbol(symbol ?? store.kind.icon),
                  secondaryValue: secondary.map { String($0.prefix(64)) },
                  progress: store.showProgress ? LiveActivityDataPolicy.progress(progress) : nil,
                  countdownTitle: countdown,
                  destinationPath: LiveActivityDataPolicy.destinations.contains(destination) ? destination : "settings")
        }
        switch store.kind {
        case .nextCourse, .planner:
            let local = store.kind == .planner
            let schedule = activitySchedule(now: now, localOnly: local)
            guard schedule.isReady else { return nil }
            guard let next = schedule.next else {
                let empty = schedule.availability == .empty
                return content(local ? (empty ? "近期暂无个人日程" : "范围内日程已结束") :
                    (empty ? "暂无后续课程或日程" : "课程与日程已结束"),
                    subtitle: local ? "未来七天的本机日程已读取" : "未来七个自然日的课表与日程已读取",
                    value: empty ? "无事项" : "已结束", destination: "course")
            }
            let ongoing = next.isOngoing(at: now)
            let label = local ? (ongoing ? "距结束" : "距开始") : (ongoing ? "距下课" : "距上课")
            let date = LiveActivityDataPolicy.dateText(next.start, format: "MM-dd HH:mm")
            let room = next.occurrence.slot.room.isEmpty ? "地点未读取" : next.occurrence.slot.room
            let partial = !schedule.portalLoaded ? " · 课表未完整读取" : ""
            return content(next.occurrence.slot.name, subtitle: "\(room) · \(date)\(partial)",
                value: LiveActivityDataPolicy.countdown(to: ongoing ? next.end : next.start, at: now),
                start: next.start, end: next.end, secondary: ongoing ? "进行中" : "即将开始",
                progress: next.progress(at: now), countdown: label, destination: "course")
        case .cardBalance:
            guard let balance = LiveActivityDataPolicy.money(cardBalance?.balance), let updatedAt = cardUpdatedAt else { return nil }
            return content("校园卡余额", subtitle: cardWarning == nil ? "最近同步的真实可用余额" : "本次同步失败，保留上次真实余额",
                value: balance, updatedAt: updatedAt, secondary: cardBalance?.status, destination: "card")
        case .custom:
            let values = activityTemplateValues(now: now)
            let rawTitle = store.customTitle.trimmingCharacters(in: .whitespacesAndNewlines)
            let title = LiveActivityTemplate.render(rawTitle.isEmpty ? "东大提醒" : rawTitle, values: values, limit: 80)
            let subtitle = LiveActivityTemplate.render(store.customSubtitle, values: values, limit: 160)
            var value = LiveActivityTemplate.render(store.customValue, values: values, limit: 32)
            let deadline = store.customDeadlineEnabled && store.customDeadline.timeIntervalSinceReferenceDate.isFinite ? store.customDeadline : nil
            if let deadline, value.isEmpty {
                value = deadline > now ? LiveActivityDataPolicy.countdown(to: deadline, at: now) : "已到期"
            }
            return content(title, subtitle: subtitle, value: value, end: deadline, symbol: store.customIcon,
                countdown: deadline.map { $0 > now ? "距截止" : "已到期" }, destination: "settings")
        case .netBalance:
            guard let net = netInfo, let balance = LiveActivityDataPolicy.money(net.balance) else { return nil }
            return content("校园网余额", subtitle: "最近成功同步的余额与用量", value: balance,
                updatedAt: netUpdatedAt ?? .distantPast,
                secondary: net.flowFromPortal ? "本月流量 \(net.usedFlowText)" : "本月流量未读取", destination: "card")
        case .electricBalance:
            guard let electric = electricInfo else { return nil }
            if electric.unbound {
                return content("宿舍电量", subtitle: "在校园卡页填写宿舍房间码后同步", value: "未绑定",
                    updatedAt: electricUpdatedAt ?? .distantPast, destination: "card")
            }
            guard let remaining = electric.remainKwh, remaining.isFinite else {
                return content("宿舍电量", subtitle: "接口已读取，但未提供可用余量", value: "未读取",
                    updatedAt: electricUpdatedAt ?? .distantPast, destination: "card")
            }
            return content("宿舍电量", subtitle: "最近读取的剩余电量", value: String(format: "%.1f kWh", remaining),
                updatedAt: electricUpdatedAt ?? .distantPast,
                secondary: remaining <= 5 ? "电量偏低，请及时检查缴费" : "以校园电费系统最新数据为准", destination: "card")
        case .assignments:
            let assignments = activityAssignments
            guard assignments.hasLoadedData else { return nil }
            let timestamp = ([cgUpdatedAt].compactMap { $0 } + Array(assignmentUpdatedAt.values)).max() ?? .distantPast
            let coverage = "仅汇总已同步的 \(assignments.loadedPlatformCount) 个平台" + (assignments.hasUnreadData ? " · 部分未读取" : "")
            guard let pending = assignments.pendingText else {
                return content("学习作业", subtitle: coverage, value: "待同步", updatedAt: timestamp,
                    secondary: "请进入学习页完成平台登录与同步", destination: "learning")
            }
            guard let next = assignments.next(at: now) else {
                return content("已同步作业已完成", subtitle: coverage, value: "待办 \(pending)", updatedAt: timestamp,
                    progress: assignments.progress, destination: "learning")
            }
            let deadline = next.deadline.flatMap { $0 > now ? $0 : nil }
            let overdue = assignments.overdueCount(at: now)
            return content(next.title, subtitle: "\(next.platform) · \(coverage)", value: "待办 \(pending)",
                updatedAt: timestamp, end: deadline,
                secondary: overdue > 0 ? "\(overdue) 项已截止但未完成" : "按截止日期优先展示",
                progress: assignments.progress, countdown: deadline == nil ? nil : "距截止", destination: "learning")
        case .dayOverview:
            let schedule = activitySchedule(now: now, dayOnly: true)
            guard schedule.isReady else { return nil }
            let next = schedule.next
            let summary = next.map { "下一项：" + $0.occurrence.slot.name } ?? "今天已加载的事项已全部结束"
            let count = schedule.items.count
            return content("今日总览", subtitle: schedule.portalLoaded ? summary : summary + " · 课表未完整读取",
                value: "剩余 \(schedule.remainingCount)", secondary: "已结束 \(schedule.finishedCount) / 已加载 \(count)",
                progress: count > 0 ? Double(schedule.finishedCount) / Double(count) : nil, destination: "course")
        case .academicOverview:
            guard gradesCache != nil else { return nil }
            let academic = LiveActivityAcademic(semesters: grades)
            guard let gpa = academic.gpa else {
                return content("学业总览", subtitle: academic.semester?.name ?? "成绩报告已读取", value: "暂无可统计成绩",
                    updatedAt: gradesUpdatedAt ?? .distantPast,
                    secondary: "缺失或未知成绩不会作为零分统计", destination: "learning")
            }
            var details: [String] = []
            if let average = academic.weightedAverage { details.append(String(format: "均分 %.1f", average)) }
            if let credits = academic.credits { details.append(String(format: "计入 %.1f 学分", credits)) }
            return content("学业总览", subtitle: academic.semester?.name ?? "已加载学期",
                value: String(format: "GPA %.2f", gpa), updatedAt: gradesUpdatedAt ?? .distantPast,
                secondary: details.joined(separator: " · "), progress: academic.progress, destination: "learning")
        }
    }
}

/// 组合根：App 根部创建并注入。
@MainActor
@Observable
final class AppEnvironment {
    let session: SessionStore
    let repository: PortalRepository
    let dynamicIslandStore: DynamicIslandStore
    let liveActivityManager = DynamicIslandActivityManager()
    var pendingActivityURL: URL?
    var pendingLearningSection: String?

    init() {
        let store = SessionStore()
        self.session = store
        self.repository = PortalRepository(session: store)
        self.dynamicIslandStore = DynamicIslandStore()
    }
}

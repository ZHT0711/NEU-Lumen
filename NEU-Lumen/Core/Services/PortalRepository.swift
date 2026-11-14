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
    private(set) var todosUpdatedAt: Date?
    private(set) var newsUpdatedAt: Date?

    private var weekCache: [Date: [CourseOccurrence]] = [:]
    private var weekUpdatedAt: [Date: Date] = [:]
    private(set) var weekStates: [Date: LoadState] = [:]
    private var weekTasks: [Date: Task<Void, Never>] = [:]
    private var weekRequests: [Date: UUID] = [:]
    // Compatibility for fixture callers; views use displayWeekState(starting:).
    private(set) var weekState: LoadState = .idle
    private var homeRequestID = UUID()

    private var gradesCache: [GradeSemester]?
    private(set) var gradesUpdatedAt: Date?
    private var gradeRequestID = 0
    private(set) var gradesState: LoadState = .idle
    private(set) var gradesWarning: String?

    // 教务查询只在当前账号 / epoch 的内存中缓存，不落盘、不回退演示值。
    private var academicCache: [AcademicQueryKey: AcademicQueryPayload] = [:]
    private var academicStates: [AcademicQueryKey: LoadState] = [:]
    private var academicDates: [AcademicQueryKey: Date] = [:]
    private var academicWarnings: [AcademicQueryKey: String] = [:]
    private var academicTasks: [AcademicQueryKey: Task<Void, Never>] = [:]
    private var academicRequests: [AcademicQueryKey: UUID] = [:]
    private var academicWaiters: [AcademicQueryKey: Set<UUID>] = [:]
    private var academicPageCache: AcademicPageSnapshot?
    private var academicPlanPages: [String: AcademicPageSnapshot] = [:]
    private(set) var academicServices: [AcademicServiceItem] = []
    private(set) var academicServicesState: LoadState = .idle
    private(set) var academicServicesError: String?
    private var academicServicesRequest = UUID()
    private var academicExamCache: [String: [AcademicExam]] = [:]
    private var academicExamStates: [String: LoadState] = [:]
    private var academicExamDates: [String: Date] = [:]
    private var academicExamErrors: [String: String] = [:]
    private var academicExamRequests: [String: UUID] = [:]

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
    private(set) var billsWarning: String?
    private(set) var billsUpdatedAt: Date?
    private var billsCache: [String: [CardBill]] = [:]
    private var billsDates: [String: Date] = [:]
    private var truncatedCache: [String: Bool] = [:]
    private var billsRequestID = UUID()
    private(set) var netInfo: NetUsageInfo?
    private(set) var netState: LoadState = .idle
    private(set) var netUpdatedAt: Date?
    private(set) var electricInfo: ElectricInfo?
    private(set) var electricState: LoadState = .idle
    private(set) var electricUpdatedAt: Date?
    private(set) var netWarning: String?
    private(set) var electricWarning: String?
    private var cardTask: Task<Void, Never>?
    private var netTask: Task<Void, Never>?
    private var electricTask: Task<Void, Never>?
    private var cardRequestID = UUID()
    private var netRequestID = UUID()
    private var electricRequestID = UUID()
    private var walletAccessTask: Task<Void, Never>?
    private var walletAccessID = UUID()
    private var electricRoom = ""
    private struct ElectricSnapshot {
        let info: ElectricInfo
        let updatedAt: Date
    }
    private var electricCache: [ElectricRoomKey: ElectricSnapshot] = [:]

    private static let monthFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM"
        return f
    }()

    /// 房间码只属于已确认账号；不迁移无法确认归属的旧设备共享值。
    var electricRoomCode: String {
        get { electricRoom }
        set {
            guard let context = requestContext else { return }
            let room = ElectricRoomKey.normalize(newValue)
            guard room.isEmpty || ElectricRoomKey.isValid(room) else { return }
            guard room != electricRoom else { return }
            electricTask?.cancel()
            electricTask = nil
            electricRequestID = UUID()
            electricRoom = room
            UserDefaults.standard.set(room, forKey: "lumen.electric.room." + context.account)
            let cached = electricCache[ElectricRoomKey(account: context.account, room: room)]
            electricInfo = cached?.info
            electricUpdatedAt = cached?.updatedAt
            electricWarning = nil
            electricState = cached == nil ? .idle : .loaded
        }
    }

    private var monthKey: String { Self.monthFormatter.string(from: Calendar.current.date(from: DateComponents(year: billsYear, month: billsMonth))!) }

    private var accountGeneration = UUID()
    private var loadedForSID: String?
    private var loadedForEpoch: UUID?
    private var requestContext: RepositoryRequestContext? {
        guard hasCurrentLiveActivityAccount, let account = loadedForSID,
              loadedForEpoch == session.requestEpoch else { return nil }
        return RepositoryRequestContext(account: account, epoch: session.requestEpoch, generation: accountGeneration)
    }
    private func isCurrent(_ context: RepositoryRequestContext) -> Bool {
        session.phase == .loggedIn && loadedForSID == context.account && loadedForEpoch == context.epoch
            && context.matches(account: currentAccountKey, epoch: session.requestEpoch, generation: accountGeneration)
    }
    private var currentAccountKey: String? {
        guard let user = session.user else { return nil }
        let key = user.sid.isEmpty ? user.uid : user.sid
        return key.isEmpty ? nil : key
    }
    private var hasCurrentLiveActivityAccount: Bool {
        loadedForEpoch == session.requestEpoch
            && LiveActivityDataPolicy.accountMatches(current: currentAccountKey, loaded: loadedForSID,
                                                      authenticated: session.phase == .loggedIn)
    }
    private var appsLoaded = false
    private var appsLoading = false
    private var appsTask: Task<Bool, Never>?
    private var appsRequestID = UUID()
    private var appsUpdatedAt: Date?

    init(session: SessionStore) {
        self.session = session
    }

    var ecodeEntryURL: URL { ServiceCatalog(apps: apps).ecodeURL }

    // MARK: - 会话恢复

    /// 登录用户变化时清空缓存，避免串号。
    func ensureLoadedForCurrentUser() async {
        if session.phase == .loggedIn { _ = await session.ensureIdentity() }
        // Identity loading may suspend: capture the account only after it returns.
        let sid = currentAccountKey ?? ""
        let epoch = session.requestEpoch
        guard loadedForSID != sid || loadedForEpoch != epoch else { return }
        accountGeneration = UUID()
        homeRequestID = UUID()
        appsTask?.cancel()
        appsTask = nil
        appsRequestID = UUID()
        appsLoading = false
        appsUpdatedAt = nil
        cardTask?.cancel(); cardTask = nil
        netTask?.cancel(); netTask = nil
        electricTask?.cancel(); electricTask = nil
        walletAccessTask?.cancel(); walletAccessTask = nil
        cardRequestID = UUID(); netRequestID = UUID(); electricRequestID = UUID()
        walletAccessID = UUID()
        cardBalanceRevision = UUID()
        electricRoom = sid.isEmpty ? "" : ElectricRoomKey.normalize(UserDefaults.standard.string(forKey: "lumen.electric.room." + sid) ?? "")
        electricCache.removeAll()
        netWarning = nil
        electricWarning = nil
        campusOverride = UserDefaults.standard.string(forKey: "lumen.campus." + sid).flatMap(Campus.init(rawValue:))
        cardWebBridge.reset()
        cardUsesWebKit = false
        newsThumbnails = [:]
        loadingNewsThumbnails = []
        dataCards = []
        apps = ServiceCatalog.merging([DemoData.apps, cachedApps(account: sid)])
        appsLoaded = false
        news = []
        todos = []
        todosUpdatedAt = nil; newsUpdatedAt = nil
        academicServices = []; academicServicesState = .idle; academicServicesError = nil; academicServicesRequest = UUID()
        academicExamCache = [:]; academicExamStates = [:]; academicExamDates = [:]; academicExamErrors = [:]; academicExamRequests = [:]
        hotSearch = []
        weekCache.removeAll()
        weekUpdatedAt.removeAll()
        for task in weekTasks.values { task.cancel() }
        weekTasks.removeAll()
        weekRequests.removeAll()
        weekStates.removeAll()
        gradesCache = nil
        gradesUpdatedAt = nil
        gradeRequestID += 1
        gradesWarning = nil
        for task in academicTasks.values { task.cancel() }
        academicTasks.removeAll()
        academicRequests.removeAll()
        academicWaiters.removeAll()
        academicCache.removeAll()
        academicStates.removeAll()
        academicDates.removeAll()
        academicWarnings.removeAll()
        academicPageCache = nil
        academicPlanPages = [:]
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
        billsDates.removeAll()
        billsWarning = nil
        billsUpdatedAt = nil
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
        SemesterSettings.shared.activate(account: sid)
        loadedForSID = sid
        loadedForEpoch = epoch
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
    private func withRecovery<T>(retryInterruptedRequest: Bool = true, _ operation: () async throws -> T) async throws -> T {
        let generation = accountGeneration
        let epoch = session.requestEpoch
        let account = currentAccountKey
        func checkRequest() throws {
            try Task.checkCancellation()
            // A pending identity may bind once inside the same session epoch.
            // Confirmed identities may never change, including A → B → A.
            guard generation == accountGeneration, epoch == session.requestEpoch,
                  account == nil || account == currentAccountKey else {
                throw CancellationError()
            }
        }
        await session.waitForRecovery()
        do {
            try checkRequest()
            let value = try await operation()
            try checkRequest()
            return value
        } catch {
            try checkRequest()
            if NetworkError.isCancellation(error) {
                guard retryInterruptedRequest else { throw error }
                await session.waitForRecovery()
                try checkRequest()
                let value = try await operation()
                try checkRequest()
                return value
            }
            let authenticationRequired = (error as? PortalAPIError)?.requiresAuthentication == true
                || (error as? NetworkError)?.isSessionExpired == true
            if authenticationRequired {
                guard await session.silentRelogin() else { throw error }
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

    /// Retry resources that failed or were still loading on the previous path.
    /// Successful account-owned values remain visible while replacement reads run.
    func recoverAfterNetworkChange() async {
        await ensureLoadedForCurrentUser()
        guard let context = requestContext, session.networkAvailable, !Task.isCancelled else { return }
        func interrupted(_ state: LoadState) -> Bool {
            if case .failed = state { return true }
            return state == .loading
        }
        var work: [Task<Void, Never>] = []
        if interrupted(homeState) { work.append(Task { await self.refreshHome(force: true) }) }
        if !appsLoaded || appsLoading {
            appsRequestID = UUID(); appsTask?.cancel(); appsTask = nil; appsLoading = false
            work.append(Task { _ = await self.loadAppsIfNeeded(force: true) })
        }
        if interrupted(cardState) || cardWarning != nil { work.append(Task { await self.loadCardBalance(force: true) }) }
        if interrupted(netState) || netWarning != nil { work.append(Task { await self.loadNetInfo(force: true) }) }
        if interrupted(electricState) || electricWarning != nil { work.append(Task { await self.loadElectric(force: true) }) }
        if interrupted(billsState) {
            let year = billsYear, month = billsMonth
            work.append(Task { await self.loadBills(year: year, month: month, force: true) })
        }
        walletAccessID = UUID(); walletAccessTask?.cancel(); walletAccessTask = nil
        for (week, state) in weekStates where interrupted(state) {
            work.append(Task { await self.loadWeek(containing: week, force: true) })
        }
        if interrupted(gradesState) || gradesWarning != nil {
            gradeRequestID += 1; gradesState = gradesCache == nil ? .idle : .loaded
            work.append(Task { await self.loadGrades(force: true) })
        }
        for (key, state) in academicStates where interrupted(state) || academicWarnings[key] != nil {
            work.append(Task { await self.loadAcademicQuery(key, force: true) })
        }
        if interrupted(cgState) {
            cgRequestID = UUID(); cgBrowser?.close(); cgBrowser = nil; cgState = .idle
            work.append(Task { await self.loadCGAssignments(force: true) })
        }
        for (platform, state) in assignmentStates where interrupted(state) {
            assignmentRequests[platform] = UUID(); assignmentBrowsers[platform]?.close(); assignmentBrowsers[platform] = nil
            assignmentStates[platform] = .idle
            work.append(Task { await self.loadAssignments(platform, force: true) })
        }
        let tasks = work
        await withTaskCancellationHandler {
            for task in tasks { await task.value }
        } onCancel: { for task in tasks { task.cancel() } }
        guard isCurrent(context), !Task.isCancelled else { return }
        session.persistWebSession()
    }

    func refreshHome(force: Bool = false) async {
        await ensureLoadedForCurrentUser()
        guard let context = requestContext, !Task.isCancelled else { return }
        if !force, homeState == .loading { return }
        let request = UUID()
        homeRequestID = request
        let previousState = homeState == .loading ? LoadState.idle : homeState
        homeState = .loading
        let client = session.client

        async let cards = run { try await client.fetchDataCards() }
        async let appList = loadAppsIfNeeded(force: force)
        async let newsList = run { try await client.fetchNews() }
        async let todoList = run { try await client.fetchTodos() }
        async let hot = run { try await client.fetchHotSearch() }

        let (cardsValue, appsValue, newsValue, todoValue, hotValue) =
            await (cards, appList, newsList, todoList, hot)
        // A child may have completed BEFORE an account switch. Recheck the
        // aggregate before touching any visible state or account-owned cache.
        guard isCurrent(context), request == homeRequestID else { return }
        guard !Task.isCancelled else { homeState = previousState; return }

        var anySuccess = cardsValue != nil || todoValue != nil || hotValue != nil || appsValue
        if let value = cardsValue { dataCards = value }
        if let value = newsValue {
            news = value
            newsUpdatedAt = Date()
            newsRevision += 1
            newsThumbnails = newsThumbnails.filter { !$0.value.isEmpty }
            anySuccess = true
        } else if news.isEmpty { news = DemoData.news }
        if let value = todoValue { todos = value; todosUpdatedAt = Date() }
        if let value = hotValue { hotSearch = value }
        else if hotSearch.isEmpty { hotSearch = DemoData.hotSearch }

        user = session.user
        usedOfflineFallback = !anySuccess
        homeState = anySuccess ? .loaded : .failed("门户接口不可用，正在展示离线演示数据")
    }

    func dataCardURL(_ card: DataCard) -> URL {
        if card.name.contains("电费") || card.name.contains("电量") { return CampusPaymentEntry.electricity }
        if let url = PortalLink.resolve(card.destination) { return url }
        if card.name.contains("卡") && (card.name.contains("余额") || card.name.contains("补助")) { return URL(string: PortalClient.serviceCard)! }
        let terms: [String]
        if card.name.contains("图书") || card.name.contains("借阅") { terms = ["图书馆"] }
        else if card.name.contains("网费") || card.name.contains("流量") { terms = ["网络计费", "网费"] }
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
        guard requestContext != nil else { return }
        cardTask?.cancel()
        cardTask = nil
        cardRequestID = UUID()
        cardBalanceRevision = UUID()
        cardUsesWebKit = true
        cardBalance = balance
        cardState = .loaded
        cardWarning = nil
        cardUpdatedAt = Date()
        session.persistWebSession()
    }

    private func cardBalanceWithWebRecovery() async throws -> CardBalance {
        guard let context = requestContext else { throw CancellationError() }
        if cardUsesWebKit { return try await cardWebBridge.balance(client: session.client) }
        do { return try await session.client.fetchCardBalance() }
        catch {
            if NetworkError.isCancellation(error) || Task.isCancelled || !isCurrent(context) { throw CancellationError() }
            let balance = try await cardWebBridge.balance(client: session.client)
            try Task.checkCancellation()
            guard isCurrent(context) else { throw CancellationError() }
            cardUsesWebKit = true
            return balance
        }
    }

    /// 首页和服务页共享同一目录任务；单个等待者取消不取消其它页面的读取。
    @discardableResult
    func loadAppsIfNeeded(force: Bool = false) async -> Bool {
        await ensureLoadedForCurrentUser()
        guard let context = requestContext, !Task.isCancelled else { return false }
        if let task = appsTask { return await task.value }
        if !force, appsLoaded, DataFreshness.isFresh(appsUpdatedAt, for: DataFreshness.apps) { return true }
        let request = UUID()
        appsRequestID = request
        appsLoading = true
        let task = Task { @MainActor in
            defer {
                if self.isCurrent(context), request == self.appsRequestID {
                    self.appsLoading = false
                    self.appsTask = nil
                }
            }
            let value = await self.run { try await self.session.client.fetchApps() }
            guard self.isCurrent(context), request == self.appsRequestID, !Task.isCancelled else { return false }
            guard let value else { return false }
            self.apps = ServiceCatalog.merging([DemoData.apps, self.cachedApps(account: context.account), self.apps, value])
            self.saveAppsCache(account: context.account)
            self.appsLoaded = true
            self.appsUpdatedAt = Date()
            return true
        }
        appsTask = task
        return await task.value
    }

    /// Explicit ownership prevents a late result from saving under the new user.
    private func cachedApps(account: String) -> [PortalApp] {
        guard !account.isEmpty, let data = UserDefaults.standard.data(forKey: "lumen.apps." + account) else { return [] }
        return (try? JSONDecoder().decode([PortalApp].self, from: data)) ?? []
    }

    private func saveAppsCache(account: String) {
        guard !account.isEmpty, let data = try? JSONEncoder().encode(apps) else { return }
        UserDefaults.standard.set(data, forKey: "lumen.apps." + account)
    }

    func loadHotSearchIfNeeded() async {
        await ensureLoadedForCurrentUser()
        guard let context = requestContext, hotSearch.isEmpty, !Task.isCancelled else { return }
        let value = await run { try await self.session.client.fetchHotSearch() }
        guard isCurrent(context), !Task.isCancelled else { return }
        if let value { hotSearch = value }
        else if hotSearch.isEmpty { hotSearch = DemoData.hotSearch }
    }

    // MARK: - 课表

    /// 拉取某天所在教学周；命中缓存直接返回，不重复请求教务。
    /// 同一周已有在途加载时等待其完成，避免快速翻周时请求被吞掉。
    func loadWeek(containing date: Date, force: Bool = false) async {
        await ensureLoadedForCurrentUser()
        guard let context = requestContext, !Task.isCancelled else { return }
        let weekStart = LiveActivityDataPolicy.portalWeekStart(for: date)
        if !force, let task = weekTasks[weekStart] { await task.value; return }
        if !force, weekCache[weekStart] != nil { return }
        weekTasks[weekStart]?.cancel()
        let request = UUID()
        weekRequests[weekStart] = request
        let previousState = weekStates[weekStart] ?? .idle
        weekStates[weekStart] = .loading
        let task = Task { @MainActor in
            defer {
                if self.isCurrent(context), self.weekRequests[weekStart] == request { self.weekTasks[weekStart] = nil }
            }
            do {
                let list = try await self.withRecovery { try await self.session.client.fetchWeek(anyDayInWeek: date) }
                try Task.checkCancellation()
                guard self.isCurrent(context), self.weekRequests[weekStart] == request else { return }
                self.weekCache[weekStart] = list
                self.weekUpdatedAt[weekStart] = Date()
                self.weekStates[weekStart] = .loaded
            } catch {
                guard self.isCurrent(context), self.weekRequests[weekStart] == request else { return }
                if NetworkError.isCancellation(error) || Task.isCancelled {
                    self.weekStates[weekStart] = previousState == .loading ? .idle : previousState
                } else {
                    // Keep cached events but never disguise a failed refresh as success.
                    self.weekStates[weekStart] = .failed(NetworkError.from(error).message)
                }
            }
        }
        weekTasks[weekStart] = task
        await task.value
    }

    /// 某教学周（周日开始）的门户事件；无缓存返回 nil。
    func portalOccurrences(weekStarting weekStart: Date) -> [CourseOccurrence]? {
        weekCache[weekStart].map { holidays.apply($0) }
    }

    func loadDisplayWeek(starting sunday: Date, force: Bool = false) async {
        await ensureLoadedForCurrentUser()
        guard let context = requestContext, !Task.isCancelled else { return }
        let first = Calendar.current.date(byAdding: .day, value: 1, to: sunday)!
        let end = Calendar.current.date(byAdding: .day, value: 8, to: sunday)!
        for week in requiredPortalWeeks(from: first, to: end).sorted() {
            await loadWeek(containing: week, force: force)
            guard isCurrent(context), !Task.isCancelled else { return }
        }
        let nextSunday = Calendar.current.date(byAdding: .day, value: 7, to: sunday)!
        for year in Set([sunday, nextSunday].map { Calendar.current.component(.year, from: $0) }) {
            await holidays.refresh(year: year)
            guard isCurrent(context), !Task.isCancelled else { return }
        }
        weekState = displayWeekState(starting: sunday)
    }

    private func requiredPortalWeeks(from first: Date, to end: Date) -> Set<Date> {
        var result = Set<Date>()
        var day = Calendar.current.startOfDay(for: first)
        while day < end {
            result.insert(LiveActivityDataPolicy.portalWeekStart(for: day))
            if let source = holidays.replacementDates[PortalDate.isoDay(day)], let date = PortalDate.day(source) {
                result.insert(LiveActivityDataPolicy.portalWeekStart(for: date))
            }
            day = Calendar.current.date(byAdding: .day, value: 1, to: day)!
        }
        return result
    }

    private func states(for weeks: Set<Date>) -> [LoadState] {
        weeks.sorted().map { weekStates[$0] ?? (weekCache[$0] == nil ? .idle : .loaded) }
    }

    func displayWeekState(starting sunday: Date) -> LoadState {
        let first = Calendar.current.date(byAdding: .day, value: 1, to: sunday)!
        let end = Calendar.current.date(byAdding: .day, value: 8, to: sunday)!
        return ScheduleReadStatus.loadState(states(for: requiredPortalWeeks(from: first, to: end)))
    }

    func todayScheduleStatus(now: Date = Date()) -> ScheduleReadStatus {
        guard hasCurrentLiveActivityAccount else { return .unread }
        let range = activityRange(now: now, dayOnly: true)
        let first = Calendar.current.date(byAdding: .day, value: -1, to: range.first)!
        let weeks = requiredPortalWeeks(from: first, to: range.end)
        let snapshot = activitySchedule(now: now, dayOnly: true)
        return ScheduleReadStatus.summarize(states(for: weeks),
            hasData: weeks.contains { weekCache[$0] != nil } || !snapshot.items.isEmpty)
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
            await loadCardBalance(force: force)
        case .netBalance:
            await loadNetInfo(force: force)
        case .electricBalance:
            await loadElectric(force: force)
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
        guard let context = requestContext, !Task.isCancelled else { return }
        gradesState = .loading
        gradeRequestID += 1
        let requestID = gradeRequestID
        do {
            let list = try await withRecovery(retryInterruptedRequest: false) {
                try await self.session.client.fetchJwxtGrades()
            }
            try Task.checkCancellation()
            guard isCurrent(context), requestID == gradeRequestID else { return }
            applyGradeReport(list)
        } catch {
            guard isCurrent(context), requestID == gradeRequestID else { return }
            if NetworkError.isCancellation(error) || Task.isCancelled {
                gradesState = gradesCache == nil ? .idle : .loaded
                return
            }
            if gradesCache != nil {
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

    // MARK: - 原生教务只读查询

    var academicRequestContext: RepositoryRequestContext? { requestContext }
    var academicTerms: [AcademicTerm] {
        if case .terms(let terms)? = academicPayload(for: .terms) { return terms }
        return []
    }
    var academicPlans: [AcademicPlan] {
        if case .plans(let plans)? = academicPayload(for: .plans) { return plans }
        return []
    }
    var academicPageSnapshot: AcademicPageSnapshot? {
        guard let context = requestContext, academicPageCache?.account == context.account else { return nil }
        return academicPageCache
    }

    func academicPageSnapshot(for planID: String) -> AcademicPageSnapshot? {
        guard let context = requestContext, academicPlanPages[planID]?.account == context.account else { return nil }
        return academicPlanPages[planID]
    }

    func restoreAcademicPlan(_ planID: String) {
        guard let context = requestContext, academicPlanPages[planID] == nil else { return }
        if let saved = AcademicPlanCacheStore(account: context.account, planID: planID).load() {
            academicPlanPages[planID] = saved
        }
    }

    func clearAcademicPlan(_ planID: String) throws {
        guard let context = requestContext else { throw AcademicQueryError.accountMismatch }
        try AcademicPlanCacheStore(account: context.account, planID: planID).clear()
        academicPlanPages[planID] = nil
    }

    func academicPayload(for key: AcademicQueryKey) -> AcademicQueryPayload? {
        guard requestContext != nil else { return nil }
        return academicCache[key]
    }
    func academicState(for key: AcademicQueryKey) -> LoadState {
        guard requestContext != nil else { return .failed("尚未确认当前账号，请重试或在应用内更新正常网页登录") }
        return academicStates[key] ?? .idle
    }
    func academicUpdatedAt(for key: AcademicQueryKey) -> Date? {
        guard requestContext != nil else { return nil }
        return academicDates[key]
    }
    func academicWarning(for key: AcademicQueryKey) -> String? {
        guard requestContext != nil else { return nil }
        return academicWarnings[key]
    }

    /// 每项数据独立 loading / error / 缓存日期；同 key 去重，强制刷新取消上一请求。
    func loadAcademicQuery(_ key: AcademicQueryKey, force: Bool = false) async {
        await ensureLoadedForCurrentUser()
        guard let context = requestContext, !Task.isCancelled else { return }
        guard session.user?.sid == context.account else {
            academicStates[key] = .failed("尚未确认当前学号，请在应用内更新正常网页登录后重试")
            return
        }
        guard AcademicQueryPolicy.allows(key, terms: academicTerms, plans: academicPlans) else {
            academicStates[key] = .failed("当前查询不在已读取的学期 / 方案列表中，或日期无效；请先刷新列表后重试")
            return
        }
        if !force, let task = academicTasks[key], let request = academicRequests[key] {
            await waitForAcademicTask(task, key: key, request: request, context: context)
            return
        }
        if !force, academicCache[key] != nil, AcademicQueryPolicy.isFresh(academicDates[key], key: key) { return }
        academicTasks[key]?.cancel()
        let request = UUID()
        academicRequests[key] = request
        academicWaiters[key] = []
        academicStates[key] = .loading
        let task = Task { @MainActor in
            defer { if self.isCurrent(context), self.academicRequests[key] == request { self.academicTasks[key] = nil } }
            do {
                let value = try await self.withRecovery(retryInterruptedRequest: false) {
                    try await self.session.client.fetchAcademicQuery(key, expectedAccount: context.account)
                }
                try Task.checkCancellation()
                guard self.isCurrent(context), self.academicRequests[key] == request else { return }
                self.academicCache[key] = value
                self.academicDates[key] = Date()
                self.academicWarnings[key] = nil
                self.academicStates[key] = .loaded
            } catch {
                guard self.isCurrent(context), self.academicRequests[key] == request else { return }
                if NetworkError.isCancellation(error) || Task.isCancelled {
                    self.academicStates[key] = self.academicCache[key] == nil ? .idle : .loaded
                } else if self.academicCache[key] != nil {
                    self.academicWarnings[key] = "本次读取失败，保留上次结果：" + NetworkError.from(error).message
                    self.academicStates[key] = .loaded
                } else {
                    self.academicStates[key] = .failed(NetworkError.from(error).message)
                }
            }
        }
        academicTasks[key] = task
        await waitForAcademicTask(task, key: key, request: request, context: context)
    }

    /// Hub and detail views can share a query. Leaving one view must not cancel
    /// a request still needed by another; the last cancelled waiter stops it.
    private func waitForAcademicTask(_ task: Task<Void, Never>, key: AcademicQueryKey,
                                     request: UUID, context: RepositoryRequestContext) async {
        let waiter = UUID()
        academicWaiters[key, default: []].insert(waiter)
        defer {
            if isCurrent(context), academicRequests[key] == request {
                academicWaiters[key]?.remove(waiter)
                if academicWaiters[key]?.isEmpty == true { academicWaiters[key] = nil }
            }
        }
        await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            Task { @MainActor in
                guard self.isCurrent(context), self.academicRequests[key] == request else { return }
                self.academicWaiters[key]?.remove(waiter)
                if self.academicWaiters[key]?.isEmpty == true { task.cancel() }
            }
        }
    }

    /// 浏览器必须先核对官方 currentUser.userId，再带打开时的账号 / epoch / generation 回写。
    func applyAcademicPageSnapshot(_ snapshot: AcademicPageSnapshot, context: RepositoryRequestContext, planID: String? = nil) throws {
        try Task.checkCancellation()
        guard isCurrent(context), session.user?.sid == context.account,
              AcademicQueryPolicy.acceptsPageAccount(snapshot.account, expected: context.account) else {
            throw AcademicQueryError.accountMismatch
        }
        var bound = snapshot
        if let planID {
            guard academicPlans.contains(where: { $0.id == planID }) else { throw AcademicQueryError.invalid("培养方案") }
            bound.planID = planID
            let previous = academicPlanPages[planID] ?? AcademicPlanCacheStore(account: context.account, planID: planID).load()
            bound.courses = AcademicPlanPresentation.merge(previous?.courses ?? [], snapshot.courses)
            try AcademicPlanCacheStore(account: context.account, planID: planID).save(bound)
            academicPlanPages[planID] = bound
        }
        academicPageCache = bound
    }

    #if DEBUG
    /// 仅供临时截图 copy 显式注入合成数据；Release 无此入口，无环境变量自动回退。
    func seedAcademicPreview(_ values: [AcademicQueryKey: AcademicQueryPayload], page: AcademicPageSnapshot? = nil,
                             updatedAt: Date = Date()) {
        guard let context = requestContext else { return }
        for task in academicTasks.values { task.cancel() }
        academicTasks.removeAll(); academicRequests.removeAll(); academicWaiters.removeAll()
        academicCache = values
        academicDates = Dictionary(uniqueKeysWithValues: values.keys.map { ($0, updatedAt) })
        academicStates = Dictionary(uniqueKeysWithValues: values.keys.map { ($0, LoadState.loaded) })
        academicWarnings.removeAll()
        if let page, page.account == context.account {
            academicPageCache = page
            if let plan = academicPlans.first(where: { $0.selected }) ?? academicPlans.first {
                var bound = page; bound.planID = plan.id
                academicPlanPages[plan.id] = bound
            }
        }
    }
    #endif

    // MARK: - 一卡通 / 网费 / 电费

    /// 一卡通总览：余额、网费、电费并行拉取（校内直连，校外自动走 WebVPN）。
    private func cardResult<T>(_ operation: () async throws -> T) async -> Result<T, Error> {
        do { return .success(try await withRecovery(operation)) }
        catch { return .failure(error) }
    }

    /// Independent resource loaders share route preparation, not one loading flag.
    func loadCardOverview(force: Bool = false) async {
        async let card: Void = loadCardBalance(force: force)
        async let net: Void = loadNetInfo(force: force)
        async let electric: Void = loadElectric(force: force)
        _ = await (card, net, electric)
    }

    private func prepareWalletAccess(_ context: RepositoryRequestContext) async throws {
        if let task = walletAccessTask { await task.value }
        else {
            let request = UUID()
            walletAccessID = request
            let task = Task { @MainActor in
                await self.session.client.prepareAccess()
                if self.isCurrent(context), self.walletAccessID == request { self.walletAccessTask = nil }
            }
            walletAccessTask = task
            await task.value
        }
        try Task.checkCancellation()
        guard isCurrent(context) else { throw CancellationError() }
    }

    func loadCardBalance(force: Bool = false) async {
        await ensureLoadedForCurrentUser()
        guard let context = requestContext, !Task.isCancelled else { return }
        if !force, let task = cardTask { await task.value; return }
        if !force, cardBalance != nil, DataFreshness.isFresh(cardUpdatedAt, for: DataFreshness.wallet) { return }
        cardTask?.cancel()
        let request = UUID()
        cardRequestID = request
        let revision = cardBalanceRevision
        cardState = .loading
        let task = Task { @MainActor in
            defer { if self.isCurrent(context), self.cardRequestID == request { self.cardTask = nil } }
            let result = await self.cardResult {
                try await self.prepareWalletAccess(context)
                return try await self.cardBalanceWithWebRecovery()
            }
            guard self.isCurrent(context), self.cardRequestID == request, revision == self.cardBalanceRevision else { return }
            if Task.isCancelled { self.cardState = self.cardBalance == nil ? .idle : .loaded; return }
            switch result {
            case .success(let value):
                self.cardBalance = value
                self.cardUpdatedAt = Date()
                self.cardWarning = nil
                self.cardState = .loaded
                self.session.persistWebSession()
            case .failure(let error):
                if NetworkError.isCancellation(error) { self.cardState = self.cardBalance == nil ? .idle : .loaded }
                else if self.cardBalance != nil {
                    self.cardWarning = "本次同步失败，显示上次真实结果：" + NetworkError.from(error).message
                    self.cardState = .loaded
                } else { self.cardState = .failed(NetworkError.from(error).message) }
            }
        }
        cardTask = task
        await task.value
    }

    func loadNetInfo(force: Bool = false) async {
        await ensureLoadedForCurrentUser()
        guard let context = requestContext, !Task.isCancelled else { return }
        if !force, let task = netTask { await task.value; return }
        if !force, netInfo != nil, DataFreshness.isFresh(netUpdatedAt, for: DataFreshness.wallet) { return }
        netTask?.cancel()
        let request = UUID()
        netRequestID = request
        let sid = session.user?.sid ?? ""
        netState = .loading
        let task = Task { @MainActor in
            defer { if self.isCurrent(context), self.netRequestID == request { self.netTask = nil } }
            let result = await self.cardResult {
                try await self.prepareWalletAccess(context)
                return try await self.session.client.fetchNetInfo(sid: sid)
            }
            guard self.isCurrent(context), self.netRequestID == request else { return }
            if Task.isCancelled { self.netState = self.netInfo == nil ? .idle : .loaded; return }
            switch result {
            case .success(let value):
                self.netInfo = value
                self.netUpdatedAt = Date()
                self.netWarning = nil
                self.netState = .loaded
                self.session.persistWebSession()
            case .failure(let error):
                if NetworkError.isCancellation(error) { self.netState = self.netInfo == nil ? .idle : .loaded }
                else if self.netInfo != nil {
                    self.netWarning = "本次同步失败，显示上次结果：" + NetworkError.from(error).message
                    self.netState = .loaded
                } else { self.netState = .failed(NetworkError.from(error).message) }
            }
        }
        netTask = task
        await task.value
    }

    /// A room switch invalidates the old selection immediately, even while card
    /// balance is loading. Only the selected account + normalized room may write.
    func loadElectric(force: Bool = false) async {
        await ensureLoadedForCurrentUser()
        guard let context = requestContext, !Task.isCancelled else { return }
        let key = ElectricRoomKey(account: context.account, room: electricRoom)
        if !force, let task = electricTask { await task.value; return }
        if !force, electricInfo != nil, DataFreshness.isFresh(electricUpdatedAt, for: DataFreshness.electric) { return }
        electricTask?.cancel()
        electricTask = nil
        let request = UUID()
        electricRequestID = request
        if key.room.isEmpty {
            electricInfo = ElectricInfo(unbound: true, remainKwh: nil, roomNo: nil, roomLabel: nil, lastReadAt: nil)
            electricState = .loaded
            electricUpdatedAt = nil
            electricWarning = nil
            return
        }
        guard ElectricRoomKey.isValid(key.room) else {
            electricInfo = nil
            electricUpdatedAt = nil
            electricState = .failed("房间码应为 3 位宿舍加 4 位寝室数字")
            return
        }
        electricState = .loading
        let task = Task { @MainActor in
            defer { if self.isCurrent(context), self.electricRequestID == request { self.electricTask = nil } }
            let result = await self.cardResult {
                try await self.prepareWalletAccess(context)
                return try await self.session.client.fetchElectric(room: key.room)
            }
            guard self.isCurrent(context), self.electricRequestID == request,
                  key.room == self.electricRoom else { return }
            if Task.isCancelled { self.electricState = self.electricInfo == nil ? .idle : .loaded; return }
            switch result {
            case .success(let value):
                guard !value.unbound, ElectricRoomKey.normalize(value.roomNo ?? "") == key.room else {
                    let message = "电费响应房间与当前选择不一致，请重试"
                    self.electricWarning = message
                    self.electricState = self.electricInfo == nil ? .failed(message) : .loaded
                    return
                }
                let updated = Date()
                self.electricCache[key] = ElectricSnapshot(info: value, updatedAt: updated)
                self.electricInfo = value
                self.electricUpdatedAt = updated
                self.electricWarning = nil
                self.electricState = .loaded
                self.session.persistWebSession()
            case .failure(let error):
                if NetworkError.isCancellation(error) { self.electricState = self.electricInfo == nil ? .idle : .loaded }
                else if self.electricInfo != nil {
                    self.electricWarning = "本次同步失败，显示同一房间上次结果：" + NetworkError.from(error).message
                    self.electricState = .loaded
                } else { self.electricState = .failed(NetworkError.from(error).message) }
            }
        }
        electricTask = task
        await task.value
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
        // Never label another month's rows with the newly selected month.
        cardBills = billsCache[key] ?? []
        billTruncated = truncatedCache[key] ?? false
        billsUpdatedAt = billsDates[key]
        billsWarning = nil
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
            let updated = Date()
            billsDates[key] = updated
            billsUpdatedAt = updated
            billsWarning = nil
            billsState = .loaded
        } catch {
            guard generation == accountGeneration, requestID == billsRequestID else { return }
            if NetworkError.isCancellation(error) {
                billsState = billsCache[key] == nil ? .idle : .loaded
            } else if billsCache[key] == nil {
                billsState = .failed(NetworkError.from(error).message)
            } else {
                billsWarning = "本次查询失败，显示所选月份上次结果：" + NetworkError.from(error).message
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

    private func activityTemplateSnapshot(now: Date, keys: Set<String>) -> (values: [String: String], expiration: Date?) {
        var values: [String: String] = [:]
        var expirations: [Date] = []
        let cal = Calendar.current
        if keys.contains("date") { values["date"] = LiveActivityDataPolicy.dateText(now, format: "yyyy-MM-dd") }
        if keys.contains("time") {
            values["time"] = LiveActivityDataPolicy.dateText(now, format: "HH:mm")
            expirations.append(cal.dateInterval(of: .minute, for: now)?.end ?? now.addingTimeInterval(60))
        }
        if keys.contains("week") {
            let week = Semester.weekNumberOf(now)
            values["week"] = (1...Semester.totalWeeks).contains(week) ? "第\(week)周" : "非教学周"
        }
        if !keys.isDisjoint(with: ["date", "week"]) {
            expirations.append(cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: now))!)
        }
        if !keys.isDisjoint(with: ["course", "room", "start", "end"]) {
            let schedule = activitySchedule(now: now)
            if let next = schedule.next {
                values["course"] = next.occurrence.slot.name
                values["room"] = next.occurrence.slot.room
                values["start"] = LiveActivityDataPolicy.dateText(next.start, format: "MM-dd HH:mm")
                values["end"] = LiveActivityDataPolicy.dateText(next.end, format: "MM-dd HH:mm")
                expirations.append(next.isOngoing(at: now) ? next.end : next.start)
            } else if schedule.isReady {
                values["course"] = schedule.availability == .empty ? "无课程或日程" : "全部已结束"
                expirations.append(cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: now))!)
            }
        }
        if keys.contains("card") {
            values["card"] = LiveActivityDataPolicy.money(cardBalance?.balance)
            if let timestamp = cardUpdatedAt { expirations.append(timestamp.addingTimeInterval(1800)) }
        }
        if keys.contains("net") {
            values["net"] = LiveActivityDataPolicy.money(netInfo?.balance)
            if let timestamp = netUpdatedAt { expirations.append(timestamp.addingTimeInterval(1800)) }
        }
        if keys.contains("electric"), let electric = electricInfo {
            if electric.unbound { values["electric"] = "未绑定" }
            else if let kwh = electric.remainKwh, kwh.isFinite { values["electric"] = String(format: "%.1f kWh", kwh) }
            if let timestamp = electricUpdatedAt { expirations.append(timestamp.addingTimeInterval(1800)) }
        }
        if keys.contains("pending") {
            values["pending"] = activityAssignments.pendingText
            if let timestamp = ([cgUpdatedAt].compactMap { $0 } + Array(assignmentUpdatedAt.values)).min() {
                expirations.append(timestamp.addingTimeInterval(1800))
            }
        }
        if keys.contains("gpa"), gradesCache != nil, let gpa = LiveActivityAcademic(semesters: grades).gpa {
            values["gpa"] = String(format: "%.2f", gpa)
            if let timestamp = gradesUpdatedAt { expirations.append(timestamp.addingTimeInterval(1800)) }
        }
        return (values, expirations.min())
    }

    /// Pure publication from current-account caches. nil is reserved for unread sources.
    func liveActivityState(store: DynamicIslandStore, now: Date = Date()) -> NEULumenActivityAttributes.ContentState? {
        guard hasCurrentLiveActivityAccount else { return nil }
        func content(_ title: String, subtitle: String, value: String,
                     updatedAt: Date = .distantPast, start: Date? = nil, end: Date? = nil,
                     symbol: String? = nil, secondary: String? = nil, progress: Double? = nil,
                     countdown: String? = nil, destination: String = "settings",
                     details: [LiveActivityDetail] = [], phase: String? = nil,
                     staleAfter: Date? = nil) -> NEULumenActivityAttributes.ContentState {
            NEULumenActivityAttributes.ContentState(title: String(title.prefix(80)), subtitle: String(subtitle.prefix(160)),
                  value: String(value.prefix(32)), kind: store.kind.rawValue, updatedAt: updatedAt,
                  startDate: start, endDate: end, accent: LiveActivityDataPolicy.accent(store.accent),
                  symbolName: LiveActivityDataPolicy.symbol(symbol ?? store.kind.icon),
                  secondaryValue: secondary.map { String($0.prefix(64)) },
                  progress: store.showProgress ? LiveActivityDataPolicy.progress(progress) : nil,
                  countdownTitle: countdown,
                  destinationPath: LiveActivityDataPolicy.destinations.contains(destination) ? destination : "settings",
                  staleAfter: staleAfter,
                  countdownTarget: countdown == "距上课" || countdown == "距开始" ? "start" : end != nil ? "end" : nil,
                  detailItems: details.isEmpty ? nil : details, phase: phase).boundedText()
        }
        func detail(_ label: String, _ value: String?, temporal: Bool = false) -> LiveActivityDetail? {
            LiveActivityText.detail(label, value, timeSensitive: temporal)
        }
        func syncDetail(_ date: Date?) -> LiveActivityDetail? {
            guard let date, date != .distantPast, date.timeIntervalSinceReferenceDate.isFinite else { return nil }
            return detail("同步", LiveActivityDataPolicy.dateText(date, format: "MM-dd HH:mm"))
        }
        let dayEnd = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: now))!
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
                    value: empty ? "无事项" : "已结束", destination: "course",
                    details: [detail("范围", "未来七个自然日"), detail("已加载", "\(schedule.items.count) 项")].compactMap { $0 },
                    phase: empty ? "empty" : "finished", staleAfter: dayEnd)
            }
            let ongoing = next.isOngoing(at: now)
            let personal = next.occurrence.slot.kind == "custom"
            let label = local || personal ? (ongoing ? "距结束" : "距开始") : (ongoing ? "距下课" : "距上课")
            let date = LiveActivityDataPolicy.dateText(next.start, format: "MM-dd HH:mm")
            let room = next.occurrence.slot.room.isEmpty ? "地点未读取" : next.occurrence.slot.room
            let partial = !schedule.portalLoaded ? " · 课表未完整读取" : ""
            let note = planner.events.first { $0.id == next.occurrence.slot.eventID }?.note
            var details = schedule.expandedDetails(for: next, at: now, note: note)
            if !local && !schedule.portalLoaded, let row = detail("来源", "课表尚未完整读取") { details.insert(row, at: 0) }
            return content(next.occurrence.slot.name, subtitle: "\(room) · \(date)\(partial)",
                value: LiveActivityDataPolicy.countdown(to: ongoing ? next.end : next.start, at: now),
                start: next.start, end: next.end, secondary: ongoing ? "进行中" : "即将开始",
                progress: next.progress(at: now), countdown: label, destination: "course",
                details: details, phase: ongoing ? "ongoing" : "upcoming")
        case .cardBalance:
            guard let balance = LiveActivityDataPolicy.money(cardBalance?.balance), let updatedAt = cardUpdatedAt else { return nil }
            return content("校园卡余额", subtitle: cardWarning == nil ? "最近同步的真实可用余额" : "本次同步失败，保留上次真实余额",
                value: balance, updatedAt: updatedAt, secondary: cardBalance?.status, destination: "card",
                details: [detail("卡状态", cardBalance?.status), detail("补助", LiveActivityDataPolicy.money(cardBalance?.subsidy)),
                          detail(cardWarning == nil ? "来源" : "同步状态", cardWarning == nil ? "校园卡系统可用余额" : "本次失败，保留上次余额"),
                          syncDetail(updatedAt)].compactMap { $0 })
        case .custom:
            let keys = LiveActivityTemplate.dependencies(in: [store.customTitle, store.customSubtitle, store.customValue])
            let snapshot = activityTemplateSnapshot(now: now, keys: keys)
            let values = snapshot.values
            let rawTitle = store.customTitle.trimmingCharacters(in: .whitespacesAndNewlines)
            let title = LiveActivityTemplate.render(rawTitle.isEmpty ? "东大提醒" : rawTitle, values: values, limit: 80)
            let subtitle = LiveActivityTemplate.render(store.customSubtitle, values: values, limit: 160)
            var value = LiveActivityTemplate.render(store.customValue, values: values, limit: 32)
            let deadline = store.customDeadlineEnabled && store.customDeadline.timeIntervalSinceReferenceDate.isFinite ? store.customDeadline : nil
            if let deadline, value.isEmpty {
                value = deadline > now ? LiveActivityDataPolicy.countdown(to: deadline, at: now) : "已到期"
            }
            var customDetails: [LiveActivityDetail] = []
            if deadline != nil, !store.customValue.isEmpty, let row = detail("辅助值", value) { customDetails.append(row) }
            if let deadline, let row = detail("截止", LiveActivityDataPolicy.dateText(deadline, format: "MM-dd HH:mm")) { customDetails.append(row) }
            var state = content(title, subtitle: subtitle, value: value, end: deadline, symbol: store.customIcon,
                countdown: deadline.map { $0 > now ? "距截止" : "已到期" }, destination: "settings",
                details: customDetails)
            state.staleAfter = snapshot.expiration
            return state.boundedText()
        case .netBalance:
            guard let net = netInfo, let balance = LiveActivityDataPolicy.money(net.balance) else { return nil }
            let usage = net.usageFacts.map { detail($0.0, $0.1) }
            return content("校园网余额", subtitle: "最近成功同步的余额与用量", value: balance,
                updatedAt: netUpdatedAt ?? .distantPast,
                secondary: net.flowFromPortal ? "本月流量 \(net.usedFlowText)" : "本月流量未读取", destination: "card",
                details: (usage + [syncDetail(netUpdatedAt)]).compactMap { $0 })
        case .electricBalance:
            guard let electric = electricInfo else { return nil }
            let electricDetails = [detail("房间", electric.roomLabel), detail("房间码", electric.roomNo),
                                   detail("抄表", electric.lastReadAt), syncDetail(electricUpdatedAt)].compactMap { $0 }
            if electric.unbound {
                return content("宿舍电量", subtitle: "在校园卡页填写宿舍房间码后同步", value: "未绑定",
                    updatedAt: electricUpdatedAt ?? .distantPast, destination: "card",
                    details: [detail("绑定", "尚未绑定宿舍"), syncDetail(electricUpdatedAt)].compactMap { $0 })
            }
            guard let remaining = electric.remainKwh, remaining.isFinite else {
                return content("宿舍电量", subtitle: "接口已读取，但未提供可用余量", value: "未读取",
                    updatedAt: electricUpdatedAt ?? .distantPast, destination: "card", details: electricDetails)
            }
            return content("宿舍电量", subtitle: "最近读取的剩余电量", value: String(format: "%.1f kWh", remaining),
                updatedAt: electricUpdatedAt ?? .distantPast,
                secondary: remaining <= 5 ? "电量偏低，请及时检查缴费" : "以校园电费系统最新数据为准", destination: "card",
                details: electricDetails + [detail("提示", remaining <= 5 ? "余量偏低，请检查缴费" : "以电费系统最新数据为准")].compactMap { $0 })
        case .assignments:
            let assignments = activityAssignments
            guard assignments.hasLoadedData else { return nil }
            let timestamps = [cgUpdatedAt].compactMap { $0 } + Array(assignmentUpdatedAt.values)
            let timestamp = timestamps.max() ?? .distantPast
            let expiration = timestamps.min()?.addingTimeInterval(1800)
            let coverage = "仅汇总已同步的 \(assignments.loadedPlatformCount) 个平台" + (assignments.hasUnreadData ? " · 部分未读取" : "")
            let taskDetails = [detail("平台", "已同步 \(assignments.loadedPlatformCount) 个"),
                               detail("覆盖", assignments.hasUnreadData ? "部分未读取，不视为零待办" : "仅统计已同步作业"),
                               detail("已完成", "\(assignments.completedCount) 项", temporal: true)].compactMap { $0 }
            guard let pending = assignments.pendingText else {
                return content("学习作业", subtitle: coverage, value: "待同步", updatedAt: timestamp,
                    secondary: "请进入学习页完成平台登录与同步", destination: "learning",
                    details: taskDetails, staleAfter: expiration)
            }
            guard let next = assignments.next(at: now) else {
                return content("已同步作业已完成", subtitle: coverage, value: "待办 \(pending)", updatedAt: timestamp,
                    progress: assignments.progress, destination: "learning", details: taskDetails,
                    phase: "finished", staleAfter: expiration)
            }
            let deadline = next.deadline.flatMap { $0 > now ? $0 : nil }
            let overdue = assignments.overdueCount(at: now)
            let nearestDetails = [detail("待办", "\(pending) 项", temporal: true), detail("来源", next.platform),
                                  next.deadline.flatMap { detail("截止", LiveActivityDataPolicy.dateText($0, format: "MM-dd HH:mm")) },
                                  overdue > 0 ? detail("已截止未完成", "\(overdue) 项", temporal: true) : nil].compactMap { $0 }
            return content(next.title, subtitle: "\(next.platform) · \(coverage)", value: "待办 \(pending)",
                updatedAt: timestamp, end: deadline,
                secondary: overdue > 0 ? "\(overdue) 项已截止但未完成" : "按截止日期优先展示",
                progress: assignments.progress, countdown: deadline == nil ? nil : "距截止", destination: "learning",
                details: nearestDetails + taskDetails, staleAfter: expiration)
        case .dayOverview:
            let schedule = activitySchedule(now: now, dayOnly: true)
            guard schedule.isReady else { return nil }
            let next = schedule.next
            let summary = next.map { ($0.isOngoing(at: now) ? "正在进行：" : "下一项：") + $0.occurrence.slot.name }
                ?? (schedule.items.isEmpty ? "今天暂无已加载事项" : "今天已加载的事项已全部结束")
            let count = schedule.items.count
            let courseCount = schedule.items.filter { $0.occurrence.slot.kind != "custom" }.count
            var dayDetails = [detail("已读课程", "\(courseCount) 门"), detail("已读日程", "\(count - courseCount) 项"),
                              detail("待完成", "\(schedule.remainingCount) 项", temporal: true),
                              detail("已结束", "\(schedule.finishedCount) 项", temporal: true)].compactMap { $0 }
            if let next {
                if let row = detail(next.isOngoing(at: now) ? "当前" : "下一项", next.occurrence.slot.name, temporal: true) { dayDetails.insert(row, at: 0) }
                if let row = detail("时间地点", LiveActivityDataPolicy.dateText(next.start, format: "HH:mm") + " " + LiveActivityText.clean(next.occurrence.slot.room)) { dayDetails.append(row) }
            }
            if !schedule.portalLoaded, let row = detail("来源", "课表未完整读取") { dayDetails.insert(row, at: 0) }
            let boundary = next.map { $0.isOngoing(at: now) ? $0.end : $0.start } ?? dayEnd
            return content("今日总览", subtitle: schedule.portalLoaded ? summary : summary + " · 课表未完整读取",
                value: "剩余 \(schedule.remainingCount)", secondary: "已结束 \(schedule.finishedCount) / 已加载 \(count)",
                progress: count > 0 ? Double(schedule.finishedCount) / Double(count) : nil, destination: "course",
                details: dayDetails, phase: schedule.availability.rawValue, staleAfter: min(dayEnd, boundary))
        case .academicOverview:
            guard gradesCache != nil else { return nil }
            let academic = LiveActivityAcademic(semesters: grades)
            guard let gpa = academic.gpa else {
                return content("学业总览", subtitle: academic.semester?.name ?? "成绩报告已读取", value: "暂无可统计成绩",
                    updatedAt: gradesUpdatedAt ?? .distantPast,
                    secondary: "缺失或未知成绩不会作为零分统计", destination: "learning",
                    details: [detail("学期", academic.semester?.name), detail("已加载", "\(academic.courseCount) 门"),
                              detail("统计", "缺失与未知成绩不按零分计入"), syncDetail(gradesUpdatedAt)].compactMap { $0 })
            }
            var details: [String] = []
            if let average = academic.weightedAverage { details.append(String(format: "均分 %.1f", average)) }
            if let credits = academic.credits { details.append(String(format: "计入 %.1f 学分", credits)) }
            return content("学业总览", subtitle: academic.semester?.name ?? "已加载学期",
                value: String(format: "GPA %.2f", gpa), updatedAt: gradesUpdatedAt ?? .distantPast,
                secondary: details.joined(separator: " · "), progress: academic.progress, destination: "learning",
                details: [detail("学期", academic.semester?.name),
                          academic.credits.flatMap { detail("计入学分", String(format: "%.1f 学分", $0)) },
                          academic.weightedAverage.flatMap { detail("加权均分", String(format: "%.1f", $0)) },
                          detail("有效成绩", "\(academic.scoredCount) / \(academic.courseCount) 门"),
                          syncDetail(gradesUpdatedAt)].compactMap { $0 })
        }
    }
}

/// 组合根：App 根部创建并注入。
extension PortalRepository {
    var hasCurrentReminderAccount: Bool { hasCurrentLiveActivityAccount }
    var latestReminderWeekUpdate: Date? { weekUpdatedAt.values.max() }

    func loadAcademicServices(force: Bool = false) async {
        await ensureLoadedForCurrentUser()
        guard let context = requestContext, let account = session.user?.sid, !account.isEmpty, !Task.isCancelled else { return }
        if !force, academicServicesState == .loaded || academicServicesState == .loading { return }
        let token = UUID(); academicServicesRequest = token; academicServicesState = .loading; academicServicesError = nil
        do {
            let result = try await withRecovery { try await self.session.client.fetchAcademicServiceDirectory(expectedAccount: account) }
            guard isCurrent(context), academicServicesRequest == token, !Task.isCancelled else { return }
            academicServices = result; academicServicesState = .loaded
        } catch {
            guard isCurrent(context), academicServicesRequest == token else { return }
            if NetworkError.isCancellation(error) { academicServicesState = academicServices.isEmpty ? .idle : .loaded; return }
            academicServicesError = NetworkError.from(error).message
            academicServicesState = academicServices.isEmpty ? .failed(academicServicesError!) : .loaded
        }
    }
    func academicExams(term: String) -> [AcademicExam] { academicExamCache[term] ?? [] }
    func academicExamsState(term: String) -> LoadState { academicExamStates[term] ?? .idle }
    func academicExamsDate(term: String) -> Date? { academicExamDates[term] }
    var latestAcademicExamUpdate: Date? { academicExamDates.values.max() }
    func academicExamsError(term: String) -> String? { academicExamErrors[term] }
    func loadAcademicExams(term: String, force: Bool = false) async {
        await ensureLoadedForCurrentUser()
        guard let context = requestContext, let account = session.user?.sid, !account.isEmpty, !term.isEmpty, !Task.isCancelled else { return }
        if !force, academicExamStates[term] == .loading || DataFreshness.isFresh(academicExamDates[term], for: 300) { return }
        let token = UUID(); academicExamRequests[term] = token; academicExamStates[term] = .loading; academicExamErrors[term] = nil
        do {
            let result = try await withRecovery { try await self.session.client.fetchAcademicExams(termCode: term, expectedAccount: account) }
            guard isCurrent(context), academicExamRequests[term] == token, !Task.isCancelled else { return }
            academicExamCache[term] = result; academicExamStates[term] = .loaded; academicExamDates[term] = Date()
        } catch {
            guard isCurrent(context), academicExamRequests[term] == token else { return }
            if NetworkError.isCancellation(error) { academicExamStates[term] = academicExamCache[term] == nil ? .idle : .loaded; return }
            academicExamErrors[term] = NetworkError.from(error).message
            academicExamStates[term] = academicExamCache[term] == nil ? .failed(academicExamErrors[term]!) : .loaded
        }
    }

    func reminderSnapshot(preferences: CampusReminderPreferences, now: Date = Date()) -> CampusReminderSnapshot {
        guard hasCurrentLiveActivityAccount else { return .init() }
        var output = CampusReminderSnapshot()
        let start = Calendar.current.startOfDay(for: now)
        let end = Calendar.current.date(byAdding: .day, value: CampusReminderPolicy.horizonDays, to: start)!
        let occurrences = (effectivePortalOccurrences(from: start, to: end) + localOccurrences(from: start, to: end)).mergeConsecutive()
        output.readySources = Set(weekCache.keys.map { "week:" + AcademicQueryPolicy.schoolDay($0) }).union(["planner", "daily"])
        let schedule = LiveActivitySchedule.snapshot(occurrences, from: start, to: end, at: now, portalLoaded: true)
        func timed(_ id: String, _ kind: CampusReminderKind, _ title: String, _ body: String, _ event: Date, _ lead: Int, _ destination: String, _ source: String) {
            guard event > now else { return }
            var item = CampusReminderPolicy.timed(id: id, kind: kind, title: title, body: body, event: event, lead: lead, destination: destination)
            item.sourceKey = source
            if item.fireAt <= now { item.fireAt = now.addingTimeInterval(5) }
            output.planned.append(item)
        }
        for item in schedule.items {
            let slot = item.occurrence.slot
            let kind: CampusReminderKind = slot.eventID == nil ? (slot.kind == "exam" ? .exam : .course) : .planner
            let lead = kind == .planner ? preferences.plannerLead : kind == .exam ? preferences.examLead : preferences.courseLead
            let event = CampusReminderPolicy.clock(day: item.occurrence.date, minutes: slot.startMinutes) ?? item.start
            timed(item.occurrence.id, kind, slot.name + "即将开始", "\(slot.timeText) · \(slot.room)", event, lead, "course",
                kind == .planner ? "planner" : "week:" + AcademicQueryPolicy.schoolDay(LiveActivityDataPolicy.portalWeekStart(for: item.occurrence.date)))
        }
        for (term, exams) in academicExamCache {
            output.readySources.insert("exam:" + term)
            for exam in exams {
                guard let start = exam.start else { continue }
                timed("exam:" + exam.id, .exam, exam.title + "考试提醒", [exam.dateText, exam.timeText, exam.place, exam.seat.isEmpty ? "" : "座位 " + exam.seat].filter { !$0.isEmpty }.joined(separator: " · "), start, preferences.examLead, "academic", "exam:" + term)
            }
        }
        let assignments = LiveActivityAssignments(cg: cgReport, reports: assignmentReports)
        if let cgReport, cgReport.warnings.isEmpty,
           cgReport.assignments.filter({ !$0.history }).allSatisfy({ $0.loaded && $0.problemCount > 0 && $0.problems.count >= $0.problemCount }) {
            output.readySources.insert("assignment:" + LearningPlatform.cg.title)
        }
        for (platform, report) in assignmentReports where report.warnings.isEmpty && report.courses.allSatisfy({ report.refreshedCourseKeys.contains($0.key) }) {
            output.readySources.insert("assignment:" + platform.title)
        }
        for item in assignments.pending {
            guard let deadline = item.deadline else { continue }
            timed(item.id, .assignment, item.title + "即将截止", item.platform + " · 截止 " + LiveActivityDataPolicy.dateText(deadline, format: "MM-dd HH:mm"), deadline, preferences.assignmentLead, "learning", "assignment:" + item.platform)
            if preferences.assignmentDayBefore, preferences.assignmentLead != 1440 {
                timed(item.id, .assignment, item.title + "将于明天截止", item.platform, deadline, 1440, "learning", "assignment:" + item.platform)
            }
        }
        if preferences.systemEvents {
            if systemCalendar.updatedAt != nil { output.readySources.insert("system") }
            for item in systemCalendar.agenda {
                let event = item.allDay ? (Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: item.date) ?? item.date) : item.date
                timed("system:" + item.id, .planner, item.title, item.source + (item.location.isEmpty ? "" : " · " + item.location), event,
                    item.allDay ? 0 : preferences.plannerLead, "course", "system")
            }
        } else { output.readySources.insert("system") }
        func balance(_ id: String, _ value: Double?, _ threshold: Double, _ updated: Date?, _ title: String, _ unit: String) {
            guard let value, value.isFinite, let updated else { return }
            let low = value < threshold
            output.changes.append(.init(id: "balance:" + id, kind: .balance,
                fingerprint: low ? "low:" + AcademicQueryPolicy.schoolDay(now) : "normal", title: low ? title : "",
                body: "最近同步余量 \(value.formatted(.number.precision(.fractionLength(0...2))))\(unit)，低于提醒阈值 \(threshold.formatted())\(unit)。",
                destination: "card", updatedAt: updated, notifyFirst: true))
        }
        balance("card", cardBalance?.balance, preferences.cardThreshold, cardUpdatedAt, "校园卡余额偏低", "元")
        balance("net", netInfo?.balance, preferences.netThreshold, netUpdatedAt, "网费余额偏低", "元")
        if electricInfo?.unbound == false {
            balance("electric:" + electricRoomCode, electricInfo?.remainKwh, preferences.electricityThreshold, electricUpdatedAt, "宿舍电量偏低", "度")
        }
        if let updated = gradesUpdatedAt, gradesWarning == nil {
            let raw = grades.map { term in term.name + ":" + term.courses.map { $0.id }.sorted().joined(separator: ";") }.sorted().joined(separator: "|")
            output.changes.append(.init(id: "grades", kind: .grades, fingerprint: CampusReminderStore.key(raw),
                title: "教务成绩有更新", body: "最新同步的成绩与上次记录有变化，点击查看成绩与绩点。", destination: "learning", updatedAt: updated))
        }
        if let updated = todosUpdatedAt {
            let raw = todos.map { $0.title + "|" + $0.instance + "|" + $0.node + "|" + String($0.percent) }.sorted().joined(separator: ";")
            output.changes.append(.init(id: "affairs", kind: .affairs, fingerprint: CampusReminderStore.key(raw),
                title: "办事进度有变化", body: "最新同步的在办事项或办理节点有变化。", destination: "affairs", updatedAt: updated))
        }
        if let updated = newsUpdatedAt, let item = news.first {
            output.changes.append(.init(id: "news", kind: .news, fingerprint: item.id, title: "校园资讯有更新",
                body: item.title, destination: "news", updatedAt: updated))
        }
        for offset in 0..<7 {
            guard let day = CampusReminderPolicy.calendar.date(byAdding: .day, value: offset, to: now),
                  let date = CampusReminderPolicy.calendar.date(bySettingHour: preferences.dailyHour, minute: preferences.dailyMinute, second: 0, of: day) else { continue }
            output.planned.append(.init(id: "daily:" + AcademicQueryPolicy.schoolDay(day), kind: .daily,
                title: "每日校园安排", body: "查看课程、本机日程、作业截止与校园账户，及时确认最新安排。", fireAt: date, destination: "course", sourceKey: "daily"))
        }
        return output
    }

    func prepareReminderData(preferences: CampusReminderPreferences, background: Bool = false,
                             onUpdate: (@MainActor () async -> Void)? = nil) async {
        await ensureLoadedForCurrentUser()
        guard hasCurrentReminderAccount, preferences.enabled, !Task.isCancelled else { return }
        var work: [Task<Void, Never>] = []
        if preferences.allows(.course) || preferences.allows(.exam) || preferences.allows(.daily) {
            work.append(Task { @MainActor in
                var week = LiveActivityDataPolicy.portalWeekStart(for: Date())
                for _ in 0..<3 {
                    guard !Task.isCancelled else { return }
                    await self.loadDisplayWeek(starting: week, force: background)
                    await onUpdate?()
                    week = Calendar.current.date(byAdding: .day, value: 7, to: week)!
                }
            })
        }
        if preferences.allows(.balance) {
            work.append(Task { @MainActor in
                await self.loadCardOverview(force: background)
                await onUpdate?()
            })
        }
        if preferences.allows(.exam) {
            work.append(Task { @MainActor in
                await self.loadAcademicQuery(.terms, force: background)
                guard !Task.isCancelled, let term = self.academicTerms.first(where: { $0.current }) ?? self.academicTerms.first else { return }
                await self.loadAcademicExams(term: term.code, force: background)
                await onUpdate?()
            })
        }
        if preferences.allows(.grades) {
            work.append(Task { @MainActor in
                await self.loadGrades(force: background)
                await onUpdate?()
            })
        }
        if preferences.allows(.affairs) || preferences.allows(.news) {
            work.append(Task { @MainActor in
                await self.refreshHome(force: background)
                await onUpdate?()
            })
        }
        if preferences.systemEvents {
            work.append(Task { @MainActor in
                await self.systemCalendar.refresh(start: Date(), end: Date().addingTimeInterval(14 * 86400))
                await onUpdate?()
            })
        }
        let requests = work
        await withTaskCancellationHandler {
            for task in requests { await task.value }
        } onCancel: { requests.forEach { $0.cancel() } }
    }
}

@MainActor
@Observable
final class AppEnvironment {
    let session: SessionStore
    let repository: PortalRepository
    let dynamicIslandStore: DynamicIslandStore
    let liveActivityManager = DynamicIslandActivityManager()
    let reminders = CampusReminderStore.shared
    var pendingActivityURL: URL?
    var pendingLearningSection: String?

    init() {
        let store = SessionStore()
        self.session = store
        self.repository = PortalRepository(session: store)
        self.dynamicIslandStore = DynamicIslandStore()
        CampusBackgroundRefresh.shared.configure(session: store, repository: self.repository)
    }
}

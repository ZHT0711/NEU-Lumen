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
        loadedForSID = sid
    }

    /// 会话过期 → 静默重登 → 重试一次。
    private func withRecovery<T>(_ operation: () async throws -> T) async throws -> T {
        do {
            return try await operation()
        } catch let e as NetworkError where e.isSessionExpired {
            guard await session.silentRelogin() else { throw e }
            user = session.user
            return try await operation()
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
        let weekStart = Semester.weekStart(forDay: date)
        if !force, weekCache[weekStart] != nil {
            weekState = .loaded
            return
        }
        if !force, loadingWeeks.contains(weekStart) {
            while loadingWeeks.contains(weekStart) {
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
        defer { loadingWeeks.remove(weekStart) }
        do {
            let list = try await withRecovery {
                try await self.session.client.fetchWeek(anyDayInWeek: date)
            }
            weekCache[weekStart] = list
            weekState = .loaded
        } catch {
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
        weekCache[weekStart]
    }

    /// 今日时间轴：门户周缓存 ∩ 今天 + 本机日程，合并相邻节次。
    func todayTimeline() -> [CourseOccurrence] {
        let today = Calendar.current.startOfDay(for: Date())
        let weekStart = Semester.weekStart(forDay: today)
        let portal = (weekCache[weekStart] ?? []).filter {
            Calendar.current.isDate($0.date, inSameDayAs: today)
        }
        return (portal + planner.occurrences(onDay: today)).mergeConsecutive()
    }

    /// 下一节未结束的课程。
    func nextCourse() -> CourseOccurrence? {
        let now = Semester.minutesNow()
        return todayTimeline().first { $0.slot.endMinutes > now }
    }

    // MARK: - 成绩

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
    private func cardResult<T>(_ operation: () async throws -> T) async -> Result<T, NetworkError> {
        do { return .success(try await withRecovery(operation)) }
        catch { return .failure(NetworkError.from(error)) }
    }

    func loadCardOverview() async {
        if cardState == .loading { return }
        cardState = .loading
        cardWarning = nil
        netState = .loading
        electricState = .loading
        let client = session.client
        // 与泥洞一致，先固定这一轮的校内/校外路由，再并发取业务数据。
        await client.prepareAccess()
        async let fetchedCard = cardResult { try await client.fetchCardBalance() }
        async let fetchedNet = cardResult { try await client.fetchNetInfo(sid: session.user?.sid ?? "") }
        async let fetchedElectric = cardResult { try await client.fetchElectric(room: electricRoomCode) }
        let (card, net, elec) = await (fetchedCard, fetchedNet, fetchedElectric)
        switch card {
        case .success(let value):
            cardBalance = value
            cardUpdatedAt = Date()
            cardState = .loaded
        case .failure(let error):
            if cardBalance != nil {
                cardWarning = "本次同步失败，显示上次真实结果：" + error.message
                cardState = .loaded
            } else { cardState = .failed(error.message) }
        }
        switch net {
        case .success(let value): netInfo = value; netState = .loaded
        case .failure(let error): netState = netInfo == nil ? .failed(error.message) : .loaded
        }
        switch elec {
        case .success(let value): electricInfo = value; electricState = .loaded
        case .failure(let error): electricState = electricInfo == nil ? .failed(error.message) : .loaded
        }
    }

    /// 拉取某自然月流水（历史月落缓存，不再自动刷新）。
    func loadBills(year: Int, month: Int, force: Bool = false) async {
        billsYear = year
        billsMonth = month
        let key = "\(year)-\(month)"
        if !force, let cached = billsCache[key] {
            cardBills = cached
            billTruncated = truncatedCache[key] ?? false
            billsState = .loaded
            return
        }
        if billsState == .loading { return }
        billsState = .loading
        do {
            let result = try await withRecovery {
                try await self.session.client.fetchCardBills(year: year, month: month)
            }
            billsCache[key] = result.bills
            truncatedCache[key] = result.truncated
            cardBills = result.bills
            billTruncated = result.truncated
            billsState = .loaded
        } catch {
            if billsCache[key] == nil {
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

    init() {
        let store = SessionStore()
        self.session = store
        self.repository = PortalRepository(session: store)
    }
}

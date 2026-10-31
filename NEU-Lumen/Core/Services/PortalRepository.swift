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
    private(set) var weekState: LoadState = .idle

    private var gradesCache: [GradeSemester]?
    private(set) var gradesState: LoadState = .idle

    private var loadedForSID: String?

    init(session: SessionStore) {
        self.session = session
    }

    // MARK: - 会话恢复

    /// 登录用户变化时清空缓存，避免串号。
    func ensureLoadedForCurrentUser() async {
        let sid = session.user?.sid ?? ""
        guard loadedForSID != sid else { return }
        dataCards = []
        apps = []
        news = []
        todos = []
        hotSearch = []
        weekCache.removeAll()
        gradesCache = nil
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
            dataCards = DemoData.dataCards
        }
        if let v = appsValue, !v.isEmpty {
            apps = v
            anySuccess = true
        } else if apps.isEmpty {
            apps = DemoData.apps
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

        if user == nil { user = session.user ?? DemoData.user }
        usedOfflineFallback = !anySuccess
        homeState = anySuccess ? .loaded : .failed("门户接口不可用，正在展示离线演示数据")
    }

    /// 服务大厅按需加载应用列表（避免冷启动时重复请求）。
    func loadAppsIfNeeded() async {
        guard apps.isEmpty else { return }
        if let v = await run({ try await session.client.fetchApps() }), !v.isEmpty {
            apps = v
        } else {
            apps = DemoData.apps
        }
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
    func loadWeek(containing date: Date, force: Bool = false) async {
        let weekStart = Semester.weekStart(forDay: date)
        if !force, weekCache[weekStart] != nil {
            weekState = .loaded
            return
        }
        if weekState == .loading { return }
        weekState = .loading
        do {
            let list = try await withRecovery {
                try await self.session.client.fetchWeek(anyDayInWeek: date)
            }
            weekCache[weekStart] = list
            weekState = .loaded
        } catch {
            // 有缓存就继续用缓存，无缓存才报错
            if weekCache[weekStart] == nil {
                weekState = .failed((error as? NetworkError)?.message ?? error.localizedDescription)
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
        do {
            let list = try await withRecovery {
                try await self.session.client.fetchJwxtGrades()
            }
            gradesCache = list
            gradesState = .loaded
        } catch {
            gradesState = .failed((error as? NetworkError)?.message ?? error.localizedDescription)
        }
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

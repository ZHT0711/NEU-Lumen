import SwiftUI

enum AppTab: Hashable {
    case home
    case schedule
    case services
    case grades
    case profile
}

private enum ActivitySheet: Identifiable {
    case settings, card, reminders, service(NativeCampusService)
    var id: String {
        switch self {
        case .settings: "settings"
        case .card: "card"
        case .reminders: "reminders"
        case .service(let value): "service:" + value.rawValue
        }
    }
}

/// 主界面：首页 / 课表 / 服务大厅 / 学习 / 我的。
struct MainTabView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.scenePhase) private var scenePhase
    @State private var selection: AppTab = .home
    @State private var scrollActivity = TabBarScrollActivity()
    @State private var activitySheet: ActivitySheet?

    var body: some View {
        tabs
            .onChange(of: environment.pendingActivityURL, initial: true) { _, pending in
                guard let url = pending else { return }
                activitySheet = nil
                if url.host == "dynamic-island" || url.path == "/settings" { activitySheet = .settings }
                if url.host == "activity", url.path == "/card" { activitySheet = .card }
                if url.host == "activity", url.path == "/reminders" { activitySheet = .reminders }
                if url.host == "activity", url.path == "/services" {
                    let name = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "native" }?.value
                    if let service = name.flatMap(NativeCampusService.init(rawValue:)) { activitySheet = .service(service) }
                    selection = .services
                }
                if url.host == "activity", url.path == "/course" { selection = .schedule }
                if url.host == "activity", url.path == "/profile" { selection = .profile }
                if url.host == "activity", url.path == "/learning" {
                    let section = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "section" }?.value
                    environment.pendingLearningSection = section == "grades" ? "成绩" : "作业"
                    selection = .grades
                }
                environment.pendingActivityURL = nil
            }
            .sheet(item: $activitySheet) { destination in
                NavigationStack {
                    Group {
                        switch destination {
                        case .settings: LiveActivitySettingsView()
                        case .card: CardView()
                        case .reminders: CampusReminderView()
                        case .service(let service): NativeServiceHost(initial: service)
                        }
                    }.toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { activitySheet = nil } } }
                }
            }
            .environment(\.tabBarScrollActivity, scrollActivity)
            .modifier(ScrollingTabBarStyle(activity: scrollActivity))
            .onChange(of: selection) { _, _ in scrollActivity.restore() }
            .onChange(of: scenePhase) { _, phase in
                if phase != .active { scrollActivity.restore() }
            }
    }

    private var tabs: some View {
        TabView(selection: $selection) {
            HomeView(selection: $selection)
                .tabItem { Label("首页", systemImage: "house.fill") }
                .tag(AppTab.home)

            ScheduleView()
                .tabItem { Label("课表", systemImage: "calendar") }
                .tag(AppTab.schedule)

            ServicesView()
                .tabItem { Label("服务", systemImage: "square.grid.2x2.fill") }
                .tag(AppTab.services)

            GradesView()
                .tabItem { Label("学习", systemImage: "book.closed.fill") }
                .tag(AppTab.grades)

            ProfileView()
                .tabItem { Label("我的", systemImage: "person.fill") }
                .tag(AppTab.profile)
        }
    }
}

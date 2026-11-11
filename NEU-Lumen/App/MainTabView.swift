import SwiftUI

enum AppTab: Hashable {
    case home
    case schedule
    case services
    case grades
    case profile
}

/// 主界面：首页 / 课表 / 服务大厅 / 学习 / 我的。
struct MainTabView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.scenePhase) private var scenePhase
    @State private var selection: AppTab = .home
    @State private var scrollActivity = TabBarScrollActivity()
    @State private var showActivitySettings = false
    @State private var showActivityCard = false

    var body: some View {
        tabs
            .onChange(of: environment.pendingActivityURL, initial: true) { _, pending in
                guard let url = pending else { return }
                showActivityCard = url.host == "activity" && url.path == "/card"
                showActivitySettings = url.host == "dynamic-island" || url.path == "/settings"
                if url.host == "activity", url.path == "/course" { selection = .schedule }
                if url.host == "activity", url.path == "/profile" { selection = .profile }
                if url.host == "activity", url.path == "/learning" {
                    let section = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "section" }?.value
                    environment.pendingLearningSection = section == "grades" ? "成绩" : "作业"
                    selection = .grades
                }
                environment.pendingActivityURL = nil
            }
            .sheet(isPresented: $showActivitySettings) {
                NavigationStack {
                    LiveActivitySettingsView()
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("完成") { showActivitySettings = false }
                            }
                        }
                }
            }
            .sheet(isPresented: $showActivityCard) {
                NavigationStack {
                    CardView()
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("完成") { showActivityCard = false }
                            }
                        }
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

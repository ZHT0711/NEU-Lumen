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
    @Environment(\.scenePhase) private var scenePhase
    @State private var selection: AppTab = .home
    @State private var scrollActivity = TabBarScrollActivity()

    var body: some View {
        tabs
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

import SwiftUI

enum AppTab: Hashable {
    case home
    case schedule
    case services
    case grades
    case profile
}

/// 主界面：首页 / 课表 / 服务大厅 / 成绩 / 我的。
struct MainTabView: View {
    @State private var selection: AppTab = .home

    var body: some View {
        TabView(selection: $selection) {
            HomeView()
                .tabItem { Label("首页", systemImage: "house.fill") }
                .tag(AppTab.home)

            ScheduleView()
                .tabItem { Label("课表", systemImage: "calendar") }
                .tag(AppTab.schedule)

            ServicesView()
                .tabItem { Label("服务", systemImage: "square.grid.2x2.fill") }
                .tag(AppTab.services)

            GradesView()
                .tabItem { Label("成绩", systemImage: "chart.bar.fill") }
                .tag(AppTab.grades)

            ProfileView()
                .tabItem { Label("我的", systemImage: "person.fill") }
                .tag(AppTab.profile)
        }
    }
}

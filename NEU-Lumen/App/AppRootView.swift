import SwiftUI

/// 根路由：启动恢复会话；未认证时无法进入主界面。
struct AppRootView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var networkMonitor = CampusNetworkMonitor()
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            switch environment.session.phase {
            case .booting:
                VStack(spacing: 16) {
                    Image(systemName: "sun.max.fill")
                        .font(.system(size: 56))
                        .foregroundStyle(AppTheme.accent)
                    Text("NEU-Lumen")
                        .font(.title2.bold())
                    ProgressView()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            case .loggedOut, .loggingIn:
                LoginView()

            case .loggedIn:
                MainTabView()
            }
        }
        .background(Color(.systemGroupedBackground))
        .task {
            networkMonitor.start { environment.session.networkDidChange() }
            await environment.session.restoreSession()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .inactive || phase == .background { environment.session.persistWebSession() }
            if phase == .active { environment.session.networkDidChange() }
        }
        .animation(.easeInOut(duration: 0.25), value: environment.session.phase)
    }
}

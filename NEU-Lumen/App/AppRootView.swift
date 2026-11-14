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
                    Image(systemName: AppTheme.daylightSymbol())
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
        .safeAreaInset(edge: .top, spacing: 0) {
            if environment.session.phase == .loggedIn {
                if !environment.session.networkAvailable {
                    Label("网络已断开，连接恢复后自动重试", systemImage: "wifi.slash")
                        .font(.caption).frame(maxWidth: .infinity).padding(8).background(.regularMaterial)
                } else if environment.session.recoveringNetwork {
                    HStack(spacing: 8) { ProgressView(); Text("正在恢复连接…") }
                        .font(.caption).frame(maxWidth: .infinity).padding(8).background(.regularMaterial)
                }
            }
        }
        .background { LiveActivityCoordinator() }
        .background { BrowserDownloadCoordinator() }
        .background { CampusReminderCoordinator() }
        .onOpenURL { url in
            guard url.scheme == "neulumen", let host = url.host,
                  ["activity", "dynamic-island"].contains(host) else { return }
            environment.pendingActivityURL = url
        }
        .task {
            networkMonitor.start { environment.session.networkDidChange(isConnected: $0) }
            await environment.session.restoreSession()
        }
        .task(id: environment.session.networkRevision) {
            guard environment.session.networkRevision > 0 else { return }
            await environment.repository.recoverAfterNetworkChange()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .inactive || phase == .background { environment.session.persistWebSession() }
            if phase == .active { environment.session.applicationDidBecomeActive() }
        }
        .animation(.easeInOut(duration: 0.25), value: environment.session.phase)
    }
}

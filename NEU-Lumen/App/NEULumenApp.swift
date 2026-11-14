import SwiftUI
import AppIntents

@main
struct NEULumenApp: App {
    @UIApplicationDelegateAdaptor(CampusApplicationDelegate.self) private var applicationDelegate
    @State private var environment = AppEnvironment()

    var body: some Scene {
        WindowGroup {
            AppRootView()
                .environment(environment)
                .tint(AppTheme.accent)
        }
    }
}

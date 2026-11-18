import SwiftUI
import AppIntents

@main
struct NEULumenApp: App {
    @UIApplicationDelegateAdaptor(CampusApplicationDelegate.self) private var applicationDelegate
    @State private var environment: AppEnvironment

    @MainActor
    init() {
        let environment = AppEnvironment()
        _environment = State(initialValue: environment)
        AppDependencyManager.shared.add(dependency: environment)
        CampusAppShortcuts.updateAppShortcutParameters()
    }

    var body: some Scene {
        WindowGroup {
            AppRootView()
                .environment(environment)
                .tint(AppTheme.accent)
        }
    }
}

import SwiftUI

@main
struct NEULumenApp: App {
    @State private var environment = AppEnvironment()

    var body: some Scene {
        WindowGroup {
            AppRootView()
                .environment(environment)
                .tint(AppTheme.accent)
        }
    }
}

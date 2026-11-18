import SwiftUI

struct CampusWidgetCoordinator: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.scenePhase) private var scenePhase

    private struct RefreshKey: Equatable {
        let phase: SessionStore.Phase
        let epoch: UUID
        let enabled: Bool
        let foreground: Bool
    }

    var body: some View {
        let session = environment.session
        let repository = environment.repository
        let key = RefreshKey(phase: session.phase, epoch: session.requestEpoch,
                             enabled: repository.widgetSharingEnabled, foreground: scenePhase == .active)
        Color.clear
            .task(id: key) { await repository.refreshWidgetSnapshot(foreground: key.foreground) }
            .onChange(of: repository.holidays.revision) { _, _ in repository.enqueueWidgetSnapshotPublication() }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

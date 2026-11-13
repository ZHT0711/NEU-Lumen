// Simulator-only: trigger the real system expanded presentation while Settings is foreground.
import ActivityKit
import UIKit

@MainActor
func prepareSystemIsland(kind: String, manager: DynamicIslandActivityManager) async {
    let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    let ready = documents.appendingPathComponent("system-island-ready.txt")
    let sent = documents.appendingPathComponent("system-island-sent.txt")
    do {
        for _ in 0..<100 {
            if UIApplication.shared.applicationState == .active { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        for activity in Activity<NEULumenActivityAttributes>.activities { await activity.end(nil, dismissalPolicy: .immediate) }
        var state = LiveActivityUIFixture.state(kind)
        state.title = "NEU TEST · " + state.title
        var initial = state; initial.title = "准备系统展开验证"
        manager.synchronize(.init(enabled: true, accountID: "system-fixture", campus: "合成校区",
            state: initial, isForeground: true, refreshDate: Date()))
        try await manager.settleForValidation()
        for _ in 0..<200 {
            if Activity<NEULumenActivityAttributes>.activities.contains(where: { $0.attributes.accountID == "system-fixture" }) { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        guard let activity = Activity<NEULumenActivityAttributes>.activities.first(where: { $0.attributes.accountID == "system-fixture" }) else {
            throw NetworkError(message: "System island fixture did not start")
        }
        let background = UIApplication.shared.beginBackgroundTask(withName: "SystemIslandValidation", expirationHandler: {})
        let finalState = state
        Task { @MainActor in
            defer { UIApplication.shared.endBackgroundTask(background) }
            do {
                for _ in 0..<300 {
                    if UIApplication.shared.applicationState == .background { break }
                    try await Task.sleep(for: .milliseconds(50))
                }
                guard UIApplication.shared.applicationState == .background else {
                    throw NetworkError(message: "System island fixture was not backgrounded")
                }
                var updated = finalState; updated.updatedAt = Date()
                await activity.update(ActivityContent(state: updated, staleDate: updated.freshnessDeadline),
                    alertConfiguration: AlertConfiguration(title: "NEU TEST", body: "模拟器系统展开验证", sound: .default))
                try "PASS: real ActivityKit background alert sent; synthetic data".write(to: sent, atomically: true, encoding: .utf8)
                try await Task.sleep(for: .seconds(5))
            } catch { try? ("FAIL: " + error.localizedDescription).write(to: sent, atomically: true, encoding: .utf8) }
        }
        try "READY: background the app to capture the actual system island".write(to: ready, atomically: true, encoding: .utf8)
    } catch { try? ("FAIL: " + error.localizedDescription).write(to: ready, atomically: true, encoding: .utf8) }
}

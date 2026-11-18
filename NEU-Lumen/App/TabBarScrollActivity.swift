import SwiftUI
import Observation

/// 使用系统 Tab 栏的液态玻璃收缩，并在用户暂停滚动后恢复。
@MainActor
@Observable
final class TabBarScrollActivity {
    enum Direction { case up, down }

    private(set) var direction: Direction?
    @ObservationIgnored private var restoreTask: Task<Void, Never>?
    @ObservationIgnored private var restoreDeadline: ContinuousClock.Instant?

    func moved(by distance: CGFloat) {
        guard abs(distance) > 0.5 else { return }
        let next: Direction = distance > 0 ? .down : .up
        if direction != next { direction = next }
        scheduleRestore(after: .milliseconds(650))
    }

    func ended() {
        guard direction != nil else { return }
        restoreTask?.cancel()
        restoreTask = nil
        scheduleRestore(after: .milliseconds(350))
    }

    func restore() {
        restoreTask?.cancel()
        restoreTask = nil
        restoreDeadline = nil
        if direction != nil { direction = nil }
    }

    private func scheduleRestore(after delay: Duration) {
        restoreDeadline = ContinuousClock.now.advanced(by: delay)
        guard restoreTask == nil else { return }
        restoreTask = Task { @MainActor [weak self] in
            while let deadline = self?.restoreDeadline {
                do { try await Task.sleep(until: deadline, clock: .continuous) }
                catch { return }
                guard let self, !Task.isCancelled else { return }
                if self.restoreDeadline == deadline {
                    self.restore()
                    return
                }
            }
        }
    }
}

private struct TabBarScrollActivityKey: EnvironmentKey {
    static let defaultValue: TabBarScrollActivity? = nil
}

extension EnvironmentValues {
    var tabBarScrollActivity: TabBarScrollActivity? {
        get { self[TabBarScrollActivityKey.self] }
        set { self[TabBarScrollActivityKey.self] = newValue }
    }
}

struct ScrollingTabBarStyle: ViewModifier {
    let activity: TabBarScrollActivity

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.tabBarMinimizeBehavior(behavior)
        } else {
            content
        }
    }

    @available(iOS 26.0, *)
    private var behavior: TabBarMinimizeBehavior {
        switch activity.direction {
        case .up: .onScrollUp
        case .down: .onScrollDown
        case nil: .never
        }
    }
}

/// 仅接在各 Tab 的主滚动容器上，横向筛选条和弹窗不会驱动底栏。
private struct TabBarScrollTracking: ViewModifier {
    @Environment(\.tabBarScrollActivity) private var activity
    @State private var userScrolling = false

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
                .onScrollPhaseChange { _, phase in
                    userScrolling = phase == .interacting || phase == .decelerating
                    if !userScrolling { activity?.ended() }
                }
                .onScrollGeometryChange(for: CGFloat.self) { geometry in
                    geometry.contentOffset.y
                } action: { previous, current in
                    if userScrolling { activity?.moved(by: current - previous) }
                }
                .onDisappear {
                    userScrolling = false
                    activity?.restore()
                }
        } else {
            content
        }
    }
}

extension View {
    func tracksTabBarScrolling() -> some View {
        modifier(TabBarScrollTracking())
    }
}

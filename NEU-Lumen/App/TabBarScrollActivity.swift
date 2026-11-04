import SwiftUI
import Observation

/// 使用系统 Tab 栏的液态玻璃收缩，并在用户暂停滚动后恢复。
@MainActor
@Observable
final class TabBarScrollActivity {
    enum Direction { case up, down }

    private(set) var direction: Direction?
    @ObservationIgnored private var restoreTask: Task<Void, Never>?

    func moved(by distance: CGFloat) {
        guard abs(distance) > 0.5 else { return }
        direction = distance > 0 ? .down : .up
        scheduleRestore(after: .milliseconds(650))
    }

    func ended() {
        scheduleRestore(after: .milliseconds(350))
    }

    func restore() {
        restoreTask?.cancel()
        restoreTask = nil
        direction = nil
    }

    private func scheduleRestore(after delay: Duration) {
        restoreTask?.cancel()
        let deadline = ContinuousClock.now.advanced(by: delay)
        restoreTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(until: deadline, clock: .continuous) }
            catch { return }
            guard !Task.isCancelled else { return }
            self?.restore()
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

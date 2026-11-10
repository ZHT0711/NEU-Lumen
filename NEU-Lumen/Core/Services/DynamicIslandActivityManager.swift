import Foundation
import ActivityKit

/// 管理锁屏和系统灵动岛上的 Live Activity 生命周期。
@MainActor
final class DynamicIslandActivityManager {
    static let shared = DynamicIslandActivityManager()
    private var activity: Activity<NEULumenActivityAttributes>?

    func startOrUpdate(store: DynamicIslandStore, repository: PortalRepository) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let state = makeState(store: store, repository: repository)
        let content = ActivityContent(state: state, staleDate: Date().addingTimeInterval(60 * 30))
        if let activity {
            Task { await activity.update(content) }
            return
        }
        let attributes = NEULumenActivityAttributes(campus: repository.campus.title)
        activity = try? Activity.request(attributes: attributes, content: content, pushType: nil)
    }

    func end() {
        guard let activity else { return }
        Task { await activity.end(nil, dismissalPolicy: .immediate) }
        self.activity = nil
    }

    private func makeState(store: DynamicIslandStore, repository: PortalRepository) -> NEULumenActivityAttributes.ContentState {
        switch store.kind {
        case .nextCourse:
            let next = repository.nextCourse()
            return .init(title: next?.slot.name ?? "暂无课程",
                         subtitle: next.map { "\(Semester.hm($0.slot.startMinutes)) · \($0.slot.room.isEmpty ? "地点待定" : $0.slot.room)" } ?? "去配置页选择自定义内容",
                         value: next.map { Semester.hm($0.slot.startMinutes) } ?? "",
                         kind: store.kind.rawValue, updatedAt: Date())
        case .cardBalance:
            let value = repository.cardSummaryText.map { "¥\($0)" } ?? "未同步"
            return .init(title: "校园卡余额", subtitle: "当前可用余额 \(value)", value: value,
                         kind: store.kind.rawValue, updatedAt: Date())
        case .custom:
            return .init(title: store.customTitle.isEmpty ? "自定义内容" : store.customTitle,
                         subtitle: store.customSubtitle, value: "", kind: store.kind.rawValue, updatedAt: Date())
        }
    }
}

import ActivityKit
import Foundation
import Observation

/// ActivityKit operations are serialized, including logout and account switches.
@MainActor
@Observable
final class DynamicIslandActivityManager {
    struct Request: Equatable {
        var enabled: Bool
        var accountID: String?
        var campus: String
        var state: NEULumenActivityAttributes.ContentState?
        var isForeground: Bool
        var refreshDate: Date
        var contentReady = true
        var contentKind: String?
    }

    private(set) var isRunning = false
    private(set) var status = "尚未开启"
    private(set) var lastError: String?

    @ObservationIgnored private var activity: Activity<NEULumenActivityAttributes>?
    @ObservationIgnored private var stateTask: Task<Void, Never>?
    @ObservationIgnored private var worker: Task<Void, Never>?
    @ObservationIgnored private var pendingRequest: Request?
    @ObservationIgnored private var latestRequest: Request?
    @ObservationIgnored private var accountID: String?
    @ObservationIgnored private var automaticStartBlocked = false

    func synchronize(_ request: Request) {
        latestRequest = request
        pendingRequest = request
        guard worker == nil else { return }
        worker = Task {
            while let request = pendingRequest {
                pendingRequest = nil
                await apply(request)
            }
            worker = nil
        }
    }

    func restart() {
        guard let request = latestRequest, request.isForeground else { return }
        automaticStartBlocked = false
        lastError = nil
        synchronize(request)
    }

    private func apply(_ request: Request) async {
        if accountID != request.accountID {
            if accountID != nil { await endAll() }
            accountID = request.accountID
            automaticStartBlocked = false
            lastError = nil
        }
        guard request.enabled, request.accountID != nil else {
            await endAll()
            automaticStartBlocked = false
            lastError = nil
            status = request.enabled ? "等待登录" : "已关闭"
            return
        }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            await endAll()
            status = "系统未允许实时活动"
            lastError = "请在系统设置中允许 NEU-Lumen 使用实时活动。"
            return
        }
        // Restore only active activities belonging to this account. Old schemas
        // have no owner and are ended before any new account data is published.
        let existing = Activity<NEULumenActivityAttributes>.activities
        if activity == nil {
            if let restored = existing.first(where: {
                $0.attributes.accountID == request.accountID &&
                ($0.activityState == .active || $0.activityState == .stale)
            }) {
                observe(restored)
            }
        }
        for orphan in existing where orphan.id != activity?.id {
            await orphan.end(nil, dismissalPolicy: .immediate)
        }
        // An awaited operation may have allowed a newer logout/configuration in.
        guard pendingRequest == nil else { return }

        guard var state = request.state else {
            if request.contentReady || activity?.content.state.kind != request.contentKind {
                await endAll()
            }
            status = isRunning ? "等待最新数据" : "等待可用的课表或校园卡数据"
            return
        }

        if let activity {
            var previous = activity.content.state
            if state.updatedAt == .distantPast { previous.updatedAt = .distantPast }
            guard previous != state else { return }
            if state.updatedAt == .distantPast { state.updatedAt = request.refreshDate }
            await activity.update(content(for: state))
            lastError = nil
            return
        }
        guard request.isForeground, !automaticStartBlocked else { return }
        if state.updatedAt == .distantPast { state.updatedAt = request.refreshDate }
        do {
            let attributes = NEULumenActivityAttributes(campus: request.campus, accountID: request.accountID)
            let started = try Activity.request(attributes: attributes,
                content: content(for: state), pushType: nil)
            observe(started)
            lastError = nil
        } catch {
            automaticStartBlocked = true
            status = "开启失败"
            lastError = error.localizedDescription
        }
    }

    private func content(for state: NEULumenActivityAttributes.ContentState)
        -> ActivityContent<NEULumenActivityAttributes.ContentState> {
        // Custom text remains valid until the system ends the activity.
        let staleDate = state.kind == "custom" ? nil :
            (state.endDate ?? state.updatedAt.addingTimeInterval(30 * 60))
        return ActivityContent(state: state, staleDate: staleDate, relevanceScore: 50)
    }

    private func observe(_ activity: Activity<NEULumenActivityAttributes>) {
        stateTask?.cancel()
        self.activity = activity
        isRunning = true
        status = activity.activityState == .stale ? "内容待更新" : "正在显示"
        stateTask = Task { [weak self] in
            for await state in activity.activityStateUpdates {
                guard let self, !Task.isCancelled, self.activity?.id == activity.id else { return }
                switch state {
                case .active:
                    self.status = "正在显示"
                case .stale:
                    self.status = "内容待更新"
                case .ended, .dismissed:
                    self.activity = nil
                    self.isRunning = false
                    self.automaticStartBlocked = true
                    self.status = "已结束，可手动重新开启"
                    return
                default:
                    self.status = "等待系统显示"
                }
            }
        }
    }

    private func endAll() async {
        stateTask?.cancel()
        stateTask = nil
        var existing = Activity<NEULumenActivityAttributes>.activities
        if let activity, !existing.contains(where: { $0.id == activity.id }) {
            existing.append(activity)
        }
        activity = nil
        isRunning = false
        for activity in existing { await activity.end(nil, dismissalPolicy: .immediate) }
    }
}

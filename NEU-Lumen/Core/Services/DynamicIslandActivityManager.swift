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
            lastError = nil
            status = isRunning ? "显示上次内容，等待最新数据" : waitingStatus(for: request)
            return
        }

        let usesRefreshDate = state.updatedAt == .distantPast
        if usesRefreshDate { state.updatedAt = request.refreshDate }
        // Bound the final timestamp too, before testing ActivityKit's full envelope.
        state = state.boundedText()
        let payloadAttributes = NEULumenActivityAttributes(campus: request.campus, accountID: request.accountID)
        let encoder = JSONEncoder()
        guard let stateBytes = try? encoder.encode(state).count,
              let attributeBytes = try? encoder.encode(payloadAttributes).count,
              stateBytes + attributeBytes < 4000 else {
            await endAll()
            status = "内容过长"
            lastError = "内容超过系统实时活动大小限制，请缩短自定义文字。"
            return
        }
        if let activity {
            var previous = activity.content.state
            var comparison = state
            if usesRefreshDate { previous.updatedAt = .distantPast; comparison.updatedAt = .distantPast }
            guard previous != comparison else { return }
            await activity.update(content(for: state))
            lastError = nil
            return
        }
        guard request.isForeground, !automaticStartBlocked else { return }
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

    private func waitingStatus(for request: Request) -> String {
        let source: String
        switch request.contentKind {
        case "nextCourse": source = "课表"
        case "cardBalance": source = "校园卡"
        case "netBalance": source = "网费"
        case "electricBalance": source = "电费"
        case "assignments": source = "作业"
        case "planner": source = "日程"
        case "dayOverview": source = "今日概览"
        case "academicOverview": source = "成绩"
        default: source = "所选内容"
        }
        return request.contentReady ? "\(source)暂无可展示的数据" : "等待读取\(source)数据"
    }

    private func content(for state: NEULumenActivityAttributes.ContentState)
        -> ActivityContent<NEULumenActivityAttributes.ContentState> {
        // Shared, natively tested policy preserves start/end and template boundaries.
        ActivityContent(state: state, staleDate: state.freshnessDeadline, relevanceScore: 50)
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

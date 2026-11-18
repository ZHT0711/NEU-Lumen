import ActivityKit
import CryptoKit
import Foundation
import Observation
import UIKit

/// ActivityKit operations are serialized, including logout and account switches.
@MainActor
@Observable
final class DynamicIslandActivityManager {
    struct ScheduledValidation: Equatable {
        let event: ScheduledLiveActivityPlan.Event
        let isCurrent: Bool
    }

    struct Request: Equatable {
        var enabled: Bool
        var accountID: String?
        var campus: String
        var state: NEULumenActivityAttributes.ContentState?
        var isForeground: Bool
        var refreshDate: Date
        var contentReady = true
        var contentKind: String?
        var scheduledValidation: ScheduledValidation? = nil
    }

    private(set) var isRunning = false
    private(set) var status = "尚未开启"
    private(set) var lastError: String?
    private(set) var scheduledCountdown: ScheduledLiveActivityPlan?
    private(set) var isChangingScheduledCountdown = false
    private(set) var scheduledCountdownMessage: String?

    @ObservationIgnored private var activity: Activity<NEULumenActivityAttributes>?
    @ObservationIgnored private var stateTask: Task<Void, Never>?
    @ObservationIgnored private var worker: Task<Void, Never>?
    @ObservationIgnored private var pendingRequest: Request?
    @ObservationIgnored private var latestRequest: Request?
    @ObservationIgnored private var accountID: String?
    @ObservationIgnored private var automaticStartBlocked = false
    @ObservationIgnored private var scheduledActivity: Activity<NEULumenActivityAttributes>?
    @ObservationIgnored private var scheduledStateTask: Task<Void, Never>?
    @ObservationIgnored private var scheduledExpiryTask: Task<Void, Never>?
    @ObservationIgnored private var scheduledOperation: (@MainActor () async -> Void)?
    @ObservationIgnored private var pendingScheduledCancellation = false

    func synchronize(_ request: Request) {
        latestRequest = request
        pendingRequest = request
        startWorker()
    }

    private func startWorker() {
        guard worker == nil else { return }
        worker = Task {
            while true {
                if pendingScheduledCancellation {
                    pendingScheduledCancellation = false
                    await finishScheduledCountdowns(except: nil)
                } else if let request = pendingRequest {
                    pendingRequest = nil
                    await apply(request)
                } else if let operation = scheduledOperation {
                    scheduledOperation = nil
                    await operation()
                } else {
                    break
                }
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
        await reconcileScheduledCountdown(for: request)
        guard pendingRequest == nil else { return }
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
        let existing = Activity<NEULumenActivityAttributes>.activities.filter { $0.attributes.scheduledCountdown == nil }
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
        var existing = Activity<NEULumenActivityAttributes>.activities.filter { $0.attributes.scheduledCountdown == nil }
        if let activity, !existing.contains(where: { $0.id == activity.id }) {
            existing.append(activity)
        }
        activity = nil
        isRunning = false
        for activity in existing { await activity.end(nil, dismissalPolicy: .immediate) }
    }

    @available(iOS 26.0, *)
    func scheduleCountdown(event: ScheduledLiveActivityPlan.Event, leadMinutes: Int, account: String,
                           canSchedule: @escaping @MainActor () -> Bool) async throws {
        guard !isChangingScheduledCountdown else { throw ScheduleError.inProgress }
        isChangingScheduledCountdown = true
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            scheduledOperation = {
                defer { self.isChangingScheduledCountdown = false }
                do {
                    try await self.createScheduledCountdown(event: event, leadMinutes: leadMinutes, account: account,
                                                            canSchedule: canSchedule)
                    continuation.resume()
                } catch { continuation.resume(throwing: error) }
            }
            startWorker()
        }
    }

    func cancelScheduledCountdown() {
        pendingScheduledCancellation = true
        scheduledCountdownMessage = nil
        startWorker()
    }

    @available(iOS 26.0, *)
    private func createScheduledCountdown(event: ScheduledLiveActivityPlan.Event, leadMinutes: Int, account: String,
                                          canSchedule: @MainActor () -> Bool) async throws {
        guard !account.isEmpty, canSchedule() else { throw ScheduleError.sourceChanged }
        guard UIApplication.shared.applicationState == .active else { throw ScheduleError.notForeground }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { throw ScheduleError.systemDisabled }
        let now = Date()
        guard let plan = ScheduledLiveActivityPlan(event: event, leadMinutes: leadMinutes, now: now) else {
            throw ScheduleError.timePassed
        }
        let owner = Self.scheduledOwner(account)
        let attributes = NEULumenActivityAttributes(campus: "", accountID: owner, scheduledCountdown: plan)
        let body: LocalizedStringResource = event.isExam ? "考试即将开始。" : "课程即将开始。"
        let started: Activity<NEULumenActivityAttributes>
        do {
            started = try Activity.request(attributes: attributes, content: content(for: plan.content(at: now)),
                pushType: nil, style: .standard,
                alertConfiguration: AlertConfiguration(title: "NEU-Lumen 倒计时", body: body, sound: .default),
                start: plan.activatesAt)
        } catch {
            throw ScheduleError.systemDeclined
        }
        // Preserve any existing reservation if the system rejects the new one.
        let previous = scheduledActivity
        observeScheduledCountdown(started)
        await finishScheduledCountdowns(except: started.id, including: previous)
        guard canSchedule() else {
            await finishScheduledCountdowns(except: nil)
            throw ScheduleError.sourceChanged
        }
        scheduledCountdownMessage = nil
    }

    private func reconcileScheduledCountdown(for request: Request) async {
        let existing = scheduledActivities()
        guard !existing.isEmpty else { clearScheduledObservation(); return }
        guard #available(iOS 26.0, *), let account = request.accountID,
              ActivityAuthorizationInfo().areActivitiesEnabled else {
            await finishScheduledCountdowns(except: nil)
            scheduledCountdownMessage = nil
            return
        }
        let owner = Self.scheduledOwner(account)
        let now = Date()
        let valid = existing.filter { candidate in
            guard let plan = candidate.attributes.scheduledCountdown,
                  candidate.attributes.accountID == owner, plan.event.startsAt > now,
                  candidate.activityState == .pending || candidate.activityState == .active
                      || candidate.activityState == .stale else { return false }
            return request.scheduledValidation?.event != plan.event || request.scheduledValidation?.isCurrent == true
        }
        let previous = scheduledActivity
        let selected = valid.first(where: { $0.id == previous?.id }) ?? valid.first
        if let selected {
            observeScheduledCountdown(selected)
        } else {
            if let validation = request.scheduledValidation, !validation.isCurrent,
               existing.contains(where: {
                   $0.attributes.accountID == owner && $0.attributes.scheduledCountdown?.event == validation.event
               }) {
                scheduledCountdownMessage = "安排已更新，预约已取消。"
            }
        }
        await finishScheduledCountdowns(except: selected?.id, including: previous)
    }

    private func observeScheduledCountdown(_ activity: Activity<NEULumenActivityAttributes>) {
        guard scheduledActivity?.id != activity.id, let plan = activity.attributes.scheduledCountdown else { return }
        clearScheduledObservation()
        scheduledActivity = activity
        scheduledCountdown = plan
        scheduledStateTask = Task { [weak self] in
            for await state in activity.activityStateUpdates {
                guard let self, !Task.isCancelled, self.scheduledActivity?.id == activity.id else { return }
                if state == .ended || state == .dismissed {
                    self.clearScheduledObservation()
                    return
                }
            }
        }
        scheduledExpiryTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(max(0, plan.event.startsAt.timeIntervalSinceNow))) }
            catch { return }
            guard let self, self.scheduledActivity?.id == activity.id else { return }
            self.cancelScheduledCountdown()
        }
    }

    private func clearScheduledObservation() {
        scheduledStateTask?.cancel()
        scheduledStateTask = nil
        scheduledExpiryTask?.cancel()
        scheduledExpiryTask = nil
        scheduledActivity = nil
        scheduledCountdown = nil
    }

    private func scheduledActivities() -> [Activity<NEULumenActivityAttributes>] {
        var existing = Activity<NEULumenActivityAttributes>.activities.filter { $0.attributes.scheduledCountdown != nil }
        if let scheduledActivity, !existing.contains(where: { $0.id == scheduledActivity.id }) {
            existing.append(scheduledActivity)
        }
        return existing
    }

    private func finishScheduledCountdowns(except id: String?, including previous: Activity<NEULumenActivityAttributes>? = nil) async {
        var existing = scheduledActivities()
        if let previous, !existing.contains(where: { $0.id == previous.id }) { existing.append(previous) }
        if id == nil { clearScheduledObservation() }
        for candidate in existing where candidate.id != id { await candidate.end(nil, dismissalPolicy: .immediate) }
    }

    private static func scheduledOwner(_ account: String) -> String {
        SHA256.hash(data: Data(account.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private enum ScheduleError: LocalizedError {
        case sourceChanged, inProgress, timePassed, notForeground, systemDisabled, systemDeclined

        var errorDescription: String? {
            switch self {
            case .sourceChanged: "请回到安排页面，确认校园账号和最新时间后再预约。"
            case .inProgress: "正在处理另一项预约。"
            case .timePassed: "该倒计时的约定开启时间已过。请选择更短的提前时间。"
            case .notForeground: "请在 NEU-Lumen 打开时预约。"
            case .systemDisabled: "请在系统设置中允许 NEU-Lumen 使用实时活动。"
            case .systemDeclined: "系统未能接受这项预约。可在“实时活动”中检查已预约的倒计时。"
            }
        }
    }
}

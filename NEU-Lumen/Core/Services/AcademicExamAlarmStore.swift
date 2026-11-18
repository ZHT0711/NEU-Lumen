import AlarmKit
import Foundation
import Observation
import SwiftUI

@available(iOS 26.0, *)
@MainActor @Observable
final class AcademicExamAlarmStore {
    static let shared = AcademicExamAlarmStore()
    private static let storageKey = "lumen.academic.exam-alarms.v1"

    private let manager = AlarmManager.shared
    private let defaults: UserDefaults
    private var records: [AcademicExamAlarmRecord]
    private var owner: String?
    private var hasResolvedAccount = false
    @ObservationIgnored private var creating: Set<AcademicExamAlarmTarget> = []
    private var inFlight: Set<UUID> = []
    private(set) var permissionDenied = false
    private(set) var changedExams: Set<AcademicExamAlarmTarget> = []

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        records = defaults.data(forKey: Self.storageKey)
            .flatMap { try? JSONDecoder().decode([AcademicExamAlarmRecord].self, from: $0) } ?? []
    }

    func alarm(for target: AcademicExamAlarmTarget) -> AcademicExamAlarmRecord? {
        records.first { $0.target == target && !inFlight.contains($0.id) }
    }

    func activate(owner: String?) {
        if owner != self.owner { changedExams.removeAll() }
        self.owner = owner
        hasResolvedAccount = true
        for index in records.indices where records[index].target.owner != owner {
            records[index].needsCancellation = true
        }
        persist()
        refreshSystemState()
    }

    func watchSystemState() async {
        for await _ in manager.alarmUpdates {
            guard !Task.isCancelled else { return }
            refreshSystemState()
        }
    }

    func refreshSystemState() {
        permissionDenied = manager.authorizationState == .denied
        guard !records.isEmpty else { return }
        let active = try? Set(manager.alarms.map(\.id))
        for record in records where !inFlight.contains(record.id) {
            if active?.contains(record.id) == false {
                remove(record.id)
            } else if record.needsCancellation || (hasResolvedAccount && record.target.owner != owner) {
                if (try? manager.cancel(id: record.id)) != nil { remove(record.id) }
            }
        }
    }

    /// This is called only with a successful authoritative result for this term.
    func reconcile(exams: [AcademicExam], term: String, owner: String) {
        for index in records.indices {
            let record = records[index]
            guard record.target.owner == owner, record.target.term == term else { continue }
            let exam = exams.first { $0.id == record.target.examID }
            if AcademicExamAlarmPolicy.invalidates(record, owner: owner, term: term, examStart: exam?.start) {
                records[index].needsCancellation = true
                changedExams.insert(record.target)
            }
        }
        persist()
        refreshSystemState()
    }

    func schedule(target: AcademicExamAlarmTarget, examStart: Date, leadMinutes: Int,
                  isCurrent: @MainActor () -> Bool) async throws {
        guard creating.insert(target).inserted else { throw AlarmIssue.inProgress }
        defer { creating.remove(target) }
        guard isCurrent(), target.owner == owner else { throw AlarmIssue.examChanged }
        refreshSystemState()
        guard !records.contains(where: { $0.target == target }) else { throw AlarmIssue.alreadyScheduled }

        guard !permissionDenied else { throw AlarmIssue.permissionDenied }
        if manager.authorizationState != .authorized {
            let state = try await manager.requestAuthorization()
            permissionDenied = state == .denied
            guard state == .authorized else { throw AlarmIssue.permissionDenied }
        }
        guard isCurrent(), target.owner == owner else { throw AlarmIssue.examChanged }
        guard let fireAt = AcademicExamAlarmPolicy.fireDate(examStart: examStart, leadMinutes: leadMinutes, now: Date()) else {
            throw AlarmIssue.timePassed
        }

        let record = AcademicExamAlarmRecord(id: UUID(), target: target, examStart: examStart, fireAt: fireAt)
        inFlight.insert(record.id)
        records.append(record)
        persist()
        let attributes = AlarmAttributes(presentation: AlarmPresentation(alert: Self.presentation()),
                                         metadata: ExamAlarmMetadata(), tintColor: AppTheme.accent)
        let configuration = AlarmManager.AlarmConfiguration.alarm(schedule: .fixed(fireAt), attributes: attributes)
        do {
            _ = try await manager.schedule(id: record.id, configuration: configuration)
        } catch {
            inFlight.remove(record.id)
            // A failed IPC reply can leave the operation in an unknown state. Retire the ID
            // before retrying so the next attempt cannot create a second alarm.
            retire(record.id)
            throw AlarmIssue.scheduleFailed
        }
        inFlight.remove(record.id)
        guard isCurrent(), target.owner == owner,
              records.contains(where: { $0.id == record.id && !$0.needsCancellation }) else {
            retire(record.id)
            throw AlarmIssue.examChanged
        }
        changedExams.remove(target)
    }

    func cancel(_ target: AcademicExamAlarmTarget) throws {
        guard let record = alarm(for: target), target.owner == owner else { return }
        do {
            try manager.cancel(id: record.id)
            remove(record.id)
        } catch {
            if (try? manager.alarms.contains(where: { $0.id == record.id })) == false {
                remove(record.id)
            } else {
                throw AlarmIssue.cancelFailed
            }
        }
    }

    private func retire(_ id: UUID) {
        guard let index = records.firstIndex(where: { $0.id == id }) else { return }
        records[index].needsCancellation = true
        persist()
        refreshSystemState()
    }

    private func remove(_ id: UUID) {
        records.removeAll { $0.id == id }
        persist()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(records) { defaults.set(data, forKey: Self.storageKey) }
    }

    private static func presentation() -> AlarmPresentation.Alert {
        if #available(iOS 26.1, *) {
            AlarmPresentation.Alert(title: "考试闹钟")
        } else {
            legacyPresentation()
        }
    }

    @available(iOS, introduced: 26.0, deprecated: 26.1)
    private static func legacyPresentation() -> AlarmPresentation.Alert {
        AlarmPresentation.Alert(title: "考试闹钟", stopButton: AlarmButton(text: "停止", textColor: .white, systemImageName: "stop.fill"))
    }

    enum AlarmIssue: LocalizedError {
        case inProgress, examChanged, alreadyScheduled, permissionDenied, timePassed, scheduleFailed, cancelFailed

        var errorDescription: String? {
            switch self {
            case .inProgress: "此考试的闹钟正在设置。"
            case .examChanged: "考试安排或校园账号已更新，请重新核对后设置。"
            case .alreadyScheduled: "这场考试已有闹钟。更改响铃时间前，请取消原闹钟。"
            case .permissionDenied: "请在系统设置中允许 NEU-Lumen 设置闹钟。"
            case .timePassed: "所选响铃时间已过，请选择更接近考试的时间。"
            case .scheduleFailed: "闹钟设置失败，请稍后重试。"
            case .cancelFailed: "系统暂时无法取消闹钟，请再试一次。"
            }
        }
    }
}

@available(iOS 26.0, *)
private struct ExamAlarmMetadata: AlarmMetadata {}

extension SessionStore {
    var examAlarmOwner: String? {
        guard phase == .loggedIn, let user else { return nil }
        let account = user.sid.isEmpty ? user.uid : user.sid
        return account.isEmpty ? nil : CampusReminderStore.key(account)
    }
}

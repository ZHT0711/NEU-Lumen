import CryptoKit
import SwiftUI

struct ScheduledLiveActivitySelection {
    let event: ScheduledLiveActivityPlan.Event
    let label: String

    static func course(_ course: CourseOccurrence) -> Self? {
        guard course.slot.kind == "course", (0..<1440).contains(course.slot.startMinutes),
              let startsAt = CampusReminderPolicy.clock(day: course.date, minutes: course.slot.startMinutes) else { return nil }
        return .init(event: .init(source: .course(day: PortalDate.isoDay(course.date)),
                                  key: key(for: course.id), startsAt: startsAt),
                     label: course.slot.name)
    }

    static func exam(_ exam: AcademicExam, term: String) -> Self? {
        guard !term.isEmpty, let startsAt = exam.start else { return nil }
        return .init(event: .init(source: .exam(term: term), key: key(for: exam.id + "\n" + exam.title),
                                  startsAt: startsAt),
                     label: exam.title)
    }

    private static func key(for identity: String) -> String {
        SHA256.hash(data: Data(identity.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

struct ScheduledLiveActivityButton: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var confirmation: Confirmation?
    @State private var showsConfirmation = false
    @State private var error: String?
    @State private var showsError = false
    let selection: ScheduledLiveActivitySelection?

    private struct Confirmation {
        let selection: ScheduledLiveActivitySelection
        let account: String
        let epoch: UUID
        let leadTimes: [Int]
    }

    init(course: CourseOccurrence) { selection = .course(course) }
    init(exam: AcademicExam, term: String) { selection = .exam(exam, term: term) }

    var body: some View {
        if #available(iOS 26.0, *), let selection {
            let manager = environment.liveActivityManager
            if manager.scheduledCountdown?.event == selection.event {
                Button("取消实时活动预约", systemImage: "timer") { manager.cancelScheduledCountdown() }
                    .disabled(manager.isChangingScheduledCountdown)
            } else if ScheduledLiveActivityPlan(event: selection.event, leadMinutes: 5, now: Date()) != nil {
                Button("预约实时活动", systemImage: "timer") { prepareConfirmation(selection) }
                    .disabled(manager.isChangingScheduledCountdown)
                    .confirmationDialog("何时开始倒计时？", isPresented: $showsConfirmation,
                                        titleVisibility: .visible, presenting: confirmation) { confirmation in
                        ForEach(confirmation.leadTimes, id: \.self) { minutes in
                            Button("提前 \(minutes) 分钟") { schedule(confirmation, leadMinutes: minutes) }
                        }
                        Button("取消", role: .cancel) {}
                    } message: { confirmation in
                        Text(explanation(for: confirmation.selection))
                    }
                    .alert("无法预约实时活动", isPresented: $showsError, presenting: error) { _ in
                        Button("好", role: .cancel) {}
                    } message: { message in
                        Text(message)
                    }
            }
        }
    }

    private func prepareConfirmation(_ selection: ScheduledLiveActivitySelection) {
        let session = environment.session
        guard session.phase == .loggedIn, let user = session.user else { return }
        let account = user.sid.isEmpty ? user.uid : user.sid
        let now = Date()
        let leads = ScheduledLiveActivityPlan.leadTimes.filter {
            ScheduledLiveActivityPlan(event: selection.event, leadMinutes: $0, now: now) != nil
        }
        guard !account.isEmpty, !leads.isEmpty else { return }
        confirmation = .init(selection: selection, account: account, epoch: session.requestEpoch, leadTimes: leads)
        showsConfirmation = true
    }

    private func explanation(for selection: ScheduledLiveActivitySelection) -> String {
        let time = LiveActivityDataPolicy.dateText(selection.event.startsAt, format: "M月d日 HH:mm",
                                                   calendar: CampusReminderPolicy.calendar)
        let replacement = environment.liveActivityManager.scheduledCountdown != nil ? "本次会替换现有预约。" : ""
        return "\(selection.label) · \(time)（北京时间）。届时系统会开始显示倒计时并发出提示。锁屏只显示倒计时，详细安排可在应用内查看。\(replacement)"
    }

    @available(iOS 26.0, *)
    private func schedule(_ confirmation: Confirmation, leadMinutes: Int) {
        let session = environment.session
        let repository = environment.repository
        let event = confirmation.selection.event
        Task { @MainActor in
            do {
                try await environment.liveActivityManager.scheduleCountdown(event: event, leadMinutes: leadMinutes,
                                                                            account: confirmation.account) {
                    guard session.phase == .loggedIn, session.requestEpoch == confirmation.epoch,
                          let user = session.user, (user.sid.isEmpty ? user.uid : user.sid) == confirmation.account else { return false }
                    return repository.scheduledLiveActivityIsCurrent(event) == true
                }
            } catch {
                self.error = error.localizedDescription
                showsError = true
            }
        }
    }
}

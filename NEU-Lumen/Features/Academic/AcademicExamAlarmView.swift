import SwiftUI
import UIKit

@available(iOS 26.0, *)
struct AcademicExamAlarmCoordinator: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.scenePhase) private var scenePhase

    private struct Access: Equatable {
        let phase: SessionStore.Phase
        let owner: String?
        let foreground: Bool
    }

    var body: some View {
        let access = Access(phase: environment.session.phase, owner: environment.session.examAlarmOwner,
                            foreground: scenePhase == .active)
        Color.clear
            .task(id: access) {
                if access.phase == .loggedOut || access.owner != nil {
                    AcademicExamAlarmStore.shared.activate(owner: access.owner)
                }
            }
            .task { await AcademicExamAlarmStore.shared.watchSystemState() }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

@available(iOS 26.0, *)
struct AcademicExamAlarmRow: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var editing = false
    let exam: AcademicExam
    let term: String

    var body: some View {
        if let owner = environment.session.examAlarmOwner {
            let target = AcademicExamAlarmTarget(owner: owner, term: term, examID: exam.id)
            let alarm = AcademicExamAlarmStore.shared.alarm(for: target)
            if alarm != nil || exam.start.map({ $0 > Date() }) == true {
                Button {
                    editing = true
                } label: {
                    if let alarm, !alarm.needsCancellation {
                        LabeledContent {
                            Text(alarm.fireAt, format: .dateTime.month().day().hour().minute())
                        } label: {
                            Label("考试闹钟", systemImage: "alarm.fill")
                        }
                    } else {
                        Label("考试闹钟", systemImage: "alarm")
                    }
                }
                .accessibilityHint("查看或设置这场考试的响铃时间")
                .sheet(isPresented: $editing) {
                    AcademicExamAlarmSheet(exam: exam, target: target, epoch: environment.session.requestEpoch)
                }
            }
        }
    }
}

@available(iOS 26.0, *)
private struct AcademicExamAlarmSheet: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var selectedLead: Int?
    @State private var working = false
    @State private var errorMessage: String?

    let exam: AcademicExam
    let target: AcademicExamAlarmTarget
    let epoch: UUID
    private var store: AcademicExamAlarmStore { .shared }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(exam.title)
                    if let start = exam.start {
                        LabeledContent("考试开始") {
                            Text(start, format: .dateTime.month().day().hour().minute())
                        }
                    }
                }
                alarmControls(now: Date())
                if let errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "exclamationmark.circle")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                if store.permissionDenied {
                    Section {
                        Button("打开系统设置", systemImage: "gear") {
                            guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                            openURL(url)
                        }
                    } footer: {
                        Text("允许 NEU-Lumen 设置闹钟后，可回到这里选择响铃时间。")
                    }
                }
            }
            .navigationTitle("考试闹钟")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(store.alarm(for: target) == nil ? "取消" : "关闭") { dismiss() }
                        .disabled(working)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .interactiveDismissDisabled(working)
        .onAppear { store.refreshSystemState() }
        .onChange(of: environment.session.requestEpoch) { _, _ in dismiss() }
    }

    @ViewBuilder
    private func alarmControls(now: Date) -> some View {
        let leads = exam.start.map { start in
            AcademicExamAlarmPolicy.leadOptions.filter {
                AcademicExamAlarmPolicy.fireDate(examStart: start, leadMinutes: $0, now: now) != nil
            }
        } ?? []
        if let alarm = store.alarm(for: target) {
            Section {
                if alarm.needsCancellation {
                    Text("原闹钟等待取消").foregroundStyle(.secondary)
                } else {
                    LabeledContent("已设响铃时间") {
                        Text(alarm.fireAt, format: .dateTime.month().day().hour().minute())
                    }
                }
                Button("取消考试闹钟", role: .destructive, action: cancel)
            }
        } else if let start = exam.start, let fallback = leads.first(where: { $0 <= 15 }) {
            let lead = selectedLead.flatMap { leads.contains($0) ? $0 : nil } ?? fallback
            Section {
                if store.changedExams.contains(target) {
                    Text("学校更新了考试安排，原闹钟已取消。").foregroundStyle(.secondary)
                }
                Picker("提前响铃", selection: Binding(get: { lead }, set: { selectedLead = $0 })) {
                    ForEach(leads, id: \.self) { minutes in
                        Text(minutes == 0 ? "考试开始时" : "提前 \(minutes) 分钟").tag(minutes)
                    }
                }
                .disabled(working)
                if let fireAt = AcademicExamAlarmPolicy.fireDate(examStart: start, leadMinutes: lead, now: now) {
                    LabeledContent("响铃时间") {
                        Text(fireAt, format: .dateTime.month().day().hour().minute())
                    }
                }
                if working {
                    ProgressView("正在设置闹钟")
                } else {
                    Button("设置闹钟") { schedule(start: start, lead: lead) }
                        .disabled(store.permissionDenied)
                }
            } footer: {
                Text("系统闹钟可以在静音和专注模式下响铃。锁屏显示「考试闹钟」，时间按设备时区显示。")
            }
        } else {
            Section {
                Text("此考试的响铃时间已过。").foregroundStyle(.secondary)
            }
        }
    }

    private var isCurrent: Bool {
        environment.session.requestEpoch == epoch && environment.session.examAlarmOwner == target.owner &&
            environment.repository.hasCurrentLiveActivityAccount &&
            environment.repository.academicExams(term: target.term).contains { $0.id == exam.id && $0.start == exam.start }
    }

    private func schedule(start: Date, lead: Int) {
        errorMessage = nil
        working = true
        Task {
            defer { working = false }
            do {
                try await store.schedule(target: target, examStart: start, leadMinutes: lead) { isCurrent }
            } catch let error as AcademicExamAlarmStore.AlarmIssue {
                errorMessage = error.localizedDescription
            } catch {
                errorMessage = "暂时无法设置闹钟，请稍后重试。"
            }
        }
    }

    private func cancel() {
        errorMessage = nil
        do { try store.cancel(target) }
        catch { errorMessage = error.localizedDescription }
    }
}

import SwiftUI
import UserNotifications
import UIKit

struct CampusReminderCoordinator: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.scenePhase) private var scenePhase
    private struct Identity: Equatable { let account: String?; let epoch: UUID; let booting: Bool }
    private struct Plan: Equatable {
        let identity: Identity
        let preferences: CampusReminderPreferences
        let personal: [CampusPersonalReminder]
        let snapshot: CampusReminderSnapshot
        let minute: Int
    }
    private struct Load: Equatable {
        let identity: Identity
        let preferences: CampusReminderPreferences
        let foreground: Bool
        let day: String
        let network: Int
    }
    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let session = environment.session, store = environment.reminders
            let user = session.phase == .loggedIn ? session.user : nil
            let account = user.map { $0.sid.isEmpty ? $0.uid : $0.sid }
            let identity = Identity(account: account, epoch: session.requestEpoch, booting: session.phase == .booting)
            let plan = Plan(identity: identity, preferences: store.preferences, personal: store.personal,
                snapshot: environment.repository.reminderSnapshot(preferences: store.preferences, now: context.date),
                minute: Int(context.date.timeIntervalSince1970 / 60))
            let load = Load(identity: identity, preferences: store.preferences, foreground: scenePhase == .active,
                day: AcademicQueryPolicy.schoolDay(context.date), network: session.networkRevision)
            Color.clear
                .task(id: identity) {
                    guard !identity.booting else { return }
                    await store.activate(account: account)
                    if account != nil { await environment.repository.ensureLoadedForCurrentUser() }
                }
                .task(id: load) {
                    guard !identity.booting, account != nil, load.foreground, load.preferences.enabled else { return }
                    await environment.repository.prepareReminderData(preferences: load.preferences)
                }
                .task(id: plan) {
                    guard !identity.booting, let account, store.accountKey == CampusReminderStore.key(account),
                          environment.repository.hasCurrentReminderAccount else { return }
                    await store.apply(plan.snapshot)
                }
                .onChange(of: store.openRequest?.id, initial: true) { _, _ in
                    if let request = store.openRequest { environment.pendingActivityURL = request.url; store.clearOpenRequest() }
                }
                .onChange(of: store.preferences) { _, _ in CampusBackgroundRefresh.shared.schedule() }
                .onChange(of: store.authorization) { _, _ in CampusBackgroundRefresh.shared.schedule() }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .background { CampusBackgroundRefresh.shared.schedule() }
                    if phase == .active { Task { await store.refreshAuthorization() } }
                }
        }.allowsHitTesting(false).accessibilityHidden(true)
    }
}

struct CampusReminderView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.openURL) private var openURL
    @State private var adding = false
    @State private var showSettings = false
    private var store: CampusReminderStore { environment.reminders }
    var body: some View {
        @Bindable var store = store
        List {
            Section {
                LabeledContent("系统通知权限", value: permission)
                Toggle("启用校园提醒", isOn: Binding(get: { store.preferences.enabled }, set: { enabled in Task { await store.setEnabled(enabled) } }))
                if !store.authorized {
                    Button("打开系统通知设置", systemImage: "gear") {
                        if let url = URL(string: UIApplication.openNotificationSettingsURLString) { openURL(url) }
                    }
                }
                if let message = store.message { Text(message).font(.footnote).foregroundStyle(.orange) }
            } footer: { Text("已有课程、日程和截止时间提前安排为系统通知。后台自动读取新数据并更新提醒；首次读取作为成绩、邮件和办事变化的基准。") }
            DisclosureGroup("提醒分类与时间", isExpanded: $showSettings) {
                ForEach(CampusReminderKind.allCases) { kind in
                    Toggle(isOn: Binding(get: { store.preferences.kinds.contains(kind.rawValue) }, set: { store.preferences.set(kind, enabled: $0) })) {
                        Label(kind.title, systemImage: kind.symbol)
                    }
                }
                Stepper("课程提前 \(store.preferences.courseLead) 分钟", value: $store.preferences.courseLead, in: 0...120, step: 5)
                Stepper("考试提前 \(store.preferences.examLead) 分钟", value: $store.preferences.examLead, in: 0...1440, step: 15)
                Stepper("日程提前 \(store.preferences.plannerLead) 分钟", value: $store.preferences.plannerLead, in: 0...1440, step: 5)
                Stepper("作业提前 \(store.preferences.assignmentLead) 分钟", value: $store.preferences.assignmentLead, in: 0...2880, step: 30)
                Toggle("作业另加前一天提醒", isOn: $store.preferences.assignmentDayBefore)
                Toggle("包含已选择的系统日历与提醒", isOn: $store.preferences.systemEvents)
                threshold("校园卡低于", value: $store.preferences.cardThreshold, unit: "元")
                threshold("网费低于", value: $store.preferences.netThreshold, unit: "元")
                threshold("宿舍电量低于", value: $store.preferences.electricityThreshold, unit: "度")
                if store.preferences.kinds.contains(CampusReminderKind.daily.rawValue) {
                    Stepper("每日提醒：\(store.preferences.dailyHour):\(String(format: "%02d", store.preferences.dailyMinute))（北京时间）", value: $store.preferences.dailyHour, in: 0...23)
                    Picker("分钟", selection: $store.preferences.dailyMinute) { ForEach([0, 15, 30, 45], id: \.self) { Text(String(format: "%02d", $0)).tag($0) } }
                }
            }
            Section("后台自动刷新") {
                Toggle("允许后台自动加载", isOn: $store.preferences.background)
                Toggle("复用已登录学习平台会话", isOn: $store.preferences.backgroundLearning)
                Toggle("复用已登录学校邮箱会话", isOn: $store.preferences.backgroundMail)
                LabeledContent("系统后台刷新", value: backgroundStatus)
                if let trigger = store.lastTrigger { LabeledContent("最近触发方式", value: trigger) }
                if let date = store.lastBackgroundAttempt { LabeledContent("最近执行", value: date.formatted(date: .abbreviated, time: .shortened)) }
                if let date = store.lastBackgroundSuccess { LabeledContent("最近取得新数据", value: date.formatted(date: .abbreviated, time: .shortened)) }
                if let message = store.backgroundMessage { Text(message).font(.footnote).foregroundStyle(.secondary) }
                if store.syncing { ProgressView("正在同步来源与安排提醒…") }
                Button("立即同步并更新提醒", systemImage: "arrow.triangle.2.circlepath") {
                    Task {
                        _ = await CampusBackgroundRefresh.shared.run(manual: true)
                    }
                }.disabled(!store.preferences.enabled || store.syncing)
            } footer: {
                Text("iOS 决定后台运行时机，通常只有短暂执行时间，无法保证固定间隔或实时推送。保持登录并允许系统“后台 App 刷新”后，可复用已保存会话读取校园数据、学习任务与邮件；失效会话等待你正常认证。未取得新数据时保留已安排的提醒。")
            }
            Section("通知外观与静默") {
                Toggle("通知中显示具体内容", isOn: $store.preferences.detailsOnLockScreen)
                Toggle("提示音", isOn: $store.preferences.sound)
                Toggle("变化通知使用静默时段", isOn: $store.preferences.quiet)
                if store.preferences.quiet {
                    Stepper("静默开始：\(store.preferences.quietStart):00", value: $store.preferences.quietStart, in: 0...23)
                    Stepper("静默结束：\(store.preferences.quietEnd):00", value: $store.preferences.quietEnd, in: 0...23)
                    Text("成绩、邮件、进度、余额和每日提醒延后到静默结束；课程、考试、日程与截止提醒保留设定时间。时间均为北京时间。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Button("发送一条测试提醒", systemImage: "bell.badge") { Task { await store.test() } }
                    .disabled(!store.preferences.enabled || !store.authorized)
            }
            Section("即将提醒 · \(store.upcoming.count)") {
                if store.upcoming.isEmpty { Text("开启提醒并同步来源后，将在这里显示最近的提醒。") .foregroundStyle(.secondary) }
                ForEach(store.upcoming) { item in reminder(item) }
                Text("优先安排最近的 \(CampusReminderPolicy.maximumPending) 条，随同步与后台刷新补充后续事项。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if !store.personal.isEmpty {
                Section("自定义与稍后提醒") {
                    ForEach(store.personal) { item in
                        VStack(alignment: .leading, spacing: 5) {
                            Text(item.title)
                            Text(item.date.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary)
                        }
                        .swipeActions { Button("删除", role: .destructive) { store.removePersonal(item.id) } }
                    }
                }
            }
            Section("本机提醒记录") {
                if store.history.isEmpty { Text("暂无记录").foregroundStyle(.secondary) }
                ForEach(store.history.filter { !$0.cancelled && $0.fireAt <= Date() }.prefix(50)) { item in reminder(item) }
                if !store.history.isEmpty { Button("全部标为已读") { store.markAllRead() } }
            }
        }
        .navigationTitle("提醒与通知").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("新增提醒", systemImage: "plus") { adding = true } } }
        .sheet(isPresented: $adding) { AddCampusReminderSheet() }
        .task { await store.refreshAuthorization() }
        .refreshable {
            _ = await CampusBackgroundRefresh.shared.run(manual: true)
        }
    }
    private var permission: String {
        switch store.authorization {
        case .authorized: "已允许"
        case .provisional: "临时允许"
        case .ephemeral: "临时允许"
        case .denied: "系统已关闭"
        case .notDetermined: "尚未授权"
        @unknown default: "请检查系统设置"
        }
    }
    private var backgroundStatus: String {
        switch UIApplication.shared.backgroundRefreshStatus {
        case .available: "系统允许调度"
        case .denied: "系统已关闭，可在设置中开启"
        case .restricted: "受系统限制"
        @unknown default: "请检查系统设置"
        }
    }
    private func threshold(_ title: String, value: Binding<Double>, unit: String) -> some View {
        HStack { Text(title); Spacer(); TextField("阈值", value: value, format: .number).keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(maxWidth: 88); Text(unit).foregroundStyle(.secondary) }
    }
    private func reminder(_ item: CampusReminderCandidate) -> some View {
        Button { store.open(item) } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: item.kind.symbol).foregroundStyle(AppTheme.accent).frame(width: 24)
                VStack(alignment: .leading, spacing: 5) {
                    Text(item.title).foregroundStyle(.primary)
                    if !item.body.isEmpty { Text(item.body).font(.caption).foregroundStyle(.secondary).lineLimit(3) }
                    Text(item.fireAt.formatted(date: .abbreviated, time: .shortened)).font(.caption2).foregroundStyle(.secondary)
                }
            }.padding(.vertical, 4).multilineTextAlignment(.leading)
        }.buttonStyle(.plain)
    }
}

private struct AddCampusReminderSheet: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var note = ""
    @State private var date = Date().addingTimeInterval(3600)
    var body: some View {
        NavigationStack {
            Form {
                TextField("提醒标题", text: $title)
                TextField("备注（可选）", text: $note, axis: .vertical)
                DatePicker("提醒时间", selection: $date, in: Date()..., displayedComponents: [.date, .hourAndMinute])
            }.navigationTitle("新增提醒").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("保存") {
                            environment.reminders.add(.init(title: String(title.trimmingCharacters(in: .whitespacesAndNewlines).prefix(100)), body: String(note.prefix(500)), date: date))
                            Task { await environment.reminders.refreshPersonalSchedule() }
                            dismiss()
                        }.disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || date <= Date())
                    }
                }
        }
    }
}

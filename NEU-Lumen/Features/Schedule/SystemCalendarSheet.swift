import SwiftUI
import EventKit
import EventKitUI

struct SystemCalendarSheet: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss
    let sunday: Date
    @State private var exportEvents = true
    @State private var exportReminders = false
    @State private var alarmMinutes = 10
    private var repo: PortalRepository { environment.repository }
    private var bridge: SystemCalendarBridge { repo.systemCalendar }
    private var start: Date { Calendar.current.date(byAdding: .day, value: 1, to: sunday)! }
    private var end: Date { Calendar.current.date(byAdding: .day, value: 8, to: sunday)! }

    var body: some View {
        @Bindable var bridge = bridge
        NavigationStack {
            Form {
                Section {
                    Button(bridge.eventsAllowed ? "日历已连接" : "连接系统日历") { Task { await bridge.requestAccess(events: true) } }
                    Button(bridge.remindersAllowed ? "提醒事项已连接" : "连接系统提醒事项") { Task { await bridge.requestAccess(events: false) } }
                    Link("打开系统权限设置", destination: URL(string: UIApplication.openSettingsURLString)!)
                } header: { Text("系统授权") } footer: {
                    Text("连接时申请完全访问，用于读取所选日历和更新应用专用清单。只有点击同步才会写入。")
                }
                Section("在课表下显示系统日历") {
                    ForEach(bridge.eventCalendars, id: \.calendarIdentifier) { calendar in
                        Toggle(calendar.title, isOn: selection(calendar.calendarIdentifier, in: $bridge.eventCalendarIDs))
                    }
                    if bridge.eventCalendars.isEmpty { Text("连接日历后选择来源").foregroundStyle(.secondary) }
                }
                Section("在课表下显示提醒事项") {
                    ForEach(bridge.reminderCalendars, id: \.calendarIdentifier) { calendar in
                        Toggle(calendar.title, isOn: selection(calendar.calendarIdentifier, in: $bridge.reminderCalendarIDs))
                    }
                    Text("显示本周有截止日期的未完成事项；可在课表中勾选完成。无截止日期的事项请在系统提醒事项中查看。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section {
                    Text("\(PortalDate.isoDay(start)) 至 \(PortalDate.isoDay(end.addingTimeInterval(-1))) · \(repo.displayWeekOccurrences(starting: sunday).count) 项")
                        .font(.footnote)
                    Toggle("同步到系统日历", isOn: $exportEvents)
                    Toggle("同步到系统提醒事项", isOn: $exportReminders)
                    Picker("课前提醒", selection: $alarmMinutes) {
                        Text("不提醒").tag(-1)
                        Text("开始时").tag(0)
                        Text("提前 5 分钟").tag(5)
                        Text("提前 10 分钟").tag(10)
                        Text("提前 30 分钟").tag(30)
                    }
                    Button(bridge.busy ? "正在同步…" : "同步当前周课表") {
                        Task {
                            await bridge.sync(repo.displayWeekOccurrences(starting: sunday), start: start, end: end,
                                events: exportEvents, reminders: exportReminders, alarmMinutes: alarmMinutes)
                        }
                    }
                    .disabled(bridge.busy || bridge.accountKey.isEmpty || !repo.displayWeekIsLoaded(starting: sunday) || (!exportEvents && !exportReminders))
                    if bridge.accountKey.isEmpty {
                        Text("请先在「我的」刷新个人资料，确认账号后重新进入课表。").font(.caption).foregroundStyle(.orange)
                    }
                    if !repo.displayWeekIsLoaded(starting: sunday) {
                        Text("请先成功加载完整周课表后再同步。").font(.caption).foregroundStyle(.orange)
                    }
                    if let message = bridge.message { Text(message).font(.footnote).foregroundStyle(.secondary) }
                } header: { Text("写入当前周") } footer: {
                    Text("写入专用的「NEU-Lumen 课表」日历/清单；重复同步更新本周并清理已停课条目，保留提醒事项的完成状态。课表、调课或提醒时间变化后请重新同步。系统日程可在应用内编辑，修改不会回写学校教务。")
                }
            }
            .navigationTitle("日历与提醒事项")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
        }
    }

    private func selection(_ id: String, in values: Binding<Set<String>>) -> Binding<Bool> {
        Binding(get: { values.wrappedValue.contains(id) }, set: { selected in
            if selected { values.wrappedValue.insert(id) } else { values.wrappedValue.remove(id) }
        })
    }
}

struct SystemEventEditor: UIViewControllerRepresentable {
    let event: EKEvent
    let store: EKEventStore
    var onDismiss: () -> Void
    func makeCoordinator() -> Coordinator { Coordinator(onDismiss: onDismiss) }
    func makeUIViewController(context: Context) -> UINavigationController {
        let controller = EKEventViewController()
        controller.event = event
        controller.allowsEditing = event.calendar.allowsContentModifications
        controller.delegate = context.coordinator
        return UINavigationController(rootViewController: controller)
    }
    func updateUIViewController(_ uiViewController: UINavigationController, context: Context) {}
    final class Coordinator: NSObject, EKEventViewDelegate {
        let onDismiss: () -> Void
        init(onDismiss: @escaping () -> Void) { self.onDismiss = onDismiss }
        func eventViewController(_ controller: EKEventViewController, didCompleteWith action: EKEventViewAction) { onDismiss() }
    }
}

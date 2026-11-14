import SwiftUI
import EventKit

/// A daily reading of the same adjusted timetable and device planner used by ScheduleView.
struct NativeAgendaView: View {
    var active = true
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.scenePhase) private var scenePhase
    @State private var day = Date()
    @State private var adding = false
    @State private var managing = false
    @State private var selected: CourseOccurrence?
    @State private var systemItem: SystemAgendaItem?
    @State private var completing: SystemAgendaItem?

    private var repo: PortalRepository { environment.repository }
    private var sunday: Date { Semester.weekStart(forDay: day) }
    private var occurrences: [CourseOccurrence] {
        repo.displayWeekOccurrences(starting: sunday)
            .filter { Calendar.current.isDate($0.date, inSameDayAs: day) }
            .sorted { $0.slot.startMinutes < $1.slot.startMinutes }
    }
    private var systemItems: [SystemAgendaItem] {
        repo.systemCalendar.agenda.filter { Calendar.current.isDate($0.date, inSameDayAs: day) }
    }

    var body: some View {
        List {
            Section {
                DatePicker("查看日期", selection: $day, displayedComponents: .date)
                HStack {
                    Button { move(-1) } label: { Label("前一天", systemImage: "chevron.left") }
                    Spacer()
                    Button("今天") { day = Date() }
                    Spacer()
                    Button { move(1) } label: { Label("后一天", systemImage: "chevron.right") }
                }.buttonStyle(.borderless).frame(minHeight: 44)
                HStack {
                    Button("添加日程", systemImage: "plus") { adding = true }
                    Spacer()
                    Button("日历与提醒", systemImage: "calendar") { managing = true }
                }.buttonStyle(.borderless).frame(minHeight: 44)
            } footer: { Text("课程采用课表中的节假日与调课规则。本机日程与课表共用；系统日历需授权并选择来源。") }
            Section("课程与本机日程") {
                if case .loading = repo.displayWeekState(starting: sunday) {
                    ProgressView("正在读取课表…")
                }
                if case .failed(let message) = repo.displayWeekState(starting: sunday) {
                    Label(message, systemImage: "exclamationmark.triangle").font(.footnote).foregroundStyle(.orange)
                    Button("重新读取课表") { Task { await refresh(force: true) } }
                }
                if occurrences.isEmpty {
                    Text("当天暂无已读取的课程或本机日程").font(.subheadline).foregroundStyle(.secondary)
                }
                ForEach(occurrences) { item in
                    Button { selected = item } label: {
                        HStack(alignment: .top, spacing: 12) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(Semester.hm(item.slot.startMinutes)).font(.subheadline.monospacedDigit().weight(.semibold))
                                Text(Semester.hm(item.slot.endMinutes)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                            }.frame(width: 54, alignment: .leading)
                            VStack(alignment: .leading, spacing: 5) {
                                Text(item.slot.name).font(.body).foregroundStyle(.primary)
                                Text([item.slot.room, item.slot.teacher].filter { !$0.isEmpty }.joined(separator: " · "))
                                    .font(.caption).foregroundStyle(.secondary)
                                if item.slot.eventID != nil { Text("本机日程").font(.caption2).foregroundStyle(AppTheme.accent) }
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                        }.multilineTextAlignment(.leading).padding(.vertical, 6)
                    }.buttonStyle(.plain)
                }
            }
            Section("系统日历与提醒") {
                if systemItems.isEmpty {
                    Text("当天暂无所选来源的日程，可在“日历与提醒”中连接和选择。")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                ForEach(systemItems) { item in
                    HStack {
                        if item.isReminder {
                            Button { completing = item } label: { Image(systemName: "circle").font(.title2).frame(width: 44, height: 44) }
                                .buttonStyle(.borderless).accessibilityLabel("完成提醒：" + item.title)
                        } else { Image(systemName: "calendar").foregroundStyle(AppTheme.accent) }
                        Button { systemItem = item } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(item.title).foregroundStyle(.primary)
                                Text("\(item.allDay ? "全天" : item.date.formatted(date: .omitted, time: .shortened)) · \(item.source)")
                                    .font(.caption).foregroundStyle(.secondary)
                                if !item.location.isEmpty { Text(item.location).font(.caption).foregroundStyle(.secondary) }
                            }.frame(maxWidth: .infinity, alignment: .leading)
                        }.buttonStyle(.plain).disabled(item.isReminder)
                    }
                }
                if let message = repo.systemCalendar.message { Text(message).font(.footnote).foregroundStyle(.secondary) }
            }
            Section { NavigationLink("学期校历与周次", destination: AcademicCalendarView()) }
        }
        .refreshable { await refresh(force: true) }
        .task(id: "\(active)|\(PortalDate.isoDay(day))|\(environment.session.requestEpoch)") {
            if active { await refresh() }
        }
        .onChange(of: scenePhase) { _, value in if active, value == .active { Task { await refreshSystem() } } }
        .onReceive(NotificationCenter.default.publisher(for: .EKEventStoreChanged)) { _ in
            if active { Task { await refreshSystem() } }
        }
        .onChange(of: environment.session.requestEpoch) { _, _ in selected = nil; systemItem = nil; completing = nil; managing = false; adding = false }
        .onChange(of: environment.session.networkRevision) { _, _ in
            if active, case .failed = repo.displayWeekState(starting: sunday) { Task { await refresh(force: true) } }
        }
        .sheet(isPresented: $adding) { AddEventSheet(date: day) { repo.planner.add($0) } }
        .sheet(isPresented: $managing, onDismiss: { Task { await refreshSystem() } }) { SystemCalendarSheet(sunday: sunday) }
        .sheet(item: $selected) { item in CourseDetailSheet(occurrence: item) { repo.planner.remove(id: $0) } }
        .sheet(item: $systemItem, onDismiss: { Task { await refreshSystem() } }) { item in
            if let event = repo.systemCalendar.event(for: item) {
                SystemEventEditor(event: event, store: repo.systemCalendar.store) { systemItem = nil }
            } else { ContentUnavailableView("日程已更新", systemImage: "calendar", description: Text("关闭后刷新，再查看此日程。")) }
        }
        .confirmationDialog("将此提醒标记为完成？", isPresented: Binding(get: { completing != nil }, set: { if !$0 { completing = nil } }), titleVisibility: .visible) {
            Button("标记完成") {
                if let completing { repo.systemCalendar.completeReminder(id: completing.id) }
                completing = nil
            }
            Button("取消", role: .cancel) { completing = nil }
        } message: { Text(completing?.title ?? "") }
    }

    private func move(_ offset: Int) {
        if let value = Calendar.current.date(byAdding: .day, value: offset, to: day) { day = value }
    }
    private func refresh(force: Bool = false) async {
        await repo.loadDisplayWeek(starting: sunday, force: force)
        guard !Task.isCancelled else { return }
        await refreshSystem()
    }
    private func refreshSystem() async {
        let start = Calendar.current.startOfDay(for: day)
        guard let end = Calendar.current.date(byAdding: .day, value: 1, to: start) else { return }
        await repo.systemCalendar.refresh(start: start, end: end)
    }
}

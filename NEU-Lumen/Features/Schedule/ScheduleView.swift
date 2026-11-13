import SwiftUI
import EventKit

/// 课表：教学周网格（第1-2节…第9-10节），门户事件 + 本机日程上格。
struct ScheduleView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.scenePhase) private var scenePhase
    @State private var showHolidaySettings = false
    @State private var showSystemCalendar = false
    @State private var selectedSystemItem: SystemAgendaItem?
    @State private var weekOffset = 0
    @State private var showAddEvent = false
    @State private var selected: CourseOccurrence?

    private var repo: PortalRepository {
        environment.repository
    }

    private var currentWeekNumber: Int {
        Semester.weekNumberOf(Date())
    }

    private var displayWeek: Int {
        currentWeekNumber + weekOffset
    }

    private var weekStartSunday: Date {
        Semester.weekStart(of: displayWeek)
    }

    /// 周一在前的 7 天。
    private var weekDates: [Date] {
        (1...7).compactMap { Calendar.current.date(byAdding: .day, value: $0, to: weekStartSunday) }
    }

    private var occurrences: [CourseOccurrence] {
        repo.displayWeekOccurrences(starting: weekStartSunday)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    weekBar
                    if displayWeek < 1 || displayWeek > Semester.totalWeeks {
                        banner("假期中（第 \(displayWeek) 周）", icon: "sun.max.fill", color: .orange)
                    } else if Semester.isExamWeek(displayWeek) {
                        banner("考试周", icon: "pencil.line", color: .red)
                    }
                    holidaySummary
                    grid
                    systemAgenda
                    loadStateFooter
                }
                .padding(.horizontal, 12)
                .padding(.top, 8)
                .padding(.bottom, 32)
            }
            .tracksTabBarScrolling()
            .background(Color(.systemGroupedBackground))
            .navigationTitle("课表")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Button("学期、节假日与调课", systemImage: "sun.max") { showHolidaySettings = true }
                        Button("日历与提醒事项", systemImage: "calendar.badge.clock") { showSystemCalendar = true }
                    } label: { Image(systemName: "slider.horizontal.3") }
                    .accessibilityLabel("课表设置")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await repo.loadDisplayWeek(starting: weekStartSunday, force: true) }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showAddEvent = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .task(id: weekOffset) {
                await repo.loadDisplayWeek(starting: weekStartSunday)
                await refreshSystemAgenda()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await refreshSystemAgenda() } }
        }
        .onReceive(NotificationCenter.default.publisher(for: .EKEventStoreChanged)) { _ in
            Task { await refreshSystemAgenda() }
        }
        .sheet(isPresented: $showHolidaySettings, onDismiss: {
            Task { await repo.loadDisplayWeek(starting: weekStartSunday) }
        }) { ScheduleSettingsSheet() }
        .sheet(isPresented: $showSystemCalendar, onDismiss: {
            Task { await refreshSystemAgenda() }
        }) { SystemCalendarSheet(sunday: weekStartSunday) }
        .sheet(item: $selectedSystemItem, onDismiss: {
            Task { await refreshSystemAgenda() }
        }) { item in
            if let event = repo.systemCalendar.event(for: item) {
                SystemEventEditor(event: event, store: repo.systemCalendar.store) { selectedSystemItem = nil }
            } else { Text("此日程已更新，请刷新课表。").padding() }
        }
        .sheet(item: $selected) { occ in
            CourseDetailSheet(occurrence: occ) { id in
                repo.planner.remove(id: id)
            }
        }
        .sheet(isPresented: $showAddEvent) {
            AddEventSheet { event in
                repo.planner.add(event)
            }
        }
    }

    private func refreshSystemAgenda() async {
        await repo.systemCalendar.refresh(start: weekDates[0], end: Calendar.current.date(byAdding: .day, value: 7, to: weekDates[0])!)
    }

    private var holidaySummary: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(weekDates, id: \.self) { date in
                if let label = repo.holidays.label(on: date) {
                    Text("\(PortalDate.isoDay(date))  \(label)").font(.caption).foregroundStyle(.orange)
                }
            }
            if !repo.holidays.enabled {
                Text("自动节假日休息已关闭").font(.caption).foregroundStyle(.secondary)
            }
            if !repo.holidays.status.isEmpty {
                Text(repo.holidays.status).font(.caption2).foregroundStyle(.secondary)
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private var systemAgenda: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("系统日历与提醒").font(.headline)
                Spacer()
                Button("管理") { showSystemCalendar = true }.font(.caption)
            }
            if repo.systemCalendar.agenda.isEmpty {
                Text("本周暂无所选系统日程，可在管理中连接并选择来源。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            ForEach(repo.systemCalendar.agenda) { item in
                HStack(spacing: 10) {
                    if item.isReminder {
                        Button { repo.systemCalendar.completeReminder(id: item.id) } label: { Image(systemName: "circle").font(.title2) }
                            .accessibilityLabel("完成提醒：" + item.title)
                    } else { Image(systemName: "calendar").foregroundStyle(AppTheme.accent) }
                    Button {
                        if !item.isReminder { selectedSystemItem = item }
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.title).font(.subheadline).foregroundStyle(.primary)
                            Text("\(PortalDate.isoDay(item.date)) · \(item.allDay ? "全天" : item.date.formatted(date: .omitted, time: .shortened)) · \(item.source)")
                                .font(.caption).foregroundStyle(.secondary)
                            if !item.location.isEmpty { Text(item.location).font(.caption).foregroundStyle(.secondary) }
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }.buttonStyle(.plain)
                }.padding(12).background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
            }
        }.padding(.top, 8)
    }

    // MARK: - 周条

    private var weekBar: some View {
        HStack(spacing: 8) {
            Button {
                weekOffset -= 1
            } label: {
                Image(systemName: "chevron.left")
            }
            .disabled(weekOffset <= -currentWeekNumber + 1 && displayWeek <= 1)
            Spacer()
            VStack(spacing: 2) {
                Text("第 \(displayWeek) 周")
                    .font(.headline)
                if displayWeek == currentWeekNumber {
                    Text("本周")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(AppTheme.accent, in: Capsule())
                }
            }
            Spacer()
            Button {
                weekOffset += 1
            } label: {
                Image(systemName: "chevron.right")
            }
            if weekOffset != 0 {
                Button("今天") {
                    weekOffset = 0
                }
                .font(.footnote)
            }
        }
        .padding(.horizontal, 4)
    }

    private func banner(_ text: String, icon: String, color: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
            Text(text)
                .font(.footnote)
        }
        .foregroundStyle(color)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(color.opacity(0.1), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: - 网格

    private let periodHeight: CGFloat = 52

    private var grid: some View {
        let today = Calendar.current.startOfDay(for: Date())
        // 同次网格构建复用整周课程，避免每个日期列重复投影、解析和合并。
        let weekOccurrences = occurrences
        return HStack(alignment: .top, spacing: 4) {
            VStack(spacing: 0) {
                Color.clear.frame(height: 42)
                ForEach(0..<5, id: \.self) { pair in
                    periodLabel(pair).frame(height: periodHeight * 2)
                }
            }
            ForEach(weekDates, id: \.self) { date in
                let isToday = Calendar.current.isDate(date, inSameDayAs: today)
                VStack(spacing: 0) {
                    dayHeader(date, isToday: isToday)
                        .frame(height: 42)
                    TimetableDayColumn(
                        placements: TimetablePlacement.layout(weekOccurrences, on: date),
                        isToday: isToday,
                        periodHeight: periodHeight
                    ) { selected = $0 }
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(8)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    private static let weekdayNames = ["周一", "周二", "周三", "周四", "周五", "周六", "周日"]

    private func dayHeader(_ date: Date, isToday: Bool) -> some View {
        let cal = Calendar.current
        return VStack(spacing: 2) {
            Text(Self.weekdayNames[PlannerEvent.mondayBasedWeekday(date) - 1])
                .font(.caption2)
            Text("\(cal.component(.month, from: date))/\(cal.component(.day, from: date))")
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
        .background(isToday ? AppTheme.accent.opacity(0.14) : Color.clear, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .foregroundStyle(isToday ? AppTheme.accent : Color.primary)
    }

    private func periodLabel(_ pair: Int) -> some View {
        VStack(spacing: 2) {
            Text("\(pair * 2 + 1)-\(pair * 2 + 2)节")
                .font(.system(size: 9, weight: .semibold))
            Text(Semester.hm(Semester.periodStarts[pair * 2]))
                .font(.system(size: 8))
                .foregroundStyle(.secondary)
            Text(Semester.hm(Semester.periodEnds[pair * 2 + 1]))
                .font(.system(size: 8))
                .foregroundStyle(.secondary)
        }
        .frame(width: 44)
    }

    @ViewBuilder
    private var loadStateFooter: some View {
        switch repo.displayWeekState(starting: weekStartSunday) {
        case .loading:
            HStack(spacing: 8) {
                ProgressView()
                Text("正在同步课表…")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 14)
        case .failed(let message):
            ErrorStateView(message: message) {
                Task { await repo.loadDisplayWeek(starting: weekStartSunday, force: true) }
            }
        default:
            EmptyView()
        }
    }
}

/// 每天的连续时间列：合并后的课程跨行显示，避免在每个双节格子重复绘制。
struct TimetableDayColumn: View {
    let placements: [TimetablePlacement]
    let isToday: Bool
    let periodHeight: CGFloat
    let onTap: (CourseOccurrence) -> Void

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                VStack(spacing: 0) {
                    ForEach(0..<5, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: 8)
                            .fill(isToday ? AppTheme.accent.opacity(0.07) : Color.primary.opacity(0.025))
                            .padding(.bottom, 4)
                            .frame(height: periodHeight * 2)
                    }
                }
                ForEach(placements) { block in
                    let width = geometry.size.width / CGFloat(block.laneCount)
                    Button { onTap(block.occurrence) } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(block.occurrence.slot.name)
                                .font(.system(size: 10, weight: .bold))
                                .lineLimit(block.periodCount > 2 ? 6 : 3)
                            Text(block.occurrence.slot.room)
                                .font(.system(size: 9))
                                .lineLimit(2)
                                .opacity(0.85)
                            if block.periodCount > 2 {
                                Text("第 \(block.firstPeriod)–\(block.lastPeriod) 节")
                                    .font(.system(size: 8))
                                    .opacity(0.8)
                            }
                            Spacer(minLength: 0)
                        }
                        .foregroundStyle(.white)
                        .padding(5)
                        .frame(width: Swift.max(1, width - 2),
                               height: CGFloat(block.periodCount) * periodHeight - 4, alignment: .topLeading)
                        .background(AppTheme.courseColor(for: block.occurrence.slot.name), in: RoundedRectangle(cornerRadius: 8))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(accessibilityLabel(for: block))
                    .accessibilityHint("打开课程详情")
                    .offset(x: CGFloat(block.lane) * width, y: CGFloat(block.firstPeriod - 1) * periodHeight)
                }
            }
        }
        .frame(height: periodHeight * 10)
    }

    private func accessibilityLabel(for block: TimetablePlacement) -> String {
        let occurrence = block.occurrence
        let date = occurrence.date.formatted(.dateTime.locale(Locale(identifier: "zh_CN")).year().month().day().weekday(.wide))
        let time: String
        if let interval = LiveActivitySchedule.interval(for: occurrence) {
            let start = interval.start.formatted(date: .omitted, time: .shortened)
            let end = interval.end.formatted(date: Calendar.current.isDate(interval.start, inSameDayAs: interval.end) ? .omitted : .abbreviated, time: .shortened)
            time = "\(start) 至 \(end)"
        } else { time = "\(Semester.hm(occurrence.slot.startMinutes)) 至 \(Semester.hm(occurrence.slot.endMinutes))" }
        return "\(date)，\(occurrence.slot.name)，\(time)，第 \(block.firstPeriod) 至 \(block.lastPeriod) 节，\(occurrence.slot.room)"
    }
}

/// 事件详情。
struct CourseDetailSheet: View {
    let occurrence: CourseOccurrence
    let onDelete: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(AppEnvironment.self) private var environment
    @State private var deleting = false

    var body: some View {
        NavigationStack {
            List {
                LabeledContent("名称", value: occurrence.slot.name)
                LabeledContent("日期", value: PortalDate.isoDay(occurrence.date))
                LabeledContent("时间", value: "\(Semester.hm(occurrence.slot.startMinutes)) – \(Semester.hm(occurrence.slot.endMinutes))")
                LabeledContent("地点", value: occurrence.slot.room)
                LabeledContent("类型", value: occurrence.slot.kind == "custom" ? "本机日程" : "门户事件")
                if let eventID = occurrence.slot.eventID,
                   let event = environment.repository.planner.events.first(where: { $0.id == eventID }), !event.note.isEmpty {
                    LabeledContent("备注", value: event.note)
                }
            }
            .navigationTitle("详情")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if let eventID = occurrence.slot.eventID {
                    Button(role: .destructive) {
                        deleting = true
                    } label: {
                        Text("删除此日程")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .padding()
                    .confirmationDialog("删除此本机日程？", isPresented: $deleting, titleVisibility: .visible) {
                        Button("删除日程", role: .destructive) { onDelete(eventID); dismiss() }
                        Button("取消", role: .cancel) {}
                    } message: { Text(occurrence.slot.name) }
                }
            }
        }
        .presentationDetents([.medium])
    }
}

/// 添加本机日程。
struct AddEventSheet: View {
    var onAdd: (PlannerEvent) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var date = Date()
    @State private var startPeriod = 1
    @State private var endPeriod = 2
    @State private var room = ""
    @State private var note = ""

    init(date: Date = Date(), onAdd: @escaping (PlannerEvent) -> Void) {
        self.onAdd = onAdd
        _date = State(initialValue: date)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("日程") {
                    TextField("名称（如：高数期中考试）", text: $name)
                }
                Section("时间") {
                    DatePicker("日期", selection: $date, displayedComponents: .date)
                    Picker("开始节次", selection: $startPeriod) {
                        ForEach(1...10, id: \.self) { p in
                            Text("第\(p)节 \(Semester.hm(Semester.periodStarts[p - 1]))").tag(p)
                        }
                    }
                    Picker("结束节次", selection: $endPeriod) {
                        ForEach(startPeriod...10, id: \.self) { p in
                            Text("第\(p)节 \(Semester.hm(Semester.periodEnds[p - 1]))").tag(p)
                        }
                    }
                }
                Section("地点与备注") {
                    TextField("地点（可选）", text: $room)
                    TextField("备注（可选）", text: $note)
                }
            }
            .navigationTitle("添加日程")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        let event = PlannerEvent(
                            name: name.trimmingCharacters(in: .whitespaces),
                            dateIso: PortalDate.isoDay(date),
                            startMinutes: Semester.periodStarts[startPeriod - 1],
                            endMinutes: Semester.periodEnds[endPeriod - 1],
                            room: room,
                            note: note
                        )
                        onAdd(event)
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onChange(of: startPeriod) { _, newValue in
                if endPeriod < newValue {
                    endPeriod = newValue
                }
            }
        }
    }
}

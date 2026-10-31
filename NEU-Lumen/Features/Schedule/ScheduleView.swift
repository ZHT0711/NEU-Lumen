import SwiftUI

/// 课表：教学周网格（第1-2节…第9-10节），门户事件 + 本机日程上格。
struct ScheduleView: View {
    @Environment(AppEnvironment.self) private var environment
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
        let portal = repo.portalOccurrences(weekStarting: weekStartSunday) ?? []
        let custom = repo.planner.occurrences(inWeekStarting: weekStartSunday)
        return (portal + custom).mergeConsecutive()
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
                    grid
                    loadStateFooter
                }
                .padding(.horizontal, 12)
                .padding(.top, 8)
                .padding(.bottom, 32)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("课表")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await repo.loadWeek(containing: weekDates[0], force: true) }
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
                await repo.loadWeek(containing: weekDates[0])
            }
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

    private var grid: some View {
        let occs = occurrences
        let today = Calendar.current.startOfDay(for: Date())
        return Grid(horizontalSpacing: 4, verticalSpacing: 4) {
            GridRow {
                Color.clear.frame(width: 44, height: 30)
                ForEach(weekDates.indices, id: \.self) { i in
                    dayHeader(weekDates[i], isToday: Calendar.current.isDate(weekDates[i], inSameDayAs: today))
                }
            }
            ForEach(0..<5, id: \.self) { pair in
                GridRow {
                    periodLabel(pair)
                    ForEach(weekDates.indices, id: \.self) { i in
                        DayCell(
                            blocks: blocksIn(occs, date: weekDates[i], pair: pair),
                            isToday: Calendar.current.isDate(weekDates[i], inSameDayAs: today)
                        ) { selected = $0 }
                    }
                }
            }
        }
        .padding(8)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
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

    private func blocksIn(_ occs: [CourseOccurrence], date: Date, pair: Int) -> [CourseOccurrence] {
        let startPeriod = pair * 2 + 1
        let endPeriod = pair * 2 + 2
        let cal = Calendar.current
        return occs.filter { occ in
            guard cal.isDate(occ.date, inSameDayAs: date) else { return false }
            let sp = Semester.periodOf(startMinutes: occ.slot.startMinutes)
            let ep = Semester.endPeriod(of: occ.slot.endMinutes)
            return !(ep < startPeriod || sp > endPeriod)
        }
    }

    @ViewBuilder
    private var loadStateFooter: some View {
        switch repo.weekState {
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
                Task { await repo.loadWeek(containing: weekDates[0], force: true) }
            }
        default:
            EmptyView()
        }
    }
}

/// 课表格子：一格内可叠多个事件块。
struct DayCell: View {
    let blocks: [CourseOccurrence]
    let isToday: Bool
    let onTap: (CourseOccurrence) -> Void

    var body: some View {
        VStack(spacing: 3) {
            ForEach(blocks) { occ in
                Button {
                    onTap(occ)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(occ.slot.name)
                            .font(.system(size: 10, weight: .bold))
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                        Text(occ.slot.room)
                            .font(.system(size: 9))
                            .lineLimit(1)
                            .opacity(0.85)
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(5)
                    .frame(height: blocks.count > 1 ? 28 : 58, alignment: .top)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(AppTheme.courseColor(for: occ.slot.name))
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .frame(minHeight: 62)
        .frame(maxWidth: .infinity)
        .background(
            isToday ? AppTheme.accent.opacity(0.06) : Color.clear,
            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
        )
    }
}

/// 事件详情。
struct CourseDetailSheet: View {
    let occurrence: CourseOccurrence
    let onDelete: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                LabeledContent("名称", value: occurrence.slot.name)
                LabeledContent("日期", value: PortalDate.isoDay(occurrence.date))
                LabeledContent("时间", value: "\(Semester.hm(occurrence.slot.startMinutes)) – \(Semester.hm(occurrence.slot.endMinutes))")
                LabeledContent("地点", value: occurrence.slot.room)
                LabeledContent("类型", value: occurrence.slot.kind == "custom" ? "本机日程" : "门户事件")
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
                        onDelete(eventID)
                        dismiss()
                    } label: {
                        Text("删除此日程")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .padding()
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

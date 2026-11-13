import SwiftUI

struct AcademicCalendarView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var selectedTermCode: String?
    @State private var selectedDate = Date()
    @State private var showOriginalWeb = false
    private var repo: PortalRepository { environment.repository }
    private var term: AcademicTerm? {
        repo.academicTerms.first { $0.code == selectedTermCode }
            ?? repo.academicTerms.first { $0.current } ?? repo.academicTerms.first
    }
    private var day: String { AcademicQueryPolicy.schoolDay(selectedDate) }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                AcademicNotice(text: "数据范围：教务学期列表、结构化学期起止日期及假期区间、所选日期的教务周次。不包含学校校历图片中的全部开学安排、考试与活动。")
                AcademicQuerySection(repo: repo, key: .terms) {
                    if repo.academicTerms.isEmpty {
                        Text("教务暂未返回学期列表").foregroundStyle(.secondary)
                    } else {
                        Menu {
                            ForEach(repo.academicTerms) { item in
                                Button(item.name + (item.current ? "（当前）" : "")) { selectedTermCode = item.code }
                            }
                        } label: {
                            Label(term?.name ?? "选择学期", systemImage: "chevron.up.chevron.down").font(.headline)
                        }
                        if let term {
                            Text("学期代码：\(term.code)\(term.current ? " · 教务标记当前" : "")")
                                .font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                        }
                    }
                }
                if let term {
                    AcademicQuerySection(repo: repo, key: .calendar(term.code)) {
                        if case .calendar(let details)? = repo.academicPayload(for: .calendar(term.code)) {
                            calendarDetails(details)
                        }
                    }
                }
                GlassCard {
                    DatePicker("查询教务周次", selection: $selectedDate, displayedComponents: .date)
                        .datePickerStyle(.compact).padding(16)
                        .environment(\.timeZone, TimeZone(identifier: "Asia/Shanghai")!)
                }
                AcademicQuerySection(repo: repo, key: .week(day)) {
                    if case .week(let week)? = repo.academicPayload(for: .week(day)) {
                        Text("\(week.day) 的教务周次").font(.headline)
                        if let value = week.value {
                            Text(value).font(.title2.bold()).foregroundStyle(AppTheme.accent).textSelection(.enabled)
                                .accessibilityLabel("教务周次 \(value)")
                        } else {
                            Text("该日期暂未返回教学周次").foregroundStyle(.secondary)
                        }
                        Text("周次按日期查询，不限定上方所选学期；不使用个人校准推算。")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
                AcademicNotice(text: "学期起始日期不等同于所有学生的报到 / 上课日期。本页不会自动覆盖课表的个人学期校准。")
                Button("打开学校完整校历网页", systemImage: "globe") { showOriginalWeb = true }.buttonStyle(.bordered)
            }.padding(16).padding(.bottom, 24)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("校历与周次").navigationBarTitleDisplayMode(.inline)
        .task(id: environment.session.requestEpoch) { await repo.loadAcademicQuery(.terms) }
        .task(id: (term?.code ?? "") + environment.session.requestEpoch.uuidString) {
            if let code = term?.code { await repo.loadAcademicQuery(.calendar(code)) }
        }
        .task(id: day + environment.session.requestEpoch.uuidString) { await repo.loadAcademicQuery(.week(day)) }
        .refreshable {
            await repo.loadAcademicQuery(.terms, force: true)
            if let code = term?.code { await repo.loadAcademicQuery(.calendar(code), force: true) }
            await repo.loadAcademicQuery(.week(day), force: true)
        }
        .sheet(isPresented: $showOriginalWeb) {
            NavigationStack { PortalWebViewScreen(url: AcademicWebSyncSheet.entryURL) }
        }
    }

    @ViewBuilder private func calendarDetails(_ details: AcademicCalendarDetails) -> some View {
        if details.hasStructuredDates {
            Text("学期日期（教务原始值）").font(.headline)
            LabeledContent("学期起始日期", value: details.startDate ?? "未提供")
            LabeledContent("学期结束日期", value: details.endDate ?? "未提供")
            if !details.holidays.isEmpty {
                Text("校历假期区间").font(.subheadline.bold())
                ForEach(Array(details.holidays.enumerated()), id: \.offset) { _, holiday in
                    Text("\(holiday.startDate) — \(holiday.endDate)").font(.subheadline).textSelection(.enabled)
                }
                Text("接口仅核实了 startDate / endDate，不补造假期名称或调休安排。")
                    .font(.caption).foregroundStyle(.secondary)
            }
        } else {
            Text("暂不可原生读取该学期的完整校历").font(.headline)
            Text("结构化接口未提供日期；学校可能仅发布了校历图片。请使用原始网页确认，不把缺失数据当作尚未开学。")
                .font(.footnote).foregroundStyle(.secondary)
        }
    }
}

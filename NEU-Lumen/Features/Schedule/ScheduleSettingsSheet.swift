import SwiftUI

struct ScheduleSettingsSheet: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss
    @State private var date = Date()
    @State private var sourceDate = Date()
    @State private var semesterName = ""
    @State private var firstWeekDay = Date()
    @State private var teachingWeeks = 16
    @State private var examWeeks = 2
    @State private var semesterMessage: String?
    @State private var confirmResetSemester = false
    private var holidays: HolidayStore { environment.repository.holidays }

    private func loadSemesterDraft() {
        let value = SemesterSettings.shared.configuration
        semesterName = value.name
        firstWeekDay = value.anchor() ?? Date()
        teachingWeeks = value.teachingWeeks
        examWeeks = value.examWeeks
    }

    var body: some View {
        @Bindable var holidays = holidays
        NavigationStack {
            Form {
                Section {
                    LabeledContent("当前配置", value: SemesterSettings.shared.configuration.name)
                    TextField("学期名称", text: $semesterName)
                    DatePicker("第一教学周中的一天", selection: $firstWeekDay, displayedComponents: .date)
                    Stepper("教学 \(teachingWeeks) 周", value: $teachingWeeks, in: 1...40)
                    Stepper("考试 \(examWeeks) 周", value: $examWeeks, in: 0...8)
                    Button("保存学期校准") {
                        let value = SemesterConfiguration.calibrated(name: semesterName, firstWeekDay: firstWeekDay,
                            teachingWeeks: teachingWeeks, examWeeks: examWeeks)
                        semesterMessage = SemesterSettings.shared.save(value) ? "已保存，教学周标记已更新" : "请登录并填写有效的学期名称和日期"
                    }
                    .disabled(semesterName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    Button("恢复内置学期", role: .destructive) { confirmResetSemester = true }
                    if let semesterMessage { Text(semesterMessage).font(.footnote).foregroundStyle(.secondary) }
                } header: { Text("学期与教学周") } footer: {
                    Text("按学校校历选择第一教学周中的任意一天，自动对齐该周周日。仅调整教学周标记，不更改门户课程日期；按当前账号保存在本机，不猜测新学期开学日。")
                }
                Section {
                    Toggle("中国节假日自动休息", isOn: $holidays.enabled)
                    Text("休息日隐藏普通课程，保留考试和本机日程；首页下一节课与系统同步使用同样的安排。国家补班日仅标注，不自动猜测学校补课。")
                        .font(.footnote).foregroundStyle(.secondary)
                    Text(holidays.status).font(.caption).foregroundStyle(.secondary)
                    Button("更新所选年份节假日") {
                        Task { await holidays.refresh(year: Calendar.current.component(.year, from: date), force: true) }
                    }
                    Link("国家放假安排（2026）", destination: URL(string: "https://www.gov.cn/zhengce/content/202511/content_7047090.htm")!)
                    Link("年度数据来源：holiday-cn", destination: URL(string: "https://github.com/NateScarlet/holiday-cn")!)
                } header: { Text("智能休息") }
                Section {
                    DatePicker("调整日期", selection: $date, displayedComponents: .date)
                    Text(holidays.label(on: date) ?? "按原课表上课").font(.footnote)
                    Button("设为停课休息") {
                        holidays.setReplacement(nil, on: date)
                        holidays.setOverride(.rest, on: date)
                    }
                    Button("保留当天原课表") {
                        holidays.setReplacement(nil, on: date)
                        holidays.setOverride(.normal, on: date)
                    }
                    DatePicker("补课参照日期", selection: $sourceDate, displayedComponents: .date)
                    Button("当天改上参照日期的课程") { holidays.setReplacement(sourceDate, on: date) }
                        .disabled(Calendar.current.isDate(date, inSameDayAs: sourceDate))
                    Button("恢复当天自动安排") {
                        holidays.setReplacement(nil, on: date)
                        holidays.setOverride(nil, on: date)
                    }
                } header: { Text("学校调课覆盖") } footer: {
                    Text("按学校通知设置具体日期。补课复制参照日的门户课程，不移动考试或本机日程；原日期若停课，请另行设为休息。")
                }
                Section("已设置的日期") {
                    if holidays.overrides.isEmpty { Text("暂无覆盖").foregroundStyle(.secondary) }
                    ForEach(holidays.overrides.keys.sorted(), id: \.self) { day in
                        HStack {
                            Text(day)
                            Spacer()
                            Text(holidays.replacementDates[day].map { "补 \($0) 的课" } ?? (holidays.overrides[day]?.title ?? "自动安排"))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("学期、节假日与调课")
            .onAppear {
                let user = environment.session.user
                SemesterSettings.shared.activate(account: user?.sid.isEmpty == false ? user!.sid : user?.uid ?? "")
                loadSemesterDraft()
            }
            .confirmationDialog("恢复为内置的 2026-2027 第一学期？", isPresented: $confirmResetSemester, titleVisibility: .visible) {
                Button("恢复内置学期", role: .destructive) {
                    SemesterSettings.shared.reset()
                    loadSemesterDraft()
                    semesterMessage = "已恢复内置学期，可重新校准"
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
        }
    }
}

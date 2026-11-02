import SwiftUI

struct ScheduleSettingsSheet: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss
    @State private var date = Date()
    @State private var sourceDate = Date()
    private var holidays: HolidayStore { environment.repository.holidays }

    var body: some View {
        @Bindable var holidays = holidays
        NavigationStack {
            Form {
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
            .navigationTitle("节假日与调课")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
        }
    }
}

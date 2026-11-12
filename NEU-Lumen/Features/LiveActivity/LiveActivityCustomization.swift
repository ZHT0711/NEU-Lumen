import SwiftUI

/// Fixed palette and symbols; no arbitrary URLs, images or executable templates.
enum LiveActivityAppearance {
    static let colors = ["cyan", "blue", "green", "orange", "pink", "purple"]
    static func name(_ token: String) -> String {
        ["cyan": "青色", "blue": "蓝色", "green": "绿色", "orange": "橙色", "pink": "粉色", "purple": "紫色"][token] ?? "青色"
    }
    static func color(_ token: String?) -> Color {
        switch token {
        case "blue": return .blue
        case "green": return .green
        case "orange": return .orange
        case "pink": return .pink
        case "purple": return .purple
        default: return .cyan
        }
    }
    static func iconName(_ symbol: String) -> String {
        ["book.closed.fill": "课程", "creditcard.fill": "钱包", "wifi": "网络", "bolt.fill": "电量",
         "checklist": "待办", "calendar": "日程", "sparkles": "星光", "chart.bar.fill": "统计",
         "bell.fill": "提醒", "heart.fill": "爱心", "flag.fill": "目标"][symbol] ?? "星光"
    }
}

struct LiveActivityAppearanceFields: View {
    @Bindable var store: DynamicIslandStore
    var body: some View {
        Section {
            HStack(spacing: 16) {
                ForEach(LiveActivityAppearance.colors, id: \.self) { token in
                    Button { store.accent = token } label: {
                        Circle().fill(LiveActivityAppearance.color(token))
                            .frame(width: 32, height: 32)
                            .overlay {
                                if store.accent == token {
                                    Image(systemName: "checkmark").font(.caption.bold()).foregroundStyle(.white)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(LiveActivityAppearance.name(token))
                    .accessibilityValue(store.accent == token ? "已选择" : "")
                }
            }
            .frame(maxWidth: .infinity, alignment: .center)
            Toggle("有进度数据时显示进度条", isOn: $store.showProgress)
        } header: {
            Text("外观")
        } footer: {
            Text("主题作用于图标、边框和锁屏点缀。背景与紧凑布局仍由 iOS 管理；课程、作业和今日总览有可用进度时才显示进度条。")
        }
    }
}

struct LiveActivityCustomizationFields: View {
    @Bindable var store: DynamicIslandStore
    @State private var insertionTarget = "副标题"

    var body: some View {
        Section {
            TextField("标题", text: $store.customTitle)
                .onChange(of: store.customTitle) { _, value in
                    if value.count > 80 { store.customTitle = String(value.prefix(80)) }
                }
            TextField("副标题", text: $store.customSubtitle, axis: .vertical)
                .lineLimit(2...4)
                .onChange(of: store.customSubtitle) { _, value in
                    if value.count > 160 { store.customSubtitle = String(value.prefix(160)) }
                }
            TextField("灵动岛短值（可选）", text: $store.customValue)
                .onChange(of: store.customValue) { _, value in
                    if value.count > 32 { store.customValue = String(value.prefix(32)) }
                }
            Picker("图标", selection: $store.customIcon) {
                ForEach(DynamicIslandStore.allowedCustomIcons, id: \.self) { symbol in
                    Label(LiveActivityAppearance.iconName(symbol), systemImage: symbol).tag(symbol)
                }
            }
            Toggle("目标倒计时", isOn: $store.customDeadlineEnabled)
            if store.customDeadlineEnabled {
                DatePicker("目标时间", selection: $store.customDeadline, displayedComponents: [.date, .hourAndMinute])
                if store.customDeadline <= Date() {
                    Text("目标已到期，活动将提示内容待更新。").font(.footnote).foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("自定义内容")
        } footer: {
            Text("标题最多 80 字，副标题 160 字，短值 32 字。紧凑灵动岛空间有限，建议短值保持在 8 字以内；倒计时与文字显示时长由系统管理。")
        }
        Section {
            Picker("插入位置", selection: $insertionTarget) {
                ForEach(["标题", "副标题", "短值"], id: \.self) { Text($0).tag($0) }
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 85))], spacing: 10) {
                ForEach(DynamicIslandStore.templateVariables) { variable in
                    Button { insert(variable.token) } label: {
                        Text(variable.token).font(.caption.monospaced())
                            .frame(maxWidth: .infinity).padding(.vertical, 8)
                            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("插入" + variable.description)
                }
            }
            DisclosureGroup("变量说明") {
                ForEach(DynamicIslandStore.templateVariables) { variable in
                    LabeledContent(variable.token) {
                        Text(variable.description).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        } header: {
            Text("数据变量")
        } footer: {
            Text("变量只读取当前账号已加载的数据，不会暗中登录学习平台。缺失值显示“未读取”，不是零。余额与学业信息可能出现在锁屏上，请按需选择。")
        }
        Section("快速模板") {
            Button("课程与地点") {
                store.customTitle = "{course}"
                store.customSubtitle = "{room} · {start}"
                store.customValue = "{week}"
                store.customIcon = "book.closed.fill"
            }
            Button("校园钱包") {
                store.customTitle = "校园账户"
                store.customSubtitle = "校园卡 {card} · 网费 {net}"
                store.customValue = "{card}"
                store.customIcon = "creditcard.fill"
            }
            Button("学习与待办") {
                store.customTitle = "学习提醒"
                store.customSubtitle = "待办 {pending} · GPA {gpa}"
                store.customValue = "{pending}"
                store.customIcon = "checklist"
            }
        }
    }

    private func insert(_ token: String) {
        switch insertionTarget {
        case "标题": store.customTitle = String((store.customTitle + token).prefix(80))
        case "短值": store.customValue = String((store.customValue + token).prefix(32))
        default: store.customSubtitle = String((store.customSubtitle + token).prefix(160))
        }
    }
}

/// Uses the same current-account payload as ActivityKit, never demo balances.
/// This is an in-app configuration preview, not a screenshot of system UI.
struct LiveActivityContentPreview: View {
    let state: NEULumenActivityAttributes.ContentState?

    var body: some View {
        if let state {
            VStack(spacing: 16) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: state.symbol)
                        .font(.title2).foregroundStyle(LiveActivityAppearance.color(state.accent))
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(state.title).font(.headline).lineLimit(2)
                        Text(state.subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(3)
                        if let secondary = state.secondaryValue, !secondary.isEmpty {
                            Text(secondary).font(.caption).foregroundStyle(LiveActivityAppearance.color(state.accent)).lineLimit(2)
                        }
                    }
                    Spacer(minLength: 0)
                    Text(state.value).font(.subheadline.monospacedDigit().bold())
                        .foregroundStyle(LiveActivityAppearance.color(state.accent))
                        .lineLimit(2).minimumScaleFactor(0.7)
                }
                if let target = countdownTarget(state), target > Date() {
                    HStack {
                        Text(state.countdownTitle ?? "倒计时").font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Text(timerInterval: Date()...target, countsDown: true).font(.caption.monospacedDigit())
                            .multilineTextAlignment(.trailing).frame(width: 100)
                    }
                }
                if let progress = state.progress, progress.isFinite {
                    ProgressView(value: min(max(progress, 0), 1)).tint(LiveActivityAppearance.color(state.accent))
                }
                HStack {
                    Image(systemName: state.symbol).foregroundStyle(LiveActivityAppearance.color(state.accent))
                    Spacer(minLength: 40)
                    if state.staleAfter.map({ $0 <= Date() }) == true {
                        Image(systemName: "arrow.clockwise").foregroundStyle(.white).accessibilityLabel("内容待更新")
                    } else if let target = state.countdownDate, target > Date() {
                        Text(timerInterval: Date()...target, countsDown: true)
                            .foregroundStyle(.white).font(.caption.monospacedDigit())
                            .multilineTextAlignment(.trailing).frame(width: 80)
                    } else {
                        Text(state.countdownDate != nil ? "待更新" : state.value.isEmpty ? String(state.title.prefix(2)) : state.value)
                            .foregroundStyle(.white).font(.caption.monospacedDigit())
                            .lineLimit(1).minimumScaleFactor(0.7).frame(maxWidth: 80)
                    }
                }
                .padding(.horizontal, 18).frame(width: 220, height: 42)
                .background(.black, in: Capsule())
                .accessibilityLabel("紧凑内容示意：" + state.title + "，" + state.value)
            }
            .padding(.vertical, 6)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Label("等待所选数据", systemImage: "arrow.triangle.2.circlepath")
                Text("同步所选来源后显示实际内容，不使用虚构余额或成绩填充预览。")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func countdownTarget(_ state: NEULumenActivityAttributes.ContentState) -> Date? { state.countdownDate }
}

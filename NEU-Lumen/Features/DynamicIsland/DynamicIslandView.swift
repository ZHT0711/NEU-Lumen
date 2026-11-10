import SwiftUI

/// 应用内灵动岛：收起时展示摘要，点按后展开为可操作的信息卡。
struct DynamicIslandView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var store = DynamicIslandStore()
    @State private var expanded = false
    @State private var showSettings = false

    private var repo: PortalRepository { environment.repository }

    var body: some View {
        if store.enabled {
            Group {
                if expanded {
                    expandedIsland
                } else {
                    collapsedIsland
                }
            }
            .animation(.spring(response: 0.34, dampingFraction: 0.82), value: expanded)
            .sheet(isPresented: $showSettings) {
                DynamicIslandSettingsView(store: store)
                    .presentationDetents([.medium, .large])
            }
            .task {
                DynamicIslandActivityManager.shared.startOrUpdate(store: store, repository: repo)
            }
            .onChange(of: store.kind) { _, _ in
                DynamicIslandActivityManager.shared.startOrUpdate(store: store, repository: repo)
            }
            .onChange(of: store.enabled) { _, enabled in
                if enabled {
                    DynamicIslandActivityManager.shared.startOrUpdate(store: store, repository: repo)
                } else {
                    DynamicIslandActivityManager.shared.end()
                }
            }
        }
    }

    private var collapsedIsland: some View {
        Button { expanded = true } label: {
            HStack(spacing: 8) {
                Image(systemName: currentIcon)
                    .font(.caption.weight(.bold))
                Text(currentTitle)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                if let value = currentValue {
                    Text(value)
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.white.opacity(0.72))
                        .lineLimit(1)
                }
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .frame(height: 36)
            .background(.black, in: Capsule())
            .shadow(color: .black.opacity(0.2), radius: 8, y: 4)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("灵动岛：\(currentTitle)")
    }

    private var expandedIsland: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("灵动岛", systemImage: "circle.dotted.and.circle")
                    .font(.headline)
                Spacer()
                Button { showSettings = true } label: {
                    Image(systemName: "slider.horizontal.3")
                }
                .accessibilityLabel("配置灵动岛")
                Button { expanded = false } label: {
                    Image(systemName: "chevron.up")
                }
                .accessibilityLabel("收起灵动岛")
            }
            HStack(spacing: 12) {
                Image(systemName: currentIcon)
                    .font(.title2)
                    .foregroundStyle(AppTheme.accent)
                    .frame(width: 42, height: 42)
                    .background(AppTheme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 13))
                VStack(alignment: .leading, spacing: 4) {
                    Text(currentTitle).font(.headline)
                    Text(currentSubtitle).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                }
                Spacer(minLength: 0)
            }
        }
        .padding(16)
        .frame(maxWidth: 360)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(AppTheme.accent.opacity(0.16)))
        .shadow(color: .black.opacity(0.16), radius: 18, y: 8)
    }

    private var currentIcon: String {
        if store.kind == .nextCourse, repo.nextCourse() == nil { return "calendar.badge.exclamationmark" }
        return store.kind.icon
    }

    private var currentTitle: String {
        switch store.kind {
        case .nextCourse: return repo.nextCourse()?.slot.name ?? "暂无课程"
        case .cardBalance: return "校园卡余额"
        case .custom: return store.customTitle.isEmpty ? "自定义内容" : store.customTitle
        }
    }

    private var currentValue: String? {
        switch store.kind {
        case .nextCourse: return repo.nextCourse().map { Semester.hm($0.slot.startMinutes) }
        case .cardBalance: return repo.cardSummaryText.map { "¥\($0)" }
        case .custom: return nil
        }
    }

    private var currentSubtitle: String {
        switch store.kind {
        case .nextCourse:
            guard let next = repo.nextCourse() else { return "去配置页选择自定义内容" }
            let room = next.slot.room.isEmpty ? "地点待定" : next.slot.room
            return "\(next.isOngoing ? "正在上课" : "\(Semester.hm(next.slot.startMinutes)) 开始") · \(room)"
        case .cardBalance:
            return repo.cardSummaryText.map { "当前可用余额 ¥\($0)" } ?? "打开校园卡页面同步余额"
        case .custom: return store.customSubtitle
        }
    }
}

struct DynamicIslandSettingsView: View {
    @Bindable var store: DynamicIslandStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("显示应用内灵动岛", isOn: $store.enabled)
                    Picker("展示内容", selection: $store.kind) {
                        ForEach(DynamicIslandStore.ContentKind.allCases) { kind in
                            Label(kind.title, systemImage: kind.icon).tag(kind)
                        }
                    }
                } footer: {
                    Text("灵动岛会悬浮在各个页面顶部，点击即可展开详情。内容来自本地已加载的课表和校园卡数据。")
                }
                if store.kind == .custom {
                    Section("自定义内容") {
                        TextField("标题", text: $store.customTitle)
                        TextField("副标题", text: $store.customSubtitle, axis: .vertical)
                            .lineLimit(2...4)
                    }
                }
                Section {
                    Button("恢复默认配置", role: .destructive) { store.reset() }
                }
            }
            .navigationTitle("灵动岛设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } }
            }
        }
    }
}

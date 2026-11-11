import SwiftUI

/// The root owns updates across tabs and sheets. ActivityKit owns presentation.
struct LiveActivityCoordinator: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let session = environment.session
            let store = environment.dynamicIslandStore
            let user = session.user
            let identity = user?.sid.isEmpty == false ? user?.sid : user?.uid
            let account = session.phase == .loggedIn && identity?.isEmpty == false ? identity : nil
            let request = DynamicIslandActivityManager.Request(
                enabled: store.enabled, accountID: account, campus: environment.repository.campus.title,
                state: account == nil ? nil : environment.repository.liveActivityState(store: store),
                isForeground: scenePhase == .active, refreshDate: context.date,
                contentReady: environment.repository.liveActivityDataIsReady(for: store.kind),
                contentKind: store.kind.rawValue)
            Color.clear
                .onChange(of: request, initial: true) { _, value in
                    guard session.phase != .booting else { return }
                    environment.liveActivityManager.synchronize(value)
                }
                .onChange(of: session.phase) { _, phase in
                    if phase != .booting { environment.liveActivityManager.synchronize(request) }
                }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

struct LiveActivitySettingsView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.openURL) private var openURL

    var body: some View {
        @Bindable var store = environment.dynamicIslandStore
        let manager = environment.liveActivityManager
        Form {
            Section {
                Toggle("启用实时活动", isOn: $store.enabled)
                Picker("展示内容", selection: $store.kind) {
                    ForEach(DynamicIslandStore.ContentKind.allCases) { kind in
                        Label(kind.title, systemImage: kind.icon).tag(kind)
                    }
                }
            } footer: {
                Text("由系统显示在锁屏和支持机型的灵动岛上。课表、余额随应用内数据更新，进入后台后保留最近内容，课程倒计时由系统继续显示。")
            }
            if store.kind == .custom {
                Section("自定义内容") {
                    TextField("标题", text: $store.customTitle)
                        .onChange(of: store.customTitle) { _, value in
                            store.customTitle = String(value.prefix(80))
                        }
                    TextField("副标题", text: $store.customSubtitle, axis: .vertical)
                        .lineLimit(2...4)
                        .onChange(of: store.customSubtitle) { _, value in
                            store.customSubtitle = String(value.prefix(160))
                        }
                }
            }
            Section {
                LabeledContent("状态", value: manager.status)
                if let error = manager.lastError {
                    Text(error).font(.footnote).foregroundStyle(.secondary)
                }
                Button(manager.isRunning ? "更新实时活动" : "开启实时活动") { manager.restart() }
                    .disabled(!store.enabled)
                Button("打开系统设置") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                }
            } footer: {
                Text("系统或你结束实时活动后，可在这里重新开启。课程结束或余额同步超过 30 分钟会显示更新提示，打开应用可更新数据。")
            }
            Section {
                Button("恢复默认配置", role: .destructive) { store.reset() }
            }
        }
        .navigationTitle("实时活动")
        .navigationBarTitleDisplayMode(.inline)
    }
}

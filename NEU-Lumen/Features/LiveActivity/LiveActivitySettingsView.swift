import SwiftUI

/// The root owns updates across tabs and sheets. ActivityKit owns presentation.
@MainActor
private func activityRequest(environment: AppEnvironment, foreground: Bool, now: Date) -> DynamicIslandActivityManager.Request {
    let session = environment.session
    let store = environment.dynamicIslandStore
    let user = session.user
    let identity = user?.sid.isEmpty == false ? user?.sid : user?.uid
    let account = session.phase == .loggedIn && identity?.isEmpty == false ? identity : nil
    let state = account != nil && store.enabled ? environment.repository.liveActivityState(store: store, now: now) : nil
    return .init(enabled: store.enabled, accountID: account, campus: environment.repository.campus.title,
        state: state, isForeground: foreground, refreshDate: now,
        contentReady: !store.enabled || state != nil || environment.repository.liveActivityDataIsReady(for: store.kind, now: now),
        contentKind: store.kind.rawValue)
}

private struct ActivityLoadKey: Hashable {
    let epoch: UUID
    let account: String?
    let source: String
    let enabled: Bool
    let foreground: Bool
    let day: String
}

struct LiveActivityCoordinator: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let session = environment.session
            let store = environment.dynamicIslandStore
            let request = activityRequest(environment: environment, foreground: scenePhase == .active, now: context.date)
            let loadKey = ActivityLoadKey(epoch: session.requestEpoch, account: request.accountID, source: store.kind.rawValue,
                enabled: store.enabled, foreground: scenePhase == .active, day: PortalDate.isoDay(context.date))
            Color.clear
                .task(id: loadKey) {
                    guard loadKey.foreground, loadKey.enabled, loadKey.account != nil else { return }
                    await environment.repository.prepareLiveActivityData(for: store)
                }
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
    @Environment(\.scenePhase) private var scenePhase
    @State private var isSynchronizing = false

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
                Text("由系统显示在锁屏和支持机型的灵动岛上。所选数据来自当前账号的应用内缓存；进入后台后保留最近内容，不会自行登录或轮询校园接口。")
            }
            Section {
                TimelineView(.periodic(from: .now, by: 60)) { context in
                    LiveActivityContentPreview(state: environment.repository.liveActivityState(store: store, now: context.date))
                }
            } header: {
                Text("内容预览")
            } footer: {
                Text("这是应用内内容与紧凑布局示意，实际锁屏和灵动岛由 iOS 渲染。余额、日程与学业信息可能出现在锁屏上。")
            }
            LiveActivityAppearanceFields(store: store)
            if store.kind == .custom {
                LiveActivityCustomizationFields(store: store)
            }
            Section {
                LabeledContent("状态", value: manager.status)
                Text(environment.repository.liveActivityDataStatus(for: store.kind))
                    .font(.footnote).foregroundStyle(.secondary)
                if let error = manager.lastError {
                    Text(error).font(.footnote).foregroundStyle(.secondary)
                }
                Button(isSynchronizing ? "正在同步…" : manager.isRunning ? "同步来源并更新活动" : "同步来源并开启活动") {
                    Task { @MainActor in
                        isSynchronizing = true
                        defer { isSynchronizing = false }
                        await environment.repository.prepareLiveActivityData(for: store, force: true)
                        manager.synchronize(activityRequest(environment: environment, foreground: scenePhase == .active, now: Date()))
                        manager.restart()
                    }
                }
                .disabled(!store.enabled || isSynchronizing || scenePhase != .active)
                Menu("打开数据来源") {
                    Button("课表与个人日程") { openSource("course") }
                    Button("校园卡、网费与电费") { openSource("card") }
                    Button("学习平台作业") { openSource("learning") }
                    Button("学业成绩") { openSource("learning?section=grades") }
                }
                Button("打开系统设置") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                }
            } footer: {
                Text("系统或你结束活动后可在这里重新开启。课程边界、目标到期或缓存变旧时，活动可能提示打开应用更新。作业和自定义变量不暗中建立平台登录，请先在数据来源页同步；系统决定展示时长。")
            }
            Section {
                Button("恢复默认配置", role: .destructive) { store.reset() }
            }
        }
        .navigationTitle("实时活动")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func openSource(_ path: String) {
        if let url = URL(string: "neulumen://activity/\(path)") { openURL(url) }
    }
}

import SwiftUI
import Observation

struct NativePaymentView: View {
    var active = true
    @Environment(AppEnvironment.self) private var environment
    @State private var web: NativeServiceWebLink?
    @State private var room = ""
    private var repo: PortalRepository { environment.repository }
    var body: some View {
        Form {
            Section("缴费服务") {
                Button("缴费项目", systemImage: "square.grid.2x2") { openPayment(path: "/openApplication") }
                Button("我的订单", systemImage: "list.clipboard") { openPayment(path: "/orders.html") }
                Button("缴费大厅首页", systemImage: "house") { openPayment() }
            }
            Section("校园账户") {
                LabeledContent("校园卡余额", value: money(repo.cardBalance?.balance))
                if let subsidy = repo.cardBalance?.subsidy { LabeledContent("补助余额", value: money(subsidy)) }
                LabeledContent("网费余额", value: money(repo.netInfo?.balance))
                if let date = repo.cardUpdatedAt { Text("校园卡更新于 " + date.formatted(date: .omitted, time: .shortened)).font(.caption).foregroundStyle(.secondary) }
                if let date = repo.netUpdatedAt { Text("网费更新于 " + date.formatted(date: .omitted, time: .shortened)).font(.caption).foregroundStyle(.secondary) }
                Text("学校页面核对缴费项目、金额并完成支付。账户余额不等同于待缴费用。")
                    .font(.caption).foregroundStyle(.secondary)
                ServiceLoadNotice(state: repo.cardState)
                ServiceLoadNotice(state: repo.netState)
            }
            Section("校园网络") {
                if let net = repo.netInfo {
                    ForEach(net.usageFacts, id: \.0) { label, value in LabeledContent(label, value: value) }
                } else { Text("尚未读取网络用量").foregroundStyle(.secondary) }
                Button("充值网费", systemImage: "wifi") { openPayment() }
            }
            Section("宿舍电费") {
                if let electric = repo.electricInfo, !electric.unbound {
                    LabeledContent("房间", value: electric.roomLabel ?? electric.roomNo ?? "已绑定")
                    LabeledContent("剩余电量", value: electric.remainKwh.map { $0.formatted(.number.precision(.fractionLength(0...2))) + " kWh" } ?? "未提供")
                    if let time = electric.lastReadAt { LabeledContent("抄表时间", value: time) }
                }
                TextField("房间码", text: $room).textInputAutocapitalization(.never).autocorrectionDisabled()
                Button("绑定并查询", systemImage: "bolt") {
                    repo.electricRoomCode = room
                    Task { await repo.loadElectric(force: true) }
                }.disabled(room.trimmingCharacters(in: .whitespaces).isEmpty)
                ServiceLoadNotice(state: repo.electricState)
                Button("缴纳电费", systemImage: "arrow.up.right") { openPayment() }
            }
            Section("校园卡本月流水") {
                if repo.cardBills.isEmpty { Text("尚无已读取的本月流水").foregroundStyle(.secondary) }
                ForEach(repo.cardBills.prefix(12)) { bill in
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(bill.subject).font(.subheadline)
                            Text(bill.timeText).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(money(bill.amount)).monospacedDigit().foregroundStyle(bill.isRecharge ? Color.green : Color.primary)
                    }
                }
                Button("刷新本月流水", systemImage: "arrow.clockwise") { Task { await loadBills() } }
                ServiceLoadNotice(state: repo.billsState)
            }
        }
        .task(id: String(active) + environment.session.requestEpoch.uuidString) {
            guard active else { return }
            room = repo.electricRoomCode
            await repo.loadCardOverview()
            await loadBills()
        }
        .refreshable { await repo.loadCardOverview(force: true); await loadBills() }
        .sheet(item: $web) { item in NavigationStack { PortalWebViewScreen(url: item.url, nativeService: .payment) } }
    }
    private func money(_ value: Double?) -> String { value.map { $0.formatted(.currency(code: "CNY")) } ?? "未读取" }
    private func openPayment(path: String? = nil) {
        let entry = NativeCampusService.payment.entryURL(apps: repo.apps)
        web = NativeServiceWebLink(url: path.flatMap { URL(string: $0, relativeTo: entry)?.absoluteURL } ?? entry)
    }
    private func loadBills() async {
        let now = Date(), calendar = Calendar.current
        await repo.loadBills(year: calendar.component(.year, from: now), month: calendar.component(.month, from: now))
    }
}

struct NativeVPNView: View {
    var active = true
    @Environment(AppEnvironment.self) private var environment
    @State private var busy = false
    @State private var campus: Bool?
    @State private var ticket = false
    @State private var checkedAt: Date?
    @State private var web: NativeServiceWebLink?
    @State private var query = ""
    private var resources: [PortalApp] {
        environment.repository.apps.filter { app in
            guard let host = URL(string: app.entryUrl())?.host?.lowercased(), host == "neu.edu.cn" || host.hasSuffix(".neu.edu.cn") else { return false }
            return query.isEmpty || app.name.localizedCaseInsensitiveContains(query)
        }
    }
    var body: some View {
        Form {
            Section("访问状态") {
                LabeledContent("网络", value: campus.map { $0 ? "校园网络可达" : "使用校外访问" } ?? "尚未检测")
                LabeledContent("WebVPN 认证", value: ticket ? "会话已建立" : "尚未建立")
                if let checkedAt { LabeledContent("检测时间", value: checkedAt.formatted(date: .omitted, time: .shortened)) }
                if busy { ProgressView("正在检测网络…") }
                Button("重新检测", systemImage: "arrow.clockwise") { Task { await check(force: true) } }.disabled(busy)
                Button("更新 WebVPN 认证", systemImage: "person.badge.key") {
                    web = NativeServiceWebLink(url: URL(string: WebVPN.casService)!)
                }
                Text("WebVPN 用于校内网页访问，不会接管其他 App 的网络。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("校内资源") {
                TextField("搜索校内应用", text: $query)
                if resources.isEmpty { Text("没有匹配的资源").foregroundStyle(.secondary) }
                ForEach(resources) { app in
                    Button {
                        if let url = URL(string: app.entryUrl()) { web = NativeServiceWebLink(url: url) }
                    } label: { Label(app.name, systemImage: "arrow.up.right.square").foregroundStyle(.primary) }
                }
            }
        }
        .task(id: String(active) + environment.session.requestEpoch.uuidString) {
            guard active else { return }
            await environment.repository.loadAppsIfNeeded()
            await check(force: false)
        }
        .refreshable { await check(force: true) }
        .sheet(item: $web, onDismiss: { Task { await check(force: false) } }) { item in
            NavigationStack { PortalWebViewScreen(url: item.url) }
        }
    }
    private func check(force: Bool) async {
        guard !busy, environment.session.phase == .loggedIn else { return }
        busy = true; defer { busy = false }
        let epoch = environment.session.requestEpoch
        let client = environment.session.client
        if force { client.invalidateAccessRoute() }
        await client.prepareAccess()
        let reachable = await client.isCampusNet()
        guard epoch == environment.session.requestEpoch, !Task.isCancelled else { return }
        campus = reachable; ticket = client.hasWebVPNTicket; checkedAt = Date()
        environment.session.persistWebSession()
    }
}

@MainActor @Observable
final class NativeAffairsStore {
    private(set) var items: [TodoItem] = []
    private(set) var loading = false
    private(set) var loaded = false
    private(set) var hasMore = true
    private(set) var error: String?
    private var page = 0
    private var owner: UUID?
    func load(session: SessionStore, reset: Bool) async {
        let epoch = session.requestEpoch
        if owner != epoch { owner = epoch; items = []; page = 0; loaded = false; hasMore = true; loading = false; error = nil }
        guard session.phase == .loggedIn, !loading, reset || hasMore else { return }
        loading = true; defer { if owner == epoch { loading = false } }
        let target = reset ? 1 : page + 1
        do {
            let rows = try await session.client.fetchTodos(page: target, pageSize: 20)
            guard owner == epoch, session.requestEpoch == epoch, !Task.isCancelled else { return }
            let previous = reset ? [] : items
            var seen = Set<String>()
            items = (previous + rows).filter { seen.insert($0.id).inserted }
            page = target; hasMore = rows.count == 20; loaded = true; error = nil
            session.persistWebSession()
        } catch {
            guard owner == epoch, session.requestEpoch == epoch else { return }
            if !NetworkError.isCancellation(error) { self.error = NetworkError.from(error).message }
        }
    }
}

struct NativeAffairsView: View {
    var active = true
    @Environment(AppEnvironment.self) private var environment
    @State private var store = NativeAffairsStore()
    @State private var query = ""
    @State private var web: NativeServiceWebLink?
    private var visible: [TodoItem] {
        store.items.filter { query.isEmpty || ($0.title + $0.instance + $0.node).localizedCaseInsensitiveContains(query) }
    }
    var body: some View {
        List {
            Section {
                NavigationLink { NativeAffairsDirectoryView() } label: { Label("办事服务中心", systemImage: "square.grid.2x2") }
                Text("申请表单可在办事指南中开始填写，下方显示门户已返回的在办事项。")
                    .font(.caption).foregroundStyle(.secondary)
                TextField("搜索事项或处理节点", text: $query)
            }
            Section("我的在办事项") {
                if let error = store.error { Text(error).font(.footnote).foregroundStyle(.red) }
                if store.loaded && visible.isEmpty { ContentUnavailableView("暂无匹配事项", systemImage: "checklist") }
                ForEach(visible) { item in
                    Button {
                        if let url = URL(string: item.url) { web = NativeServiceWebLink(url: url) }
                    } label: {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(item.title).font(.headline).foregroundStyle(.primary)
                            if !item.instance.isEmpty { Text(item.instance).font(.subheadline).foregroundStyle(.secondary) }
                            HStack { Text(item.node); Spacer(); Text(item.time) }.font(.caption).foregroundStyle(.secondary)
                            if item.progressKnown { ProgressView(value: Double(min(100, max(0, item.percent))), total: 100) }
                        }.padding(.vertical, 6)
                    }.buttonStyle(.plain)
                }
                if store.loading { ProgressView("读取办事进度…") }
                if store.hasMore && !store.loading && store.loaded {
                    Button("加载更多") { Task { await store.load(session: environment.session, reset: false) } }
                }
            }
        }
        .task(id: String(active) + environment.session.requestEpoch.uuidString) {
            if active { await store.load(session: environment.session, reset: true) }
        }
        .refreshable { await store.load(session: environment.session, reset: true) }
        .sheet(item: $web) { item in NavigationStack { PortalWebViewScreen(url: item.url, nativeService: .affairs) } }
    }
}

private struct ServiceLoadNotice: View {
    let state: LoadState
    var body: some View {
        if case .loading = state { ProgressView() }
        else if case .failed(let message) = state { Text(message).font(.caption).foregroundStyle(.secondary) }
    }
}

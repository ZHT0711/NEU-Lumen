import SwiftUI
import Observation

struct NativePaymentView: View {
    var active = true
    @Environment(AppEnvironment.self) private var environment
    @State private var web: NativeServiceWebLink?
    @State private var room = ""
    @State private var section = "账户"
    @State private var roomOwner: UUID?
    @State private var paymentBrowsers: [URL: PortalBrowser] = [:]
    @State private var billQuery = ""
    @State private var billFilter: PaymentBillFilter = .all
    @State private var selectedBill: CardBill?
    @FocusState private var roomFocused: Bool
    private var repo: PortalRepository { environment.repository }
    private var hasUnsavedRoom: Bool { ElectricRoomKey.normalize(room) != repo.electricRoomCode }
    private var filteredBills: [CardBill] { NativePaymentPresentation.bills(repo.cardBills, matching: billQuery, filter: billFilter) }
    private var isCurrentMonth: Bool {
        let current = NativePaymentPresentation.currentMonth()
        return repo.billsYear == current.year && repo.billsMonth == current.month
    }
    var body: some View {
        Form {
            Section {
                Picker("缴费分类", selection: $section) {
                    Text("账户").tag("账户")
                    Text("电费").tag("电费")
                    Text("流水").tag("流水")
                }.pickerStyle(.segmented).accessibilityIdentifier("payment.section")
            }.listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
            if section == "账户" {
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
                Section("缴费服务") {
                    Button("缴费项目", systemImage: "square.grid.2x2") { openPayment(path: "/openApplication") }
                    Button("我的订单", systemImage: "list.clipboard") { openPayment(path: "/orders.html") }
                    Button("缴费大厅首页", systemImage: "house") { openPayment() }
                }
            }
            if section == "电费" {
                Section("宿舍电费") {
                    if let electric = repo.electricInfo, !electric.unbound {
                        LabeledContent("房间", value: electric.roomLabel ?? electric.roomNo ?? "已绑定")
                        LabeledContent("剩余电量", value: electric.remainKwh.map { $0.formatted(.number.precision(.fractionLength(0...2))) + " kWh" } ?? "未提供")
                        if let time = electric.lastReadAt { LabeledContent("抄表时间", value: time) }
                    }
                    TextField("房间码（3 位宿舍 + 4 位寝室）", text: $room)
                        .keyboardType(.numbersAndPunctuation).textInputAutocapitalization(.never).autocorrectionDisabled()
                        .focused($roomFocused).submitLabel(.search).onSubmit { queryRoom() }
                    Button("查询并记住房间", systemImage: "bolt") { queryRoom() }
                        .disabled(!ElectricRoomKey.isValid(room) || (repo.electricState == .loading && !hasUnsavedRoom))
                    if hasUnsavedRoom {
                        Text("请先查询新房间，再去缴费。").font(.caption).foregroundStyle(.secondary)
                        if !repo.electricRoomCode.isEmpty {
                            Button("恢复已保存的房间") { room = repo.electricRoomCode; roomFocused = false }
                        }
                    }
                    ServiceLoadNotice(state: repo.electricState)
                    if let warning = repo.electricWarning { Text(warning).font(.caption).foregroundStyle(.orange) }
                    if let date = repo.electricUpdatedAt { Text("上次成功查询 " + date.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary) }
                    Button("缴纳电费", systemImage: "bolt.fill") { openPaymentURL(CampusPaymentEntry.electricity) }
                        .disabled(hasUnsavedRoom)
                    if !repo.electricRoomCode.isEmpty {
                        Text("缴费时沿用房间码 \(repo.electricRoomCode)，学校表单仍可修改。").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            if section == "流水" {
                Section("校园卡月流水") {
                    HStack {
                        Button { Task { await repo.shiftBillsMonth(-1) } } label: { Image(systemName: "chevron.left") }
                            .accessibilityLabel("上个月").disabled(repo.billsState == .loading)
                        Spacer()
                        Text("\(String(repo.billsYear)) 年 \(repo.billsMonth) 月").font(.headline).monospacedDigit()
                        Spacer()
                        Button { Task { await repo.shiftBillsMonth(1) } } label: { Image(systemName: "chevron.right") }
                            .accessibilityLabel("下个月").disabled(isCurrentMonth || repo.billsState == .loading)
                    }.buttonStyle(.borderless)
                    if !isCurrentMonth {
                        Button("回到本月") {
                            let current = NativePaymentPresentation.currentMonth()
                            Task { await repo.loadBills(year: current.year, month: current.month) }
                        }
                    }
                    TextField("搜索交易、地点、日期或金额", text: $billQuery)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    Picker("交易类型", selection: $billFilter) {
                        ForEach(PaymentBillFilter.allCases) { filter in Text(filter.rawValue).tag(filter) }
                    }.pickerStyle(.segmented)
                    if repo.billsState == .loaded, filteredBills.isEmpty {
                        Text(repo.cardBills.isEmpty ? "该月没有流水记录" : "没有匹配的流水记录").foregroundStyle(.secondary)
                    }
                    ForEach(filteredBills) { bill in
                        Button { selectedBill = bill } label: { HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(bill.subject).font(.subheadline).foregroundStyle(.primary)
                                Text(bill.timeText).font(.caption).foregroundStyle(.secondary)
                                if !bill.station.isEmpty { Text(bill.station).font(.caption).foregroundStyle(.secondary) }
                            }
                            Spacer()
                            Text(money(bill.amount)).monospacedDigit().foregroundStyle(bill.isRecharge ? Color.green : Color.primary)
                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                        } }.buttonStyle(.plain)
                    }
                    if repo.billsState == .loaded {
                        Text("显示 \(filteredBills.count) 笔，共读取 \(repo.cardBills.count) 笔").font(.caption).foregroundStyle(.secondary)
                    }
                    if repo.billTruncated { Label("该月记录较多，学校本次返回可能不完整", systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange) }
                    if let warning = repo.billsWarning { Text(warning).font(.caption).foregroundStyle(.orange) }
                    if let updated = repo.billsUpdatedAt { Text("上次成功查询 " + updated.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary) }
                    Button("刷新所选月份", systemImage: "arrow.clockwise") { Task { await loadBills(force: true) } }
                        .disabled(repo.billsState == .loading)
                    ServiceLoadNotice(state: repo.billsState)
                }
            }
        }
        .task(id: String(active) + environment.session.requestEpoch.uuidString) {
            guard active else { return }
            await repo.ensureLoadedForCurrentUser()
            if roomOwner != environment.session.requestEpoch {
                for browser in paymentBrowsers.values { browser.close() }
                paymentBrowsers = [:]; web = nil; selectedBill = nil
                billQuery = ""; billFilter = .all; section = "账户"
                room = repo.electricRoomCode
                roomOwner = environment.session.requestEpoch
            }
            await repo.loadCardOverview()
            await loadBills()
        }
        .onChange(of: repo.electricRoomCode) { previous, current in
            if room.isEmpty || ElectricRoomKey.normalize(room) == previous { room = current }
        }
        .refreshable { await repo.loadCardOverview(force: true); await loadBills(force: true) }
        .sheet(item: $web) { item in
            NavigationStack { PortalWebViewScreen(url: item.url, nativeService: .payment, retainedBrowser: paymentBrowsers[item.url]) }
        }
        .sheet(item: $selectedBill) { bill in
            NavigationStack {
                Form {
                    LabeledContent("交易", value: bill.subject)
                    LabeledContent("时间", value: bill.timeText)
                    LabeledContent("金额", value: money(bill.amount))
                    LabeledContent("交易后余额", value: bill.balanceAfter.map { money($0) } ?? "学校未提供")
                    if !bill.station.isEmpty { LabeledContent("交易地点", value: bill.station) }
                    if let fee = bill.fee { LabeledContent("手续费", value: money(fee)) }
                }.textSelection(.enabled).privacySensitive()
                    .navigationTitle("流水详情").navigationBarTitleDisplayMode(.inline)
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { selectedBill = nil } } }
            }
        }
    }
    private func money(_ value: Double?) -> String { value.map { $0.formatted(.currency(code: "CNY")) } ?? "未读取" }
    private func queryRoom() {
        guard ElectricRoomKey.isValid(room), repo.electricState != .loading || hasUnsavedRoom else { return }
        repo.electricRoomCode = room
        room = repo.electricRoomCode
        roomFocused = false
        Task { await repo.loadElectric(force: true) }
    }
    private func openPayment(path: String? = nil) {
        let entry = NativeCampusService.payment.entryURL(apps: repo.apps)
        openPaymentURL(path.flatMap { URL(string: $0, relativeTo: entry)?.absoluteURL } ?? entry)
    }
    private func openPaymentURL(_ url: URL) {
        if paymentBrowsers[url] == nil { paymentBrowsers[url] = PortalBrowser() }
        web = NativeServiceWebLink(url: url)
    }
    private func loadBills(force: Bool = false) async {
        await repo.loadBills(year: repo.billsYear, month: repo.billsMonth, force: force)
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
    @State private var owner: UUID?
    @State private var checkRequest = UUID()
    private var resources: [PortalApp] {
        environment.repository.apps.filter { app in
            guard let url = URL(string: app.entryUrl()), WebVPN.shouldProxyBrowserURL(url) else { return false }
            let keyword = query.trimmingCharacters(in: .whitespacesAndNewlines)
            return keyword.isEmpty || [app.name, app.desc, app.category].contains { $0.localizedCaseInsensitiveContains(keyword) }
        }
    }
    var body: some View {
        Form {
            Section("访问状态") {
                LabeledContent("网络", value: environment.session.networkAvailable ? (campus.map { $0 ? "校园网络可达" : "使用校外访问" } ?? "尚未检测") : "网络已断开")
                DisclosureGroup("连接详情") {
                    LabeledContent("WebVPN 认证", value: ticket ? "已保存学校会话" : "未读取到学校会话")
                    if let checkedAt { LabeledContent("检测时间", value: checkedAt.formatted(date: .omitted, time: .shortened)) }
                }
                if busy { ProgressView("正在检测网络…") }
                Button("重新检测", systemImage: "arrow.clockwise") { Task { await check(force: true) } }.disabled(busy)
                Button("更新 WebVPN 认证", systemImage: "person.badge.key") {
                    web = NativeServiceWebLink(url: URL(string: WebVPN.casService)!)
                }
                Text("WebVPN 用于校内网页访问，不会接管其他 App 的网络。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("校内资源") {
                HStack {
                    TextField("搜索校内应用", text: $query).autocorrectionDisabled().textInputAutocapitalization(.never)
                    if !query.isEmpty {
                        Button("清除搜索", systemImage: "xmark.circle.fill") { query = "" }
                            .labelStyle(.iconOnly).frame(minWidth: 44, minHeight: 44)
                    }
                }
                if resources.isEmpty { Text("没有匹配的资源").foregroundStyle(.secondary) }
                ForEach(resources) { app in
                    Button {
                        if let url = URL(string: app.entryUrl()) { web = NativeServiceWebLink(url: url) }
                    } label: { Label(app.name, systemImage: "arrow.up.right.square").foregroundStyle(.primary) }
                }
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .task(id: String(active) + environment.session.requestEpoch.uuidString) {
            if owner != environment.session.requestEpoch {
                owner = environment.session.requestEpoch; checkRequest = UUID()
                campus = nil; ticket = false; checkedAt = nil; query = ""; web = nil; busy = false
            }
            guard active else { return }
            _ = await environment.repository.loadAppsIfNeeded()
            await check(force: false)
        }
        .refreshable { await check(force: true) }
        .onChange(of: environment.session.networkRevision) { _, _ in
            if active { Task { await check(force: true) } }
        }
        .sheet(item: $web, onDismiss: { Task { await check(force: false) } }) { item in
            NavigationStack { PortalWebViewScreen(url: item.url) }
        }
    }
    private func check(force: Bool) async {
        guard !busy || force, environment.session.phase == .loggedIn else { return }
        let request = UUID(); checkRequest = request
        busy = true; defer { if checkRequest == request { busy = false } }
        let epoch = environment.session.requestEpoch
        let client = environment.session.client
        if force { client.invalidateAccessRoute() }
        await client.prepareAccess()
        let reachable = await client.isCampusNet()
        guard epoch == environment.session.requestEpoch, checkRequest == request, !Task.isCancelled else { return }
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
    private var request = UUID()
    private var retryReset = true
    private(set) var updatedAt: Date?

    func bind(to epoch: UUID) {
        guard owner != epoch else { return }
        owner = epoch; request = UUID(); items = []; page = 0
        loaded = false; hasMore = true; loading = false; error = nil; updatedAt = nil
        retryReset = true
    }

    func load(session: SessionStore, reset: Bool) async {
        let epoch = session.requestEpoch
        bind(to: epoch)
        guard session.phase == .loggedIn, !loading, reset || hasMore else { return }
        let token = UUID(); request = token
        retryReset = reset
        loading = true; defer { if owner == epoch, request == token { loading = false } }
        do {
            // Refresh every loaded page as one transaction, retaining the expanded
            // list and the last successful results if any page fails.
            let first = reset ? 1 : page + 1
            let last = reset ? max(1, page) : first
            var received: [TodoItem] = []
            var finalPage = first
            var more = false
            for target in first...last {
                let rows = try await session.client.fetchTodos(page: target, pageSize: 20)
                guard owner == epoch, request == token, session.requestEpoch == epoch, !Task.isCancelled else { return }
                received += rows; finalPage = target; more = rows.count == 20
                if !more { break }
            }
            guard owner == epoch, request == token, session.requestEpoch == epoch, !Task.isCancelled else { return }
            let previous = reset ? [] : items
            var seen = Set<String>()
            items = (previous + received).filter { seen.insert($0.id).inserted }
            page = finalPage; hasMore = more; loaded = true; error = nil; updatedAt = Date()
            session.persistWebSession()
        } catch {
            guard owner == epoch, request == token, session.requestEpoch == epoch else { return }
            if !NetworkError.isCancellation(error) { self.error = NetworkError.from(error).message }
        }
    }
    func retry(session: SessionStore) async { await load(session: session, reset: retryReset) }
    func recoverAfterNetworkChange(session: SessionStore) async {
        guard error != nil || loading else { return }
        request = UUID(); loading = false
        await retry(session: session)
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
            }
            Section("我的在办事项") {
                TextField("搜索事项或处理节点", text: $query)
                    .autocorrectionDisabled().textInputAutocapitalization(.never)
                if let error = store.error {
                    Text(error).font(.footnote).foregroundStyle(.orange)
                    Button("重新读取办事进度") { Task { await store.retry(session: environment.session) } }
                        .disabled(store.loading)
                    if !store.items.isEmpty { Text("已保留上次读取的事项和分页。 ").font(.caption).foregroundStyle(.secondary) }
                }
                if let updatedAt = store.updatedAt {
                    Text("更新于 " + updatedAt.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary)
                }
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
        .scrollDismissesKeyboard(.interactively)
        .task(id: String(active) + environment.session.requestEpoch.uuidString) {
            store.bind(to: environment.session.requestEpoch)
            if active, !store.loaded { await store.load(session: environment.session, reset: true) }
        }
        .onChange(of: environment.session.requestEpoch) { _, epoch in
            store.bind(to: epoch); query = ""; web = nil
        }
        .refreshable { await store.load(session: environment.session, reset: true) }
        .onChange(of: environment.session.networkRevision) { _, _ in
            if active { Task { await store.recoverAfterNetworkChange(session: environment.session) } }
        }
        .sheet(item: $web, onDismiss: {
            if active { Task { await store.load(session: environment.session, reset: true) } }
        }) { item in NavigationStack { PortalWebViewScreen(url: item.url, nativeService: .affairs) } }
    }
}

private struct ServiceLoadNotice: View {
    let state: LoadState
    var body: some View {
        if case .loading = state { ProgressView() }
        else if case .failed(let message) = state { Text(message).font(.caption).foregroundStyle(.secondary) }
    }
}

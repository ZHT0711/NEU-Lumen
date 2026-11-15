import SwiftUI
import Observation

@MainActor @Observable
final class NativeVPNDirectoryStore {
    private(set) var directory: WebVPNDirectory?
    private(set) var loading = false
    private(set) var error: String?
    private(set) var updatedAt: Date?
    private(set) var favorites: Set<String> = []
    private(set) var opened: [String] = []
    private var account = ""
    private var epoch: UUID?
    private var request = UUID()
    private let defaults = UserDefaults.standard
    private var key: String { "lumen.webvpn.resources." + account }

    func bind(account: String, epoch: UUID) {
        guard self.account != account || self.epoch != epoch else { return }
        self.account = account; self.epoch = epoch; request = UUID()
        directory = nil; error = nil; updatedAt = nil; loading = false
        favorites = account.isEmpty ? [] : Set(defaults.stringArray(forKey: key + ".favorites") ?? [])
        opened = account.isEmpty ? [] : defaults.stringArray(forKey: key + ".recent") ?? []
    }

    func load(client: PortalClient, force: Bool = false) async {
        guard !account.isEmpty, (!loading || force), directory == nil || force else { return }
        let token = UUID(); request = token
        let owner = account
        loading = true; error = nil
        defer { if request == token { loading = false } }
        do {
            let value = try await client.loadWebVPNDirectory(expectedAccount: owner)
            guard request == token, owner == account, !Task.isCancelled else { return }
            directory = value; updatedAt = Date()
        } catch {
            guard request == token, owner == account, !Task.isCancelled else { return }
            self.error = (error as? WebVPNDirectoryError)?.localizedDescription ?? NetworkError.from(error).message
        }
    }

    func toggle(_ item: WebVPNResource) {
        guard !account.isEmpty else { return }
        if !favorites.insert(item.id).inserted { favorites.remove(item.id) }
        defaults.set(favorites.sorted(), forKey: key + ".favorites")
    }

    func visit(_ item: WebVPNResource) {
        guard !account.isEmpty else { return }
        opened = Array(([item.id] + opened.filter { $0 != item.id }).prefix(20))
        defaults.set(opened, forKey: key + ".recent")
    }

    var recent: [WebVPNResource] {
        guard let directory else { return [] }
        let resources = directory.resources
        var seen = Set<String>()
        return (opened.compactMap { id in resources.first(where: { $0.id == id }) } + directory.recent)
            .filter { seen.insert($0.originalURL.absoluteString).inserted }
    }
}

struct NativeVPNView: View {
    var active = true
    @Environment(AppEnvironment.self) private var environment
    @State private var store = NativeVPNDirectoryStore()
    @State private var busy = false
    @State private var campus: Bool?
    @State private var ticket = false
    @State private var checkedAt: Date?
    @State private var web: NativeServiceWebLink?
    @State private var query = ""
    @State private var category = "all"
    @State private var owner: UUID?
    @State private var checkRequest = UUID()
    private var account: String {
        guard let user = environment.session.user else { return "" }
        return user.sid.isEmpty ? user.uid : user.sid
    }
    private var sections: [WebVPNResourceGroup] {
        guard let directory = store.directory else { return [] }
        let groups: [WebVPNResourceGroup]
        switch category {
        case "favorites": groups = [WebVPNResourceGroup(id: "favorites", name: "本机收藏", resources: directory.resources.filter { store.favorites.contains($0.id) })]
        case "recent": groups = [WebVPNResourceGroup(id: "recent", name: "最近访问", resources: store.recent)]
        case "all": groups = directory.groups
        default: groups = directory.groups.filter { $0.id == category }
        }
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return groups.map { group in WebVPNResourceGroup(id: group.id, name: group.name, resources: group.resources.filter {
            term.isEmpty || [$0.name, $0.detail, $0.originalURL.host ?? ""].contains { $0.localizedCaseInsensitiveContains(term) }
        }) }.filter { !$0.resources.isEmpty }
    }

    var body: some View {
        List {
            Section("访问状态") {
                LabeledContent("网络", value: environment.session.networkAvailable ? (campus.map { $0 ? "校园网络可达" : "校外 WebVPN 访问" } ?? "尚未检测") : "网络已断开")
                LabeledContent("资源站点", value: store.directory.map { "\($0.resources.count) 项" } ?? "等待同步")
                DisclosureGroup("连接详情") {
                    LabeledContent("WebVPN 认证", value: store.directory != nil && store.error == nil ? "当前账号已核对" : (ticket ? "会话待核对" : "需要学校认证"))
                    if let updated = store.updatedAt { LabeledContent("目录更新", value: updated.formatted(date: .omitted, time: .shortened)) }
                    if let checkedAt { LabeledContent("网络检测", value: checkedAt.formatted(date: .omitted, time: .shortened)) }
                }
                Button("刷新状态与目录", systemImage: "arrow.clockwise") { Task { await refresh(force: true) } }
                    .disabled(busy || store.loading)
                Button("学校认证与原站", systemImage: "person.badge.key") { web = NativeServiceWebLink(url: URL(string: WebVPN.casService)!) }
            }
            Section {
                Picker("资源分类", selection: $category) {
                    Text("全部资源").tag("all")
                    Text("本机收藏").tag("favorites")
                    Text("最近访问").tag("recent")
                    ForEach(store.directory?.groups ?? []) { Text($0.name).tag($0.id) }
                }
                TextField("搜索站点、数据库或地址", text: $query)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                if busy || store.loading { ProgressView("正在读取学校资源站点…") }
                if let error = store.error {
                    Text(error).foregroundStyle(.orange).font(.subheadline)
                    Button("在学校页面完成认证") { web = NativeServiceWebLink(url: URL(string: WebVPN.casService)!) }
                }
                if !store.loading, store.directory != nil, sections.isEmpty {
                    ContentUnavailableView(category == "favorites" ? "还没有收藏资源" : "没有匹配的资源站点", systemImage: category == "favorites" ? "star" : "magnifyingglass", description: Text(category == "favorites" ? "点站点右侧的星标，常用资源就会出现在这里。" : "试试其他关键词或分类。"))
                }
            } header: { Text("资源目录") } footer: {
                Text("目录来自学校 WebVPN，包含校内网站和图书馆数据库。收藏按账号保存在本机；访问站点使用学校提供的网关链接。")
            }
            ForEach(sections) { group in
                Section(group.name) {
                    ForEach(group.resources) { item in
                        HStack(spacing: 12) {
                            Button {
                                store.visit(item)
                                web = NativeServiceWebLink(url: item.gatewayURL)
                            } label: {
                                HStack(spacing: 12) {
                                    Text(String(item.name.prefix(1))).font(.headline).frame(width: 38, height: 38)
                                        .background(AppTheme.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 10))
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(item.name).font(.subheadline.weight(.medium)).foregroundStyle(.primary)
                                        Text(item.detail).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                                    }
                                    Spacer(minLength: 0)
                                }.contentShape(Rectangle())
                            }.buttonStyle(.plain)
                            Button {
                                store.toggle(item)
                            } label: {
                                Image(systemName: store.favorites.contains(item.id) ? "star.fill" : "star")
                                    .frame(width: 44, height: 44)
                            }.buttonStyle(.borderless)
                                .accessibilityLabel((store.favorites.contains(item.id) ? "取消收藏 " : "收藏 ") + item.name)
                        }
                    }
                }
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .task(id: String(active) + environment.session.requestEpoch.uuidString) {
            if owner != environment.session.requestEpoch {
                owner = environment.session.requestEpoch; checkRequest = UUID()
                campus = nil; ticket = false; checkedAt = nil; query = ""; category = "all"; web = nil; busy = false
            }
            store.bind(account: account, epoch: environment.session.requestEpoch)
            guard active else { return }
            await refresh(force: false)
        }
        .refreshable { await refresh(force: true) }
        .onChange(of: environment.session.networkRevision) { _, _ in if active { Task { await refresh(force: true) } } }
        .sheet(item: $web, onDismiss: { Task { await refresh(force: true) } }) { item in
            NavigationStack { PortalWebViewScreen(url: item.url) }
        }
    }

    private func refresh(force: Bool) async {
        await check(force: force)
        guard active, environment.session.phase == .loggedIn else { return }
        await store.load(client: environment.session.client, force: force)
        environment.session.persistWebSession()
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
    }
}

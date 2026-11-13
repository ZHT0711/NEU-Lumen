import SwiftUI
import Observation

@MainActor @Observable
final class NativeNewsStore {
    private(set) var channels: [NewsChannel] = []
    private(set) var items: [NewsItem] = []
    private(set) var busy = false
    private(set) var error: String?
    private(set) var hasMore = false
    var channelID = ""
    var keyword = ""
    private var page = 0
    private var request = UUID()

    func load(session: SessionStore, reset: Bool) async {
        guard session.phase == .loggedIn else { return }
        let epoch = session.requestEpoch, token = UUID()
        request = token
        busy = true; error = nil
        if reset { page = 0; items = []; hasMore = false }
        let target = page + 1
        let query = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        defer { if request == token { busy = false } }
        do {
            let options = channels.isEmpty ? try await session.client.fetchNewsChannels() : channels
            guard session.requestEpoch == epoch, request == token, !Task.isCancelled else { return }
            channels = options
            let channel = options.first { $0.id == channelID } ?? options.first { $0.name == "东大要闻" } ?? options.first
            guard let channel else { throw NetworkError(message: "学校暂未返回可用的资讯频道") }
            channelID = channel.id
            let result = try await session.client.fetchNews(pageSize: 30, channel: channel, page: target, keyword: query)
            guard session.requestEpoch == epoch, session.phase == .loggedIn, request == token, !Task.isCancelled else { return }
            var seen = Set(items.map(\.id))
            items += result.filter { !$0.id.isEmpty && seen.insert($0.id).inserted }
            page = target; hasMore = result.count == 30
        } catch {
            guard session.requestEpoch == epoch, request == token, !Task.isCancelled else { return }
            self.error = error.localizedDescription
        }
    }

    func clear() {
        request = UUID(); channels = []; items = []; page = 0
        channelID = ""; keyword = ""; error = nil; busy = false; hasMore = false
    }
}

struct NativeNewsView: View {
    var active = true
    @Environment(AppEnvironment.self) private var environment
    @State private var store = NativeNewsStore()
    @State private var article: NativeServiceWebLink?
    @State private var draft = ""

    var body: some View {
        @Bindable var store = store
        List {
            Section {
                HStack {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("搜索学校资讯", text: $draft).submitLabel(.search)
                        .onSubmit { search() }
                    if !draft.isEmpty {
                        Button("清除", systemImage: "xmark.circle.fill") { draft = ""; search() }
                            .labelStyle(.iconOnly).frame(minWidth: 44, minHeight: 44)
                    }
                    Button("搜索") { search() }.disabled(store.busy)
                }
                if !store.channels.isEmpty {
                    Picker("资讯频道", selection: $store.channelID) {
                        ForEach(store.channels) { Text($0.name).tag($0.id) }
                    }
                    .onChange(of: store.channelID) { old, new in
                        if !old.isEmpty, old != new, active { Task { await load(reset: true) } }
                    }
                }
            } footer: { Text("新闻列表来自学校门户。点开资讯可查看学校发布的完整图文与附件。") }
            if let error = store.error {
                Section {
                    Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                    Button("重试") { Task { await load(reset: store.items.isEmpty) } }
                }
            }
            if store.busy, store.items.isEmpty { ProgressView("正在读取校园资讯…") }
            else if store.items.isEmpty, store.error == nil {
                ContentUnavailableView("暂无匹配资讯", systemImage: "newspaper", description: Text("试试其他关键词或频道。"))
            }
            Section {
                ForEach(store.items) { item in
                    Button {
                        if let url = PortalLink.resolve(item.url) { article = NativeServiceWebLink(url: url) }
                    } label: {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(item.title).font(.body).foregroundStyle(.primary).multilineTextAlignment(.leading)
                            HStack {
                                Text(item.category); Text(item.date)
                                Spacer(); Image(systemName: "chevron.right")
                            }.font(.caption).foregroundStyle(.secondary)
                        }.padding(.vertical, 6)
                    }.disabled(PortalLink.resolve(item.url) == nil)
                }
                if store.hasMore {
                    Button { Task { await load(reset: false) } } label: {
                        HStack { Text("加载更多资讯"); if store.busy { ProgressView() } }
                    }.disabled(store.busy)
                }
            }
        }
        .refreshable { await load(reset: true) }
        .task(id: "\(active)|\(environment.session.requestEpoch)") {
            if active { store.clear(); draft = ""; await load(reset: true) }
        }
        .onChange(of: environment.session.requestEpoch) { _, _ in
            if !active { store.clear() }
            article = nil; draft = ""
        }
        .onChange(of: environment.session.networkRevision) { _, _ in
            if active, store.error != nil || store.busy { Task { await load(reset: store.items.isEmpty) } }
        }
        .sheet(item: $article) { link in NavigationStack { PortalWebViewScreen(url: link.url) } }
    }

    private func load(reset: Bool) async { await store.load(session: environment.session, reset: reset) }
    private func search() {
        store.keyword = draft
        Task { await load(reset: true) }
    }
}

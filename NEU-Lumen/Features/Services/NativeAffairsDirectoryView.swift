import SwiftUI
import Observation

@MainActor @Observable
private final class AffairsDirectoryStore {
    var catalog: AffairsCatalog?
    var loading = false
    var error: String?
    private(set) var loadedQuery: AffairsCatalogQuery?
    private var request = UUID()
    private var owner: UUID?

    func load(_ query: AffairsCatalogQuery, session: SessionStore) async {
        let epoch = session.requestEpoch
        if owner != epoch { catalog = nil; error = nil; loadedQuery = nil; owner = epoch }
        let token = UUID()
        request = token
        loading = true
        defer { if request == token { loading = false } }
        do {
            let result = try await session.client.fetchAffairsCatalog(query)
            guard session.requestEpoch == epoch, request == token, !Task.isCancelled else { return }
            catalog = result
            loadedQuery = query
            error = nil
        } catch {
            guard session.requestEpoch == epoch, request == token, !NetworkError.isCancellation(error) else { return }
            self.error = NetworkError.from(error).message
        }
    }
}

struct NativeAffairsDirectoryView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var store = AffairsDirectoryStore()
    @State private var query = AffairsCatalogQuery()
    @State private var searchText = ""
    @State private var owner: UUID?
    @FocusState private var searchFocused: Bool
    private struct RequestKey: Hashable {
        let query: AffairsCatalogQuery
        let epoch: UUID
    }

    var body: some View {
        List {
            Section {
                HStack {
                    TextField("搜索学校办事服务", text: $searchText)
                        .submitLabel(.search).focused($searchFocused)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .onSubmit { search() }
                    if !searchText.isEmpty {
                        Button("清除搜索", systemImage: "xmark.circle.fill") { searchText = ""; search() }
                            .labelStyle(.iconOnly).frame(minWidth: 44, minHeight: 44)
                    }
                    Button("搜索") { search() }
                }
                if let catalog = store.catalog {
                    filter("服务对象", selection: $query.audience, values: catalog.audiences)
                    filter("服务类别", selection: $query.category, values: catalog.categories)
                    filter("服务部门", selection: $query.department, values: catalog.departments)
                    filter("名称首字母", selection: $query.initial, values: catalog.initials)
                }
                Button("重置筛选", systemImage: "line.3.horizontal.decrease.circle") {
                    query = AffairsCatalogQuery(); searchText = ""; searchFocused = false
                }
            }
            if let error = store.error {
                Section {
                    Text(error).foregroundStyle(.secondary)
                    Button("重新读取") { Task { await store.load(query, session: environment.session) } }
                    if store.loadedQuery == query { Text("已保留上次读取的目录。下拉可重新读取。 ").font(.caption).foregroundStyle(.secondary) }
                }
            }
            if store.loading { ProgressView("读取服务目录…") }
            if let catalog = store.catalog, store.loadedQuery == query {
                Section("学校返回的服务（\(catalog.services.count)）") {
                    if catalog.services.isEmpty { ContentUnavailableView.search(text: query.keyword) }
                    ForEach(catalog.services) { service in
                        NavigationLink {
                            NativeAffairsGuideView(service: service)
                        } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(service.title).font(.body)
                                Text(service.department).font(.caption).foregroundStyle(.secondary)
                            }.padding(.vertical, 4)
                        }
                    }
                }
            }
        }
        .navigationTitle("办事服务中心").navigationBarTitleDisplayMode(.inline)
        .scrollDismissesKeyboard(.interactively)
        .task(id: RequestKey(query: query, epoch: environment.session.requestEpoch)) {
            if owner != environment.session.requestEpoch {
                owner = environment.session.requestEpoch
                query = AffairsCatalogQuery(); searchText = ""; searchFocused = false
            }
            await store.load(query, session: environment.session)
        }
        .refreshable { await store.load(query, session: environment.session) }
        .onChange(of: environment.session.networkRevision) { _, _ in
            if store.error != nil || store.loading { Task { await store.load(query, session: environment.session) } }
        }
    }

    private func search() {
        searchFocused = false
        let keyword = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if query.keyword == keyword { Task { await store.load(query, session: environment.session) } }
        else { query.keyword = keyword }
    }

    private func filter(_ title: String, selection: Binding<String>, values: [AffairsCatalogFilter]) -> some View {
        Picker(title, selection: selection) {
            if !values.contains(where: { $0.id == selection.wrappedValue }) { Text("学校未返回此选项").tag(selection.wrappedValue) }
            ForEach(values) { item in Text(item.title).tag(item.id) }
        }.pickerStyle(.menu)
    }
}

private struct NativeAffairsGuideView: View {
    let service: AffairsService
    @Environment(AppEnvironment.self) private var environment
    @State private var guide: AffairsServiceGuide?
    @State private var error: String?
    @State private var loading = false
    @State private var owner: UUID?
    @State private var request = UUID()
    @State private var web: NativeServiceWebLink?

    var body: some View {
        List {
            if let guide {
                Section {
                    Text(guide.title).font(.title3.bold())
                    ForEach(Array(guide.facts.enumerated()), id: \.offset) { _, fact in
                        Text(fact).font(.subheadline).textSelection(.enabled)
                    }
                    if let url = guide.applicationURL {
                        Button("开始办理", systemImage: "square.and.pencil") { web = NativeServiceWebLink(url: url) }
                    }
                }
                ForEach(guide.sections) { section in
                    Section(section.title) {
                        if !section.text.isEmpty { Text(section.text).textSelection(.enabled) }
                        ForEach(Array(section.images.enumerated()), id: \.offset) { _, url in
                            AffairsGuideImage(url: url, referer: service.guideURL, title: section.title + "图示") {
                                web = NativeServiceWebLink(url: url)
                            }
                        }
                        ForEach(Array(section.links.enumerated()), id: \.offset) { _, link in
                            Button(link.title, systemImage: "doc") { web = NativeServiceWebLink(url: link.url) }
                        }
                    }
                }
            }
            if loading { ProgressView("读取办事指南…") }
            if let error {
                Text(error).foregroundStyle(.secondary)
                Button("重试") { Task { await load() } }
            }
        }
        .navigationTitle("办事指南").navigationBarTitleDisplayMode(.inline)
        .task(id: environment.session.requestEpoch) { await load() }
        .refreshable { await load() }
        .onChange(of: environment.session.networkRevision) { _, _ in
            if error != nil || loading { Task { await load() } }
        }
        .sheet(item: $web) { link in NavigationStack {
            PortalWebViewScreen(url: link.url, nativeService: link.url == guide?.applicationURL ? .affairs : nil)
        } }
    }

    private func load() async {
        let epoch = environment.session.requestEpoch
        if owner != epoch { guide = nil; web = nil; error = nil; owner = epoch }
        let token = UUID()
        request = token
        loading = true
        defer { if request == token { loading = false } }
        do {
            let result = try await environment.session.client.fetchAffairsGuide(service)
            guard epoch == environment.session.requestEpoch, request == token, !Task.isCancelled else { return }
            guide = result; error = nil
        } catch {
            guard epoch == environment.session.requestEpoch, request == token, !NetworkError.isCancellation(error) else { return }
            self.error = NetworkError.from(error).message
        }
    }
}

private struct AffairsGuideImage: View {
    let url: URL
    let referer: URL
    let title: String
    let openWebsite: () -> Void
    @Environment(AppEnvironment.self) private var environment
    @State private var image: UIImage?
    @State private var error: String?
    @State private var revision = 0
    @State private var owner: UUID?
    @State private var loadedURL: URL?
    private struct RequestKey: Hashable { let epoch: UUID; let revision: Int; let url: URL }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let image { Image(uiImage: image).resizable().scaledToFit().accessibilityLabel(title) }
            else if let error {
                Label(error, systemImage: "photo.badge.exclamationmark").font(.footnote).foregroundStyle(.secondary)
                Button("重新读取图示") { revision += 1 }
                Button("在学校页面查看图示", action: openWebsite)
            } else { ProgressView("读取" + title) }
        }
        .task(id: RequestKey(epoch: environment.session.requestEpoch, revision: revision, url: url)) {
            let epoch = environment.session.requestEpoch
            if owner != epoch || loadedURL != url { image = nil; owner = epoch }
            error = nil
            do {
                let data = try await environment.session.client.fetchAffairsGuideImage(url, referer: referer)
                guard epoch == environment.session.requestEpoch, !Task.isCancelled else { return }
                guard let decoded = UIImage(data: data) else { throw NetworkError(message: "此图示需在学校页面查看") }
                image = decoded
                loadedURL = url
            } catch {
                guard epoch == environment.session.requestEpoch, !NetworkError.isCancellation(error), !Task.isCancelled else { return }
                self.error = NetworkError.from(error).message
            }
        }
        .onChange(of: environment.session.networkRevision) { _, _ in if error != nil { revision += 1 } }
    }
}

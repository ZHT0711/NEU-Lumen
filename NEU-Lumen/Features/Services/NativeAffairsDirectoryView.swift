import SwiftUI
import Observation

@MainActor @Observable
private final class AffairsDirectoryStore {
    var catalog: AffairsCatalog?
    var loading = false
    var error: String?
    private var request = UUID()
    private var owner: UUID?

    func load(_ query: AffairsCatalogQuery, session: SessionStore) async {
        let epoch = session.requestEpoch
        if owner != epoch { catalog = nil; error = nil; owner = epoch }
        let token = UUID()
        request = token
        loading = true
        defer { if request == token { loading = false } }
        do {
            let result = try await session.client.fetchAffairsCatalog(query)
            guard session.requestEpoch == epoch, request == token, !Task.isCancelled else { return }
            catalog = result
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
    private struct RequestKey: Hashable {
        let query: AffairsCatalogQuery
        let epoch: UUID
    }

    var body: some View {
        List {
            Section {
                TextField("搜索学校办事服务", text: $searchText)
                    .submitLabel(.search)
                    .onSubmit { query.keyword = searchText.trimmingCharacters(in: .whitespacesAndNewlines) }
                if let catalog = store.catalog {
                    filter("服务对象", selection: $query.audience, values: catalog.audiences)
                    filter("服务类别", selection: $query.category, values: catalog.categories)
                    filter("服务部门", selection: $query.department, values: catalog.departments)
                    filter("名称首字母", selection: $query.initial, values: catalog.initials)
                }
                Button("重置筛选", systemImage: "line.3.horizontal.decrease.circle") {
                    query = AffairsCatalogQuery(); searchText = ""
                }
            }
            if let error = store.error {
                Section {
                    Text(error).foregroundStyle(.secondary)
                    Button("重新读取") { Task { await store.load(query, session: environment.session) } }
                }
            }
            if store.loading { ProgressView("读取服务目录…") }
            if let catalog = store.catalog {
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
        .task(id: RequestKey(query: query, epoch: environment.session.requestEpoch)) {
            await store.load(query, session: environment.session)
        }
        .refreshable { await store.load(query, session: environment.session) }
        .onChange(of: environment.session.networkRevision) { _, _ in
            if store.error != nil || store.loading { Task { await store.load(query, session: environment.session) } }
        }
    }

    private func filter(_ title: String, selection: Binding<String>, values: [AffairsCatalogFilter]) -> some View {
        Picker(title, selection: selection) {
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
                            AsyncImage(url: url) { image in
                                image.resizable().scaledToFit()
                            } placeholder: { ProgressView() }
                            .accessibilityLabel(section.title + "图示")
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

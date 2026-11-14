import SwiftUI

/// 服务大厅：门户分类、热搜词、本地联合筛选与智慧搜索。
struct ServicesView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var path: [AppDestination] = []
    @State private var showFavorites = false
    @State private var favoritesOnly = false
    @State private var showDirectory = false
    @State private var query = ""
    @State private var selectedCategory: String?
    @State private var catalogReadFailed = false
    @State private var readingCatalog = false
    @State private var ownerEpoch: UUID?
    @State private var catalogRequest = UUID()
    @FocusState private var searchFocused: Bool
    @ScaledMetric(relativeTo: .caption) private var appColumnWidth: CGFloat = 76

    private var repo: PortalRepository {
        environment.repository
    }

    private var catalog: ServiceCatalog { ServiceCatalog(apps: repo.apps) }

    private var keyword: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var filtered: [PortalApp] {
        ServiceCatalog(apps: favoritesOnly ? repo.favorites.apps(in: repo.apps) : repo.apps)
            .filtered(query: query, category: selectedCategory)
    }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 24) {
                    searchField
                    if keyword.isEmpty {
                        Picker("服务范围", selection: $showDirectory) {
                            Text("校园服务").tag(false)
                            Text("应用目录").tag(true)
                        }
                        .pickerStyle(.segmented)
                        .accessibilityIdentifier("services.scope")
                    }
                    if catalogReadFailed && !showDirectory && keyword.isEmpty {
                        Label("应用目录更新失败，下拉可重试", systemImage: "exclamationmark.triangle")
                            .font(.footnote).foregroundStyle(.orange)
                    }
                    if !showDirectory || !keyword.isEmpty { nativeStudyServices }
                    if showDirectory || !keyword.isEmpty {
                        if keyword.isEmpty && !repo.hotSearch.isEmpty { hotChips }
                        HStack {
                            Toggle("只看收藏", isOn: $favoritesOnly).toggleStyle(.button)
                            Spacer()
                            Button("管理收藏") { showFavorites = true }
                        }.font(.subheadline)
                        categoryChips
                        appsSection
                        smartSearchCard
                    } else {
                        favoriteAppsSection
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 32)
            }
            .tracksTabBarScrolling()
            .background(Color(.systemGroupedBackground))
            .sheet(isPresented: $showFavorites) { FavoritesEditor() }
            .navigationTitle("服务大厅")
            .navigationBarTitleDisplayMode(.inline)
            .scrollDismissesKeyboard(.interactively)
            .refreshable { await loadCatalog(force: true) }
            .onChange(of: showDirectory) { _, directory in
                if !directory { selectedCategory = nil; favoritesOnly = false }
            }
            .onChange(of: catalog.categories) { _, categories in
                if let selectedCategory, !categories.contains(where: { $0.name == selectedCategory }) {
                    self.selectedCategory = nil
                }
            }
            .task(id: environment.session.requestEpoch) {
                if ownerEpoch != environment.session.requestEpoch {
                    ownerEpoch = environment.session.requestEpoch
                    query = ""; selectedCategory = nil; favoritesOnly = false; showDirectory = false
                    path = []; showFavorites = false; searchFocused = false
                    catalogReadFailed = false; readingCatalog = false
                }
                await repo.ensureLoadedForCurrentUser()
                await loadCatalog(force: false)
                await repo.loadHotSearchIfNeeded()
            }
            .navigationDestination(for: AppDestination.self) { dest in
                switch dest {
                case .web(let url):
                    PortalWebViewScreen(url: url)
                case .card:
                    CardView()
                case .academic:
                    AcademicCenterView()
                case .ecode:
                    NativeECodeView()
                case .nativeService(let service):
                    NativeServiceHost(initial: service)
                }
            }
        }
    }

    private var favoriteAppsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("常用应用").font(.headline)
                Spacer()
                Button("编辑") { showFavorites = true }.font(.subheadline)
            }
            let apps = repo.favorites.apps(in: repo.apps)
            if apps.isEmpty {
                Button("添加常用应用", systemImage: "plus") { showFavorites = true }
                    .frame(maxWidth: .infinity, minHeight: 64)
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
            } else {
                GlassCard {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: appColumnWidth), spacing: 12)], spacing: 16) {
                        ForEach(apps) { app in
                            Button { open(app) } label: {
                                VStack(spacing: 8) {
                                    ServiceAppIcon(app: app).frame(width: 40, height: 40)
                                    Text(app.name).font(.caption).foregroundStyle(.primary)
                                        .lineLimit(2).multilineTextAlignment(.center)
                                }
                                .frame(maxWidth: .infinity, minHeight: 76)
                            }.buttonStyle(.plain)
                        }
                    }.padding(16)
                }
            }
            Button("浏览全部应用", systemImage: "arrow.right") { showDirectory = true }
                .font(.subheadline).frame(minHeight: 44)
        }
    }

    @ViewBuilder
    private var nativeStudyServices: some View {
        let services = NativeCampusService.allCases.filter {
            keyword.isEmpty || ($0.title + $0.subtitle).localizedCaseInsensitiveContains(keyword)
        }
        if !services.isEmpty {
            NativeServicesCarousel(services: services, searching: !keyword.isEmpty) { service in
                path.append(.nativeService(service))
            }
        }
    }

    private var categoryChips: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("服务分类")
                .font(.subheadline.bold())
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    categoryChip(name: "全部", count: repo.apps.count, category: nil)
                    ForEach(catalog.categories) { category in
                        categoryChip(name: category.name, count: category.count, category: category.name)
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    private func categoryChip(name: String, count: Int, category: String?) -> some View {
        let active = selectedCategory == category
        return Button {
            selectedCategory = category
        } label: {
            HStack(spacing: 6) {
                Text(name)
                    .font(.subheadline.weight(active ? .semibold : .medium))
                Text("\(count)")
                    .font(.caption.monospacedDigit())
                    .opacity(0.8)
            }
            .foregroundStyle(active ? Color.white : Color.primary)
            .padding(.horizontal, 14)
            .frame(minHeight: 44)
            .background(
                active ? AppTheme.accent : Color(.secondarySystemGroupedBackground),
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(name)，\(count) 个应用")
        .accessibilityAddTraits(active ? .isSelected : [])
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("搜索服务和应用", text: $query)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($searchFocused)
                .submitLabel(.search)
                .onSubmit { searchFocused = false }
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("清除搜索")
            }
        }
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    /// 智慧搜索入口：一键跳转智搜平台全校搜索（SSO 免登录）。
    private var smartSearchCard: some View {
        Group {
            if !keyword.isEmpty {
                Button {
                    if let url = URL(string: "https://so.neu.edu.cn/#/accessLogin?searchWord=\(keyword.urlFormEncoded)") {
                        path.append(.web(url))
                    }
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "sparkle.magnifyingglass")
                            .font(.title3)
                            .foregroundStyle(AppTheme.accent)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("在智搜平台全校搜索")
                                .font(.subheadline.bold())
                                .foregroundStyle(.primary)
                            Text("「\(keyword)」")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer()
                        Image(systemName: "arrow.up.right")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(14)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var hotChips: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("热搜")
                .font(.subheadline.bold())
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 8) {
                    ForEach(repo.hotSearch, id: \.self) { word in
                        Button {
                            query = word
                            selectedCategory = nil
                        } label: {
                            Text(word)
                                .font(.caption)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(AppTheme.accent.opacity(0.1), in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var appsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            if catalogReadFailed {
                HStack(alignment: .top, spacing: 12) {
                    Label(repo.apps.isEmpty ? "应用目录未能读取" : "应用目录更新失败，已保留现有应用", systemImage: "exclamationmark.triangle")
                        .font(.footnote).foregroundStyle(.orange)
                    Spacer(minLength: 0)
                    Button("重试") { Task { await loadCatalog(force: true) } }
                        .font(.footnote).disabled(readingCatalog)
                }
            }
            // 标题、空态与网格使用同一轮筛选结果；下一次构建仍读取最新状态。
            let apps = filtered
            HStack {
                Text("\(selectedCategory ?? (favoritesOnly ? "我的收藏" : "全部应用"))（\(apps.count)）")
                    .font(.subheadline.bold())
                Spacer()
                if selectedCategory != nil || !keyword.isEmpty || favoritesOnly {
                    Button("重置") {
                        query = ""
                        favoritesOnly = false
                        selectedCategory = nil
                    }
                    .font(.caption.weight(.medium))
                }
            }
            if apps.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                    Text(keyword.isEmpty ? (favoritesOnly ? "暂无收藏，点击应用右上角的星标添加" : "暂无可用应用") : "没有匹配「\(keyword)」的应用")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    if selectedCategory != nil {
                        Button("在全部分类中查找") { selectedCategory = nil }
                            .font(.footnote)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 32)
            } else {
                GlassCard {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: appColumnWidth), spacing: 10)], spacing: 14) {
                        ForEach(apps) { app in
                            Button {
                                open(app)
                            } label: {
                                VStack(spacing: 6) {
                                    ServiceAppIcon(app: app)
                                        .frame(width: 40, height: 40)
                                    Text(app.name)
                                        .font(.caption2)
                                        .foregroundStyle(.primary)
                                        .lineLimit(2)
                                        .multilineTextAlignment(.center)
                                        .frame(minHeight: 28, alignment: .top)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .padding(.horizontal, 4)
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button { repo.favorites.toggle(app) } label: {
                                    Label(repo.favorites.contains(app) ? "取消收藏" : "添加收藏",
                                          systemImage: repo.favorites.contains(app) ? "star.slash" : "star")
                                }
                            }
                        }
                    }
                    .padding(12)
                }
            }
        }
    }

    private func open(_ app: PortalApp) {
        guard let destination = AppDestination.service(app) else { return }
        path.append(destination)
    }

    private func loadCatalog(force: Bool) async {
        let epoch = environment.session.requestEpoch
        let request = UUID()
        catalogRequest = request
        readingCatalog = true
        defer {
            if environment.session.requestEpoch == epoch, catalogRequest == request { readingCatalog = false }
        }
        let loaded = await repo.loadAppsIfNeeded(force: force)
        guard environment.session.requestEpoch == epoch, catalogRequest == request, !Task.isCancelled else { return }
        catalogReadFailed = !loaded
    }
}

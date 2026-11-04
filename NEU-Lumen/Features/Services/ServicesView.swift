import SwiftUI

/// 服务大厅：门户分类、热搜词、本地联合筛选与智慧搜索。
struct ServicesView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var path: [AppDestination] = []
    @State private var showFavorites = false
    @State private var favoritesOnly = false
    @State private var query = ""
    @State private var selectedCategory: String?
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
                LazyVStack(alignment: .leading, spacing: 14) {
                    serviceHeader
                    searchField
                    if keyword.isEmpty && !repo.hotSearch.isEmpty {
                        hotChips
                    }
                    HStack {
                        Toggle("只看收藏", isOn: $favoritesOnly).toggleStyle(.button)
                        Spacer()
                        Button("管理收藏") { showFavorites = true }
                    }.font(.subheadline)
                    categoryChips
                    smartSearchCard
                    appsSection
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
            .onChange(of: catalog.categories) { _, categories in
                if let selectedCategory, !categories.contains(where: { $0.name == selectedCategory }) {
                    self.selectedCategory = nil
                }
            }
            .task {
                await repo.ensureLoadedForCurrentUser()
                await repo.loadAppsIfNeeded()
                await repo.loadHotSearchIfNeeded()
            }
            .navigationDestination(for: AppDestination.self) { dest in
                switch dest {
                case .web(let url):
                    PortalWebViewScreen(url: url)
                case .card:
                    CardView()
                }
            }
        }
    }

    private var serviceHeader: some View {
        HStack(spacing: 14) {
            Image(systemName: "square.grid.2x2.fill")
                .font(.title2)
                .foregroundStyle(AppTheme.accent)
                .frame(width: 52, height: 52)
                .background(AppTheme.accent.opacity(0.1), in: RoundedRectangle(cornerRadius: 16))
            VStack(alignment: .leading, spacing: 5) {
                Text("东大服务，一站直达")
                    .font(.title3.bold())
                Text("\(repo.apps.count) 个应用 · \(catalog.categories.count) 类校园服务")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 8)
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
            TextField("搜索校内应用", text: $query)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
                .accessibilityLabel("清除搜索")
            }
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
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
            HStack {
                Text("\(selectedCategory ?? (favoritesOnly ? "我的收藏" : "全部应用"))（\(filtered.count)）")
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
            if filtered.isEmpty {
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
                        ForEach(filtered) { app in
                            Button {
                                open(app)
                            } label: {
                                VStack(spacing: 6) {
                                    RemoteImageView(path: app.iconUrl)
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
                            .overlay(alignment: .topTrailing) {
                                Button { repo.favorites.toggle(app) } label: {
                                    Image(systemName: repo.favorites.contains(app) ? "star.fill" : "star")
                                        .foregroundStyle(repo.favorites.contains(app) ? Color.orange : Color.secondary)
                                        .frame(width: 32, height: 32)
                                        .background(.regularMaterial, in: Circle())
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel((repo.favorites.contains(app) ? "取消收藏" : "收藏") + app.name)
                            }
                        }
                    }
                    .padding(12)
                }
            }
        }
    }

    private func open(_ app: PortalApp) {
        let entry = app.entryUrl()
        guard !entry.isEmpty, let url = URL(string: entry) else { return }
        path.append(.web(url))
    }
}

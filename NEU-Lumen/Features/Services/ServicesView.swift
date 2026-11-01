import SwiftUI

/// 服务大厅：全部校内应用 + 热搜词 + 本地即时过滤。
struct ServicesView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var path: [AppDestination] = []
    @State private var query = ""

    private var repo: PortalRepository {
        environment.repository
    }

    private var filtered: [PortalApp] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return repo.apps }
        return repo.apps.filter {
            $0.name.localizedCaseInsensitiveContains(q)
                || $0.desc.localizedCaseInsensitiveContains(q)
                || $0.category.localizedCaseInsensitiveContains(q)
        }
    }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    searchField
                    smartSearchCard
                    if query.isEmpty {
                        hotChips
                    }
                    appsSection
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 32)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("服务大厅")
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
            }
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    /// 智慧搜索入口：一键跳转智搜平台全校搜索（SSO 免登录）。
    private var smartSearchCard: some View {
        Group {
            if !query.trimmingCharacters(in: .whitespaces).isEmpty {
                Button {
                    let keyword = query.trimmingCharacters(in: .whitespaces)
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
                            Text("「\(query.trimmingCharacters(in: .whitespaces))」")
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
            Text("全部应用（\(filtered.count)）")
                .font(.subheadline.bold())
            if filtered.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                    Text("没有匹配「\(query)」的应用")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 32)
            } else {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4), spacing: 14) {
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
                                    .lineLimit(1)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .padding(.horizontal, 4)
                        }
                        .buttonStyle(.plain)
                    }
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

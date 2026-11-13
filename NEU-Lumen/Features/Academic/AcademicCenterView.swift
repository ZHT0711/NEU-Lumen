import SwiftUI

/// 由现有服务 / 学习导航压栈；不自行创建 NavigationStack。
struct AcademicCenterView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var showOriginalWeb = false
    private var repo: PortalRepository { environment.repository }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                AcademicNotice(text: "按当前账号的正常教务权限读取。校历日期、周次、培养方案与修读进度使用官方只读接口；完整课程明细暂需网页同步。")
                if environment.session.phase != .loggedIn {
                    ContentUnavailableView("请先登录", systemImage: "person.crop.circle", description: Text("登录当前账号后才能读取个人教务信息。"))
                } else {
                    NavigationLink { AcademicCalendarView() } label: {
                        AcademicEntryCard(title: "校历与周次", subtitle: "学期列表 · 学期起止日期 · 教务周次", icon: "calendar")
                    }.buttonStyle(.plain)
                    AcademicQuerySection(repo: repo, key: .terms) {
                        Text(repo.academicTerms.first(where: { $0.current })?.name ?? "当前学期未标记")
                            .font(.subheadline)
                        Text("已读取 \(repo.academicTerms.count) 个学期；以教务 selected 字段为准。")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    NavigationLink { AcademicPlanView() } label: {
                        AcademicEntryCard(title: "培养计划", subtitle: "方案选择 · 官方修读进度 · 当前页面课程明细", icon: "list.bullet.rectangle.portrait")
                    }.buttonStyle(.plain)
                    AcademicQuerySection(repo: repo, key: .plans) {
                        Text(repo.academicPlans.first(where: { $0.selected })?.name ?? "培养方案未标记默认项")
                            .font(.subheadline)
                        Text("已读取 \(repo.academicPlans.count) 个方案；未将成绩总学分当作培养要求。")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Button("学校原始教务入口", systemImage: "globe") { showOriginalWeb = true }
                    .buttonStyle(.bordered)
                AcademicNotice(text: "原始入口仍是学校网页，不是完整原生功能。不会自动选课、报名或修改学校记录。")
            }
            .padding(16).padding(.bottom, 24)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("学业查询")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("刷新学业查询", systemImage: "arrow.clockwise") { Task { await reload(force: true) } }
                    .disabled(repo.academicState(for: .terms) == .loading || repo.academicState(for: .plans) == .loading)
            }
        }
        .task(id: environment.session.requestEpoch) { await reload(force: false) }
        .refreshable { await reload(force: true) }
        .sheet(isPresented: $showOriginalWeb) {
            NavigationStack { PortalWebViewScreen(url: AcademicWebSyncSheet.entryURL) }
        }
    }

    private func reload(force: Bool) async {
        await repo.loadAcademicQuery(.terms, force: force)
        await repo.loadAcademicQuery(.plans, force: force)
    }
}

struct AcademicEntryCard: View {
    let title: String
    let subtitle: String
    let icon: String
    var body: some View {
        GlassCard {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: icon).font(.title2).foregroundStyle(AppTheme.accent).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 6) {
                    Text(title).font(.headline)
                    Text(subtitle).font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").foregroundStyle(.secondary).accessibilityHidden(true)
            }.padding(16)
        }
        .accessibilityElement(children: .combine)
    }
}

struct AcademicNotice: View {
    let text: String
    var body: some View {
        Label { Text(text).fixedSize(horizontal: false, vertical: true) } icon: { Image(systemName: "info.circle") }
            .font(.footnote).foregroundStyle(.secondary)
    }
}

struct AcademicQuerySection<Content: View>: View {
    let repo: PortalRepository
    let key: AcademicQueryKey
    let content: () -> Content
    init(repo: PortalRepository, key: AcademicQueryKey, @ViewBuilder content: @escaping () -> Content) {
        self.repo = repo; self.key = key; self.content = content
    }
    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                switch repo.academicState(for: key) {
                case .failed(let message):
                    ErrorStateView(message: message) { Task { await repo.loadAcademicQuery(key, force: true) } }
                case .idle, .loading:
                    HStack { ProgressView(); Text("正在读取\(key.title)…").font(.subheadline) }
                    if repo.academicPayload(for: key) != nil { content() }
                case .loaded: content()
                }
                if let warning = repo.academicWarning(for: key) {
                    Label(warning, systemImage: "exclamationmark.circle").font(.footnote).foregroundStyle(.orange)
                        .accessibilityLabel("保留上次结果。\(warning)")
                    Button("重试\(key.title)", systemImage: "arrow.clockwise") {
                        Task { await repo.loadAcademicQuery(key, force: true) }
                    }.buttonStyle(.bordered).disabled(repo.academicState(for: key) == .loading)
                }
                if let date = repo.academicUpdatedAt(for: key) {
                    Text("教务接口 · 更新于 \(date.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }.frame(maxWidth: .infinity, alignment: .leading).padding(16)
        }
    }
}

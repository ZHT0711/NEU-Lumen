import SwiftUI

/// 服务大厅横向胶囊进入的唯一学业工具首页。
struct AcademicCenterView: View {
    @Environment(AppEnvironment.self) private var environment
    private var repo: PortalRepository { environment.repository }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(repo.academicTerms.first(where: { $0.current })?.name ?? "我的学业")
                        .font(.title2.bold())
                    Text("查看课表、成绩、校历和培养计划")
                        .font(.subheadline).foregroundStyle(.secondary)
                }.padding(.vertical, 8)
                Button {
                    environment.pendingActivityURL = URL(string: "neulumen://activity/learning?section=grades")
                } label: {
                    AcademicEntryCard(title: "成绩与绩点", subtitle: "学期成绩 · 学分 · 加权均分", icon: "chart.bar.doc.horizontal")
                }.buttonStyle(.plain)
                Button {
                    environment.pendingActivityURL = URL(string: "neulumen://activity/course")
                } label: {
                    AcademicEntryCard(title: "我的课表", subtitle: "周课表 · 课程详情 · 个人日程", icon: "calendar.day.timeline.left")
                }.buttonStyle(.plain)
                NavigationLink { AcademicCalendarView() } label: {
                    AcademicEntryCard(title: "校历与周次", subtitle: "学期日期 · 假期 · 教学周查询", icon: "calendar")
                }.buttonStyle(.plain)
                NavigationLink { AcademicPlanView() } label: {
                    AcademicEntryCard(title: "培养计划", subtitle: "方案进度 · 课程模块 · 修读状态", icon: "list.bullet.rectangle.portrait")
                }.buttonStyle(.plain)
                Text("选课、考试报名及其他业务可通过右上角「学校原站」办理。")
                    .font(.footnote).foregroundStyle(.secondary)
            }.padding(16).padding(.bottom, 24)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("学业查询").navigationBarTitleDisplayMode(.inline)
        .task(id: environment.session.requestEpoch) { await repo.loadAcademicQuery(.terms) }
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

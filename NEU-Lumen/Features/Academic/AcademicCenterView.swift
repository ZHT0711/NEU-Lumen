import SwiftUI

struct AcademicCenterView: View {
    @Environment(AppEnvironment.self) private var environment
    private var repo: PortalRepository { environment.repository }

    var body: some View {
        List {
            Section(repo.academicTerms.first(where: { $0.current })?.name ?? "学习记录") {
                Button {
                    environment.pendingActivityURL = URL(string: "neulumen://activity/learning?section=grades")
                } label: {
                    AcademicEntryCard(title: "成绩与绩点", subtitle: "学期成绩、学分与加权均分", icon: "chart.bar.doc.horizontal")
                }.buttonStyle(.plain)
                Button {
                    environment.pendingActivityURL = URL(string: "neulumen://activity/course")
                } label: {
                    AcademicEntryCard(title: "我的课表", subtitle: "每周课程与课程详情", icon: "calendar.day.timeline.left")
                }.buttonStyle(.plain)
            }
            Section("教学安排") {
                NavigationLink { AcademicExamsView() } label: {
                    AcademicEntryCard(title: "考试安排", subtitle: "时间、地点、座位与提醒", icon: "pencil.and.list.clipboard")
                }
                NavigationLink { AcademicCalendarView() } label: {
                    AcademicEntryCard(title: "校历与周次", subtitle: "学期日期与教学周", icon: "calendar")
                }
                NavigationLink { AcademicPlanView() } label: {
                    AcademicEntryCard(title: "培养计划", subtitle: "个人方案与学分要求", icon: "list.bullet.rectangle.portrait")
                }
            }
            Section {
                NavigationLink { AcademicServicesView() } label: {
                    AcademicEntryCard(title: "全部教务功能", subtitle: "空闲教室、选课与学校业务", icon: "square.grid.2x2")
                }
            }
        }
        .navigationTitle("学业查询").navigationBarTitleDisplayMode(.inline)
        .task(id: environment.session.requestEpoch) { await repo.loadAcademicQuery(.terms) }
    }
}

struct AcademicEntryCard: View {
    let title: String
    let subtitle: String
    let icon: String
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon).font(.title3).foregroundStyle(AppTheme.accent)
                .frame(width: 36, height: 40).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.body.weight(.medium)).foregroundStyle(.primary)
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 8)
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

import SwiftUI

struct CampusIntelligenceCoordinator: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.scenePhase) private var scenePhase
    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let repo = environment.repository
            let key = repo.intelligenceRefreshKey(now: context.date, foreground: scenePhase == .active)
            Color.clear.task(id: key) {
                guard key.foreground, key.available, key.preferences.enabled, environment.session.phase == .loggedIn else { return }
                await repo.refreshIntelligenceSummaries(now: context.date)
            }
        }
        .onChange(of: environment.session.requestEpoch) { _, _ in environment.repository.intelligence.reset() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { environment.repository.intelligence.cancelPending() }
        }
    }
}

struct CampusIntelligenceDigestView: View {
    let title: String
    let digest: CampusIntelligenceStore.Digest
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: "sparkles").font(.subheadline.weight(.semibold)).foregroundStyle(AppTheme.accent)
            Text(digest.text).font(.subheadline).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
            Text(digest.caption + " · Apple 智能生成，请以原始信息为准")
                .font(.caption2).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

struct AssignmentIntelligenceSection: View {
    @Environment(AppEnvironment.self) private var environment
    var body: some View {
        if let digest = environment.repository.intelligenceDigest(for: .assignments) {
            Section {
                CampusIntelligenceDigestView(title: "临期作业速览", digest: digest)
                ForEach(environment.repository.intelligenceAssignments.prefix(5)) { item in
                    VStack(alignment: .leading, spacing: 5) {
                        Text(item.title).font(.subheadline.weight(.medium))
                        Text(item.platform + " · 截止 " + item.deadline.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}

struct CampusIntelligenceSettingsView: View {
    @Environment(AppEnvironment.self) private var environment
    var body: some View {
        @Bindable var intelligence = environment.repository.intelligence
        Form {
            if intelligence.available {
                Section {
                    Toggle("启用 Apple 智能", isOn: $intelligence.preferences.enabled)
                } footer: {
                    Text("在本机总结已同步的作业、校园新闻和已规划的路线。关闭后，各页面的智能摘要区域一并隐藏。")
                }
                if intelligence.preferences.enabled {
                    Section("显示内容") {
                        Toggle("临期作业提醒", isOn: $intelligence.preferences.assignments)
                        Toggle("东大要闻摘要", isOn: $intelligence.preferences.news)
                        Toggle("路线速览", isOn: $intelligence.preferences.journey)
                    }
                    Section {
                        NavigationLink("作业通知与提前时间") { CampusReminderView() }
                    } footer: {
                        Text("摘要仅根据已读取的信息生成，未同步的平台不会计为已完成。系统通知仍按“提醒与通知”中的设置发送。路线由地图服务计算。")
                    }
                }
            }
        }
        .navigationTitle("Apple 智能").navigationBarTitleDisplayMode(.inline)
    }
}

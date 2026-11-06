import SwiftUI

struct PlatformAssignmentsView: View {
    let platform: LearningPlatform
    var openPlatform: () -> Void
    @Environment(AppEnvironment.self) private var environment
    private var repo: PortalRepository { environment.repository }
    private var state: LoadState { repo.assignmentStates[platform] ?? .idle }
    private var sections: [LearningAssignmentSection] { repo.assignmentSections[platform] ?? [] }

    var body: some View {
        List {
            Section {
                HStack {
                    Button("同步全部作业", systemImage: "arrow.triangle.2.circlepath") {
                        Task { await repo.loadAssignments(platform, force: true) }
                    }.buttonStyle(.borderedProminent).disabled(state == .loading)
                    Spacer(minLength: 8)
                    Button("网页登录", systemImage: "globe", action: openPlatform).buttonStyle(.bordered)
                }
                if state == .loading { LoadingView(text: "正在读取\(platform.title)测验与作业…") }
                if case .failed(let message) = state {
                    ErrorStateView(message: message) { Task { await repo.loadAssignments(platform, force: true) } }
                }
                if let warning = repo.assignmentCacheWarning {
                    Text(warning).font(.caption).foregroundStyle(.orange)
                }
                if let report = repo.assignmentReports[platform] {
                    overview
                    ForEach(report.warnings, id: \.self) { warning in
                        Label(warning, systemImage: "info.circle").font(.caption).foregroundStyle(.secondary)
                    }
                    if sections.isEmpty {
                        Text("本次没有读到作业或测验，请留意同步提示。")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                } else if state != .loading {
                    Text("首次使用请在网页登录\(platform.title)。登录状态会保存在本机，之后可直接同步。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            // Each assignment is a native list row, including large single-course reports.
            ForEach(sections) { section in
                Section {
                    courseSummary(section)
                    ForEach(section.items) { item in
                        NavigationLink {
                            PortalWebViewScreen(url: item.url, learningPlatform: platform)
                        } label: { assignmentRow(item) }
                    }
                } header: { Text(section.course.title).font(.headline).textCase(nil) }
            }
        }
        .listStyle(.insetGrouped)
        .id(platform)
        .tracksTabBarScrolling()
        .task(id: platform) { await repo.loadAssignments(platform) }
        .refreshable { await repo.loadAssignments(platform, force: true) }
    }

    private var overview: some View {
        let count = sections.reduce(0) { $0 + $1.items.count }
        let completed = sections.reduce(0) { $0 + $1.completedCount }
        return VStack(alignment: .leading, spacing: 8) {
            Text("\(sections.count) 门课程 · \(count) 项作业与测验").font(.headline)
            Text("已提交或完成 \(completed) 项 · 待完成 \(count - completed) 项")
                .font(.subheadline).foregroundStyle(.secondary)
            if let updated = repo.assignmentUpdatedAt[platform] {
                Text("同步于 \(updated.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }.padding(.vertical, 4)
    }

    private func courseSummary(_ section: LearningAssignmentSection) -> some View {
        let course = section.course
        return VStack(alignment: .leading, spacing: 8) {
            Text(!section.read && section.items.isEmpty ? "作业未读取" : "作业 \(section.completedCount)/\(section.items.count)")
                .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            if platform == .chaoxing {
                if let progress = course.progress {
                    HStack {
                        Text("课程进度").font(.subheadline)
                        Spacer()
                        Text(progress.total > 0 ? progress.fraction.formatted(.percent.precision(.fractionLength(0))) : "暂无任务点")
                            .font(.subheadline.monospacedDigit())
                    }
                    if progress.total > 0 { ProgressView(value: progress.fraction) }
                    Text("已完成 \(progress.completed) / \(progress.total) 个任务点")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Text(course.progressWarning ?? "课程进度尚未读取").font(.caption).foregroundStyle(.orange)
                }
                if let deadline = course.deadline {
                    Label("课程截止 \(deadline.formatted(date: .abbreviated, time: .shortened))", systemImage: "calendar")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("平台未提供课程截止日期").font(.caption).foregroundStyle(.secondary)
                }
            }
            if section.items.isEmpty {
                Text(section.read ? "平台暂未发布作业。" : "该课程尚未读取，请结合同步提示核对。")
                    .font(.caption).foregroundStyle(.secondary)
            } else if !section.read {
                Text("本次未读取，以下保留上次同步的数据。")
                    .font(.caption).foregroundStyle(.orange)
            }
        }.padding(.vertical, 4)
    }

    private func assignmentRow(_ item: LearningAssignment) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: item.completed ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(item.completed ? .green : item.overdue ? .red : .secondary)
            VStack(alignment: .leading, spacing: 5) {
                Text(item.title).font(.subheadline.weight(.medium)).foregroundStyle(.primary)
                Text("\(item.kind) · \(item.statusText)").font(.caption).foregroundStyle(.secondary)
                if let deadline = item.deadline {
                    Text("截止 \(deadline.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption).foregroundStyle(item.overdue ? .red : .secondary)
                } else {
                    Text(item.deadlineText.isEmpty ? "平台未提供截止日期" : item.deadlineText)
                        .font(.caption).foregroundStyle(.secondary)
                }
                if !item.scoreText.isEmpty { Text("得分 \(item.scoreText)").font(.caption).foregroundStyle(.secondary) }
            }
        }.padding(.vertical, 4)
    }
}

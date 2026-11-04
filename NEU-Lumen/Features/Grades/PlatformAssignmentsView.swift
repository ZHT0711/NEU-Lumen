import SwiftUI

struct PlatformAssignmentsView: View {
    let platform: LearningPlatform
    var openPlatform: () -> Void
    @Environment(AppEnvironment.self) private var environment
    private var repo: PortalRepository { environment.repository }
    private var state: LoadState { repo.assignmentStates[platform] ?? .idle }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                Button("打开\(platform.title)登录与同步", systemImage: "globe", action: openPlatform)
                    .buttonStyle(.borderedProminent)
                if state == .loading { LoadingView(text: "正在读取\(platform.title)课程作业…") }
                if case .failed(let message) = state {
                    ErrorStateView(message: message) { Task { await repo.loadAssignments(platform, force: true) } }
                }
                if let report = repo.assignmentReports[platform] {
                    overview(report)
                    ForEach(report.warnings, id: \.self) { warning in
                        Label(warning, systemImage: "info.circle").font(.caption).foregroundStyle(.secondary)
                    }
                    ForEach(report.courses, id: \.key) { course in
                        courseCard(course, items: report.assignments.filter { $0.courseKey == course.key })
                    }
                } else if state != .loading {
                    Text("首次使用请打开平台完成登录，再点击“同步作业到学习”。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }.padding(.horizontal, 16).padding(.bottom, 32)
        }
        .id(platform)
        .tracksTabBarScrolling()
        .task(id: platform) { await repo.loadAssignments(platform) }
        .refreshable { await repo.loadAssignments(platform, force: true) }
    }

    private func overview(_ report: LearningAssignmentReport) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 8) {
                Text("\(report.courses.count) 门课程 · \(report.assignments.count) 项作业与测验").font(.headline)
                let completed = report.assignments.filter(\.completed).count
                Text("已提交或完成 \(completed) 项 · 待完成 \(report.assignments.count - completed) 项")
                    .font(.subheadline).foregroundStyle(.secondary)
                if let updated = repo.assignmentUpdatedAt[platform] {
                    Text("同步于 \(updated.formatted(date: .omitted, time: .shortened))")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }.padding(16)
        }
    }

    private func courseCard(_ course: LearningCourse, items: [LearningAssignment]) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    Text(course.title).font(.headline)
                    Spacer()
                    Text("\(items.filter(\.completed).count)/\(items.count)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
                if items.isEmpty {
                    Text("本次未读取到作业，请结合上方同步提示核对课程。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                ForEach(items.sorted { ($0.deadline ?? .distantFuture) < ($1.deadline ?? .distantFuture) }) { item in
                    NavigationLink {
                        PortalWebViewScreen(url: item.url, learningPlatform: platform)
                    } label: {
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
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                        }.padding(.vertical, 4)
                    }.buttonStyle(.plain)
                    if item.id != items.last?.id { Divider() }
                }
            }.padding(16)
        }
    }
}

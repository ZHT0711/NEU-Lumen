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
                HStack {
                    Button("同步全部作业", systemImage: "arrow.triangle.2.circlepath") {
                        Task { await repo.loadAssignments(platform, force: true) }
                    }.buttonStyle(.borderedProminent).disabled(state == .loading)
                    Spacer(minLength: 8)
                    Button("网页登录", systemImage: "globe", action: openPlatform).buttonStyle(.bordered)
                }
                if state == .loading { LoadingView(text: "正在读取\(platform.title)全部课程与作业…") }
                if case .failed(let message) = state {
                    ErrorStateView(message: message) { Task { await repo.loadAssignments(platform, force: true) } }
                }
                if let report = repo.assignmentReports[platform] {
                    let assignments = report.assignments.filter { platform != .mooc || ["作业", "测验"].contains($0.kind) }
                    let courses = report.courses.filter { course in platform != .mooc || assignments.contains { $0.courseKey == course.key } }
                    overview(courseCount: courses.count, assignments: assignments)
                    ForEach(report.warnings, id: \.self) { warning in
                        Label(warning, systemImage: "info.circle").font(.caption).foregroundStyle(.secondary)
                    }
                    if courses.isEmpty {
                        Text("本次没有读到作业或测验，请留意上方同步提示。")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    ForEach(courses, id: \.key) { course in
                        courseCard(course, items: assignments.filter { $0.courseKey == course.key },
                            read: report.refreshedCourseKeys.contains(course.key))
                    }
                } else if state != .loading {
                    Text("首次使用请在网页登录\(platform.title)，随后即可一键同步全部课程。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }.padding(.horizontal, 16).padding(.bottom, 32)
        }
        .id(platform)
        .tracksTabBarScrolling()
        .task(id: platform) { await repo.loadAssignments(platform) }
        .refreshable { await repo.loadAssignments(platform, force: true) }
    }

    private func overview(courseCount: Int, assignments: [LearningAssignment]) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 8) {
                Text("\(courseCount) 门课程 · \(assignments.count) 项作业与测验").font(.headline)
                let completed = assignments.filter(\.completed).count
                Text("已提交或完成 \(completed) 项 · 待完成 \(assignments.count - completed) 项")
                    .font(.subheadline).foregroundStyle(.secondary)
                if let updated = repo.assignmentUpdatedAt[platform] {
                    Text("同步于 \(updated.formatted(date: .omitted, time: .shortened))")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }.frame(maxWidth: .infinity, alignment: .leading).padding(16)
        }
    }

    private func courseCard(_ course: LearningCourse, items: [LearningAssignment], read: Bool) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    Text(course.title).font(.headline)
                    Spacer()
                    Text(!read && items.isEmpty ? "作业未读取" : "作业 \(items.filter(\.completed).count)/\(items.count)")
                        .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
                if platform == .chaoxing {
                    if let progress = course.progress {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("课程进度").font(.subheadline)
                                Spacer()
                                Text(progress.total > 0 ? progress.fraction.formatted(.percent.precision(.fractionLength(0))) : "暂无任务点")
                                    .font(.subheadline.monospacedDigit())
                            }
                            if progress.total > 0 { ProgressView(value: progress.fraction) }
                            Text("已完成 \(progress.completed) / \(progress.total) 个任务点")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    } else {
                        Text(course.progressWarning ?? "课程进度尚未读取").font(.caption).foregroundStyle(.orange)
                    }
                    if let deadline = course.deadline {
                        Label("课程截止 \(deadline.formatted(date: .abbreviated, time: .shortened))", systemImage: "calendar")
                            .font(.caption).foregroundStyle(.secondary)
                    } else {
                        Text("平台未提供课程截止日期").font(.caption).foregroundStyle(.secondary)
                    }
                    Divider()
                }
                if items.isEmpty {
                    Text(read ? "平台暂未发布作业。" : "该课程尚未读取，请结合上方同步提示核对。")
                        .font(.caption).foregroundStyle(.secondary)
                } else if !read {
                    Text("本次未读取，以下保留上次同步的数据。")
                        .font(.caption).foregroundStyle(.orange)
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

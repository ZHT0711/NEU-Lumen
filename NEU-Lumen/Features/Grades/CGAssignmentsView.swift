import SwiftUI

struct CGAssignmentsView: View {
    @Environment(AppEnvironment.self) private var environment
    var openPlatform: () -> Void
    private var repo: PortalRepository { environment.repository }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                if repo.cgState == .loading { LoadingView(text: "正在读取 CG 作业与完成情况…") }
                if case .failed(let message) = repo.cgState {
                    ErrorStateView(message: message) { Task { await repo.loadCGAssignments(force: true) } }
                }
                Button("打开 CG 平台登录与同步", systemImage: "globe", action: openPlatform)
                    .buttonStyle(.borderedProminent)
                if let report = repo.cgReport {
                    overview(report)
                    ForEach(report.warnings, id: \.self) { warning in
                        Label(warning, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange)
                    }
                    ForEach(report.assignments) { assignment in assignmentCard(assignment) }
                } else if repo.cgState != .loading {
                    Text("首次使用请在网页完成 CG 平台登录，再点击“同步作业到学习”。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 16).padding(.bottom, 32)
        }
        .tracksTabBarScrolling()
        .task { await repo.loadCGAssignments() }
        .refreshable { await repo.loadCGAssignments(force: true) }
    }

    private func overview(_ report: CGAssignmentReport) -> some View {
        let total = report.assignments.reduce(0) { $0 + $1.problemCount }
        let completed = report.assignments.reduce(0) { $0 + $1.completedCount }
        return GlassCard {
            VStack(alignment: .leading, spacing: 8) {
                Text(total == 0 ? "题目数据待同步" : "已完成 \(completed) / \(total) 题").font(.title3.bold())
                if total > 0 { ProgressView(value: Double(completed), total: Double(total)) }
                Text("已提交但未完全正确的题目会单独标记；展开作业可查看逐题结果。")
                    .font(.caption).foregroundStyle(.secondary)
                if report.assignments.contains(where: { !$0.loaded }) {
                    Label("部分作业未读取，完成统计尚不完整", systemImage: "exclamationmark.triangle")
                        .font(.caption).foregroundStyle(.orange)
                }
                if let updated = repo.cgUpdatedAt {
                    Text("同步于 \(updated.formatted(date: .omitted, time: .shortened))")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }.padding(16)
        }
    }

    private func assignmentCard(_ assignment: CGAssignment) -> some View {
        GlassCard {
            DisclosureGroup {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(assignment.problems) { problem in
                        if let url = problem.url {
                            NavigationLink { PortalWebViewScreen(url: url, cgMode: true) } label: { problemRow(problem) }
                                .buttonStyle(.plain)
                        } else { problemRow(problem) }
                    }
                    if assignment.problems.isEmpty { Text("尚未读取到题目，请打开平台核对。").font(.caption).foregroundStyle(.secondary) }
                }.padding(.top, 10)
            } label: {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(assignment.title).font(.headline)
                        Spacer()
                        Text(!assignment.loaded ? "未读取" : assignment.isComplete ? "全部完成" : "\(assignment.completedCount)/\(assignment.problemCount) 完成")
                            .font(.caption).foregroundStyle(assignment.isComplete ? .green : .secondary)
                    }
                    Text(assignment.deadlineText.isEmpty ? "截止日期未提供" : "截止 \(assignment.deadlineText)")
                        .font(.caption).foregroundStyle(deadlineColor(assignment))
                    if assignment.late { Text("平台允许补交").font(.caption2).foregroundStyle(.orange) }
                    if assignment.history { Text("历史作业").font(.caption2).foregroundStyle(.secondary) }
                }
            }.padding(16)
        }
    }

    private func problemRow(_ problem: CGProblem) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: problem.status == .complete ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(problem.status == .complete ? .green : .secondary)
            VStack(alignment: .leading, spacing: 4) {
                Text(problem.title).font(.subheadline.weight(.medium))
                Text(problem.statusLabel).font(.caption).foregroundStyle(problem.status == .needsWork ? .orange : .secondary)
                if !problem.scoreText.isEmpty { Text("得分 \(problem.scoreText)").font(.caption.weight(.medium)) }
                if !problem.submittedAt.isEmpty { Text("最后提交 \(problem.submittedAt)").font(.caption2).foregroundStyle(.secondary) }
                ForEach(Array(problem.testResults.enumerated()), id: \.offset) { _, result in
                    Text(result).font(.caption2).foregroundStyle(result.contains("完全正确") ? .green : .orange)
                }
                if problem.testResults.isEmpty && !problem.statusText.isEmpty {
                    Text(problem.statusText).font(.caption2).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            if problem.url != nil { Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary) }
        }.foregroundStyle(.primary)
    }

    private func deadlineColor(_ assignment: CGAssignment) -> Color {
        if !assignment.isComplete, let date = assignment.deadline, date < Date() { return .red }
        return .secondary
    }
}

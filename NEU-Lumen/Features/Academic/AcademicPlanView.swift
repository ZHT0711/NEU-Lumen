import SwiftUI

struct AcademicPlanView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var selectedPlanID: String?
    @State private var showPageSync = false
    @State private var showOriginalWeb = false
    private var repo: PortalRepository { environment.repository }
    private var plan: AcademicPlan? {
        repo.academicPlans.first { $0.id == selectedPlanID }
            ?? repo.academicPlans.first { $0.selected } ?? repo.academicPlans.first
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                AcademicNotice(text: "原生读取培养方案名称、官方修读百分比与教务未通过课程。公开学生首页接口未确认完整课程要求 / 模块学分接口，暂需用户主动网页同步。")
                AcademicQuerySection(repo: repo, key: .plans) {
                    if repo.academicPlans.isEmpty {
                        Text("教务暂未返回培养方案").foregroundStyle(.secondary)
                    } else {
                        Menu {
                            ForEach(repo.academicPlans) { item in
                                Button(item.name + (item.selected ? "（默认）" : "")) { selectedPlanID = item.id }
                            }
                        } label: {
                            Label(plan?.name ?? "选择培养方案", systemImage: "chevron.up.chevron.down").font(.headline)
                        }
                        Text("切换仅改变本页查询，不修改学校的培养方案或修读记录。")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
                if let plan {
                    AcademicQuerySection(repo: repo, key: .status(plan.id)) {
                        if case .status(let status)? = repo.academicPayload(for: .status(plan.id)) { statusDetails(status) }
                    }
                }
                GlassCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("课程与模块明细：需网页同步").font(.headline)
                        Text("在网页内正常登录，手动进入有权限的培养方案 / 学业明细课程表，再点“同步当前课程表”。仅读取已加载的表格，不自动翻页或提交。")
                            .font(.footnote).foregroundStyle(.secondary)
                        Button("只读同步当前课程表", systemImage: "arrow.down.doc") { showPageSync = true }
                            .buttonStyle(.borderedProminent)
                    }.padding(16)
                }
                if let snapshot = repo.academicPageSnapshot { pageCourses(snapshot) }
                Button("学校原始教务入口", systemImage: "globe") { showOriginalWeb = true }.buttonStyle(.bordered)
            }.padding(16).padding(.bottom, 24)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("培养计划").navigationBarTitleDisplayMode(.inline)
        .task(id: environment.session.requestEpoch) { await repo.loadAcademicQuery(.plans) }
        .task(id: (plan?.id ?? "") + environment.session.requestEpoch.uuidString) {
            if let id = plan?.id { await repo.loadAcademicQuery(.status(id)) }
        }
        .refreshable {
            await repo.loadAcademicQuery(.plans, force: true)
            if let id = plan?.id { await repo.loadAcademicQuery(.status(id), force: true) }
        }
        .sheet(isPresented: $showPageSync) { AcademicWebSyncSheet() }
        .sheet(isPresented: $showOriginalWeb) {
            NavigationStack { PortalWebViewScreen(url: AcademicWebSyncSheet.entryURL) }
        }
    }

    @ViewBuilder private func statusDetails(_ status: AcademicStudyStatus) -> some View {
        Text("官方修读进度").font(.headline)
        if let rate = status.academicRate {
            Text(rate.formatted(.number.precision(.fractionLength(0...2))) + "%")
                .font(.title2.bold()).foregroundStyle(AppTheme.accent).monospacedDigit()
            ProgressView(value: rate, total: 100)
                .accessibilityLabel("官方修读进度").accessibilityValue("\(rate.formatted()) 百分比")
        } else {
            Text("教务未提供修读百分比").foregroundStyle(.secondary)
        }
        if let count = status.unusualCount { LabeledContent("教务学业异常数", value: "\(count)") }
        Text("academicRate 是教务原始百分数，不等同于毕业资格认定；不把学业树动画值当作学分。")
            .font(.caption).foregroundStyle(.secondary)
        Divider()
        Text("教务未通过课程").font(.subheadline.bold())
        if status.hasFailedCourseList {
            if status.failedCourses.isEmpty { Text("本次教务列表为空").foregroundStyle(.secondary) }
            ForEach(status.failedCourses) { course in Text(course.name).font(.subheadline).textSelection(.enabled) }
        } else {
            Text("该接口未提供未通过课程列表").foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private func pageCourses(_ snapshot: AcademicPageSnapshot) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("已同步网页课程（\(snapshot.courses.count) 行）").font(.headline)
                Text(snapshot.title).font(.subheadline)
                Text("网页只读同步 · \(snapshot.updatedAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption).foregroundStyle(.secondary)
                AcademicNotice(text: "仅此账号当前网页已渲染的课程行；未加载分页 / 折叠内容不包含在内。不会自动关联上方方案，也不据此汇总毕业所需学分。")
                if snapshot.courses.isEmpty { Text("当前已识别表格暂无课程行").foregroundStyle(.secondary) }
            }.padding(16)
        }
        ForEach(snapshot.courses) { course in
            GlassCard {
                VStack(alignment: .leading, spacing: 8) {
                    Text(course.name).font(.headline).fixedSize(horizontal: false, vertical: true)
                    if let code = course.code { LabeledContent("课程代码", value: code) }
                    if let credits = course.creditsText { LabeledContent("表格学分", value: credits) }
                    if let module = course.module { LabeledContent("课程模块", value: module) }
                    if let status = course.studyStatus { LabeledContent("表格修读状态", value: status) }
                    if let term = course.suggestedTerm { LabeledContent("表格学期", value: term) }
                }.font(.subheadline).padding(16).textSelection(.enabled)
            }.accessibilityElement(children: .combine)
        }
    }
}

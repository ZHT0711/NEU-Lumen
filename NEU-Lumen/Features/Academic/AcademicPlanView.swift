import SwiftUI

struct AcademicSyncedCoursesView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var selectedPlanID: String?
    @State private var showPageSync = false
    @State private var query = ""
    @State private var filter: AcademicCourseStatus?
    @State private var grouping: AcademicPlanGrouping = .module
    @State private var selectedCourse: AcademicPageCourse?
    @State private var confirmClear = false
    @State private var cacheError: String?
    private var repo: PortalRepository { environment.repository }
    private var plan: AcademicPlan? {
        repo.academicPlans.first { $0.id == selectedPlanID }
            ?? repo.academicPlans.first { $0.selected } ?? repo.academicPlans.first
    }
    private var snapshot: AcademicPageSnapshot? {
        plan.flatMap { repo.academicPageSnapshot(for: $0.id) }
    }
    private var groups: [AcademicCourseGroup] {
        AcademicPlanPresentation.groups(snapshot?.courses ?? [], query: query, status: filter, grouping: grouping)
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                if let cacheError { Text(cacheError).font(.footnote).foregroundStyle(.red) }
                planSelector
                if let plan {
                    AcademicQuerySection(repo: repo, key: .status(plan.id)) {
                        if case .status(let status)? = repo.academicPayload(for: .status(plan.id)) {
                            studyProgress(status)
                        }
                    }
                    if let snapshot {
                        courseOverview(snapshot)
                        courseFilters
                        if groups.isEmpty {
                            ContentUnavailableView.search(text: query)
                        }
                        ForEach(groups) { group in courseGroup(group) }
                        Text("显示已同步的课程；未加载的分页不计入。学分合计只统计表格中明确提供的数值，不代表毕业要求。")
                            .font(.caption).foregroundStyle(.secondary)
                    } else {
                        ContentUnavailableView {
                            Label("还没有课程明细", systemImage: "list.bullet.rectangle")
                        } description: {
                            Text("首次使用请打开培养计划课程表并同步，之后可在这里离线查看、筛选和搜索。")
                        } actions: {
                            Button("同步课程明细", systemImage: "arrow.triangle.2.circlepath") { showPageSync = true }
                                .buttonStyle(.borderedProminent)
                        }
                    }
                }
            }.padding(16).padding(.bottom, 24)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("培养计划").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("同步课程明细", systemImage: "arrow.triangle.2.circlepath") { showPageSync = true }
                    if snapshot != nil {
                        Button(role: .destructive) { confirmClear = true } label: { Label("清除已同步明细", systemImage: "trash") }
                    }
                } label: { Image(systemName: "ellipsis.circle").accessibilityLabel("培养计划操作") }
                .disabled(plan == nil)
            }
        }
        .task(id: environment.session.requestEpoch) { await repo.loadAcademicQuery(.plans) }
        .task(id: (plan?.id ?? "") + environment.session.requestEpoch.uuidString) {
            if let id = plan?.id {
                repo.restoreAcademicPlan(id)
                await repo.loadAcademicQuery(.status(id))
            }
        }
        .refreshable {
            await repo.loadAcademicQuery(.plans, force: true)
            if let id = plan?.id { await repo.loadAcademicQuery(.status(id), force: true) }
        }
        .sheet(isPresented: $showPageSync) { AcademicWebSyncSheet(plan: plan) }
        .sheet(item: $selectedCourse) { course in AcademicCourseDetail(course: course) }
        .confirmationDialog("清除本方案在本机保存的课程明细？", isPresented: $confirmClear, titleVisibility: .visible) {
            Button("清除明细", role: .destructive) {
                guard let id = plan?.id else { return }
                do { try repo.clearAcademicPlan(id); cacheError = nil }
                catch { cacheError = error.localizedDescription }
            }
        } message: { Text("学校的培养方案和修读记录不受影响，可重新同步。") }
    }

    private var planSelector: some View {
        AcademicQuerySection(repo: repo, key: .plans) {
            if repo.academicPlans.isEmpty {
                Text("暂未读取到培养方案").foregroundStyle(.secondary)
            } else {
                Menu {
                    ForEach(repo.academicPlans) { item in
                        Button(item.name + (item.selected ? "（默认）" : "")) { selectedPlanID = item.id; filter = nil; query = "" }
                    }
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 5) {
                            Text("当前培养方案").font(.caption).foregroundStyle(.secondary)
                            Text(plan?.name ?? "选择方案").font(.headline).multilineTextAlignment(.leading)
                        }
                        Spacer()
                        Image(systemName: "chevron.up.chevron.down").font(.caption)
                    }
                }
            }
        }
    }

    @ViewBuilder private func studyProgress(_ status: AcademicStudyStatus) -> some View {
        HStack {
            Text("学校修读进度").font(.headline)
            Spacer()
            Text(status.academicRate.map { $0.formatted(.number.precision(.fractionLength(0...2))) + "%" } ?? "未提供")
                .font(.title3.bold()).monospacedDigit().foregroundStyle(AppTheme.accent)
        }
        if let rate = status.academicRate { ProgressView(value: rate, total: 100) }
        if status.hasFailedCourseList && !status.failedCourses.isEmpty {
            DisclosureGroup("未通过课程（\(status.failedCourses.count)）") {
                ForEach(status.failedCourses) { course in
                    Label(course.name, systemImage: "exclamationmark.circle").font(.subheadline).padding(.vertical, 4)
                }
            }.tint(.orange)
        }
        Text("进度由学校提供，毕业资格以学校审核结果为准。")
            .font(.caption).foregroundStyle(.secondary)
    }

    private func courseOverview(_ snapshot: AcademicPageSnapshot) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("已同步课程").font(.headline)
                    Spacer()
                    Text("\(snapshot.courses.count) 门").font(.headline.monospacedDigit())
                }
                HStack(spacing: 0) {
                    countColumn("已完成", snapshot.courses.filter { $0.status == .completed }.count, .green)
                    countColumn("在修", snapshot.courses.filter { $0.status == .inProgress }.count, AppTheme.accent)
                    countColumn("未修", snapshot.courses.filter { $0.status == .pending }.count, .secondary)
                    countColumn("未通过", snapshot.courses.filter { $0.status == .failed }.count, .orange)
                }
                let unknown = snapshot.courses.filter { $0.status == .unknown }.count
                if unknown > 0 { Text("\(unknown) 门课程未标注修读状态").font(.caption).foregroundStyle(.secondary) }
                Text("更新于 " + snapshot.updatedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption).foregroundStyle(.secondary)
            }.padding(16)
        }
    }

    private func countColumn(_ title: String, _ count: Int, _ tint: Color) -> some View {
        VStack(spacing: 4) {
            Text("\(count)").font(.title3.bold()).monospacedDigit().foregroundStyle(tint)
            Text(title).font(.caption).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity)
    }

    private var courseFilters: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("搜索课程、代码或模块", text: $query).textInputAutocapitalization(.never)
                if !query.isEmpty { Button { query = "" } label: { Image(systemName: "xmark.circle.fill") }.accessibilityLabel("清除课程搜索") }
            }.padding(12).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            HStack {
                Menu {
                    Button("全部状态") { filter = nil }
                    ForEach(AcademicCourseStatus.allCases) { status in Button(status.rawValue) { filter = status } }
                } label: { Label(filter?.rawValue ?? "全部状态", systemImage: "line.3.horizontal.decrease") }
                Spacer()
                Menu {
                    ForEach(AcademicPlanGrouping.allCases) { value in Button(value.rawValue) { grouping = value } }
                } label: { Label(grouping.rawValue, systemImage: "square.grid.2x2") }
            }.font(.subheadline)
        }
    }

    private func courseGroup(_ group: AcademicCourseGroup) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(group.title).font(.headline)
                Spacer()
                Text(group.unknownCredits == group.courses.count ? "学分未提供" : group.knownCredits.formatted(.number.precision(.fractionLength(0...2))) + " 已知学分")
                    .font(.caption).foregroundStyle(.secondary)
            }
            GlassCard {
                LazyVStack(spacing: 0) {
                    ForEach(Array(group.courses.enumerated()), id: \.element.id) { index, course in
                        if index > 0 { Divider().padding(.leading, 16) }
                        Button { selectedCourse = course } label: {
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(course.name).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                                        .multilineTextAlignment(.leading)
                                    Text([course.code, course.category, course.creditsText.map { $0 + " 学分" }].compactMap { $0 }.joined(separator: " · "))
                                        .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.leading)
                                }
                                Spacer(minLength: 6)
                                VStack(alignment: .trailing, spacing: 5) {
                                    Text(course.status.rawValue).font(.caption.weight(.medium))
                                        .foregroundStyle(course.status == .completed ? Color.green : Color.secondary)
                                    if let score = course.scoreText { Text(score).font(.caption.monospacedDigit()).foregroundStyle(.secondary) }
                                }
                                Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
                            }.padding(16).contentShape(Rectangle())
                        }.buttonStyle(.plain).accessibilityElement(children: .combine)
                    }
                }
            }
        }
    }
}

struct AcademicCourseDetail: View {
    let course: AcademicPageCourse
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(course.name).font(.title3.bold()).textSelection(.enabled)
                    LabeledContent("修读状态", value: course.studyStatus ?? "未标注")
                }
                Section("课程信息") {
                    detail("课程代码", course.code); detail("课程性质", course.category)
                    detail("所属模块", course.module); detail("建议学期", course.suggestedTerm)
                    detail("学分", course.creditsText); detail("学时", course.hoursText)
                    detail("成绩", course.scoreText); detail("考核方式", course.assessment)
                }
            }.navigationTitle("课程详情").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
        }
    }
    @ViewBuilder private func detail(_ title: String, _ value: String?) -> some View {
        if let value, !value.isEmpty { LabeledContent(title, value: value).textSelection(.enabled) }
    }
}

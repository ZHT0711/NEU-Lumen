import SwiftUI

/// 学习：CG 作业进度与截止日期，以及教务成绩和学分统计。
struct GradesView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var selectedSemesterID: String?
    @State private var showAcademicWeb = false
    @State private var showAssignmentWeb = false
    @State private var section = "作业"
    @State private var platform = LearningPlatform.cg

    private var repo: PortalRepository {
        environment.repository
    }

    private var currentSemester: GradeSemester? {
        repo.grades.first { $0.id == selectedSemesterID }
            ?? repo.grades.first { $0.current && !$0.courses.isEmpty }
            ?? repo.grades.first { !$0.courses.isEmpty }
            ?? repo.grades.first { $0.current }
            ?? repo.grades.first
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("学习内容", selection: $section) {
                    Text("作业").tag("作业")
                    Text("成绩").tag("成绩")
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16).padding(.vertical, 10)
                if section == "作业" {
                    Picker("作业平台", selection: $platform) {
                        ForEach(LearningPlatform.allCases) { platform in Text(platform.title).tag(platform) }
                    }
                    .pickerStyle(.segmented).padding(.horizontal, 16).padding(.bottom, 12)
                    if platform == .cg { CGAssignmentsView { showAssignmentWeb = true } }
                    else { PlatformAssignmentsView(platform: platform) { showAssignmentWeb = true } }
                } else {
                    gradesContent
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("学习")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    NavigationLink {
                        AcademicCenterView()
                    } label: {
                        Label("教务查询", systemImage: "graduationcap.fill")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(section == "作业" ? platform.title : "教务网页", systemImage: "globe") {
                        if section == "作业" { showAssignmentWeb = true } else { showAcademicWeb = true }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task {
                            if section == "作业" { await repo.loadAssignments(platform, force: true) }
                            else { await repo.loadGrades(force: true) }
                        }
                    } label: { Image(systemName: "arrow.clockwise") }
                    .disabled(section == "作业" ? (platform == .cg ? repo.cgState : repo.assignmentStates[platform]) == .loading : repo.gradesState == .loading)
                    .accessibilityLabel("刷新学习数据")
                }
            }
            .task(id: section) {
                await repo.ensureLoadedForCurrentUser()
                if section == "成绩" { await repo.loadGrades() }
            }
        }
        .onChange(of: environment.pendingLearningSection, initial: true) { _, target in
            guard let target else { return }
            section = target == "成绩" ? "成绩" : "作业"
            environment.pendingLearningSection = nil
        }
        .sheet(isPresented: $showAcademicWeb) {
            NavigationStack {
                PortalWebViewScreen(url: URL(string: PortalClient.jwxtBase + "/jwapp/sys/homeapp/index.do")!, academicMode: true)
            }
        }
        .sheet(isPresented: $showAssignmentWeb) {
            NavigationStack {
                PortalWebViewScreen(url: platform == .cg ? repo.cgEntryURL : platform.entryURL,
                    cgMode: platform == .cg, learningPlatform: platform == .cg ? nil : platform)
            }
        }
    }

    private var gradesContent: some View {
        Group {
            switch repo.gradesState {
            case .idle, .loading:
                LoadingView(text: "正在从教务系统同步成绩…")
            case .failed(let message):
                VStack(spacing: 8) {
                    ErrorStateView(message: message) {
                        Task { await repo.loadGrades(force: true) }
                    }
                    Button("打开教务网页并同步成绩", systemImage: "globe") { showAcademicWeb = true }
                        .buttonStyle(.borderedProminent)
                    Text("网页内完成认证后，点击“同步成绩到应用”。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .padding()
            case .loaded:
                if let semester = currentSemester {
                    content(semester)
                } else {
                    ErrorStateView(message: "暂无成绩数据") {
                        Task { await repo.loadGrades(force: true) }
                    }
                }
            }
        }
        .refreshable {
            await repo.loadGrades(force: true)
        }
    }

    private func content(_ semester: GradeSemester) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                semesterPicker
                if let warning = repo.gradesWarning {
                    Label(warning, systemImage: "exclamationmark.circle")
                        .font(.footnote).foregroundStyle(.orange)
                }
                statTiles(semester)
                if semester.courses.isEmpty {
                    ContentUnavailableView("本学期暂无成绩", systemImage: "doc.text", description: Text("可以切换到其他学期查看已公布的成绩。"))
                }
                GlassCard {
                    VStack(spacing: 0) {
                        ForEach(Array(semester.courses.enumerated()), id: \.element.id) { index, course in
                            GradeRow(course: course)
                            if index < semester.courses.count - 1 {
                                Divider().padding(.leading, 14)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 32)
        }
        .tracksTabBarScrolling()
    }

    private var semesterPicker: some View {
        Menu {
            ForEach(repo.grades) { semester in
                Button {
                    selectedSemesterID = semester.id
                } label: {
                    if semester.id == currentSemester?.id {
                        Label(semester.name, systemImage: "checkmark")
                    } else {
                        Text(semester.name)
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Text(currentSemester?.name ?? "选择学期")
                    .font(.headline)
                    .foregroundStyle(.primary)
                Image(systemName: "chevron.down")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func statTiles(_ semester: GradeSemester) -> some View {
        HStack(spacing: 10) {
            statTile("GPA", String(format: "%.2f", semester.gpa))
            statTile("加权平均分", String(format: "%.1f", semester.weightedAvg))
            statTile("总学分", String(format: "%.1f", semester.credits))
        }
    }

    private func statTile(_ title: String, _ value: String) -> some View {
        GlassCard(cornerRadius: 16) {
            VStack(spacing: 6) {
                Text(value)
                    .font(.title3.bold())
                    .foregroundStyle(AppTheme.accent)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text(title)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
        }
    }
}

struct GradeRow: View {
    let course: GradeCourse

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(course.name)
                    .font(.subheadline.bold())
                    .lineLimit(1)
                HStack(spacing: 6) {
                    if !course.category.isEmpty {
                        Text(course.category)
                            .font(.system(size: 9))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(AppTheme.accent.opacity(0.1), in: Capsule())
                    }
                    Text("学分 \(String(format: "%.1f", course.credit))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Text(course.scoreText)
                .font(.title3.bold())
                .foregroundStyle(AppTheme.accent)
                .monospacedDigit()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}

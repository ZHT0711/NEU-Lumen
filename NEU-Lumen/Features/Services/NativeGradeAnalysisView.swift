import SwiftUI
import Charts

struct NativeGradeAnalysisView: View {
    var active = true
    @Environment(AppEnvironment.self) private var environment
    @State private var term = ""
    @State private var recordFilter = "未及格"
    private var repo: PortalRepository { environment.repository }
    private var analysis: GradeAnalysis {
        GradeAnalysis(courses: repo.grades.filter { term.isEmpty || $0.id == term }.flatMap(\.courses))
    }

    var body: some View {
        List {
            Section {
                Picker("分析学期", selection: $term) {
                    Text("全部学期").tag("")
                    ForEach(repo.grades) { Text($0.name).tag($0.id) }
                }
                ServiceLoadNotice(state: repo.gradesState)
                if let warning = repo.gradesWarning { Text(warning).font(.caption).foregroundStyle(.orange) }
            }
            if !repo.grades.isEmpty {
                Section {
                    LabeledContent("成绩记录", value: "\(analysis.courses.count) 门")
                    LabeledContent("已折算成绩", value: "\(analysis.scored.count) 门")
                    LabeledContent("成绩记录学分", value: analysis.gradedCredits.formatted(.number.precision(.fractionLength(0...2))))
                    LabeledContent("通过记录学分", value: analysis.passedCredits.formatted(.number.precision(.fractionLength(0...2))))
                    LabeledContent("加权均分", value: analysis.weightedAverage?.formatted(.number.precision(.fractionLength(2))) ?? "未提供可折算成绩")
                } header: { Text("成绩概览") } footer: {
                    Text("按学校返回的成绩记录统计，每条补修或重修记录分别计入。毕业学分要求可在培养计划中核对。")
                }
                Section("分数分布") {
                    Chart(analysis.bands) { band in
                        BarMark(x: .value("分数段", band.title), y: .value("课程数", band.count))
                            .foregroundStyle(Color.blue.gradient)
                    }
                    .frame(height: 180).padding(.vertical, 8)
                    .accessibilityLabel("课程成绩分布")
                }
                Section("学期均分") {
                    ForEach(repo.grades) { semester in
                        let value = GradeAnalysis(courses: semester.courses)
                        if let average = value.weightedAverage {
                            LabeledContent(semester.name, value: average.formatted(.number.precision(.fractionLength(2))))
                        }
                    }
                }
                Section {
                    Picker("成绩记录筛选", selection: $recordFilter) {
                        Text("未及格").tag("未及格")
                        Text("状态记录").tag("状态记录")
                    }.pickerStyle(.segmented)
                    let rows = recordFilter == "未及格" ? analysis.failed : analysis.statusRecords
                    if rows.isEmpty { Text("当前范围没有此类记录").foregroundStyle(.secondary) }
                    ForEach(Array(rows.enumerated()), id: \.offset) { _, course in
                        LabeledContent(course.name, value: course.scoreText)
                    }
                } header: { Text("需要留意的记录") } footer: {
                    Text("缓考、待公布等文字状态单独列出，分数和学分沿用教务记录。")
                }
            } else if repo.gradesState == .loaded {
                ContentUnavailableView("暂无成绩记录", systemImage: "chart.bar.xaxis")
            }
            Section {
                Button("重新同步成绩", systemImage: "arrow.clockwise") { Task { await repo.loadGrades(force: true) } }
                    .disabled(repo.gradesState == .loading)
                NavigationLink { AcademicPlanView() } label: { Label("查看培养计划", systemImage: "list.bullet.rectangle") }
            }
        }
        .task(id: String(active) + environment.session.requestEpoch.uuidString) {
            guard active else { return }
            await repo.ensureLoadedForCurrentUser()
            await repo.loadGrades()
        }
        .onChange(of: environment.session.requestEpoch) { _, _ in term = ""; recordFilter = "未及格" }
        .refreshable { await repo.loadGrades(force: true) }
        .navigationTitle("成绩分析").navigationBarTitleDisplayMode(.inline)
        .privacySensitive()
    }
}

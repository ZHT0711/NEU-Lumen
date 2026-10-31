import SwiftUI

/// 成绩：教务系统真实数据，全部学期 + GPA / 加权平均分 / 学分统计。
struct GradesView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var selectedSemesterID: String?

    private var repo: PortalRepository {
        environment.repository
    }

    private var currentSemester: GradeSemester? {
        repo.grades.first { $0.id == selectedSemesterID }
            ?? repo.grades.first { $0.current }
            ?? repo.grades.first
    }

    var body: some View {
        NavigationStack {
            Group {
                switch repo.gradesState {
                case .idle, .loading:
                    LoadingView(text: "正在从教务系统同步成绩…")
                case .failed(let message):
                    ErrorStateView(message: message) {
                        Task { await repo.loadGrades(force: true) }
                    }
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
            .background(Color(.systemGroupedBackground))
            .navigationTitle("成绩")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await repo.loadGrades(force: true) }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
            .task {
                await repo.ensureLoadedForCurrentUser()
                await repo.loadGrades()
            }
            .refreshable {
                await repo.loadGrades(force: true)
            }
        }
    }

    private func content(_ semester: GradeSemester) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                semesterPicker
                statTiles(semester)
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

// Explicitly synthetic screenshot helper. Only copied to the disposable Debug app.
import SwiftUI
import WebKit

extension View {
    func nativeUIFixtureCaption(_ caption: String) -> some View {
        safeAreaInset(edge: .bottom) {
            Text(caption).font(.caption).foregroundStyle(.secondary).padding(6)
                .frame(maxWidth: .infinity).background(.regularMaterial)
        }
    }
}

@MainActor
func seedAcademicUIValidation(_ environment: AppEnvironment) async throws {
    let repo = environment.repository
    await repo.ensureLoadedForCurrentUser()
    guard let account = repo.academicRequestContext?.account else {
        throw NetworkError(message: "Synthetic academic preview has no isolated account context")
    }
    let now = Date()
    let day = AcademicQueryPolicy.schoolDay(now)
    let term = AcademicTerm(code: "SYNTH-TERM", name: "合成学期 · UI 验证", current: true)
    let plan = AcademicPlan(id: "SYNTH-PLAN", name: "合成培养方案 · UI 验证", selected: true)
    let page = AcademicPageSnapshot(account: account, title: "合成培养课程表 · 非真实账号数据",
        sourceURL: URL(string: "https://jwxt.neu.edu.cn/jwapp/sys/synthetic/index.html")!,
        courses: [AcademicPageCourse(id: "SYNTH-C-1", name: "合成课程：支持大字体多行展示",
            code: "SYNTH-C-1", creditsText: "2.5", module: "合成基础模块", studyStatus: "已修读", suggestedTerm: "合成第一学期",
            category: "合成必修", hoursText: "40", scoreText: "90", assessment: "合成考试"),
            AcademicPageCourse(id: "SYNTH-C-2", name: "合成课程：程序设计基础",
                code: "SYNTH-C-2", creditsText: "3", module: "合成专业模块", studyStatus: "在修", suggestedTerm: "合成第二学期", category: "合成必修"),
            AcademicPageCourse(id: "SYNTH-C-3", name: "合成课程：校园通识",
                code: "SYNTH-C-3", creditsText: "2", module: "合成通识模块", studyStatus: "未修", suggestedTerm: "合成第三学期", category: "合成选修")],
        recognizedTables: 1, updatedAt: now)
    #if DEBUG
    repo.seedAcademicPreview([
        .terms: .terms([term]),
        .calendar(term.code): .calendar(AcademicCalendarDetails(termCode: term.code,
            startDate: "2031-09-08", endDate: "2032-01-18",
            holidays: [AcademicHolidayRange(startDate: "2031-10-01", endDate: "2031-10-03")])),
        .week(day): .week(AcademicWeek(day: day, value: "9")),
        .plans: .plans([plan]),
        .status(plan.id): .status(AcademicStudyStatus(planID: plan.id, academicRate: 62.5, unusualCount: 1,
            failedCourses: [AcademicStatusCourse(id: "SYNTH-FAIL", name: "合成未通过课程")], hasFailedCourseList: true))
    ], page: page, updatedAt: now)
    #else
    throw NetworkError(message: "Academic fixture must never run in Release")
    #endif
}

@MainActor
func verifyAcademicUIValidation(_ environment: AppEnvironment) throws {
    let repo = environment.repository
    let keys: [AcademicQueryKey] = [.terms, .plans, .calendar("SYNTH-TERM"),
        .week(AcademicQueryPolicy.schoolDay(Date())), .status("SYNTH-PLAN")]
    guard environment.session.phase == .loggedIn,
          keys.allSatisfy({ repo.academicState(for: $0) == .loaded && repo.academicPayload(for: $0) != nil }),
          repo.academicTerms.first?.code == "SYNTH-TERM", repo.academicPlans.first?.id == "SYNTH-PLAN",
          repo.academicPageSnapshot?.courses.first?.id == "SYNTH-C-1" else {
        throw NetworkError(message: "Native academic screenshots lost their explicit DEBUG synthetic seed")
    }
}

@MainActor
final class ProgramViewportValidation {
    static let shared = ProgramViewportValidation()
    var content = CGRect.zero
    var viewport = CGRect.zero
    var fits: Bool {
        content.width > 0 && content.height > 0 && viewport.width > 0 && viewport.height > 0 &&
            viewport.insetBy(dx: -1, dy: -1).contains(content)
    }
}

@MainActor
func writeNativeUIValidationMarker(screen: String, environment: AppEnvironment) async {
    guard screen.hasPrefix("academic-") else { return }
    let output = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        .appendingPathComponent(screen + "-screenshot.txt")
    do {
        try await Task.sleep(for: .milliseconds(300))
        try verifyAcademicUIValidation(environment)
        if screen == "academic-plan" {
            for _ in 0..<40 where !ProgramViewportValidation.shared.fits {
                try await Task.sleep(for: .milliseconds(50))
            }
            guard ProgramViewportValidation.shared.fits else {
                throw NetworkError(message: "Actual rendered program branches exceed the viewport: \(ProgramViewportValidation.shared.content) / \(ProgramViewportValidation.shared.viewport)")
            }
        }
        try "PASS: actual native \(screen) mounted; explicit DEBUG synthetic academic seed only; no real account or network data"
            .write(to: output, atomically: true, encoding: .utf8)
    } catch {
        try? ("FAIL: " + error.localizedDescription).write(to: output, atomically: true, encoding: .utf8)
    }
}

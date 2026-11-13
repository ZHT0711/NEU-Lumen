import Foundation

enum AcademicCourseStatus: String, CaseIterable, Identifiable {
    case completed = "已完成", inProgress = "在修", pending = "未修", failed = "未通过", unknown = "未标注"
    var id: String { rawValue }
}

extension AcademicPageCourse {
    /// 使用表格明确的修读状态；不按未知课程的及格线猜测毕业完成情况。
    var status: AcademicCourseStatus {
        let value = (studyStatus ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if ["在修", "修读中", "学习中", "已选", "重修中"].contains(where: value.contains) { return .inProgress }
        if ["未通过", "不及格", "不合格", "挂科", "未达标"].contains(where: value.contains) { return .failed }
        if ["未修", "待修", "未选", "未完成"].contains(where: value.contains) { return .pending }
        if ["已修", "完成", "通过", "免修", "合格", "已获得"].contains(where: value.contains) { return .completed }
        return .unknown
    }

    var credits: Double? {
        guard let raw = creditsText?.replacingOccurrences(of: "学分", with: "").trimmingCharacters(in: .whitespaces),
              raw.range(of: #"^\d+(\.\d+)?$"#, options: .regularExpression) != nil,
              let value = Double(raw), value.isFinite, value >= 0, value <= 100 else { return nil }
        return value
    }

    func matches(_ query: String) -> Bool {
        let key = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return key.isEmpty || [name, code, module, suggestedTerm, category, studyStatus]
            .compactMap { $0 }.contains { $0.localizedCaseInsensitiveContains(key) }
    }
}

enum AcademicPlanGrouping: String, CaseIterable, Identifiable {
    case module = "课程模块", term = "建议学期", category = "课程性质"
    var id: String { rawValue }
    func title(for course: AcademicPageCourse) -> String {
        let value: String?
        switch self { case .module: value = course.module; case .term: value = course.suggestedTerm; case .category: value = course.category }
        return value?.isEmpty == false ? value! : "未标注" + rawValue
    }
}

struct AcademicCourseGroup: Identifiable {
    let title: String
    let courses: [AcademicPageCourse]
    var id: String { title }
    var knownCredits: Double { courses.compactMap(\.credits).reduce(0, +) }
    var unknownCredits: Int { courses.filter { $0.credits == nil }.count }
}

enum AcademicPlanPresentation {
    static func merge(_ previous: [AcademicPageCourse], _ incoming: [AcademicPageCourse]) -> [AcademicPageCourse] {
        func key(_ course: AcademicPageCourse) -> String {
            [course.code ?? course.name, course.module ?? "", course.suggestedTerm ?? ""].joined(separator: "\u{0}")
        }
        var result: [AcademicPageCourse] = []
        var positions: [String: Int] = [:]
        for course in previous + incoming {
            let id = key(course)
            if let index = positions[id] { result[index] = course }
            else { positions[id] = result.count; result.append(course) }
        }
        // Page-local row numbers repeat across pages; UI identities must be unique after merging.
        return result.enumerated().map { index, row in
            AcademicPageCourse(id: String(index), name: row.name, code: row.code, creditsText: row.creditsText,
                module: row.module, studyStatus: row.studyStatus, suggestedTerm: row.suggestedTerm,
                category: row.category, hoursText: row.hoursText, scoreText: row.scoreText, assessment: row.assessment)
        }
    }
    static func groups(_ courses: [AcademicPageCourse], query: String, status: AcademicCourseStatus?,
                       grouping: AcademicPlanGrouping) -> [AcademicCourseGroup] {
        let rows = courses.filter { $0.matches(query) && (status == nil || $0.status == status) }
        let grouped = Dictionary(grouping: rows) { grouping.title(for: $0) }
        return grouped.keys.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
            .map { AcademicCourseGroup(title: $0, courses: grouped[$0] ?? []) }
    }
}

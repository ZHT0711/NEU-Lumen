import Foundation

enum LearningPlatform: String, CaseIterable, Identifiable {
    case cg, mooc, chaoxing
    var id: String { rawValue }
    var title: String {
        switch self {
        case .cg: "NEUCSECG"
        case .mooc: "慕课"
        case .chaoxing: "学习通"
        }
    }
    var entryURL: URL {
        switch self {
        case .cg: URL(string: "http://neucsecg.neu.edu.cn")!
        case .mooc: URL(string: "https://www.icourse163.org/home.htm#/home/course")!
        case .chaoxing: URL(string: "https://i.chaoxing.com/")!
        }
    }
    func accepts(_ url: URL) -> Bool {
        let host = (url.host ?? "").lowercased()
        switch self {
        case .cg: return host == "neucsecg.neu.edu.cn"
        case .mooc: return host == "www.icourse163.org" || host == "icourse163.org"
        case .chaoxing: return host == "chaoxing.com" || host.hasSuffix(".chaoxing.com")
        }
    }
}

struct LearningCourse: Identifiable, Codable, Hashable {
    let id: String
    let termID: String
    let title: String
    let url: URL
    var key: String { id + "." + termID }
}

struct LearningAssignment: Identifiable, Codable, Hashable {
    let id: String
    let courseKey: String
    let courseTitle: String
    let title: String
    let kind: String
    let url: URL
    let deadline: Date?
    let deadlineText: String
    let statusText: String
    let completed: Bool
    let scoreText: String
    var overdue: Bool { !completed && deadline.map { $0 < Date() } == true }
}

struct LearningAssignmentReport {
    var courses: [LearningCourse]
    var assignments: [LearningAssignment]
    var warnings: [String]
    /// Failed courses retain their previous rows when the user retries a partial sync.
    var refreshedCourseKeys: Set<String>
    var accountKey = ""

    func merging(_ previous: LearningAssignmentReport?) -> LearningAssignmentReport {
        guard let previous, previous.accountKey == accountKey else { return self }
        var report = self
        let keys = Set(courses.map(\.key))
        report.courses += previous.courses.filter { !keys.contains($0.key) }
        let freshIDs = Set(assignments.map(\.id))
        report.assignments += previous.assignments.filter {
            !refreshedCourseKeys.contains($0.courseKey) && !freshIDs.contains($0.id)
        }
        return report
    }

    static func decodeRows(_ raw: Any, platform: LearningPlatform) throws -> [LearningAssignment] {
        guard let rows = raw as? [[String: Any]] else { throw NetworkError(message: "作业返回格式异常") }
        return try rows.map { row in
            guard let id = row["id"] as? String, !id.isEmpty,
                  let link = row["url"] as? String, let url = URL(string: link),
                  ["http", "https"].contains(url.scheme ?? ""), platform.accepts(url),
                  let title = row["title"] as? String, !title.isEmpty,
                  let key = row["courseKey"] as? String else { throw NetworkError(message: "作业记录缺少有效字段") }
            let epoch = row["deadline"] as? Double
            return LearningAssignment(id: id, courseKey: key, courseTitle: row["courseTitle"] as? String ?? "",
                title: title, kind: row["kind"] as? String ?? "作业", url: url,
                deadline: epoch.flatMap { $0 > 0 ? Date(timeIntervalSince1970: $0 / 1000) : nil },
                deadlineText: row["deadlineText"] as? String ?? "",
                statusText: row["statusText"] as? String ?? "完成情况待确认",
                completed: row["completed"] as? Bool ?? false, scoreText: row["scoreText"] as? String ?? "")
        }
    }
}

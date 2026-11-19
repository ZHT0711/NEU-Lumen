import Foundation

enum LearningPlatform: String, CaseIterable, Identifiable, Codable {
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

    func ownsCookie(_ cookie: HTTPCookie) -> Bool {
        let host = cookie.domain.trimmingCharacters(in: CharacterSet(charactersIn: ".")).lowercased()
        guard let url = URL(string: "https://" + host) else { return false }
        if accepts(url) { return true }
        switch self {
        case .mooc: return host == "163.com" || host.hasSuffix(".163.com")
        case .cg: return host == "webvpn.neu.edu.cn"
        case .chaoxing: return false
        }
    }
}

struct LearningCourse: Identifiable, Codable, Hashable {
    let id: String
    let termID: String
    let title: String
    let url: URL
    var activeTermID: String? = nil
    var progress: LearningCourseProgress? = nil
    var deadline: Date? = nil
    var progressWarning: String? = nil
    var key: String { id + "." + termID }
}

struct LearningCourseProgress: Codable, Hashable {
    let completed: Int
    let total: Int
    var fraction: Double { total > 0 ? Double(completed) / Double(total) : 0 }

    /// The gear response contains both chapter aggregates and knowledge nodes.
    /// Count each leaf once so parent totals cannot inflate course progress.
    static func chaoxing(_ payload: Any, courseID: String) throws -> LearningCourseProgress {
        func records(_ raw: Any?) -> [[String: Any]] {
            if let rows = raw as? [[String: Any]] { return rows }
            guard let object = raw as? [String: Any] else { return [] }
            if let data = object["data"] ?? object["msg"] { return records(data) }
            return [object]
        }
        let classes = records(payload)
        let courses = classes.flatMap { records($0["course"]) }
        guard let course = courses.first(where: { String(describing: $0["id"] ?? "") == courseID }),
              course["knowledge"] != nil else { throw NetworkError(message: "课程进度返回格式异常") }
        let nodes = records(course["knowledge"])
        if nodes.isEmpty { return LearningCourseProgress(completed: 0, total: 0) }
        let parents = Set(nodes.compactMap { $0["parentnodeid"].map { String(describing: $0) } })
        let leaves = nodes.filter { !parents.contains(String(describing: $0["id"] ?? "")) }
        var seen = Set<String>()
        var completed = 0
        var total = 0
        func count(_ raw: Any?) -> Int? {
            guard let raw, let value = Int(String(describing: raw)), value >= 0 else { return nil }
            return value
        }
        for node in leaves {
            guard let id = node["id"], seen.insert(String(describing: id)).inserted else { continue }
            let finished = count(node["finishcount"] ?? node["jobFinishedCount"])
            let unfinished = count(node["unfinishcount"] ?? node["jobUnfinishedCount"])
            let all = count(node["jobcount"]) ?? finished.flatMap { f in unfinished.map { f + $0 } }
            guard let all, let done = finished ?? unfinished.map({ all - $0 }), done >= 0, done <= all else {
                throw NetworkError(message: "平台未提供完整的课程任务点统计")
            }
            completed += done
            total += all
        }
        guard !seen.isEmpty else { throw NetworkError(message: "课程任务点未读取") }
        return LearningCourseProgress(completed: completed, total: total)
    }

    static func chaoxingDeadline(_ raw: Any?) -> Date? {
        guard let raw else { return nil }
        let text = String(describing: raw).trimmingCharacters(in: .whitespacesAndNewlines)
        if let value = Double(text), value > 0 {
            return Date(timeIntervalSince1970: value > 100_000_000_000 ? value / 1000 : value)
        }
        if let date = ISO8601DateFormatter().date(from: text) { return date }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
        for format in ["yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd HH:mm", "yyyy-MM-dd"] {
            formatter.dateFormat = format
            if let date = formatter.date(from: text.replacingOccurrences(of: "/", with: "-")) {
                return format == "yyyy-MM-dd" ? date.addingTimeInterval(86_399) : date
            }
        }
        return nil
    }
}

enum MOOCReadError: LocalizedError, Equatable {
    case authenticationRequired
    case unsupportedContentType
    case invalidCourseList

    var errorDescription: String? {
        switch self {
        case .authenticationRequired: "慕课会话未登录或已失效，请打开慕课网页登录"
        case .unsupportedContentType: "慕课课程接口不接受本次请求格式，请稍后重试"
        case .invalidCourseList: "慕课返回了无法识别的课程列表，已保留上次同步"
        }
    }
}

struct MOOCCoursePage {
    let courses: [LearningCourse]
    let hasMore: Bool
    /// The platform can return a well-formed empty first page to a guest.
    let requiresAccountConfirmation: Bool

    /// Both signed-in and guest list responses can wrap the paginated result twice.
    static func decode(_ data: Data, page: Int, pageSize: Int, courseType: Int = 1) throws -> MOOCCoursePage {
        guard let envelope = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            throw MOOCReadError.invalidCourseList
        }
        let code = integer(envelope["code"])
        let message = ((envelope["message"] ?? envelope["msg"]) as? String ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if code == 401 || ["未登录", "请先登录", "登录已失效", "登录已过期", "not logged in"].contains(where: message.contains) {
            throw MOOCReadError.authenticationRequired
        }
        if code == 415 || message.hasPrefix("不支持类型") || message.hasPrefix("unsupported media type") {
            throw MOOCReadError.unsupportedContentType
        }
        guard (code == nil || code == 0), let result = envelope["result"] as? [String: Any] else {
            throw MOOCReadError.invalidCourseList
        }
        let pagination = result["pagination"] as? [String: Any] ?? [:]
        let total = integer(pagination["total"] ?? pagination["totleCount"] ?? pagination["totalCount"])
        if result["result"] is NSNull, page > 1 || total == 0 {
            return MOOCCoursePage(courses: [], hasMore: false, requiresAccountConfirmation: page == 1)
        }
        guard let rows = result["result"] as? [[String: Any]] else {
            throw MOOCReadError.invalidCourseList
        }
        let courses = try rows.map { row -> LearningCourse in
            let term = row["termPanel"] as? [String: Any] ?? [:]
            let school = row["schoolPanel"] as? [String: Any] ?? [:]
            let id = String(describing: row["id"] ?? "")
            let tid = String(describing: term["id"] ?? "")
            guard id.range(of: #"^[1-9]\d*$"#, options: .regularExpression) != nil,
                  tid.range(of: #"^[1-9]\d*$"#, options: .regularExpression) != nil,
                  let abbreviation = school["shortName"] as? String,
                  abbreviation.range(of: #"^[A-Za-z0-9_-]+$"#, options: .regularExpression) != nil else {
                throw NetworkError(message: "部分慕课课程缺少学校或学期信息，课程列表未取全")
            }
            let key = abbreviation + "-" + id
            let mode = row["mode"] as? Int ?? (courseType == 2 ? 20 : 0)
            let prefix = mode == 0 ? "/learn/" : "/spoc/learn/"
            let url = URL(string: "https://www.icourse163.org" + prefix + key + "?tid=" + tid)!
            return LearningCourse(id: key, termID: tid, title: row["name"] as? String ?? key, url: url)
        }
        let reachedTotal = total.map { page * pageSize >= $0 } ?? false
        return MOOCCoursePage(courses: courses, hasMore: rows.count >= pageSize && !reachedTotal,
                              requiresAccountConfirmation: page == 1 && courses.isEmpty)
    }

    private static func integer(_ value: Any?) -> Int? {
        (value as? Int) ?? (value as? String).flatMap { Int($0) }
    }
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

struct LearningAssignmentReport: Codable {
    var courses: [LearningCourse]
    var assignments: [LearningAssignment]
    var warnings: [String]
    /// Failed courses retain their previous rows when the user retries a partial sync.
    var refreshedCourseKeys: Set<String>
    var accountKey = ""

    func sections(for platform: LearningPlatform) -> [LearningAssignmentSection] {
        let rows = assignments.filter { platform != .mooc || ["作业", "测验"].contains($0.kind) }
        let grouped = Dictionary(grouping: rows, by: \.courseKey)
        return courses.compactMap { course in
            let items = (grouped[course.key] ?? []).sorted {
                if $0.deadline == $1.deadline { return $0.id < $1.id }
                return ($0.deadline ?? .distantFuture) < ($1.deadline ?? .distantFuture)
            }
            guard platform != .mooc || !items.isEmpty else { return nil }
            return LearningAssignmentSection(course: course, items: items,
                completedCount: items.filter(\.completed).count, read: refreshedCourseKeys.contains(course.key))
        }
    }

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

struct LearningAssignmentSection: Identifiable {
    let course: LearningCourse
    let items: [LearningAssignment]
    let completedCount: Int
    let read: Bool
    var id: String { course.key }
}

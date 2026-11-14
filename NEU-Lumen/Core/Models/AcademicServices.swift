import Foundation

struct AcademicServiceItem: Identifiable, Equatable {
    let id: String
    let title: String
    let category: String
    let path: String
    let url: URL?
    var isSchoolAcademicPage: Bool { url?.host == "jwxt.neu.edu.cn" }
}

struct AcademicExam: Identifiable, Equatable {
    let id: String
    let title: String
    let dateText: String
    let timeText: String
    let place: String
    let teachers: String
    let seat: String
    let type: String
    let start: Date?
}

enum AcademicServiceParser {
    /// Framework menus.do supplies the current role's complete tree. No fixed menu list.
    static func menus(_ raw: Any) throws -> [AcademicServiceItem] {
        let data = try AcademicQueryParser.payload(raw, title: "教务功能目录")
        guard let rows = data as? [[String: Any]], rows.count <= 1000 else { throw AcademicQueryError.invalid("教务功能目录") }
        var result: [AcademicServiceItem] = [], count = 0
        func visit(_ nodes: [[String: Any]], ancestors: [String], ids: [String], depth: Int) throws {
            guard depth <= 20 else { throw AcademicQueryError.invalid("教务功能层级") }
            for (index, row) in nodes.enumerated() {
                count += 1
                guard count <= 2000, let title = AcademicQueryParser.scalar(row["menuName"]), !title.isEmpty else { throw AcademicQueryError.invalid("教务功能目录") }
                let id = AcademicQueryParser.scalar(row["menuId"]) ?? String(index)
                let children = row["children"] as? [[String: Any]] ?? []
                if !children.isEmpty { try visit(children, ancestors: ancestors + [title], ids: ids + [id], depth: depth + 1); continue }
                let app = AcademicQueryParser.scalar(row["appName"]) ?? ""
                let code = AcademicQueryParser.scalar(row["menuCode"]) ?? ""
                let entry = AcademicQueryParser.scalar(row["entry"]) ?? ""
                let url: URL?
                if !entry.isEmpty { url = schoolURL(entry) }
                else if app.range(of: #"^[a-zA-Z][a-zA-Z0-9_]*$"#, options: .regularExpression) != nil,
                        !code.isEmpty, code.count < 256, !code.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) {
                    var parts = URLComponents(string: "https://jwxt.neu.edu.cn/jwapp/sys/" + app + "/*default/index.do")!
                    parts.queryItems = [URLQueryItem(name: "forceApp", value: app), URLQueryItem(name: "EMAP_LANG", value: "zh")]
                    parts.fragment = "/" + code
                    url = parts.url
                } else { url = nil }
                result.append(.init(id: (ids + [id, String(index)]).joined(separator: ":"), title: title,
                    category: ancestors.first ?? "其他功能", path: (ancestors + [title]).joined(separator: " › "), url: url))
            }
        }
        try visit(rows, ancestors: [], ids: [], depth: 0)
        return result
    }
    static func schoolURL(_ value: String) -> URL? {
        let base = URL(string: "https://jwxt.neu.edu.cn/jwapp/")!
        let path = value.hasPrefix("/sys/") ? "/jwapp" + value : value
        guard value.count <= 4096, !value.hasPrefix("#"),
              !value.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }),
              let url = URL(string: path, relativeTo: base)?.absoluteURL,
              ["http", "https"].contains(url.scheme?.lowercased() ?? ""), url.user == nil, url.password == nil,
              url.host?.isEmpty == false else { return nil }
        return url
    }
    /// Verified student/exams.do fields used by the school's studentTab renderer.
    static func exams(_ raw: Any, term: String) throws -> [AcademicExam] {
        let data = try AcademicQueryParser.payload(raw, title: "考试安排")
        guard let rows = data as? [[String: Any]], rows.count <= 3000 else { throw AcademicQueryError.invalid("考试安排") }
        return try rows.enumerated().map { index, row in
            guard let title = AcademicQueryParser.scalar(row["courseDesc"]), !title.isEmpty else { throw AcademicQueryError.invalid("考试安排") }
            let date = AcademicQueryParser.scalar(row["examDate"]) ?? ""
            let time = AcademicQueryParser.scalar(row["startTime"]) ?? ""
            let description = AcademicQueryParser.scalar(row["examTimeDescription"]) ?? time
            return AcademicExam(id: term + ":" + (AcademicQueryParser.scalar(row["taskId"]) ?? String(index)), title: title,
                dateText: date, timeText: description, place: AcademicQueryParser.scalar(row["examPlace"]) ?? "",
                teachers: AcademicQueryParser.scalar(row["teachers"]) ?? "", seat: AcademicQueryParser.scalar(row["examSeatNo"]) ?? "",
                type: AcademicQueryParser.scalar(row["examType"]) ?? "", start: examDate(day: date, time: time))
        }
    }
    static func examDate(day: String, time: String) -> Date? {
        guard let date = AcademicQueryPolicy.schoolDate(String(day.prefix(10))),
              time.range(of: #"^\d{1,2}:\d{2}(:\d{2})?$"#, options: .regularExpression) != nil else { return nil }
        let components = time.split(separator: ":").compactMap { Int($0) }
        guard components.count >= 2, (0...23).contains(components[0]), (0...59).contains(components[1]),
              components.count < 3 || (0...59).contains(components[2]) else { return nil }
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return calendar.date(bySettingHour: components[0], minute: components[1], second: components.count == 3 ? components[2] : 0, of: date)
    }
}

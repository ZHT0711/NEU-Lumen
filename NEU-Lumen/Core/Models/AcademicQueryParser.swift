import Foundation

/// 精确读取官方 datas envelope，不把未知结构或失败响应压成空列表。
enum AcademicQueryParser {
    static func decode(_ raw: Any, key: AcademicQueryKey) throws -> AcademicQueryPayload {
        let data = try payload(raw, title: key.title)
        switch key {
        case .terms:
            let rows = try records(data, title: key.title)
            var seen = Set<String>()
            let terms = try rows.map { row -> AcademicTerm in
                let code = try required(row["itemCode"], title: key.title)
                guard seen.insert(code).inserted else { throw AcademicQueryError.invalid(key.title) }
                return AcademicTerm(code: code, name: scalar(row["itemName"]) ?? code,
                                    current: flag(row["selected"]) == true)
            }
            return .terms(terms)
        case .plans:
            let rows = try records(data, title: key.title)
            var seen = Set<String>()
            let plans = try rows.map { row -> AcademicPlan in
                let id = try required(row["planId"], title: key.title)
                guard seen.insert(id).inserted else { throw AcademicQueryError.invalid(key.title) }
                return AcademicPlan(id: id, name: scalar(row["planName"]) ?? id,
                                    selected: flag(row["selected"]) == true)
            }
            return .plans(plans)
        case .calendar(let code):
            let row = try optionalMap(data, title: key.title)
            let start = try optionalScalar(row["startDate"], title: key.title)
            let end = try optionalScalar(row["endDate"], title: key.title)
            let holidays: [AcademicHolidayRange]
            if let rawHolidays = row["holidays"], !(rawHolidays is NSNull) {
                holidays = try records(rawHolidays, title: "校历假期").map { holiday in
                    AcademicHolidayRange(startDate: try required(holiday["startDate"], title: "校历假期"),
                                         endDate: try required(holiday["endDate"], title: "校历假期"))
                }
            } else { holidays = [] }
            return .calendar(AcademicCalendarDetails(termCode: code, startDate: start, endDate: end, holidays: holidays))
        case .week(let day):
            let row = try optionalMap(data, title: key.title)
            return .week(AcademicWeek(day: day, value: try optionalScalar(row["classWeek"], title: key.title)))
        case .status(let planID):
            let row = try optionalMap(data, title: key.title)
            let rate = try optionalNumber(row["academicRate"], title: key.title)
            if let rate, !(0...100).contains(rate) { throw AcademicQueryError.invalid(key.title) }
            let unusual = try optionalNumber(row["academicUnusual"], title: key.title)
            if let unusual, unusual < 0 || unusual > 1_000_000 || unusual.rounded() != unusual {
                throw AcademicQueryError.invalid(key.title)
            }
            let hasList = row["flunkList"] != nil && !(row["flunkList"] is NSNull)
            let failed = hasList ? try records(row["flunkList"], title: "教务未通过课程").enumerated().map { index, item in
                AcademicStatusCourse(id: (scalar(item["courseId"]) ?? "") + "|\(index)",
                                     name: try required(item["courseName"], title: "教务未通过课程"))
            } : []
            return .status(AcademicStudyStatus(planID: planID, academicRate: rate,
                unusualCount: unusual.map { Int($0) }, failedCourses: failed, hasFailedCourseList: hasList))
        }
    }

    static func validateIdentity(_ raw: Any, expectedAccount: String) throws {
        let data = try payload(raw, title: "教务身份")
        guard let map = data as? [String: Any], let account = scalar(map["userId"]),
              AcademicQueryPolicy.acceptsPageAccount(account, expected: expectedAccount) else {
            throw AcademicQueryError.accountMismatch
        }
    }

    static func payload(_ raw: Any, title: String) throws -> Any {
        guard let map = raw as? [String: Any], let code = scalar(map["code"]) else {
            throw AcademicQueryError.invalid(title)
        }
        if ["401", "-401"].contains(code) { throw AcademicQueryError.authenticationRequired }
        if code == "403" { throw AcademicQueryError.forbidden }
        guard code == "0" else {
            let message = scalar(map["msg"]) ?? ""
            if message.contains("未登录") || message.contains("登录失效") || message.contains("会话失效") {
                throw AcademicQueryError.authenticationRequired
            }
            throw AcademicQueryError.business(title)
        }
        guard let data = map["datas"] else { throw AcademicQueryError.invalid(title) }
        return data
    }

    private static func records(_ raw: Any?, title: String) throws -> [[String: Any]] {
        guard let array = raw as? [Any] else { throw AcademicQueryError.invalid(title) }
        return try array.map { item in
            guard let row = item as? [String: Any] else { throw AcademicQueryError.invalid(title) }
            return row
        }
    }

    private static func optionalMap(_ raw: Any, title: String) throws -> [String: Any] {
        if raw is NSNull { return [:] }
        if let empty = raw as? [Any], empty.isEmpty { return [:] }
        guard let map = raw as? [String: Any] else { throw AcademicQueryError.invalid(title) }
        return map
    }

    static func scalar(_ raw: Any?) -> String? {
        let value: String
        if let text = raw as? String { value = text }
        else if let number = raw as? NSNumber, String(cString: number.objCType) != "c", number.doubleValue.isFinite {
            value = number.stringValue
        } else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty || trimmed.count > 4096 ? nil : trimmed
    }

    private static func required(_ raw: Any?, title: String) throws -> String {
        guard let text = scalar(raw) else { throw AcademicQueryError.invalid(title) }
        return text
    }

    private static func optionalScalar(_ raw: Any?, title: String) throws -> String? {
        guard let raw, !(raw is NSNull) else { return nil }
        if let text = raw as? String, text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return nil }
        return try required(raw, title: title)
    }

    private static func optionalNumber(_ raw: Any?, title: String) throws -> Double? {
        guard let raw, !(raw is NSNull) else { return nil }
        if let text = raw as? String, text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return nil }
        guard let text = scalar(raw), let number = Double(text), number.isFinite else {
            throw AcademicQueryError.invalid(title)
        }
        return number
    }

    private static func flag(_ raw: Any?) -> Bool? {
        if let value = raw as? NSNumber, String(cString: value.objCType) == "c" { return value.boolValue }
        guard let value = scalar(raw)?.lowercased() else { return nil }
        if ["true", "1"].contains(value) { return true }
        if ["false", "0"].contains(value) { return false }
        return nil
    }
}

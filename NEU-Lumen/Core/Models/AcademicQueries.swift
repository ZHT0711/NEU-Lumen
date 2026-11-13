import Foundation

/// 2026-11-12 核对官方 home/index.html → umi.c0e3fcc9.js（C2cd / Cio5 / O2sj）。
/// 所有请求均为官方 GET；不调用学业树的 collect-growthvalue / record-failscore 等写接口。
enum AcademicQueryKey: Hashable {
    case terms
    case calendar(String)
    case week(String)
    case plans
    case status(String)

    var title: String {
        switch self {
        case .terms: return "学期列表"
        case .calendar: return "校历日期"
        case .week: return "教务周次"
        case .plans: return "培养方案"
        case .status: return "修读进度"
        }
    }

    /// 只接受从已读取的学期 / 方案列表选择的参数；日期使用上海时区的日历日。
    var path: String {
        get throws {
            switch self {
            case .terms: return "api/home/student/schoolCalendars.do"
            case .plans: return "api/home/student/educational-program.do"
            case .calendar(let code):
                return "api/home/homeSchoolCalendar.do?termCode=" + (try Self.encode(code))
            case .status(let id):
                return "api/home/student/academic-status.do?planId=" + (try Self.encode(id))
            case .week(let day):
                guard AcademicQueryPolicy.schoolDate(day) != nil, day.count == 10 else {
                    throw AcademicQueryError.invalid("教务周次日期")
                }
                return "api/home/teachingSchedule/classWeek.do?rq=" + day
            }
        }
    }

    private static func encode(_ value: String) throws -> String {
        guard !value.isEmpty, value.utf8.count <= 256,
              !value.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
            throw AcademicQueryError.invalid("教务查询参数")
        }
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")
        guard let encoded = value.addingPercentEncoding(withAllowedCharacters: allowed) else {
            throw AcademicQueryError.invalid("教务查询参数")
        }
        return encoded
    }
}

struct AcademicTerm: Identifiable, Equatable {
    let code: String
    let name: String
    let current: Bool
    var id: String { code }
}

struct AcademicHolidayRange: Identifiable, Equatable {
    let startDate: String
    let endDate: String
    var id: String { startDate + "|" + endDate }
}

struct AcademicCalendarDetails: Equatable {
    let termCode: String
    let startDate: String?
    let endDate: String?
    let holidays: [AcademicHolidayRange]
    /// 结构化接口不是学校发布的校历图片，不包含图片中的全部事件。
    var hasStructuredDates: Bool { startDate != nil || endDate != nil || !holidays.isEmpty }
}

struct AcademicWeek: Equatable {
    let day: String
    /// classWeek 的原始标量值；缺失不是第 0 周，也不按个人校准推算。
    let value: String?
}

struct AcademicPlan: Identifiable, Equatable {
    let id: String
    let name: String
    let selected: Bool
}

struct AcademicStatusCourse: Identifiable, Equatable {
    let id: String
    let name: String
}

struct AcademicStudyStatus: Equatable {
    let planID: String
    /// 官方 academicRate 已以百分数显示；不是自行按课程数量推算的毕业判定。
    let academicRate: Double?
    let unusualCount: Int?
    let failedCourses: [AcademicStatusCourse]
    let hasFailedCourseList: Bool
}

enum AcademicQueryPayload {
    case terms([AcademicTerm])
    case calendar(AcademicCalendarDetails)
    case week(AcademicWeek)
    case plans([AcademicPlan])
    case status(AcademicStudyStatus)
}

struct AcademicPageCourse: Identifiable, Equatable {
    let id: String
    let name: String
    let code: String?
    let creditsText: String?
    let module: String?
    let studyStatus: String?
    let suggestedTerm: String?
}

/// 仅属于一次已验证账号的当前可见网页，不与某个方案自动关联，不声明完整培养计划。
struct AcademicPageSnapshot {
    let account: String
    let title: String
    let sourceURL: URL
    let courses: [AcademicPageCourse]
    let recognizedTables: Int
    let updatedAt: Date
}

enum AcademicQueryError: LocalizedError, Equatable {
    case authenticationRequired
    case forbidden
    case invalid(String)
    case business(String)
    case accountMismatch

    var errorDescription: String? {
        switch self {
        case .authenticationRequired: return "教务会话已失效，请在正常网页登录后重试"
        case .forbidden: return "教务查询权限不足，请检查校园网 / WebVPN 或使用学校原始入口"
        case .invalid(let title): return "\(title)返回格式暂不支持，保留上次结果；可打开教务网页查看"
        case .business(let title): return "\(title)未能读取，请重试或打开教务网页查看"
        case .accountMismatch: return "网页账号与应用账号不一致或无法确认，请关闭网页并使用当前账号重新认证"
        }
    }
}

enum AcademicQueryPolicy {
    static func isFresh(_ date: Date?, key: AcademicQueryKey, now: Date = Date()) -> Bool {
        guard let date else { return false }
        let age = now.timeIntervalSince(date)
        let lifetime: TimeInterval
        if case .week = key { lifetime = 300 } else { lifetime = 900 }
        return age >= 0 && age < lifetime
    }

    static func schoolDay(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    static func schoolDate(_ raw: String) -> Date? {
        guard raw.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.isLenient = false
        guard let date = formatter.date(from: raw), formatter.string(from: date) == raw else { return nil }
        return date
    }

    static func acceptsPageAccount(_ pageAccount: String, expected: String) -> Bool {
        !expected.isEmpty && pageAccount == expected
    }

    /// Native requests may use WebVPN, but callers must unwrap both URLs first.
    /// A successful envelope from another endpoint (or a lost term / plan query)
    /// must not be labelled as the requested academic resource.
    static func acceptsResponseURL(_ actual: URL, expected: URL) -> Bool {
        guard let source = URLComponents(url: actual, resolvingAgainstBaseURL: false),
              let request = URLComponents(url: expected, resolvingAgainstBaseURL: false),
              ["http", "https"].contains(source.scheme?.lowercased() ?? ""),
              source.scheme?.lowercased() == request.scheme?.lowercased(),
              source.host?.lowercased() == "jwxt.neu.edu.cn",
              source.host?.lowercased() == request.host?.lowercased(),
              source.port == request.port, source.user == nil, source.password == nil,
              source.path == request.path, source.path.hasPrefix("/jwapp/sys/homeapp/") else { return false }
        return source.queryItems == request.queryItems
    }

    static func allows(_ key: AcademicQueryKey, terms: [AcademicTerm], plans: [AcademicPlan]) -> Bool {
        switch key {
        case .calendar(let code): return terms.contains { $0.code == code }
        case .status(let id): return plans.contains { $0.id == id }
        case .terms, .plans: return true
        case .week(let day): return schoolDate(day) != nil
        }
    }
}

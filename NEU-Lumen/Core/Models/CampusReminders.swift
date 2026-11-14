import Foundation

enum CampusReminderKind: String, Codable, CaseIterable, Identifiable {
    case course, exam, planner, assignment, balance, grades, affairs, mail, news, daily, custom
    var id: String { rawValue }
    var title: String {
        switch self {
        case .course: "上课提醒"
        case .exam: "考试提醒"
        case .planner: "本机日程"
        case .assignment: "作业与测验截止"
        case .balance: "余额与电量不足"
        case .grades: "成绩更新"
        case .affairs: "办事进度变化"
        case .mail: "邮箱未读变化"
        case .news: "校园资讯更新"
        case .daily: "每日安排提醒"
        case .custom: "自定义提醒"
        }
    }
    var symbol: String {
        switch self {
        case .course: "book.closed"
        case .exam: "pencil.and.list.clipboard"
        case .planner, .daily: "calendar.badge.clock"
        case .assignment: "checklist"
        case .balance: "bolt.circle"
        case .grades: "chart.bar.doc.horizontal"
        case .affairs: "list.clipboard"
        case .mail: "envelope.badge"
        case .news: "newspaper"
        case .custom: "bell.badge"
        }
    }
}

struct CampusReminderPreferences: Codable, Equatable {
    var enabled = false
    var background = true
    var backgroundLearning = true
    var backgroundMail = true
    var systemEvents = false
    var kinds = Set(CampusReminderKind.allCases.filter { $0 != .news && $0 != .daily }.map(\.rawValue))
    var courseLead = 15
    var examLead = 60
    var plannerLead = 30
    var assignmentLead = 120
    var assignmentDayBefore = true
    var cardThreshold = 20.0
    var netThreshold = 10.0
    var electricityThreshold = 10.0
    var dailyHour = 20
    var dailyMinute = 0
    var quiet = false
    var quietStart = 22
    var quietEnd = 8
    var detailsOnLockScreen = true
    var sound = true

    func allows(_ kind: CampusReminderKind) -> Bool { enabled && kinds.contains(kind.rawValue) }
    mutating func set(_ kind: CampusReminderKind, enabled: Bool) {
        if enabled { kinds.insert(kind.rawValue) } else { kinds.remove(kind.rawValue) }
    }
}

struct CampusReminderCandidate: Identifiable, Codable, Equatable {
    var id: String
    var kind: CampusReminderKind
    var title: String
    var body: String
    var fireAt: Date
    var destination: String
    var eventAt: Date? = nil
    var read = false
    var cancelled = false
    var sourceKey: String? = nil

    var url: URL {
        switch destination {
        case "mail", "affairs", "academic", "news":
            return URL(string: "neulumen://activity/services?native=" + destination)!
        case "course", "card", "learning", "profile", "reminders":
            return URL(string: "neulumen://activity/" + destination)!
        default: return URL(string: "neulumen://activity/reminders")!
        }
    }
}

struct CampusReminderChange: Equatable {
    let id: String
    let kind: CampusReminderKind
    let fingerprint: String
    let title: String
    let body: String
    let destination: String
    let updatedAt: Date
    var notifyFirst = false
}

struct CampusReminderSnapshot: Equatable {
    var planned: [CampusReminderCandidate] = []
    var changes: [CampusReminderChange] = []
    var readySources: Set<String> = []
}

struct CampusPersonalReminder: Identifiable, Codable, Equatable {
    var id = UUID().uuidString
    var title: String
    var body = ""
    var date: Date
    var kind: CampusReminderKind = .custom
    var destination = "reminders"
    var candidate: CampusReminderCandidate {
        .init(id: "personal:" + id, kind: kind, title: title, body: body, fireAt: date, destination: destination, sourceKey: "personal")
    }
}

enum CampusReminderPolicy {
    static let maximumPending = 60
    static let horizonDays = 14
    static var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return value
    }
    static func clock(day: Date, minutes: Int) -> Date? {
        // The displayed timetable day and school clock, even while travelling abroad.
        let components = Calendar.current.dateComponents([.year, .month, .day], from: day)
        guard let base = calendar.date(from: components) else { return nil }
        return calendar.date(byAdding: .minute, value: minutes, to: base)
    }
    static func timed(id: String, kind: CampusReminderKind, title: String, body: String, event: Date,
                      lead: Int, destination: String) -> CampusReminderCandidate {
        .init(id: id + ":" + String(Int(event.timeIntervalSince1970)) + ":" + String(lead), kind: kind,
              title: title, body: body, fireAt: event.addingTimeInterval(-Double(max(0, lead)) * 60), destination: destination, eventAt: event)
    }
    static func planned(_ source: [CampusReminderCandidate], preferences: CampusReminderPreferences,
                        now: Date) -> [CampusReminderCandidate] {
        guard preferences.enabled else { return [] }
        let end = calendar.date(byAdding: .day, value: horizonDays, to: now)!
        var seen = Set<String>()
        return source.compactMap { original -> CampusReminderCandidate? in
            guard preferences.allows(original.kind), !original.id.isEmpty, seen.insert(original.id).inserted,
                  original.fireAt.timeIntervalSinceReferenceDate.isFinite, original.fireAt > now,
                  original.kind == .custom || original.fireAt <= end else { return nil }
            var item = original
            // Time-bound lessons/exams/deadlines stay at the chosen time. Quiet hours
            // defer only optional changes and daily digests, without making a late reminder.
            if preferences.quiet, [.balance, .grades, .affairs, .mail, .news, .daily].contains(item.kind),
               (0...23).contains(preferences.quietStart), (0...23).contains(preferences.quietEnd),
               preferences.quietStart != preferences.quietEnd {
                let hour = calendar.component(.hour, from: item.fireAt)
                let start = preferences.quietStart, finish = preferences.quietEnd
                let inside = start < finish ? (hour >= start && hour < finish) : (hour >= start || hour < finish)
                if inside {
                    var day = calendar.startOfDay(for: item.fireAt)
                    if start > finish, hour >= start { day = calendar.date(byAdding: .day, value: 1, to: day)! }
                    item.fireAt = calendar.date(byAdding: .hour, value: finish, to: day)!
                }
            }
            item.title = String(item.title.prefix(100)); item.body = String(item.body.prefix(500))
            return item
        }.sorted {
            $0.fireAt == $1.fireAt ? $0.id < $1.id : $0.fireAt < $1.fireAt
        }.prefix(maximumPending).map { $0 }
    }
    static func reconciled(_ incoming: [CampusReminderCandidate], previous: [CampusReminderCandidate],
                           readySources: Set<String>, history: [CampusReminderCandidate],
                           preferences: CampusReminderPreferences, now: Date) -> [CampusReminderCandidate] {
        let ready = readySources.union(["personal"])
        let retained = previous.filter { !$0.cancelled && $0.fireAt > now && !ready.contains($0.sourceKey ?? "unread") }
        let fired = Set(history.filter { !$0.cancelled && $0.fireAt <= now }.map(\.id))
        return planned((incoming + retained).filter { !fired.contains($0.id) }, preferences: preferences, now: now)
    }
}

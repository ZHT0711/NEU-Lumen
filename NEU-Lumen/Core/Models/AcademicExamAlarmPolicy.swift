import Foundation

struct AcademicExamAlarmTarget: Equatable, Codable, Hashable {
    let owner: String
    let term: String
    let examID: String
}

struct AcademicExamAlarmRecord: Identifiable, Equatable, Codable {
    let id: UUID
    let target: AcademicExamAlarmTarget
    let examStart: Date
    let fireAt: Date
    var needsCancellation = false
}

enum AcademicExamAlarmPolicy {
    static let leadOptions = [60, 30, 15, 5, 0]

    static func fireDate(examStart: Date, leadMinutes: Int, now: Date) -> Date? {
        guard leadOptions.contains(leadMinutes) else { return nil }
        let date = examStart.addingTimeInterval(-Double(leadMinutes * 60))
        return date > now ? date : nil
    }

    static func invalidates(_ record: AcademicExamAlarmRecord, owner: String, term: String, examStart: Date?) -> Bool {
        record.target.owner == owner && record.target.term == term && record.examStart != examStart
    }
}

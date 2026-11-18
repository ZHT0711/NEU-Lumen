import Foundation

let exam = Date(timeIntervalSince1970: 1_800_000_000)
let early = exam.addingTimeInterval(-5400)

precondition(AcademicExamAlarmPolicy.leadOptions == [60, 30, 15, 5, 0])
for minutes in AcademicExamAlarmPolicy.leadOptions {
    let expected = exam.addingTimeInterval(-Double(minutes * 60))
    precondition(AcademicExamAlarmPolicy.fireDate(examStart: exam, leadMinutes: minutes, now: early) == expected)
    precondition(AcademicExamAlarmPolicy.fireDate(examStart: exam, leadMinutes: minutes, now: expected) == nil)
}
precondition(AcademicExamAlarmPolicy.fireDate(examStart: exam, leadMinutes: -10, now: early) == nil)
precondition(AcademicExamAlarmPolicy.fireDate(examStart: exam, leadMinutes: Int.max, now: early) == nil)

let target = AcademicExamAlarmTarget(owner: "owner-A", term: "term", examID: "exam-A")
let record = AcademicExamAlarmRecord(id: UUID(), target: target, examStart: exam, fireAt: early)
precondition(!AcademicExamAlarmPolicy.invalidates(record, owner: "owner-A", term: "term", examStart: exam))
precondition(AcademicExamAlarmPolicy.invalidates(record, owner: "owner-A", term: "term", examStart: exam.addingTimeInterval(60)))
precondition(AcademicExamAlarmPolicy.invalidates(record, owner: "owner-A", term: "term", examStart: nil))
precondition(!AcademicExamAlarmPolicy.invalidates(record, owner: "owner-B", term: "term", examStart: nil))
precondition(!AcademicExamAlarmPolicy.invalidates(record, owner: "owner-A", term: "another-term", examStart: nil))

var awaitingCancellation = record
awaitingCancellation.needsCancellation = true
let persisted = try JSONEncoder().encode([record, awaitingCancellation])
let restored = try JSONDecoder().decode([AcademicExamAlarmRecord].self, from: persisted)
precondition(restored == [record, awaitingCancellation])

print("PASS: exam alarm absolute offsets, account/term scoped invalidation and persistent cancellation")

import Foundation

func date(_ text: String) -> Date { ISO8601DateFormatter().date(from: text)! }
let now = date("2026-11-14T04:00:00Z")
var preferences = CampusReminderPreferences()
preferences.enabled = true
func item(_ id: String, _ fire: Date, _ kind: CampusReminderKind = .course) -> CampusReminderCandidate {
    .init(id: id, kind: kind, title: id, body: "合成通知测试", fireAt: fire, destination: "course")
}
let past = item("past", now.addingTimeInterval(-1))
let soon = item("soon", now.addingTimeInterval(60))
let later = item("later", now.addingTimeInterval(3600))
let planned = CampusReminderPolicy.planned([later, past, soon, soon], preferences: preferences, now: now)
precondition(planned.map(\.id) == ["soon", "later"])
preferences.enabled = false
precondition(CampusReminderPolicy.planned([soon], preferences: preferences, now: now).isEmpty)
preferences.enabled = true; preferences.set(.course, enabled: false)
precondition(CampusReminderPolicy.planned([soon], preferences: preferences, now: now).isEmpty)
preferences.set(.course, enabled: true)
let many = (1...100).reversed().map { item(String($0), now.addingTimeInterval(Double($0) * 60)) }
precondition(CampusReminderPolicy.planned(many, preferences: preferences, now: now).count == 60)
precondition(CampusReminderPolicy.planned(many, preferences: preferences, now: now).first?.id == "1")
let distant = now.addingTimeInterval(90 * 86400)
precondition(CampusReminderPolicy.planned([item("custom", distant, .custom), item("course", distant)], preferences: preferences, now: now).map(\.id) == ["custom"])

preferences.quiet = true; preferences.quietStart = 22; preferences.quietEnd = 8
let night = date("2026-11-14T15:00:00Z") // 23:00 Shanghai
let morning = date("2026-11-15T00:00:00Z")
let quiet = CampusReminderPolicy.planned([item("grade", night, .grades), item("exam", night, .exam)], preferences: preferences, now: now)
precondition(quiet.first { $0.id == "grade" }?.fireAt == morning)
precondition(quiet.first { $0.id == "exam" }?.fireAt == night)
preferences.quietStart = 8; preferences.quietEnd = 18
let midday = date("2026-11-14T05:00:00Z")
precondition(CampusReminderPolicy.planned([item("grade", midday, .grades)], preferences: preferences, now: now).first?.fireAt == date("2026-11-14T10:00:00Z"))
preferences.quietStart = preferences.quietEnd
precondition(CampusReminderPolicy.planned([item("grade", midday, .grades)], preferences: preferences, now: now).first?.fireAt == midday)

let timed = CampusReminderPolicy.timed(id: "assignment", kind: .assignment, title: "合成作业", body: "", event: later.fireAt, lead: 15, destination: "learning")
precondition(timed.fireAt == later.fireAt.addingTimeInterval(-900) && timed.eventAt == later.fireAt)
precondition(timed.url.absoluteString == "neulumen://activity/learning")
var route = soon; route.destination = "mail"
precondition(route.url.absoluteString == "neulumen://activity/services?native=mail")
route.destination = "https://external.invalid"
precondition(route.url.absoluteString == "neulumen://activity/reminders")
let encoded = try JSONEncoder().encode(preferences)
let decodedPreferences = try JSONDecoder().decode(CampusReminderPreferences.self, from: encoded)
precondition(decodedPreferences == preferences)
var retained = soon; retained.sourceKey = "week:synthetic"
let offline = CampusReminderPolicy.reconciled([], previous: [retained], readySources: [], history: [], preferences: preferences, now: now)
precondition(offline == [retained], "An unread source must keep previously scheduled reminders")
let updatedSource = CampusReminderPolicy.reconciled([], previous: [retained], readySources: ["week:synthetic"], history: [], preferences: preferences, now: now)
precondition(updatedSource.isEmpty, "A successfully read empty schedule must cancel obsolete reminders")
var fired = soon; fired.fireAt = now.addingTimeInterval(-1)
precondition(CampusReminderPolicy.reconciled([soon], previous: [], readySources: [], history: [fired], preferences: preferences, now: now).isEmpty)
print("Reminders: source switches, chronological cap, deduplication, school quiet hours, unshifted deadlines, distant personal reminders and safe routes passed")

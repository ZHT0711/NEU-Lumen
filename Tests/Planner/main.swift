import Foundation

enum PortalClient { static let portalBase = "https://personal.neu.edu.cn/portal" }

func occurrence(_ day: String, _ name: String = "数学", kind: String = "course") -> CourseOccurrence {
    let date = PortalDate.day(day)!
    return CourseOccurrence(date: date, slot: CourseSlot(weekday: PlannerEvent.mondayBasedWeekday(date),
        startMinutes: 510, endMinutes: 610, name: name, room: "A101", kind: kind))
}

let html = #"""
<INPUT VALUE='20260042' NAME='username' TYPE='HIDDEN'>
<input name=timestamp value=123456 type=hidden>
<input name='auid' value='x&#x2b;y&#61;z&amp;t' type='hidden'>
<input value="9.20" id='ContentPlaceHolder1_txtOddFare'>
<input data-name='wrong' data-value='wrong' name='actual' value=''>
<input name='greater' value='a>b'>
"""#
let fields = HTMLInputFields.parse(html)
precondition(fields.count == 6)
precondition(fields[0]["name"] == "username" && fields[0]["value"] == "20260042" && fields[0]["hidden"] == "1")
precondition(fields[1]["value"] == "123456" && fields[1]["hidden"] == "1")
precondition(fields[2]["value"] == "x+y=z&t")
precondition(fields[3]["id"] == "ContentPlaceHolder1_txtOddFare" && fields[3]["value"] == "9.20")
precondition(fields[4]["name"] == "actual" && fields[4]["value"] == "")
precondition(fields[5]["value"] == "a>b")
precondition(HTMLInputFields.decode("&#20013;&#x56fd;&quot;&apos;") == "中国\"'")
print("Card form parser: mixed quoting, unquoted fields, hidden inputs, entities and attribute boundaries passed")

let year = HolidayYear.bundled2026
precondition(year.days.filter(\.isOffDay).count == 33)
precondition(year.days.filter { !$0.isOffDay }.count == 6)
let roundTrip = try HolidayYear.decode(JSONEncoder().encode(year), year: 2026)
precondition(roundTrip.days == year.days)
do {
    _ = try HolidayYear.decode(JSONEncoder().encode(year), year: 2027)
    preconditionFailure("必须拒绝年份不符的数据")
} catch {}
do {
    _ = try HolidayYear.decode(Data(#"{"year":2026,"days":[{"name":"假日","date":"2026-02-30","isOffDay":true}]}"#.utf8), year: 2026)
    preconditionFailure("必须拒绝非法日期")
} catch {}
let days = Dictionary(uniqueKeysWithValues: year.days.map { ($0.date, $0) })
let classes = [occurrence("2026-10-01"), occurrence("2026-10-01", "考试", kind: "exam"),
               occurrence("2026-10-01", "约会", kind: "custom"), occurrence("2026-10-10")]
precondition(HolidayRules.apply(classes, enabled: true, days: days, overrides: [:]).count == 3)
precondition(HolidayRules.apply(classes, enabled: false, days: days, overrides: [:]).count == 4)
precondition(HolidayRules.apply(classes, enabled: true, days: days, overrides: ["2026-10-01": .normal]).count == 4)
precondition(HolidayRules.apply(classes, enabled: false, days: days, overrides: ["2026-10-10": .rest]).count == 3)
let source = occurrence("2026-09-28", "参照日课程")
let projected = HolidayRules.project(classes + [source], from: PortalDate.day("2026-09-28")!, to: PortalDate.day("2026-10-05")!,
                                    replacements: ["2026-10-01": "2026-09-28"])
precondition(projected.count == 4, "保留原日期、考试及自定义事项，替换目标日课程")
precondition(projected.contains { PortalDate.isoDay($0.date) == "2026-10-01" && $0.slot.name == "参照日课程" && $0.slot.weekday == 4 })
let sunday = occurrence("2026-10-04")
precondition(HolidayRules.project([sunday], from: PortalDate.day("2026-09-28")!, to: PortalDate.day("2026-10-05")!, replacements: [:]).count == 1)
print("Holiday policy: 33 rest days, 6 work days, validation, overrides, exams, custom events, makeup and Sunday passed")

@MainActor func testStores() {
    let suite = "lumen.tests." + UUID().uuidString
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let apps = (1...10).map { PortalApp(name: "服务\($0)", appId: String($0), url: "", mobileUrl: "", iconUrl: "", desc: "", category: "测试", visits: 0) }
    let favorites = ServiceFavorites(defaults: defaults)
    favorites.activate(account: "A", apps: apps)
    precondition(favorites.ids.count == 8)
    favorites.toggle(apps[9])
    favorites.move(from: IndexSet(integer: 8), to: 0)
    precondition(favorites.apps(in: apps).first == apps[9])
    favorites.activate(account: "B", apps: apps)
    precondition(!favorites.contains(apps[9]), "不同账号独立")
    favorites.activate(account: "A", apps: apps)
    precondition(favorites.ids.first == "10")
    favorites.move(from: IndexSet([0, 2]), to: 5)
    precondition(favorites.ids.count == 9 && favorites.ids[3] == "10" && favorites.ids[4] == "2")
    for app in apps where favorites.contains(app) { favorites.toggle(app) }
    favorites.activate(account: "A", apps: apps)
    precondition(favorites.ids.isEmpty, "空收藏不能被默认项覆盖")
    favorites.reset(apps: apps)
    precondition(favorites.ids == Array(apps.prefix(8)).map(\.id))

    let holidays = HolidayStore(defaults: defaults)
    holidays.activate(account: "A")
    holidays.setReplacement(PortalDate.day("2026-09-28"), on: PortalDate.day("2026-10-01")!)
    precondition(holidays.overrides["2026-10-01"] == .normal)
    holidays.activate(account: "B")
    precondition(holidays.overrides.isEmpty && holidays.replacementDates.isEmpty)
    holidays.activate(account: "A")
    precondition(holidays.replacementDates["2026-10-01"] == "2026-09-28")
    holidays.enabled = false
    precondition(!HolidayStore(defaults: defaults).enabled)
    print("Persistence: favorites ordering/reset/empty state/account isolation and school-day overrides passed")
}
await MainActor.run { testStores() }

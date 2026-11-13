import Foundation

var checks = 0
func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    checks += 1
    if !condition() { fatalError("Academic test failed: " + message) }
}
func rejects(_ message: String, _ body: () throws -> Void) {
    checks += 1
    do { try body(); fatalError("Academic test accepted invalid data: " + message) }
    catch { }
}
func envelope(_ data: Any) -> [String: Any] { ["code": "0", "datas": data] }
let path = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Tests/Academic/fixtures/synthetic.json"
let fixtures = try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: path))) as! [String: Any]

try AcademicQueryParser.validateIdentity(fixtures["identity"]!, expectedAccount: "SYNTH-A")
rejects("wrong server account") { try AcademicQueryParser.validateIdentity(fixtures["identity"]!, expectedAccount: "SYNTH-B") }
rejects("unknown server account") { try AcademicQueryParser.validateIdentity(envelope([:]), expectedAccount: "SYNTH-A") }
if case .terms(let terms) = try AcademicQueryParser.decode(fixtures["terms"]!, key: .terms) {
    expect(terms.count == 2, "term list")
    expect(terms[0].current && !terms[1].current, "current term comes only from selected")
}
if case .plans(let plans) = try AcademicQueryParser.decode(fixtures["plans"]!, key: .plans) {
    expect(plans.first?.id == "SYNTH-PLAN-A", "real planId field")
    expect(plans.first?.selected == true, "selected string flag")
}
if case .calendar(let details) = try AcademicQueryParser.decode(fixtures["calendar"]!, key: .calendar("SYNTH-TERM-1")) {
    expect(details.startDate == "2031-09-08", "calendar startDate")
    expect(details.holidays.count == 1, "calendar holiday intervals")
}
if case .calendar(let missing) = try AcademicQueryParser.decode(envelope(NSNull()), key: .calendar("SYNTH-TERM-1")) {
    expect(!missing.hasStructuredDates, "missing date is not a made-up start date")
}
if case .week(let week) = try AcademicQueryParser.decode(fixtures["week"]!, key: .week("2031-11-10")) {
    expect(week.value == "9", "raw official classWeek")
}
if case .week(let week) = try AcademicQueryParser.decode(envelope([:]), key: .week("2031-11-10")) {
    expect(week.value == nil, "missing week not zero")
}
if case .status(let status) = try AcademicQueryParser.decode(fixtures["status"]!, key: .status("SYNTH-PLAN-A")) {
    expect(status.academicRate == 62.5, "official percentage not animation nutrients")
    expect(status.unusualCount == 1 && status.failedCourses.count == 1, "official status fields")
}
if case .status(let status) = try AcademicQueryParser.decode(envelope([:]), key: .status("SYNTH-PLAN-A")) {
    expect(status.academicRate == nil && !status.hasFailedCourseList, "unknown status not completed or empty list")
}
if case .terms(let terms) = try AcademicQueryParser.decode(envelope([]), key: .terms) { expect(terms.isEmpty, "confirmed empty list") }
let invalidResponses: [Any] = [["code":"403", "datas":[]], ["code":"401", "datas":[]], ["code":"200", "datas":[]],
                 ["success":true, "data":[]], ["code":false, "datas":[]], ["code":"0"],
                 envelope(["rows":[]]), envelope(["bad-row"]), envelope([["itemName":"no-code"]])]
for raw in invalidResponses {
    rejects("strict envelope and list shape") { _ = try AcademicQueryParser.decode(raw, key: .terms) }
}
rejects("rate outside percentage range") { _ = try AcademicQueryParser.decode(envelope(["academicRate":101]), key: .status("SYNTH-PLAN-A")) }
rejects("boolean progress") { _ = try AcademicQueryParser.decode(envelope(["academicRate":true]), key: .status("SYNTH-PLAN-A")) }
rejects("non-finite progress") { _ = try AcademicQueryParser.decode(envelope(["academicRate":"nan"]), key: .status("SYNTH-PLAN-A")) }
rejects("fractional anomaly count") { _ = try AcademicQueryParser.decode(envelope(["academicUnusual":1.5]), key: .status("SYNTH-PLAN-A")) }
rejects("duplicate terms") { _ = try AcademicQueryParser.decode(envelope([["itemCode":"SYNTH"], ["itemCode":"SYNTH"]]), key: .terms) }
rejects("invalid date request") { _ = try AcademicQueryKey.week("2031-02-30").path }
rejects("control-character parameter") { _ = try AcademicQueryKey.status("SYNTH\nPLAN").path }
let encodedPath = try AcademicQueryKey.status("SYNTH&PLAN").path
expect(encodedPath == "api/home/student/academic-status.do?planId=SYNTH%26PLAN", "query encoding")
let now = Date(timeIntervalSince1970: 2_000_000_000)
expect(AcademicQueryPolicy.isFresh(now.addingTimeInterval(-299), key: .week("2031-11-10"), now: now), "week fresh")
expect(!AcademicQueryPolicy.isFresh(now.addingTimeInterval(-300), key: .week("2031-11-10"), now: now), "week expires")
expect(!AcademicQueryPolicy.isFresh(now.addingTimeInterval(1), key: .terms, now: now), "future cache not fresh")
let epoch = UUID(), generation = UUID()
let context = RepositoryRequestContext(account: "SYNTH-A", epoch: epoch, generation: generation)
expect(context.matches(account: "SYNTH-A", epoch: epoch, generation: generation), "current context")
expect(!context.matches(account: "SYNTH-B", epoch: epoch, generation: generation), "account switch")
expect(!context.matches(account: "SYNTH-A", epoch: UUID(), generation: generation), "logout and re-login same account")
expect(!context.matches(account: "SYNTH-A", epoch: epoch, generation: UUID()), "A-B-A generation isolation")
let pageURL = URL(string: "https://jwxt.neu.edu.cn/jwapp/sys/synthetic/index.html")!
let page = try AcademicPageReader.decode(fixtures["page"]!, expectedAccount: "SYNTH-A", expectedSourceURL: pageURL, now: now)
expect(page.sourceURL.query == nil, "no auth query persisted")
expect(page.courses.first?.creditsText == "2.5" && page.courses.first?.module == "合成基础模块", "read original page fields")
rejects("different page account") { _ = try AcademicPageReader.decode(fixtures["page"]!, expectedAccount: "SYNTH-B", expectedSourceURL: pageURL) }
rejects("different source URL") { _ = try AcademicPageReader.decode(fixtures["page"]!, expectedAccount: "SYNTH-A", expectedSourceURL: URL(string:"https://example.invalid/jwapp/page")!) }
rejects("unrecognized page not empty curriculum") { _ = try AcademicPageReader.decode(["error":"format"], expectedAccount:"SYNTH-A", expectedSourceURL:pageURL) }
print("Academic Swift parser/policy: \(checks) checks passed (synthetic only)")

func planCourse(_ code: String, status: String?, credits: String?, module: String = "基础", term: String = "第1学期") -> AcademicPageCourse {
    AcademicPageCourse(id: "page-local-row-0", name: "课程" + code, code: code, creditsText: credits,
        module: module, studyStatus: status, suggestedTerm: term, category: "必修", hoursText: "32", scoreText: nil, assessment: "考试")
}
let done = planCourse("A", status: "已通过", credits: "2.5")
let pending = planCourse("B", status: "未完成", credits: "待定")
let studying = planCourse("C", status: "重修中", credits: "0")
let failed = planCourse("D", status: "未通过", credits: "3学分", module: "专业")
expect(done.status == .completed && pending.status == .pending && failed.status == .failed, "negative states do not become passed")
expect(studying.status == .inProgress && studying.credits == 0, "explicit zero credits and in-progress status")
expect(pending.credits == nil, "unknown credits are not zero")
let noState = planCourse("E", status: nil, credits: "1")
expect(noState.status == .unknown, "missing completion does not imply passed")
let merged = AcademicPlanPresentation.merge([done, pending], [studying, planCourse("A", status: "已完成", credits: "3")])
expect(merged.count == 3 && Set(merged.map(\.id)).count == 3, "pagination merges and gives unique row IDs")
expect(merged.first?.credits == 3, "new page updates an existing course")
let grouped = AcademicPlanPresentation.groups([done,pending,studying,failed], query: "", status: nil, grouping: .module)
expect(grouped.count == 2 && grouped.first(where: { $0.title == "基础" })?.unknownCredits == 1,
       "module summaries retain missing-credit counts independently of locale collation")
expect(AcademicPlanPresentation.groups([done,pending], query: "B", status: .pending, grouping: .term).first?.courses.count == 1,
       "course search and status filter intersect")
var savedPlan = page; savedPlan.planID = "SYNTH-PLAN-A"; savedPlan.courses = merged
let cacheRoot = FileManager.default.temporaryDirectory.appendingPathComponent("academic-cache-" + UUID().uuidString, isDirectory: true)
var planCache = AcademicPlanCacheStore(account: "SYNTH-A", planID: "SYNTH-PLAN-A"); planCache.directory = cacheRoot
try planCache.save(savedPlan)
expect(planCache.load()?.courses == merged, "course details survive disk round-trip")
var otherAccount = AcademicPlanCacheStore(account: "SYNTH-B", planID: "SYNTH-PLAN-A"); otherAccount.directory = cacheRoot
var otherPlan = AcademicPlanCacheStore(account: "SYNTH-A", planID: "SYNTH-PLAN-B"); otherPlan.directory = cacheRoot
expect(otherAccount.load() == nil && otherPlan.load() == nil, "account and plan cache isolation")
rejects("cannot bind another account") { try otherAccount.save(savedPlan) }
try planCache.clear()
expect(planCache.load() == nil, "clear removes only this plan snapshot")
try FileManager.default.removeItem(at: cacheRoot)
print("Academic plan browsing: status, credits, filtering, page merge and isolated persistent cache passed")

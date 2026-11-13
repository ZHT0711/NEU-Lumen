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

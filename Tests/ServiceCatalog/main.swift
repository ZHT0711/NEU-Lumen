import Foundation

// 模型测试只需入口常量，不链接真实网络客户端或会话。
enum PortalClient {
    static let portalBase = "https://personal.neu.edu.cn/portal"
}

func app(_ name: String, category: String, desc: String = "") -> PortalApp {
    PortalApp(name: name, appId: name, url: "", mobileUrl: "", iconUrl: "",
              desc: desc, category: category, visits: 0)
}

let apps = [
    app("教务系统", category: "教学学习", desc: "选课、成绩与课表"),
    app("Blackboard", category: "教学学习"),
    app("图书馆", category: " 校园生活\n", desc: "馆藏查询"),
    app("校园卡", category: "校园生活"),
    app("未分类应用", category: " \n"),
]
let catalog = ServiceCatalog(apps: apps)

precondition(catalog.categories.reduce(0) { $0 + $1.count } == apps.count, "分类必须覆盖全部应用")
precondition(catalog.categories.last == ServiceCategory(name: "其他服务", count: 1), "空分类应归入其他服务")
precondition(catalog.categories.first?.count == 2, "按应用数量降序排列")
precondition(catalog.categories == ServiceCatalog(apps: Array(apps.reversed())).categories, "同数量分类顺序应稳定")
precondition(catalog.filtered(query: "", category: nil) == apps, "全部分类保留门户应用顺序")
precondition(catalog.filtered(query: " \n", category: nil) == apps, "忽略空白搜索")
precondition(catalog.filtered(query: "", category: "校园生活").count == 2, "分类去除首尾空白")
precondition(catalog.filtered(query: "  成绩\n", category: "教学学习").map(\.name) == ["教务系统"], "分类与描述联合筛选")
precondition(catalog.filtered(query: "BLACKBOARD", category: nil).map(\.name) == ["Blackboard"], "英文搜索忽略大小写")
precondition(catalog.filtered(query: "校园生活", category: nil).count == 2, "支持搜索分类名称")
precondition(catalog.filtered(query: "成绩", category: "校园生活").isEmpty, "分类过滤不能泄漏其他分类结果")
precondition(catalog.filtered(query: "", category: "其他服务").map(\.name) == ["未分类应用"], "未分类应用仍可访问")
precondition(catalog.filtered(query: "不存在", category: nil).isEmpty, "无匹配返回空结果")
precondition(ServiceCatalog(apps: []).categories.isEmpty, "空目录不生成虚假分类")
print("ServiceCatalog: 14 checks passed")

// Exercise the same routing function used by Home/Services favorites, not a fixture replica.
func routingApp(_ entry: String, mobile: String = "", id: String = "SYNTH-ROUTE") -> PortalApp {
    PortalApp(name: "合成教务入口", appId: id, url: entry, mobileUrl: mobile,
              iconUrl: "", desc: "", category: "教学学习", visits: 0)
}
for entry in ["https://jwxt.neu.edu.cn", "https://jwxt.neu.edu.cn/",
              "https://jwxt.neu.edu.cn/jwapp/sys/homeapp/index.do",
              "https://jwxt.neu.edu.cn/jwapp/sys/homeapp/home/index.html?av=&contextPath=/jwapp"] {
    let official = routingApp(entry)
    precondition(AppDestination.service(official) == .web(URL(string: entry)!), "学校教务入口始终打开原网页")
}
for entry in ["https://jwxt.neu.edu.cn/jwapp/sys/registration/index.do",
              "http://jwxt.neu.edu.cn/", "https://jwxt.neu.edu.cn:8443/",
              "https://jwxt.neu.edu.cn.evil.example/", "https://legacy.example/教务"] {
    let external = routingApp(entry)
    precondition(AppDestination.service(external) == .web(URL(string: external.entryUrl())!), "原网页入口仍可用")
}
precondition(AppDestination.service(routingApp("https://user:password@jwxt.neu.edu.cn/")) == nil,
             "拒绝带 URL 凭据的服务入口")
precondition(AppDestination.service(routingApp("https://jwxt.neu.edu.cn/", mobile: "https://library.example/")) == .web(URL(string: "https://library.example/")!),
             "继续优先使用门户移动端地址，不按名称误路由")
precondition(AppDestination.service(routingApp("", id: "")) == nil, "空地址和空应用 ID 不生成虚假入口")
print("Original portal routing: academic URLs, mobile URLs and favorites preserve school destinations")

// 整周相同时间的课程曾经会互相打断合并。
func occurrence(_ day: String, _ start: Int, _ end: Int, name: String = "高等数学", room: String = "A101",
                teacher: String = "张老师", kind: String = "course", eventID: String? = nil) -> CourseOccurrence {
    let date = PortalDate.day(day)!
    return CourseOccurrence(date: date, slot: CourseSlot(weekday: PlannerEvent.mondayBasedWeekday(date),
        startMinutes: start, endMinutes: end, name: name, room: room, teacher: teacher, kind: kind, eventID: eventID))
}
let monday = "2026-11-02", tuesday = "2026-11-03"
let week = [occurrence(monday,510,555), occurrence(tuesday,510,555), occurrence(monday,565,610),
            occurrence(tuesday,565,610), occurrence(monday,630,675), occurrence(monday,685,730)]
let mergedWeek = week.mergeConsecutive()
precondition(mergedWeek.count == 2, "按日期分组，四节连堂合成一个课程块")
precondition(mergedWeek[0].slot.startMinutes == 510 && mergedWeek[0].slot.endMinutes == 730, "保留完整连堂时间")
precondition(week.reversed().map { $0 }.mergeConsecutive() == mergedWeek, "乱序输入结果一致")
precondition([week[0],week[0]].mergeConsecutive().count == 1, "重复事件去重")
precondition([week[0], occurrence(monday,540,610)].mergeConsecutive().first?.slot.endMinutes == 610, "重叠片段合并")
precondition([week[0], occurrence(monday,565,610,room:"A102")].mergeConsecutive().count == 2, "不同教室不合并")
precondition([week[0], occurrence(monday,565,610,teacher:"李老师")].mergeConsecutive().count == 2, "不同教师不合并")
precondition([week[0], occurrence(monday,840,885)].mergeConsecutive().count == 2, "午休前后不合并")
precondition([occurrence(monday,510,555,kind:"custom",eventID:"a"), occurrence(monday,565,610,kind:"custom",eventID:"b")].mergeConsecutive().count == 2, "独立本机日程保留各自删除入口")
let placements = TimetablePlacement.layout(week, on: PortalDate.day(monday)!)
precondition(placements.count == 1 && placements[0].periodCount == 4, "四节课程只渲染一个跨行块")
let conflicts = TimetablePlacement.layout([week[0], occurrence(monday,510,555,name:"英语")], on: PortalDate.day(monday)!)
precondition(conflicts.count == 2 && Set(conflicts.map(\.lane)).count == 2, "冲突课程分列且都保留")
print("Timetable: 11 checks passed")

// 对照旧的“整周先合并”路径，验证筛选前移不改变块、节次或冲突列。
func legacyLayout(_ occurrences: [CourseOccurrence], on date: Date) -> [TimetablePlacement] {
    let daily = occurrences.mergeConsecutive().filter { Calendar.current.isDate($0.date, inSameDayAs: date) }
    var assigned: [(CourseOccurrence, Int, Int, Int)] = []
    var laneEnds: [Int] = []
    for item in daily {
        let first = Semester.periodOf(startMinutes: item.slot.startMinutes)
        let last = max(first, Semester.endPeriod(of: item.slot.endMinutes))
        let lane = laneEnds.firstIndex { $0 < first } ?? laneEnds.count
        if lane == laneEnds.count { laneEnds.append(last) } else { laneEnds[lane] = last }
        assigned.append((item, first, last, lane))
    }
    return assigned.map { TimetablePlacement(occurrence: $0.0, firstPeriod: $0.1, lastPeriod: $0.2,
        lane: $0.3, laneCount: max(1, laneEnds.count)) }
}
func checkLayoutEquivalence(_ occurrences: [CourseOccurrence], on date: Date) {
    let actual = TimetablePlacement.layout(occurrences, on: date)
    let expected = legacyLayout(occurrences, on: date)
    precondition(actual.map(\.occurrence) == expected.map(\.occurrence), "课程内容、日期与合并范围不变")
    precondition(actual.count == expected.count)
    for index in actual.indices {
        precondition(actual[index].firstPeriod == expected[index].firstPeriod && actual[index].lastPeriod == expected[index].lastPeriod)
        precondition(actual[index].lane == expected[index].lane && actual[index].laneCount == expected[index].laneCount)
    }
}
struct LayoutGenerator {
    private var seed: UInt64 = 42
    mutating func next(_ limit: Int) -> Int {
        seed = seed &* 6364136223846793005 &+ 1
        return Int((seed >> 32) % UInt64(limit))
    }
}
var layoutGenerator = LayoutGenerator()
let layoutDates = (0..<7).map { Calendar.current.date(byAdding: .day, value: $0, to: PortalDate.day(monday)!)! }
for _ in 0..<40 {
    var mixed: [CourseOccurrence] = []
    for index in 0..<56 {
        let date = layoutDates[layoutGenerator.next(7)]
        let start = 480 + layoutGenerator.next(20) * 25
        let kind = ["course", "exam", "custom"][layoutGenerator.next(3)]
        let slot = CourseSlot(weekday: PlannerEvent.mondayBasedWeekday(date), startMinutes: start,
            endMinutes: start + 25 + layoutGenerator.next(4) * 25, name: ["数学", "数 学", "英语"][layoutGenerator.next(3)],
            room: ["A101", "A102"][layoutGenerator.next(2)], teacher: ["张老师", "李老师"][layoutGenerator.next(2)],
            kind: kind, weekStart: 1 + layoutGenerator.next(3), weekEnd: 10 + layoutGenerator.next(3),
            eventID: kind == "custom" ? "event-\(index)" : nil)
        let item = CourseOccurrence(date: date, slot: slot)
        mixed.append(item)
        if index % 8 == 0 { mixed.append(item) }
    }
    for date in layoutDates { checkLayoutEquivalence(mixed, on: date) }
}
checkLayoutEquivalence([], on: layoutDates[0])
checkLayoutEquivalence(week, on: Calendar.current.date(byAdding: .day, value: 9, to: layoutDates[0])!)
let midday = CourseOccurrence(date: layoutDates[0].addingTimeInterval(12 * 3600), slot: week[4].slot)
checkLayoutEquivalence(week + [midday], on: layoutDates[0].addingTimeInterval(15 * 3600))
print("Timetable performance regression: 283 legacy-path equivalence checks passed")

let termJSON: [String:Any] = ["code":0,"datas":["rows":[["itemCode":"2026-1","itemName":"秋季","selected":"1"]]]]
let terms = try AcademicResponse.terms(termJSON)
precondition(terms.count == 1 && terms[0].current, "兼容数字响应码、嵌套列表和字符串选中状态")
let scoreJSON: [String:Any] = ["code":"0","datas":[["courseName":"数学","credit":"3.5","score":" 92 "], ["courseName":"体育","credit":1,"score":"良"]]]
let courses = try AcademicResponse.courses(scoreJSON)
precondition(courses.count == 2 && courses[0].score == 92 && courses[0].credit == 3.5, "正确解析数字成绩及学分")
precondition(courses[1].scoreRaw == "良", "保留五级制原文")
do { try AcademicResponse.validate(["code":401], stage:"成绩"); preconditionFailure("认证失效必须抛出") }
catch { precondition(NetworkError.from(error).isSessionExpired) }
let report = try AcademicResponse.browserReport(["semesters":[
    ["code":"1","name":"春季","current":false,"response":scoreJSON],
    ["code":"2","name":"秋季","current":true,"response":["code":"-1"]]
]])
precondition(report.semesters.count == 1 && report.failedTerms == ["秋季"], "单学期失败保留成功学期并明确标记")
print("Grades: 5 checks passed")

let jar = CookieJar()
let origin = URL(string:"https://jwxt.neu.edu.cn/jwapp/index.do")!
jar.absorbRaw(origin,"SESSION=root; Path=/, SESSION=student; Path=/jwapp, ONLY=secure; Secure; Path=/, EXP=ok; Expires=Wed, 09 Jun 2038 10:18:14 GMT, NEXT=ok; Path=/")
let header = jar.headerFor(URL(string:"https://jwxt.neu.edu.cn/jwapp/api")!)!
precondition(header.contains("SESSION=root") && header.contains("SESSION=student"), "同名 Cookie 不同路径均保留")
precondition(header.contains("EXP=ok") && header.contains("NEXT=ok"), "Expires 后合并的 Cookie 仍能解析")
precondition(jar.headerFor(URL(string:"http://jwxt.neu.edu.cn/")!)?.contains("ONLY=secure") == false, "Secure Cookie 不经 HTTP 发送")
precondition(jar.headerFor(URL(string:"https://child.jwxt.neu.edu.cn/")!) == nil, "Host-only Cookie 不扩散到子域")
precondition(jar.headerFor(URL(string:"https://jwxt.neu.edu.cn/jwapplication")!)?.contains("SESSION=student") == false, "路径按边界匹配")
let transferred = CookieJar(); transferred.absorb(jar.allCookies())
precondition(transferred.headerFor(URL(string:"https://jwxt.neu.edu.cn/jwapp/api")!) == header, "WebKit Cookie 传递保留路径和属性")
jar.clear(); precondition(jar.allCookies().isEmpty, "退出清除会话")
print("Cookies: 7 checks passed")

let nativePayment = NativeCampusService.payment
precondition(NativeCampusService.allCases.count == 5)
precondition(nativePayment.entryURL(apps: [routingApp("https://pay.neu.edu.cn.evil.example/",id:"62")]) == nativePayment.fallbackURL)
precondition(nativePayment.entryURL(apps: [routingApp("https://pay.neu.edu.cn:8443/",id:"62")]) == nativePayment.fallbackURL)
precondition(NativeCampusService.mail.owns(host: "mails.neu.edu.cn") && !NativeCampusService.mail.owns(host: "mails.neu.edu.cn.evil.example"))
let mailRows = try NativeMailProtocol.messages([["id":"fixture-1","subject":"合成邮件","sender":"fixture@example.invalid","unread":false]])
precondition(mailRows.count == 1 && mailRows[0].unread == false)
do { _ = try NativeMailProtocol.messages([["id":"x"],["id":"x"]]); preconditionFailure("Duplicate mail IDs must fail") } catch { }
print("Native services: original routes, verified hosts, five native services and Coremail decoder passed")

var mailSearch = NativeMailSearch()
mailSearch.from = " fixture@example.invalid "
mailSearch.to = "synthetic@stu.neu.edu.cn"
mailSearch.unreadOnly = true; mailSearch.attachedOnly = true; mailSearch.flaggedOnly = true
precondition(mailSearch.parameters["from"] as? String == "fixture@example.invalid")
precondition(mailSearch.parameters["read"] as? Bool == false && mailSearch.parameters["attachType"] as? String == "attached")
precondition(mailSearch.parameters["flagType"] as? String == "flagged")
let movedMail = NativeMailMutation.move("7").attributes
precondition(movedMail["fid"] as? Int == 7)
let unflaggedMail = NativeMailMutation.flagged(false).attributes
precondition(unflaggedMail["label0"] as? Int == 0)
let serviceDocumentJSON = #"""
{"token":"synthetic","title":"合成缴费订单","fields":[],"actions":[],"tables":[{"id":"t","title":"订单","headers":["状态","金额"],"rows":[["待确认",""]],"truncated":false}],"notices":[],"needsWeb":true}
"""#
let serviceDocument = try JSONDecoder().decode(NativeServiceDocument.self, from: Data(serviceDocumentJSON.utf8))
precondition(serviceDocument.tables[0].rows[0] == ["待确认", ""] && serviceDocument.needsWeb)
print("Native services: advanced mail criteria, reversible mutations and original order values passed")

let affairsHTML = #"""
<a class="object_class active" id="object_1">学生办事</a>
<a id="type_0" class="type_class">全部</a>
<a class="organize_class" id="organize_0">全部部门</a>
<a class="english_class" id="english_0">ALL</a>
<div class="alk-service-nav"><h2><a href="/db_portal/guide?id=SYNTH-A">合成部门</a></h2>
<a href="/db_portal/guide?id=SYNTH-A"><img src="/file/synthetic"></a>
<span><a href="/db_portal/guide?id=SYNTH-A">合成证明 &amp; 申请</a></span></div>
"""#
let affairsCatalog = try NativeAffairsCatalogParser.catalog(affairsHTML)
precondition(affairsCatalog.services.count == 1 && affairsCatalog.services[0].department == "合成部门")
precondition(affairsCatalog.services[0].title == "合成证明 & 申请" && affairsCatalog.audiences[0].id == "1")
precondition(affairsCatalog.departments[0].id == "0" && affairsCatalog.initials[0].title == "ALL")
let emptyCatalog = String(affairsHTML.prefix { $0 != "\n" }) + "<a class='type_class' id='type_0'>全部</a><a class='organize_class' id='organize_0'>全部</a><a class='english_class' id='english_0'>ALL</a>"
let emptyAffairsCatalog = try NativeAffairsCatalogParser.catalog(emptyCatalog)
precondition(emptyAffairsCatalog.services.isEmpty)
do { _ = try NativeAffairsCatalogParser.catalog("<html>请登录</html>"); preconditionFailure("A login page cannot become an empty service directory") } catch { }
do {
    _ = try NativeAffairsCatalogParser.catalog(affairsHTML.replacingOccurrences(of: "/db_portal/guide?id=SYNTH-A", with: "https://evil.example/db_portal/guide?id=SYNTH-A"))
    preconditionFailure("A changed service destination must be rejected")
} catch { }
let guideHTML = #"""
<h2 class="title-h2">合成指南</h2><input onclick="jump_open('https://ehall.neu.edu.cn/infoplus/form/SYNTH/start')">
<div class="top-nav-box"><p>收费标准：无</p></div>
<ul><li class="left-nav"><h3>办理条件</h3><p>合成条件</p><li></ul>
<div id="cont_one_1"><img src="/file/synthetic-flow"></div>
<div id="cont_one_2"><p>合成公告</p></div>
<div id="cont_one_3"><a href="/file/synthetic-document">合成材料</a></div><!--relevance-->
"""#
let affairsGuide = try NativeAffairsCatalogParser.guide(guideHTML)
precondition(affairsGuide.sections.first?.text == "合成条件" && affairsGuide.facts == ["收费标准：无"])
precondition(affairsGuide.sections.first(where: { $0.title == "办事流程" })?.images.count == 1)
precondition(affairsGuide.sections.first(where: { $0.title == "所需材料" })?.links.first?.title == "合成材料")
precondition(affairsGuide.applicationURL?.path == "/infoplus/form/SYNTH/start")
var affairsQuery = AffairsCatalogQuery(); affairsQuery.keyword = "合成 & 材料"
precondition(URLComponents(url: affairsQuery.url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "keyword" })?.value == affairsQuery.keyword)
print("Native affairs: dynamic catalogs, all filters, guide sections, attachments, diagrams and safe destinations passed")

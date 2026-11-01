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

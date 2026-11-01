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

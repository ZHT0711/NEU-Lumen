import Foundation

/// 离线演示快照：任一门户接口失败时兜底展示，并明确标注「离线数据」。
enum DemoData {
    static let user = PortalUser(
        uid: "0",
        name: "东大学子",
        sid: "20250001",
        identity: "本科生",
        department: "计算机科学与工程学院",
        email: "student@mails.neu.edu.cn",
        avatarUrl: ""
    )

    static let dataCards: [DataCard] = [
        DataCard(name: "校园卡余额", value: "66.50"),
        DataCard(name: "网费余额", value: "25.00"),
        DataCard(name: "图书借阅", value: "3"),
        DataCard(name: "寒假余额", value: "48天"),
    ]

    static let apps: [PortalApp] = [
        PortalApp(name: "本科教务系统", appId: "demo-1", url: "https://jwxt.neu.edu.cn/jwapp/sys/homeapp/index.do", mobileUrl: "", iconUrl: "", desc: "选课、成绩、课表", category: "教学学习", visits: 0),
        PortalApp(name: "校园卡自助", appId: "demo-2", url: "http://ecard.neu.edu.cn/selflogin/login.aspx", mobileUrl: "", iconUrl: "", desc: "余额与流水", category: "校园生活", visits: 0),
        PortalApp(name: "缴费大厅", appId: "demo-3", url: "https://pay.neu.edu.cn/drCasLogin", mobileUrl: "", iconUrl: "", desc: "网费电费缴纳", category: "财务资产", visits: 0),
        PortalApp(name: "图书馆", appId: "demo-4", url: "https://lib.neu.edu.cn", mobileUrl: "", iconUrl: "", desc: "馆藏与借阅", category: "校园生活", visits: 0),
        PortalApp(name: "学生邮箱", appId: "demo-5", url: "https://mail.stumail.neu.edu.cn", mobileUrl: "", iconUrl: "", desc: "学校邮箱", category: "公共服务", visits: 0),
        PortalApp(name: "校园网关", appId: "demo-6", url: "https://ipgw.neu.edu.cn", mobileUrl: "", iconUrl: "", desc: "网络自助服务", category: "公共服务", visits: 0),
    ]

    static let news: [NewsItem] = [
        NewsItem(id: "demo-1", title: "【离线演示】欢迎使用 NEU-Lumen 原生 iOS 客户端", date: "2026-11-01", category: "东大要闻", url: "https://personal.neu.edu.cn/portal", picUrl: ""),
        NewsItem(id: "demo-2", title: "【离线演示】登录统一身份认证后即可浏览实时校园资讯", date: "2026-11-01", category: "东大要闻", url: "https://personal.neu.edu.cn/portal", picUrl: ""),
        NewsItem(id: "demo-3", title: "【离线演示】课程表、服务大厅与成绩查询均已接入真实接口", date: "2026-11-01", category: "东大要闻", url: "https://personal.neu.edu.cn/portal", picUrl: ""),
    ]

    static let todos: [TodoItem] = [
        TodoItem(title: "离线演示事项", instance: "演示流程", node: "处理中", percent: 50, time: "2026-11-01 08:00", url: ""),
    ]

    static let hotSearch: [String] = ["选课", "成绩查询", "校园卡", "奖学金评定", "体测成绩", "校车时刻", "讲座预约"]
}

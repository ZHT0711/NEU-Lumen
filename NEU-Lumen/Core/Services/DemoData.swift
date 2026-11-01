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

    // 公共服务入口快照，对齐 NEUPortal 1e4c787；不代表账号访问权限。
    static let apps: [PortalApp] = [
        PortalApp(name: "教务系统（新）", appId: "138", url: "https://jwxt.neu.edu.cn", mobileUrl: "", iconUrl: "https://personal.neu.edu.cn/portal/staticdata/open/image/20260123/UG/904b30d9f7127265d89e1c1b6345de25.png", desc: "", category: "教学学习", visits: 2785049),
        PortalApp(name: "财务系统", appId: "4", url: "https://cw.neu.edu.cn/WFManager/home2.jsp", mobileUrl: "", iconUrl: "https://personal.neu.edu.cn/portal/staticdata/open/image/20241220/eT/7ba3efd02fa39289ecbba59f6e979891.png", desc: "", category: "财务资产", visits: 1287092),
        PortalApp(name: "缴费服务大厅", appId: "62", url: "https://pay.neu.edu.cn/drCasLogin", mobileUrl: "", iconUrl: "https://personal.neu.edu.cn/portal/staticdata/open/image/20241220/qz/498def6dd099f986409ba1d45d43ac66.png", desc: "", category: "财务资产", visits: 2178906),
        PortalApp(name: "VPN服务", appId: "2", url: "https://webvpn.neu.edu.cn/portal", mobileUrl: "", iconUrl: "https://personal.neu.edu.cn/portal/staticdata/open/image/20241220/Wn/e122eb1b51d6b14cc6cc9001e21cce2d.png", desc: "", category: "公共服务", visits: 1578802),
        PortalApp(name: "办事大厅", appId: "1", url: "https://ehall.neu.edu.cn/db_portal/service_personal", mobileUrl: "", iconUrl: "https://personal.neu.edu.cn/portal/staticdata/open/image/20241220/tQ/559c7da02fc691a7eba1142f9e118c72.png", desc: "", category: "公共服务", visits: 762910),
        PortalApp(name: "一号通智能填报", appId: "44", url: "https://ehall.neu.edu.cn/service/v2/site/index", mobileUrl: "", iconUrl: "https://personal.neu.edu.cn/portal/staticdata/open/image/20241220/O5/70324c9780c80279ec78fb3bd7ea2c4e.png", desc: "", category: "公共服务", visits: 149434),
        PortalApp(name: "心理港湾", appId: "41", url: "http://210.30.206.130/user/web-v2/sso", mobileUrl: "", iconUrl: "https://personal.neu.edu.cn/portal/staticdata/open/image/20241220/Mh/05bb558b62a1c4f8dc67ecf0e83560a6.png", desc: "", category: "校园生活", visits: 512185),
        PortalApp(name: "科研系统", appId: "18", url: "http://219.216.96.91/neusoftcas.jsp", mobileUrl: "", iconUrl: "https://personal.neu.edu.cn/portal/staticdata/open/image/20241220/kj/d86477b7e8256896c8454418014c262a.png", desc: "", category: "科研创新", visits: 387571),
        PortalApp(name: "邮件系统", appId: "121", url: "https://mails.neu.edu.cn/coremail/cmcu_addon/dbdxsso.jsp", mobileUrl: "", iconUrl: "https://personal.neu.edu.cn/portal/staticdata/open/image/20250804/Q6/522550d99d82522e781244228197452c.png", desc: "新版学生邮件地址", category: "公共服务", visits: 474168),
        PortalApp(name: "一卡通系统", appId: "6", url: "http://ecard.neu.edu.cn/selflogin/login.aspx", mobileUrl: "", iconUrl: "https://personal.neu.edu.cn/portal/staticdata/open/image/20241220/K9/2056c33da0669b79bcbe4d4f5e52702d.png", desc: "", category: "校园生活", visits: 388886),
        PortalApp(name: "体测系统", appId: "130", url: "http://210.30.202.96:8080", mobileUrl: "", iconUrl: "https://personal.neu.edu.cn/portal/staticdata/open/image/20251016/Hn/ed7860dfb93f2aeee6649d65b5da5534.png", desc: "", category: "教学学习", visits: 330118),
        PortalApp(name: "图书馆系统", appId: "21", url: "https://portal.neu.edu.cn/tp_up/up/subgroup/gotoLibirarySystem", mobileUrl: "", iconUrl: "https://personal.neu.edu.cn/portal/staticdata/open/image/20241220/qz/ae1339dc35b14b38e9dc406ec3092694.png", desc: "", category: "校园生活", visits: 206106),
        PortalApp(name: "大仪共享平台", appId: "5", url: "http://sbgx.neu.edu.cn/lims/neu/cas/login", mobileUrl: "", iconUrl: "https://personal.neu.edu.cn/portal/staticdata/open/image/20241220/l0/08322c908530694e7a6c46d4942ccdbb.png", desc: "", category: "财务资产", visits: 170379),
        PortalApp(name: "教务BB系统", appId: "24", url: "https://bb.neu.edu.cn/webapps/bb-sso-BBLEARN/index.jsp", mobileUrl: "", iconUrl: "https://personal.neu.edu.cn/portal/staticdata/open/image/20241220/qN/0f63f394a85ade35297bd5f4aebaf6a6.png", desc: "", category: "教学学习", visits: 257990),
        PortalApp(name: "培训管理", appId: "132", url: "https://hr.neu.edu.cn/epxing-frame/api/v1/callBack/pxgl", mobileUrl: "", iconUrl: "https://personal.neu.edu.cn/portal/staticdata/open/image/20251126/yH/0189a07e0921e65e7474c6245ecaced9.png", desc: "", category: "组织人事", visits: 272),
        PortalApp(name: "创新创业管理系统", appId: "94", url: "https://cxcy.neu.edu.cn/", mobileUrl: "", iconUrl: "https://personal.neu.edu.cn/portal/staticdata/open/image/20241220/k1/3648514fe7767fdab5f4b08acf5a6c16.png", desc: "", category: "科研创新", visits: 145399),
        PortalApp(name: "智慧教室", appId: "80", url: "http://zhjs.neu.edu.cn/", mobileUrl: "", iconUrl: "https://personal.neu.edu.cn/portal/staticdata/open/image/20241220/qH/bafb7a3b82774fad85b78cb7db37b1dd.png", desc: "", category: "教学学习", visits: 150555),
        PortalApp(name: "知识产权运营管理平台", appId: "103", url: "http://neuip.neu.edu.cn", mobileUrl: "", iconUrl: "https://personal.neu.edu.cn/portal/staticdata/open/image/20241220/ox/fb300b541bf17b02ab5cf5741279e9fa.png", desc: "", category: "科研创新", visits: 94927),
        PortalApp(name: "网络计费系统", appId: "7", url: "http://ipgw.neu.edu.cn:8800/sso/default/neusoft", mobileUrl: "", iconUrl: "https://personal.neu.edu.cn/portal/staticdata/open/image/20241220/v9/2d3835ccfc9b1af1e5a0a568a8d20d3c.png", desc: "", category: "公共服务", visits: 11506),
        PortalApp(name: "学工系统", appId: "122", url: "https://xg.neu.edu.cn/xsfw/sys/swmxggzptapp/*default/index.do", mobileUrl: "", iconUrl: "https://personal.neu.edu.cn/portal/staticdata/open/image/20250819/4c/a4d217ec30f83b36e330331fe02eaefb.png", desc: "", category: "教学学习", visits: 517861),
        PortalApp(name: "CG实验平台", appId: "125", url: "http://neucsecg.neu.edu.cn", mobileUrl: "", iconUrl: "https://personal.neu.edu.cn/portal/staticdata/open/image/20250903/6F/9b4abc03dd5f41f767f1f1bdf2416208.png", desc: "", category: "教学学习", visits: 74232),
        PortalApp(name: "教学质量监控与评价平台", appId: "137", url: "http://zljk.neu.edu.cn", mobileUrl: "", iconUrl: "https://personal.neu.edu.cn/portal/staticdata/open/image/20260117/lc/ff9e06e8ed0ce527c6ec70d924abc54a.png", desc: "", category: "教学学习", visits: 17920),
        PortalApp(name: "场馆中心", appId: "9", url: "http://219.216.96.64/redirect/cas/login", mobileUrl: "", iconUrl: "https://personal.neu.edu.cn/portal/staticdata/open/image/20241220/vm/19785e1855ea411b5883c2edfbd8d53c.png", desc: "", category: "公共服务", visits: 6578),
        PortalApp(name: "站群系统", appId: "31", url: "http://adminweb.neu.edu.cn", mobileUrl: "", iconUrl: "https://personal.neu.edu.cn/portal/staticdata/open/image/20241220/8r/63399d68b1ccf4de9e01efc69011f18e.png", desc: "", category: "管理决策", visits: 37135),
        PortalApp(name: "网信服务问题反馈", appId: "124", url: "https://plat.neu.edu.cn/xwb-support/mobile/add", mobileUrl: "", iconUrl: "https://personal.neu.edu.cn/portal/staticdata/open/image/20250831/at/ac7e837e57d0da251cfb80fd313c8ecb.png", desc: "", category: "校园生活", visits: 23346),
        PortalApp(name: "化学品实验平台", appId: "10", url: "http://whp.neu.edu.cn/neu/public/", mobileUrl: "", iconUrl: "https://personal.neu.edu.cn/portal/staticdata/open/image/20241220/Ok/555fe670092eb2a845b0891c147d8e20.png", desc: "", category: "科研创新", visits: 4755),
        PortalApp(name: "校内电话簿", appId: "91", url: "https://plat.neu.edu.cn/telephone-directory/", mobileUrl: "", iconUrl: "https://personal.neu.edu.cn/portal/staticdata/open/image/20241220/6x/3a8c514d6dae487f066dba9d43a95424.png", desc: "", category: "校园生活", visits: 20810),
        PortalApp(name: "公用房管理系统", appId: "127", url: "http://210.30.202.99/extend_vgo/cas/login", mobileUrl: "", iconUrl: "https://personal.neu.edu.cn/portal/staticdata/open/image/20250911/xY/2a2ed16c2f9579e18ccf0f3f00316826.png", desc: "", category: "财务资产", visits: 9486),
        PortalApp(name: "规范性文件查询", appId: "42", url: "https://plat.neu.edu.cn/normative-document/documents", mobileUrl: "", iconUrl: "https://personal.neu.edu.cn/portal/staticdata/open/image/20241220/Px/1f27af3e722db00b0b683c9beba89fd8.png", desc: "", category: "公共服务", visits: 8248),
        PortalApp(name: "巡检助手", appId: "101", url: "https://plat.neu.edu.cn/inspection/pcservice", mobileUrl: "", iconUrl: "https://personal.neu.edu.cn/portal/staticdata/open/image/20241220/Fc/422c382679a1dce21861c9a065695d8f.png", desc: "", category: "行政办公", visits: 2542),
        PortalApp(name: "公文材料传递服务", appId: "105", url: "https://plat.neu.edu.cn/officialdocumenttransmission/pcservice", mobileUrl: "", iconUrl: "https://personal.neu.edu.cn/portal/staticdata/open/image/20241220/X3/c0a4d9625510a2dbd17d0f9cf8e2a30e.png", desc: "", category: "行政办公", visits: 14457),
        PortalApp(name: "教育资讯聚合平台", appId: "109", url: "http://tszs.neu.edu.cn/", mobileUrl: "", iconUrl: "https://personal.neu.edu.cn/portal/staticdata/open/image/20241220/vF/b05d3867dd22be9d2ce5797ae9f2c32f.png", desc: "", category: "公共服务", visits: 20441),
        PortalApp(name: "智搜平台", appId: "110", url: "https://so.neu.edu.cn/#/accessLogin?searchWord=", mobileUrl: "", iconUrl: "https://personal.neu.edu.cn/portal/staticdata/open/image/20241220/Xq/48624ac4cdfc31f63bad81676a16f978.png", desc: "", category: "公共服务", visits: 19848),
        PortalApp(name: "毕业生就业信息网", appId: "39", url: "http://job.neu.edu.cn/", mobileUrl: "", iconUrl: "https://personal.neu.edu.cn/portal/staticdata/open/image/20241220/zx/0dc1e07c92c112bbbc303ea533a6b372.png", desc: "", category: "教学学习", visits: 51909),
        PortalApp(name: "国际学术资源访问（需登录国际学术VPN）", appId: "139", url: "https://scholar.edu.cn", mobileUrl: "", iconUrl: "https://personal.neu.edu.cn/portal/staticdata/open/image/20260410/DH/dfd771990490c3fdd61d47feb1075a27.png", desc: "", category: "公共服务", visits: 4634),
        PortalApp(name: "数字党校", appId: "146", url: "", mobileUrl: "", iconUrl: "https://personal.neu.edu.cn/portal/staticdata/open/image/20261008/Cg/97e129d26ae0ae6b3c70fe9fc5b30dd4.png", desc: "", category: "教学学习", visits: 3208),
        PortalApp(name: "会议预约地址", appId: "106", url: "http://210.30.206.223:8088/signal_web/into/201/3", mobileUrl: "", iconUrl: "https://personal.neu.edu.cn/portal/staticdata/open/image/20241220/bR/872aea9ef9707d9f5107843dcf582283.png", desc: "", category: "行政办公", visits: 1273),
        PortalApp(name: "教务系统（旧）", appId: "27", url: "http://219.216.96.4/eams", mobileUrl: "", iconUrl: "https://personal.neu.edu.cn/portal/staticdata/open/image/20241220/lm/c6f350873a2ddb9234261c8722943393.png", desc: "", category: "教学学习", visits: 2129051),
        PortalApp(name: "研究生系统（旧）", appId: "14", url: "http://210.30.200.57/gmis5/oauthLogin/dbdxLogin", mobileUrl: "", iconUrl: "https://personal.neu.edu.cn/portal/staticdata/open/image/20241220/u2/6de897e8ea923852ff3f10467741403a.png", desc: "", category: "教学学习", visits: 861649),
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

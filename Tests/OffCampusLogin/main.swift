import Foundation

let portal = URL(string: PortalClient.portalBase)!
let gateway = URL(string: WebVPN.base)!
let wrapped = URL(string: WebVPN.wrap(PortalClient.portalBase))!
var flow = PortalLoginFlow()
precondition(flow.action(for: gateway) == .navigate(URL(string: WebVPN.casService)!))
precondition(flow.action(for: URL(string: WebVPN.casService)!) == .navigate(wrapped))
precondition(flow.action(for: wrapped) == .capture, "必须进入代理门户后再交接会话")
var direct = PortalLoginFlow()
precondition(direct.action(for: portal) == .capture, "校内直连不应强制改走网关")
var legacy = PortalLoginFlow()
precondition(legacy.action(for: URL(string: "https://portal.neu.edu.cn/tp_up/")!) == .navigate(portal))
precondition(!PortalLoginFlow.isPersonalPortal(URL(string: "https://personal.neu.edu.cn.attacker.com/portal")!))
precondition(!PortalLoginFlow.isPersonalPortal(URL(string: "http://personal.neu.edu.cn/portal")!))
precondition(flow.action(for: gateway) == .capture, "失败兜底不循环跳转")
precondition(flow.action(for: CasCrypto.casLoginURL) == .wait)
print("Off-campus routing: 9 checks passed")

// Gateway-first must never send the user through another gateway login after authentication.
var singleLogin = PortalLoginFlow(gatewayFirst: true)
let proxyCAS = URL(string: WebVPN.wrap(CasCrypto.casLoginURL.absoluteString))!
precondition(singleLogin.action(for: proxyCAS, hasLoginForm: true) == .wait)
precondition(singleLogin.action(for: gateway) == .navigate(wrapped))
precondition(singleLogin.action(for: wrapped) == .capture)
precondition(singleLogin.action(for: gateway) == .capture, "不能在认证完成后重新打开网关登录")
let browserURLs = [
    "https://bb.neu.edu.cn/webapps/bb-sso-BBLEARN/index.jsp",
    "http://ipgw.neu.edu.cn:8800/sso/default/neusoft",
    "http://210.30.206.223:8088/signal_web/into/201/3",
    "http://219.216.96.64/redirect/cas/login",
    "https://plat.neu.edu.cn/telephone-directory/",
    "https://so.neu.edu.cn/#/accessLogin?searchWord=课表",
    "https://personal.neu.edu.cn/portal/pages/mimipath/mimipath?appId=146",
    "https://bb.neu.edu.cn/a%2Fb?q=a%26b#part%201",
    "https://bb.neu.edu.cn#course"
].map { URL(string: $0)! }
for url in browserURLs {
    precondition(WebVPN.shouldProxyBrowserURL(url))
    let encoded = WebVPN.wrap(url.absoluteString)
    precondition(WebVPN.wrap(encoded) == encoded)
    precondition(WebVPN.unwrap(URL(string: encoded)!) == url, "端口、路径编码、查询及 SPA 锚点必须完整保留")
}
precondition(WebVPN.encryptHost("pass.neu.edu.cn") == "62304135386136393339346365373340a0e0b72cc4cb43c8bc1d6f66c806db", "与学校实际认证入口一致")
for rawURL in ["https://example.com/", "http://127.0.0.1:8787/", "mailto:test@neu.edu.cn",
               "https://neu.edu.cn.attacker.com/", "https://example.com/?next=https://webvpn.neu.edu.cn/"] {
    precondition(!WebVPN.shouldProxyBrowserURL(URL(string: rawURL)!))
    precondition(!WebVPN.isWrapped(rawURL))
}
precondition(!WebVPN.isIntranet("https://ecard.neu.edu.cn.attacker.com/"))
precondition(WebVPN.unwrap(URL(string: "https://webvpn.neu.edu.cn/https/not-valid/x")!) == nil)
let callback = URL(string: "https://jwxt.neu.edu.cn/jwapp/sys/homeapp/index.do?a=1&b=2")!
var proxiedAuth = URLComponents(url: proxyCAS, resolvingAgainstBaseURL: false)!
proxiedAuth.queryItems = [URLQueryItem(name: "service", value: WebVPN.wrap(callback.absoluteString)), URLQueryItem(name: "method", value: "get")]
let publicAuth = WebVPN.publicCASURL(from: proxiedAuth.url!)!
precondition(publicAuth.host == "pass.neu.edu.cn" && publicAuth.path == "/tpass/login")
precondition(URLComponents(url: publicAuth, resolvingAgainstBaseURL: false)!.queryItems!.first!.value == callback.absoluteString)
print("Gateway-first login, complete campus URL routing, official codec vector, round trips and CAS callbacks passed")

let raw = #"{"uid":"42","name":"测试同学","xgh":"20260042","identity":"本科生","depart":"计算机学院","email":"test@example.edu"}"#
let user = PortalUser.fromBrowserJSON(raw)!
precondition(user.hasCoreProfile && user.email == "test@example.edu")
precondition(PortalUser.fromBrowserJSON(#"{"uid":"42"}"#) == nil)
precondition(PortalUser.fromBrowserJSON("{}") == nil)
let quoted = String(data: try JSONSerialization.data(withJSONObject: raw, options: [.fragmentsAllowed]), encoding: .utf8)!
precondition(PortalUser.fromBrowserJSON(quoted) == user)
let partial = PortalUser.fromBrowserJSON(#"{"uid":"42","name":"测试同学"}"#)!
precondition(!partial.hasCoreProfile && partial.merging(user) == user)
precondition(user.merging(partial).department == user.department)
precondition(user.merging(.fromInfoJson(["uid":"43", "xgh":"20260043"])).email.isEmpty)
precondition(PortalClient.extractUser(fromHTML: "window.userInfoDSL = \(raw);") == user)
precondition(PortalClient.extractUser(fromHTML: "window.userInfoDSL = {};") == nil)
print("Browser profile handoff: 9 checks passed")

let fresh = PortalApp(name: "教务系统（新）", appId: "138", url: "https://jwxt.neu.edu.cn/new", mobileUrl: "",
                      iconUrl: "", desc: "", category: "教学学习", visits: 1)
let extra = PortalApp(name: "缓存服务", appId: "900", url: "https://extra.neu.edu.cn", mobileUrl: "",
                      iconUrl: "", desc: "", category: "公共服务", visits: 1)
let merged = ServiceCatalog.merging([DemoData.apps, [extra], [fresh]])
precondition(merged.count == DemoData.apps.count + 1)
precondition(merged.prefix(16).contains { $0.appId == "2" && $0.name == "VPN服务" })
precondition(merged.first?.url == fresh.url && merged.first?.iconUrl.isEmpty == false)
precondition(ServiceCatalog.merging([merged, []]) == merged)
let restored = try JSONDecoder().decode([PortalApp].self, from: JSONEncoder().encode(merged))
precondition(restored == merged)
print("Service catalog preservation: 5 checks passed")

func requestBody(_ request: URLRequest) -> String {
    if let data = request.httpBody { return String(decoding: data, as: UTF8.self) }
    guard let stream = request.httpBodyStream else { return "" }
    stream.open()
    defer { stream.close() }
    var data = Data()
    var bytes = [UInt8](repeating: 0, count: 1024)
    while stream.hasBytesAvailable {
        let count = stream.read(&bytes, maxLength: bytes.count)
        if count <= 0 { break }
        data.append(contentsOf: bytes.prefix(count))
    }
    return String(decoding: data, as: UTF8.self)
}

final class MockPortalProtocol: URLProtocol {
    static var handle: ((URLRequest) -> (Int, [String: String], String))!
    static var failure: Error?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        if let failure = Self.failure { client?.urlProtocol(self, didFailWithError: failure); return }
        let (status, headers, text) = Self.handle(request)
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(text.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

let config = URLSessionConfiguration.ephemeral
config.protocolClasses = [MockPortalProtocol.self]
let http = HTTPClient(configuration: config)
let client = PortalClient(http: http)
let ticket = HTTPCookie(properties: [.name:"wengine_vpn_ticket", .value:"fixture-ticket", .domain:"webvpn.neu.edu.cn", .path:"/", .secure:"TRUE"])!
client.absorbCookies([ticket])
client.adoptGatewayTicket()
client.setUserAgent("Fixture WebKit UA")
// A gateway-authenticated user must not be reclassified by a fresh campus probe.
MockPortalProtocol.handle = { _ in preconditionFailure("已有网关票据时不应再探测并覆盖校外路由") }
let gatewayEntry = await client.browserLoginEntryURL()
precondition(gatewayEntry == URL(string: WebVPN.casService)!)
for url in browserURLs {
    let destination = await client.prepareBrowserURL(url)
    precondition(destination.absoluteString == WebVPN.wrap(url.absoluteString))
}
for app in DemoData.apps {
    guard let url = URL(string: app.entryUrl()) else { continue }
    let expected = WebVPN.shouldProxyBrowserURL(url) ? URL(string: WebVPN.wrap(url.absoluteString))! : url
    let routed = await client.prepareBrowserURL(url)
    precondition(routed == expected, "完整服务目录必须统一使用校外路由：" + app.name)
}
precondition(client.browserDestination(for: proxyCAS) == proxyCAS, "网关登录继续使用同域 CAS")
let nativeConfig = URLSessionConfiguration.ephemeral
nativeConfig.protocolClasses = [MockPortalProtocol.self]
let nativeRealm = PortalClient(http: HTTPClient(configuration: nativeConfig))
nativeRealm.absorbCookies([ticket, HTTPCookie(properties: [.name:"CASTGC", .value:"native-cas", .domain:"pass.neu.edu.cn", .path:"/tpass", .secure:"TRUE"])!])
nativeRealm.adoptGatewayTicket()
precondition(nativeRealm.browserDestination(for: proxiedAuth.url!) == publicAuth, "原生登录复用公网 CAS，不要求重新在代理域输入密码")
nativeRealm.clearSession()
precondition(nativeRealm.browserDestination(for: browserURLs[0]) == browserURLs[0])

// Public denial pages are not evidence of an on-campus connection.
let probeConfig = URLSessionConfiguration.ephemeral
probeConfig.protocolClasses = [MockPortalProtocol.self]
let probeClient = PortalClient(http: HTTPClient(configuration: probeConfig))
var probes = 0
MockPortalProtocol.handle = { request in
    precondition(["ecard.neu.edu.cn", "jwxt.neu.edu.cn"].contains(request.url!.host!))
    probes += 1
    return (403, [:], "Access Denied")
}
let detectedEntry = await probeClient.browserLoginEntryURL()
precondition(detectedEntry == URL(string: WebVPN.casService)! && probes == 2)
MockPortalProtocol.handle = { request in
    precondition(request.url?.host == "webvpn.neu.edu.cn")
    return (200, [:], "<html>login required</html>")
}
let gatewayFallback = await probeClient.prepareBrowserURL(browserURLs[0])
precondition(gatewayFallback.absoluteString == WebVPN.wrap(browserURLs[0].absoluteString))
precondition(!probeClient.hasLoginSession, "选择校外地址不能伪造已登录状态")
print("Login entry detection, sticky off-campus mode, account cleanup and public/native CAS realm reuse passed")

var requests = 0
MockPortalProtocol.handle = { request in
    requests += 1
    precondition(request.url == wrapped)
    precondition(request.value(forHTTPHeaderField: "User-Agent") == "Fixture WebKit UA")
    precondition(request.value(forHTTPHeaderField: "Cookie")?.contains("fixture-ticket") == true)
    return (200, [:], "<script>window.userInfoDSL = \(raw);</script>")
}
let fetched = try await client.fetchUserInfo()
precondition(fetched == user && requests == 1 && client.hasWebVPNTicket)
MockPortalProtocol.handle = { request in
    precondition(request.url!.absoluteString.hasPrefix(wrapped.absoluteString + "/appmarket/"))
    precondition(request.url!.query!.contains("limit=999"))
    precondition(request.value(forHTTPHeaderField: "User-Agent") == "Fixture WebKit UA")
    precondition(request.value(forHTTPHeaderField: "X-Requested-With") == "XMLHttpRequest")
    return (200, [:], #"{"e":0,"d":{"list":[{"id":138,"name":"教务系统（新）","url":"https://jwxt.neu.edu.cn"}]}}"#)
}
let shortList = try await client.fetchApps()
precondition(shortList.count == 1 && shortList[0].appId == "138")
precondition(ServiceCatalog.merging([DemoData.apps, shortList]).contains { $0.appId == "2" })
// Native news must keep channel, page and Chinese search terms in the actual routed GET.
var newsRequests = 0
MockPortalProtocol.handle = { request in
    let destination = WebVPN.unwrap(request.url!) ?? request.url!
    precondition(request.httpMethod == "GET")
    if destination.path.hasSuffix("/news/frontend/default/tabs") {
        return (200, [:], #"{"e":0,"d":{"list":[{"id":"campus","name":"东大要闻"},{"id":"culture","name":"校园文化"},{"id":"culture","name":"重复频道"},{"id":"","name":"无效频道"}]}}"#)
    }
    precondition(destination.path.hasSuffix("/news/frontend/default/news-list"))
    let fields = URLComponents(url: destination, resolvingAgainstBaseURL: false)!.queryItems!
    func value(_ key: String) -> String? { fields.first { $0.name == key }?.value }
    precondition(value("cid") == "culture" && value("page") == "2")
    precondition(value("pageSize") == "30" && value("keyword") == "校园 科技&人文")
    newsRequests += 1
    return (200, [:], #"{"e":0,"d":{"list":[{"id":"article-2","title":"合成资讯","publish_time":"2026-11-14 09:00:00","url":"https://neunews.neu.edu.cn/info/1/2.htm"}]}}"#)
}
let newsChannels = try await client.fetchNewsChannels()
precondition(newsChannels.count == 2 && newsChannels[1].name == "校园文化")
let newsPage = try await client.fetchNews(pageSize: 30, channel: newsChannels[1], page: 2, keyword: "校园 科技&人文")
precondition(newsRequests == 1 && newsPage.count == 1 && newsPage[0].category == "校园文化" && newsPage[0].date == "2026-11-14")
print("Native news: unique channels, routed pagination and encoded Chinese keyword passed")
// 校外资料被 WAF 拦截但没有 CASTGC 时，重试不能销毁唯一可用的网关票据。
MockPortalProtocol.handle = { _ in (403, [:], "仅用于我校师生在校外登录") }
do { _ = try await client.fetchUserInfo(); preconditionFailure("拦截页不能冒充个人资料") }
catch { precondition(client.hasWebVPNTicket && client.hasLoginSession) }
client.clearSession()
precondition(!client.hasLoginSession && !client.webvpnOn)
print("HTTP session handoff, gateway APIs, UA and ticket preservation: passed")


let anonymous = HTTPCookie(properties: [.name:"SESS_ID", .value:"anonymous", .domain:"personal.neu.edu.cn", .path:"/"])!
precondition(!PortalLoginDocument.canComplete(user: nil, cookies: [anonymous], hasLoginForm: false))
precondition(!PortalLoginDocument.canComplete(user: user, cookies: [ticket], hasLoginForm: true))
precondition(PortalLoginDocument.canComplete(user: user, cookies: [ticket], hasLoginForm: false))
var typing = PortalLoginFlow()
precondition(typing.action(for: portal, hasLoginForm: true) == .wait)
precondition(typing.action(for: URL(string: WebVPN.wrap(CasCrypto.casLoginURL.absoluteString))!) == .wait)
precondition(PortalLoginDocument.decode(nil).hasLoginForm)
print("Login typing: anonymous cookies, visible forms and failed document reads cannot dismiss the sheet")

let schoolConfig = URLSessionConfiguration.ephemeral
schoolConfig.protocolClasses = [MockPortalProtocol.self]
let schoolHTTP = HTTPClient(configuration: schoolConfig)
let schoolClient = PortalClient(http: schoolHTTP)
schoolHTTP.cookies.absorbRaw(CasCrypto.casLoginURL, "CASTGC=fixture-cas; Path=/tpass")
var exchangedJWXT = false
var exchangedCard = false
MockPortalProtocol.handle = { request in
    let url = request.url!
    if url.host == "ecard.neu.edu.cn" && url.path == "/" {
        // 正常的校园网 302 必须算可达，不能强制转向 WebVPN。
        return (302, ["Location":"/selflogin/login.aspx"], "")
    }
    if url.host == "pass.neu.edu.cn" {
        let service = URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems!.first { $0.name == "service" }!.value!
        precondition(request.value(forHTTPHeaderField: "Cookie")?.contains("fixture-cas") == true)
        if service.contains("jwxt.neu.edu.cn") {
            exchangedJWXT = true
            return (302, ["Location":service + "?ticket=ST-jwxt"], "")
        }
        precondition(service == PortalClient.serviceCard)
        exchangedCard = true
        return (302, ["Location":service + "?ticket=ST-card"], "")
    }
    if url.host == "jwxt.neu.edu.cn" {
        if url.path.hasSuffix("/index.do") {
            precondition(exchangedJWXT)
            return (200, ["Set-Cookie":"JSESSIONID=jwxt; Path=/jwapp"], "<html>student</html>")
        }
        precondition(request.value(forHTTPHeaderField: "Cookie")?.contains("JSESSIONID=jwxt") == true)
        if url.path.hasSuffix("/home/index.html") { return (200, [:], "<html>student home</html>") }
        let referer = "https://jwxt.neu.edu.cn/jwapp/sys/homeapp/home/index.html?av=&contextPath=/jwapp"
        // 模拟学校 Referer 检查，错误的认证入口 Referer 会得到 403。
        guard request.value(forHTTPHeaderField: "Referer") == referer else { return (403, [:], "Forbidden") }
        precondition(request.value(forHTTPHeaderField: "Fetch-Api") == "true")
        if url.path.hasSuffix("schoolCalendars.do") {
            return (200, [:], #"{"code":0,"datas":[{"itemCode":"2026-1","itemName":"秋季","selected":true}]}"#)
        }
        precondition(url.path.hasSuffix("scores.do"))
        return (200, [:], #"{"code":0,"datas":[{"courseName":"数学","credit":3,"score":"92"}]}"#)
    }
    precondition(url.host == "ecard.neu.edu.cn" && exchangedCard)
    if url.path == "/selflogin/login.aspx" {
        return (200, [:], #"<form><INPUT VALUE='20260042' NAME='username'><input value=fixture-time name=timestamp><input name='auid' value='fixture&#45;auid&amp;token'></form>"#)
    }
    if url.path == "/selfsearch/SSOLogin.aspx" {
        precondition(request.httpMethod == "POST")
        let body = requestBody(request)
        precondition(body.contains("username=20260042") && body.contains("timestamp=fixture-time"))
        precondition(body.contains("auid=fixture-auid%26token"), "必须解码 HTML 实体后再表单编码")
        precondition(request.value(forHTTPHeaderField: "Referer")?.contains("/selflogin/login.aspx") == true)
        precondition(request.value(forHTTPHeaderField: "Origin") == "http://ecard.neu.edu.cn")
        return (200, ["Set-Cookie":"ASP.NET_SessionId=card; Path=/selfsearch"], "<html>ok</html>")
    }
    precondition(url.path == PortalClient.cardHomePath)
    precondition(request.value(forHTTPHeaderField: "Cookie")?.contains("ASP.NET_SessionId=card") == true)
    return (200, [:], #"<input id="ContentPlaceHolder1_txtOddFare" value="52.30"><input id="ContentPlaceHolder1_txtSpecialOddFare" value="7.50">"#)
}
let onCampus = await schoolClient.isCampusNet()
precondition(onCampus && !schoolClient.webvpnOn)
let campusEntry = await schoolClient.browserLoginEntryURL()
precondition(campusEntry == CasCrypto.casLoginURL)
let grades = try await schoolClient.fetchJwxtGrades()
precondition(grades.semesters.count == 1 && grades.semesters[0].courses.first?.score == 92)
let card = try await schoolClient.fetchCardBalance()
precondition(card.balance == 52.30 && card.subsidy == 7.50 && !schoolClient.webvpnOn)

let reorderedBills = #"""
<table><tr><td>外层布局<table>
<tr><th>序号</th><th>终端商户</th><th>交易日期</th><th>交易金额</th><th>交易类型</th><th>余额</th><th>手续费</th></tr>
<tr><td>1</td><td>一食堂</td><td>2026年10月1日 12:30</td><td>￥ 5.00 元</td><td>消费</td><td>66.50</td><td>0.00</td></tr>
<tr><td>2</td><td>充值站</td><td>2026/10/2 9:05</td><td>-1,234.56</td><td>补助充值</td><td>1,301.06</td><td>0.00</td></tr>
<tr><td>3</td><td>物联网采集</td><td>2026-10-02</td><td>0.00</td><td>消费</td><td>66.50</td><td>0.00</td></tr>
</table></td></tr></table>
"""#
let parsedBills = try PortalClient.parseBillTable(reorderedBills)
precondition(parsedBills.count == 2 && parsedBills[0].amount == -5 && parsedBills[0].station == "一食堂")
precondition(parsedBills[1].amount == 1234.56 && parsedBills[1].balanceAfter == 1301.06)
precondition(parsedBills.allSatisfy { $0.time != nil })
let legacyBills = try PortalClient.parseBillTable("<table><tr><td>2026-10-01 12:00</td><td>消费</td><td>3.50</td><td>0</td><td>0</td></tr></table>")
precondition(legacyBills.count == 1 && legacyBills[0].amount == -3.5)
let emptyBills = try PortalClient.parseBillTable("<p>共 0 条记录</p>")
precondition(emptyBills.isEmpty)
for invalid in ["<html>Service unavailable</html>", reorderedBills.replacingOccurrences(of: "￥ 5.00 元", with: "***")] {
    do {
        _ = try PortalClient.parseBillTable(invalid)
        preconditionFailure("未识别页面和掩码金额不能作为空流水或零元消费")
    } catch {}
}
precondition(PortalClient.hasNextPage("<div>共 12 页</div>", 11))
precondition(!PortalClient.hasNextPage("<div>共 2 页</div>", 3))
precondition(PortalClient.hasNextPage(#"<a href="javascript:__doPostBack('ctl00$ContentPlaceHolder1$AspNetPager1','2')">下一页</a>"#, 2))
precondition(!PortalClient.hasNextPage("<input value='2'><td>2</td>", 2))
let formHTML = #"<input type='hidden' name='__VIEWSTATE' value='state&amp;2'><input name='ctl00$ContentPlaceHolder1$btnSearch' value='查询'>"#
let searchFields = PortalClient.cardBillSearchFields(html: formHTML, year: 2024, month: 2)
precondition(searchFields["ctl00$ContentPlaceHolder1$txtEndDate"] == "2024-02-29")
precondition(searchFields["ctl00$ContentPlaceHolder1$btnSearch"] == "查询")
let pageFields = PortalClient.cardBillSearchFields(html: formHTML, year: 2026, month: 10, includeSearchButton: false)
precondition(pageFields["__VIEWSTATE"] == "state&2" && pageFields["ctl00$ContentPlaceHolder1$btnSearch"] == nil)
precondition(pageFields["ctl00$ContentPlaceHolder1$txtStartDate"] == "2026-10-01")

let cardSessionHandler = MockPortalProtocol.handle!
var statementPageCount = 2
var repeatStatement = false
var statementPosts = 0
MockPortalProtocol.handle = { request in
    guard request.url!.path.hasSuffix("ConsumeInfo.aspx") else { return cardSessionHandler(request) }
    if request.httpMethod != "POST" { return (200, [:], "<input type='hidden' name='__VIEWSTATE' value='first'>") }
    let fields = URLComponents(string: "https://fixture/?" + requestBody(request))!.queryItems!
    func field(_ name: String) -> String? { fields.first { $0.name == name }?.value }
    let prefix = "ctl00$ContentPlaceHolder1$"
    let page = Int(field("__EVENTARGUMENT") ?? "1")!
    statementPosts += 1
    precondition(field("__VIEWSTATE") == (page == 1 ? "first" : "state-\(page - 1)"))
    precondition(field(prefix + "txtStartDate") == "2026-10-01" && field(prefix + "txtEndDate") == "2026-10-31")
    precondition(field(prefix + "rbtnType") == "0")
    precondition((page == 1) == (field(prefix + "btnSearch") != nil))
    if page > 1 { precondition(field("__EVENTTARGET") == prefix + "AspNetPager1") }
    let day = repeatStatement ? 1 : page
    return (200, [:], "<input type='hidden' name='__VIEWSTATE' value='state-\(page)'>" +
        "<table><tr><th>商户</th><th>日期</th><th>金额</th><th>摘要</th></tr>" +
        "<tr><td>食堂</td><td>2026-10-\(day)</td><td>5.00</td><td>消费</td></tr></table><div>共 \(statementPageCount) 页</div>")
}
let nativeStatement = try await schoolClient.fetchCardBills(year: 2026, month: 10)
precondition(nativeStatement.bills.count == 2 && !nativeStatement.truncated && statementPosts == 2)
statementPageCount = 12
statementPosts = 0
let limitedStatement = try await schoolClient.fetchCardBills(year: 2026, month: 10)
precondition(limitedStatement.bills.count == 10 && limitedStatement.truncated && statementPosts == 10)
repeatStatement = true
do {
    _ = try await schoolClient.fetchCardBills(year: 2026, month: 10)
    preconditionFailure("重复页面不能被当作完整流水")
} catch { precondition(NetworkError.from(error).message.contains("翻页未推进")) }
MockPortalProtocol.handle = cardSessionHandler
print("Card statements: header columns, legacy rows, Chinese dates, signed money, empty/error pages, latest viewstate, date filters, repeat detection and ten-page limit passed")
do {
    _ = try PortalClient.parseCardBalance(fromHTML: #"<input id="ContentPlaceHolder1_txtOddFare" value="***">"#)
    preconditionFailure("掩码余额不能变成假零元")
} catch {}
let missingSubsidy = try PortalClient.parseCardBalance(fromHTML: #"<input id="ContentPlaceHolder1_txtOddFare" value="0.00">"#)
precondition(missingSubsidy.balance == 0 && missingSubsidy.subsidy == nil)
print("Campus grades/card: 302 probes, explicit CAS ST, session cookies, Referer, real balances and masked-data errors passed")

let visibleWallet = try PortalClient.parseCardBalance(fromHTML: #"""
<span>学号：20269999</span><span>卡状态：正常卡</span>
<div><span>主钱包余额：</span><span>￥1,234.50元</span></div>
<div>补助余额：0元</div>
"""#)
precondition(visibleWallet.balance == 1234.50 && visibleWallet.subsidy == 0 && visibleWallet.status == "正常卡")
let labelWallet = try PortalClient.parseCardBalance(fromHTML: #"<span id='ctl00_NewContent_lblOddFare'>32.10</span><label id='NewContent_lblSpecialOddFare'>7.50</label>"#)
precondition(labelWallet.balance == 32.10 && labelWallet.subsidy == 7.50)
for invalid in ["***", "**.23", "12.345", "1,23.45"] {
    do {
        _ = try PortalClient.parseCardBalance(fromHTML: "<span>主钱包余额：\(invalid)元</span><span>学号：20269999</span>")
        preconditionFailure("Masked or malformed amounts cannot become balances")
    } catch { }
}
do {
    _ = try PortalClient.parseCardBalance(fromHTML: #"<script>const example = '<input id="ContentPlaceHolder1_txtOddFare" value="99">';</script><span>补助余额：8元</span>"#)
    preconditionFailure("Script examples and subsidy amounts cannot become wallet balances")
} catch { }
precondition(NetworkError.isCancellation(CancellationError()) && NetworkError.isCancellation(URLError(.cancelled)))
precondition(!NetworkError.from(CancellationError()).message.contains("Swift"))
print("Card visible labels, ASP.NET spans, thousands, zero subsidy, masked/malformed values and cancellation messages passed")

// 三个字段共用输入解析时仍保持 input > ASP.NET label > 可见文字的原有优先级。
let cachedInputFixtures: [(String, Double, Double?, String)] = [
    (#"<input id='ctl00$TXTODDFARE' value='￥1,234.50'><input name=txtSubsidy value='0'><input id='prefix_txtStatus' value='正&#24120;卡'><span id='lblOddFare'>999</span>"#, 1234.50, 0, "正常卡"),
    (#"<input id=txtOddFare value=' '><span id='prefix_lblOddFare'>12.50</span><output id='prefix_lblSpecialOddFare'>7.25</output><label id='labStatus'>挂失</label>"#, 12.50, 7.25, "挂失"),
    (#"<input id=txtOddFare value='1.25'><div>主钱包余额：99元 补助余额：2.50元 卡状态：正常卡</div>"#, 1.25, 2.50, "正常卡"),
    (#"<input id='notxtOddFare' value='999'><div>主钱包余额：3.75元</div>"#, 3.75, nil, ""),
    (#"<span id='lblOddFare'>4.25</span><input id='txtSpecialOddFare' value='6.50'><input name='txtStatus' value='冻结'>"#, 4.25, 6.50, "冻结"),
    (#"<!-- <input id='txtOddFare' value='999'> --><style>input[value='999']{}</style><input id='txtOddFare' value='0'>"#, 0, nil, "")
]
for _ in 0..<20 {
    for (html, balance, subsidy, status) in cachedInputFixtures {
        let result = try CardBalanceDocument.parse(html)
        precondition(result.balance == balance && result.subsidy == subsidy && result.status == status,
                     "同页字段优先级及连续解析不同页面不串值")
    }
}
do {
    _ = try CardBalanceDocument.parse(#"<input id='txtOddFare' value='***'><span id='lblOddFare'>99</span>主钱包余额：88元"#)
    preconditionFailure("已有掩码 input 不得回退为示例金额")
} catch { }
print("Card parsing performance regression: 120 multi-field/page isolation checks and masked-input precedence passed")

let cgReport = try CGAssignmentReport.decode(["assignments": [[
    "id": "7", "title": "课后作业", "deadline": "2026-11-10 23:59:59", "loaded": true,
    "problems": [["id": "1", "title": "题目一", "statusText": "得分：100 完全正确"],
                 ["id": "2", "title": "题目二", "statusText": "还未提交"],
                 ["id": "3", "title": "题目三", "statusText": "完全正确 答案错误"],
                 ["id": "4", "title": "题目四", "statusText": "得分：100"]]
]], "warnings": []])
let assignment = cgReport.assignments[0]
precondition(assignment.completedCount == 1 && !assignment.isComplete && assignment.deadline != nil)
precondition(assignment.problems.map(\.status) == [.complete, .notSubmitted, .needsWork, .submitted])
do {
    _ = try CGAssignmentReport.decode(["assignments": [], "warnings": []])
    preconditionFailure("Blank CG sessions cannot become completed assignments")
} catch { }
print("CG report: deadlines, full correctness, unsubmitted/partial/unknown results and blank session handling passed")

let detailedProblem = CGProblem(id: "opaque", title: "题目", url: nil,
    statusText: "最后一次提交时间: 2026-11-02 12:13:14 得分：10.00 共有测试数据:2 测试数据1 完全正确 测试数据2 答案错误 详细")
precondition(detailedProblem.scoreText == "10.00", "CG score field was \(detailedProblem.scoreText)")
precondition(detailedProblem.submittedAt == "2026-11-02 12:13:14", "CG submission date was \(detailedProblem.submittedAt)")
precondition(detailedProblem.testResults.count == 2 && detailedProblem.status == .needsWork)
precondition(CGProblem(id: "pending", title: "待评判", url: nil, statusText: "得分：100 测试数据1 结果待公布").status == .submitted)
let cgStatusFixtures: [(String, CGProblem.Status, String, String, Int)] = [
    ("", .submitted, "", "", 0),
    ("完全正确", .complete, "", "", 0),
    ("未提交 完全正确", .notSubmitted, "", "", 0),
    ("完全正确 答案错误", .needsWork, "", "", 0),
    ("共有测试数据：2 测试数据1 完全正确 测试数据2 完全正确 详细", .complete, "", "", 2),
    ("共有测试数据：3 测试数据1 完全正确 测试数据2 完全正确", .submitted, "", "", 2),
    ("共有测试数据：0 测试数据1 完全正确", .complete, "", "", 1),
    ("得分:100 测试数据1 结果待公布", .submitted, "100", "", 1),
    ("😀 得分：10.50 最后一次提交时间：2026-11-02 12:13 测试数据 1 完全正确", .complete, "10.50", "2026-11-02 12:13", 1),
    ("得分：0 最后一次提交时间:2026-11-02 12:13:14 测试数据1 超时", .needsWork, "0", "2026-11-02 12:13:14", 1)
]
for _ in 0..<20 {
    for (text, status, score, submittedAt, count) in cgStatusFixtures {
        let problem = CGProblem(id: "shared-id", title: "题目", url: nil, statusText: text)
        precondition(problem.status == status && problem.scoreText == score && problem.submittedAt == submittedAt)
        precondition(problem.testResults.count == count)
        precondition(problem.status == status, "重复读取及相同 ID 的不同状态文本不串值")
        let data = try JSONEncoder().encode(problem)
        let restored = try JSONDecoder().decode(CGProblem.self, from: data)
        precondition(restored == problem && restored.status == status && restored.testResults == problem.testResults)
        let object = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        precondition(Set(object.keys) == Set(["id", "title", "statusText"]), "只读正则不得改变历史缓存格式")
    }
}
print("CG parsing performance regression: 200 repeated status/detail/Codable checks passed")
let partialAssignment = CGAssignment(id: "partial", title: "作业", url: nil, deadlineText: "", late: false,
    history: false, loaded: true, problems: [CGProblem(id: "1", title: "已读题", url: nil, statusText: "完全正确")], expectedProblemCount: 2)
precondition(!partialAssignment.isComplete && partialAssignment.problemCount == 2)
precondition(Campus.inferred(from: "未来技术学院/人工智能") == .hunnan)
precondition(Campus.inferred(from: "信息科学与工程学院") == .nanhu)
precondition(Campus.inferred(from: "浑南校区/未知专业") == .hunnan)
precondition(Campus.inferred(from: "未知学院") == nil)
let learningURL = URL(string: "https://www.icourse163.org/learn/NEU-1?tid=1")!
let course = LearningCourse(id: "NEU-1", termID: "1", title: "课程", url: learningURL)
let oldTask = LearningAssignment(id: "old", courseKey: course.key, courseTitle: course.title, title: "旧作业", kind: "作业",
    url: learningURL, deadline: nil, deadlineText: "", statusText: "未提交", completed: false, scoreText: "")
let previousLearning = LearningAssignmentReport(courses: [course], assignments: [oldTask], warnings: [], refreshedCourseKeys: [course.key], accountKey: "a")
let interruptedLearning = LearningAssignmentReport(courses: [course], assignments: [], warnings: ["读取失败"], refreshedCourseKeys: [], accountKey: "a")
precondition(interruptedLearning.merging(previousLearning).assignments.count == 1)
let emptyLearning = LearningAssignmentReport(courses: [course], assignments: [], warnings: [], refreshedCourseKeys: [course.key], accountKey: "a")
precondition(emptyLearning.merging(previousLearning).assignments.isEmpty)
var otherLearning = interruptedLearning
otherLearning.accountKey = "b"
precondition(otherLearning.merging(previousLearning).assignments.isEmpty)
let restoredLearning = try JSONDecoder().decode(LearningAssignmentReport.self, from: JSONEncoder().encode(previousLearning))
precondition(restoredLearning.accountKey == "a" && restoredLearning.assignments == [oldTask])
let restoredSections = restoredLearning.sections(for: .mooc)
precondition(restoredSections.count == 1 && restoredSections[0].items == [oldTask] && restoredSections[0].read)
let restoredCG = try JSONDecoder().decode(CGAssignmentReport.self, from: JSONEncoder().encode(CGAssignmentReport(assignments: [partialAssignment], warnings: [])))
precondition(restoredCG.assignments == [partialAssignment])
let savedAssignments = AssignmentCacheStore.Snapshot(cg: restoredCG, cgUpdatedAt: Date(), reports: [.mooc: previousLearning], updatedAt: [.mooc: Date()])
let restoredAssignments = try JSONDecoder().decode(AssignmentCacheStore.Snapshot.self, from: JSONEncoder().encode(savedAssignments))
precondition(restoredAssignments.reports[.mooc]?.assignments == [oldTask] && restoredAssignments.cg?.assignments == [partialAssignment])
let learningCookies = CookieJar()
let learningCookie = HTTPCookie(properties: [.name: "NTESSTUDYSI", .value: "session", .domain: ".icourse163.org", .path: "/"])!
let otherCookie = HTTPCookie(properties: [.name: "other", .value: "retained", .domain: "personal.neu.edu.cn", .path: "/"])!
learningCookies.absorb([learningCookie, otherCookie])
learningCookies.replace([], matching: LearningPlatform.mooc.ownsCookie)
precondition(!learningCookies.hasCookie(learningURL, "NTESSTUDYSI"))
precondition(learningCookies.hasCookie(portal, "other"), "Platform logout must preserve other services")
precondition(!LearningPlatform.mooc.ownsCookie(HTTPCookie(properties: [.name: "foreign", .value: "x", .domain: "163.com.evil.test", .path: "/"])!))
let learningRestoreClient = PortalClient()
let currentGatewayCookie = HTTPCookie(properties: [.name: "wengine_vpn_ticket", .value: "current-ticket", .domain: "webvpn.neu.edu.cn", .path: "/"])!
let oldGatewayCookie = HTTPCookie(properties: [.name: "wengine_vpn_ticket", .value: "stale-ticket", .domain: "webvpn.neu.edu.cn", .path: "/"])!
learningRestoreClient.absorbBrowserCookies([learningCookie, otherCookie, currentGatewayCookie])
learningRestoreClient.restoreLearningCookies([oldGatewayCookie])
precondition(!learningRestoreClient.browserCookies().contains { $0.name == "NTESSTUDYSI" }, "Platform logout in a newer snapshot must override older portal cookies")
precondition(learningRestoreClient.browserCookies().contains { $0.name == "wengine_vpn_ticket" && $0.value == "current-ticket" })
print("CG opaque IDs and details, expected problem counts, campus inference and per-account partial learning report merge passed")

@MainActor
func verifyLearningProfiles() {
    let suite = "learning-profiles-" + UUID().uuidString
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let profiles = LearningBrowserProfiles(defaults: defaults)
    let a = profiles.identifier(account: "A", platform: .mooc)!
    let b = profiles.identifier(account: "B", platform: .mooc)!
    let cx = profiles.identifier(account: "A", platform: .chaoxing)!
    let mail = profiles.identifier(account: "A", service: .mail)!
    let otherMail = profiles.identifier(account: "B", service: .mail)!
    precondition(Set([a, b, cx, mail, otherMail]).count == 5)
    precondition(LearningBrowserProfiles(defaults: UserDefaults(suiteName: suite)!).identifier(account: "A", service: .mail) == mail)
    precondition(a != b && a != cx && b != cx)
    precondition(LearningBrowserProfiles(defaults: UserDefaults(suiteName: suite)!).identifier(account: "A", platform: .mooc) == a)
    precondition(profiles.identifier(account: "", platform: .mooc) == nil)
    precondition(profiles.identifier(account: "A", platform: .cg) == nil)
    profiles.retire(account: "A")
    precondition(profiles.identifier(account: "A", service: .mail) != mail)
    precondition(profiles.identifier(account: "B", service: .mail) == otherMail)
    precondition(profiles.identifier(account: "A", platform: .mooc) != a)
    precondition(profiles.identifier(account: "A", platform: .chaoxing) != cx)
    precondition(profiles.identifier(account: "B", platform: .mooc) == b)
}
verifyLearningProfiles()
let unorderedSnapshot = SavedWebSession(user: user, userAgent: "fixture", cookies: [learningCookie, otherCookie])
precondition(unorderedSnapshot == SavedWebSession(user: user, userAgent: "fixture", cookies: [otherCookie, learningCookie]),
             "WebKit cookie order must not trigger repeated Keychain writes")
precondition(unorderedSnapshot != SavedWebSession(user: user, userAgent: "fixture", cookies: [otherCookie]),
             "Deleting a platform cookie must change the persistence snapshot")
let renewedLearningCookie = HTTPCookie(properties: [.name: learningCookie.name, .value: "renewed", .domain: learningCookie.domain, .path: "/"])!
precondition(unorderedSnapshot != SavedWebSession(user: user, userAgent: "fixture", cookies: [otherCookie, renewedLearningCookie]))
print("Learning profiles: durable IDs, account/platform isolation, logout rotation and cookie snapshot deduplication passed")

let legacyCourseJSON = Data(#"{"id":"1","termID":"2","title":"课程","url":"https://i.chaoxing.com/"}"#.utf8)
let legacyCourse = try JSONDecoder().decode(LearningCourse.self, from: legacyCourseJSON)
precondition(legacyCourse.progress == nil && legacyCourse.deadline == nil)
let progressFixture = try JSONSerialization.jsonObject(with: Data(#"""
{"data":[{"id":"2","course":{"data":[{"id":"1","knowledge":{"data":[
    {"id":"10","parentnodeid":"0","finishcount":7,"unfinishcount":3},
    {"id":"11","parentnodeid":"10","finishcount":"3","unfinishcount":"1"},
    {"id":"12","parentnodeid":"10","finishcount":4,"unfinishcount":2},
    {"id":"12","parentnodeid":"10","finishcount":4,"unfinishcount":2}
]}}]}}]}
"""#.utf8))
let progress = try LearningCourseProgress.chaoxing(progressFixture, courseID: "1")
precondition(progress.completed == 7 && progress.total == 10 && progress.fraction == 0.7)
precondition((try? LearningCourseProgress.chaoxing(progressFixture, courseID: "other")) == nil)
let missingCounts = try JSONSerialization.jsonObject(with: Data(#"{"data":[{"course":{"data":[{"id":"1","knowledge":{"data":[{"id":"10"}]}}]}}]}"#.utf8))
precondition((try? LearningCourseProgress.chaoxing(missingCounts, courseID: "1")) == nil)
let exactCourseDeadline = LearningCourseProgress.chaoxingDeadline("2026-12-01 23:59:59")!
precondition(LearningCourseProgress.chaoxingDeadline("2026-12-01") == exactCourseDeadline)
precondition(LearningCourseProgress.chaoxingDeadline("2026-12-01T15:59:59Z") == exactCourseDeadline)
precondition(LearningCourseProgress.chaoxingDeadline(exactCourseDeadline.timeIntervalSince1970 * 1000) == exactCourseDeadline)
precondition(LearningCourseProgress.chaoxingDeadline("") == nil)

func courseListData(_ count: Int, mode: Int = 0, total: Int = 51) throws -> Data {
    let rows: [[String: Any]] = (1...count).map { id in
        ["id": id, "name": "测试课程", "mode": mode, "termPanel": ["id": id + 100], "schoolPanel": ["shortName": "NEU"]]
    }
    return try JSONSerialization.data(withJSONObject: ["code": 0, "result": ["result": rows, "pagination": ["totleCount": total]]])
}
let firstMOOCPage = try MOOCCoursePage.decode(courseListData(50), page: 1, pageSize: 50)
precondition(firstMOOCPage.hasMore && firstMOOCPage.courses.count == 50)
precondition(firstMOOCPage.courses[0].id == "NEU-1" && firstMOOCPage.courses[0].termID == "101")
let lastMOOCPage = try MOOCCoursePage.decode(courseListData(1, mode: 20), page: 2, pageSize: 50)
precondition(!lastMOOCPage.hasMore && lastMOOCPage.courses[0].url.path == "/spoc/learn/NEU-1")
let terminalMOOCPage = try MOOCCoursePage.decode(Data(#"{"result":{"result":null,"pagination":{"totleCount":51}}}"#.utf8), page: 3, pageSize: 50)
precondition(terminalMOOCPage.courses.isEmpty && !terminalMOOCPage.hasMore)
precondition((try? MOOCCoursePage.decode(Data(#"{"result":null}"#.utf8), page: 1, pageSize: 50)) == nil)
print("Learning course progress: leaf-only task counts, missing data, Beijing deadlines, old models and paginated MOOC/SPOC courses passed")


// A gateway-only web login must also authenticate native academic APIs through that CAS realm.
let gatewayConfig = URLSessionConfiguration.ephemeral
gatewayConfig.protocolClasses = [MockPortalProtocol.self]
let gatewayHTTP = HTTPClient(configuration: gatewayConfig)
let gatewayNative = PortalClient(http: gatewayHTTP)
let proxyCASPath = URL(string: WebVPN.wrap("https://pass.neu.edu.cn/tpass"))!.path
let proxyCASTGC = HTTPCookie(properties: [.name:"CASTGC", .value:"proxy-only-cas", .domain:"webvpn.neu.edu.cn",
    .path:proxyCASPath, .secure:"TRUE"])!
gatewayNative.absorbCookies([ticket, proxyCASTGC])
gatewayNative.adoptGatewayTicket()
var proxyExchanges = 0
MockPortalProtocol.handle = { request in
    let url = request.url!
    precondition(url.host == "webvpn.neu.edu.cn", "不能从代理登录切到没有会话的公网 CAS")
    if url.path == proxyCASPath + "/login" {
        precondition(request.value(forHTTPHeaderField: "Cookie")?.contains("proxy-only-cas") == true)
        let service = URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems!.first { $0.name == "service" }!.value!
        proxyExchanges += 1
        return (302, ["Location":service + "?ticket=ST-proxy"], "")
    }
    precondition(request.value(forHTTPHeaderField: "Cookie")?.contains("proxy-only-cas") != true, "CAS Cookie 不泄漏到业务路径")
    if url.path.hasSuffix("/index.do") || url.path.hasSuffix("/home/index.html") { return (200, [:], "<html>student</html>") }
    if url.path.hasSuffix("schoolCalendars.do") {
        return (200, [:], #"{"code":0,"datas":[{"itemCode":"2026-1","itemName":"秋季"}]}"#)
    }
    precondition(url.path.hasSuffix("scores.do"))
    return (200, [:], #"{"code":0,"datas":[{"courseName":"数学","credit":3,"score":"92"}]}"#)
}
let gatewayGrades = try await gatewayNative.fetchJwxtGrades()
precondition(proxyExchanges == 1 && gatewayGrades.semesters.first?.courses.first?.score == 92)
precondition(gatewayNative.browserDestination(for: proxyCAS) == proxyCAS)
print("Gateway-only CAS: native academic SSO, rewritten redirects and cookie path isolation passed")

final class MemoryWebSessionStore: WebSessionPersisting {
    var data: Data?
    var refuseDeletion = false
    func load() -> SavedWebSession? { data.flatMap { try? JSONDecoder().decode(SavedWebSession.self, from: $0) } }
    func save(_ session: SavedWebSession) throws { data = try JSONEncoder().encode(session) }
    func clear() { if !refuseDeletion { data = nil } }
    func clearAndReport() -> Bool { clear(); return !refuseDeletion }
}

@MainActor
func verifySessionRestart() async throws {
    let vault = MemoryWebSessionStore()
    let suite = "NEU-Lumen.SessionRestart." + UUID().uuidString
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    func makeSession() -> SessionStore {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockPortalProtocol.self]
        return SessionStore(client: PortalClient(http: HTTPClient(configuration: config)), webSessions: vault, defaults: defaults)
    }
    let cas = HTTPCookie(properties: [.name:"CASTGC", .value:"fixture-cas", .domain:"pass.neu.edu.cn", .path:"/tpass", .secure:"TRUE"])!
    let scoped = HTTPCookie(properties: [.name:"SESS_ID", .value:"scoped-session", .domain:"webvpn.neu.edu.cn", .path:wrapped.path,
        .secure:"TRUE", HTTPCookiePropertyKey(rawValue:"HttpOnly"):"TRUE"])!
    let root = HTTPCookie(properties: [.name:"SESS_ID", .value:"root-session", .domain:"webvpn.neu.edu.cn", .path:"/"])!
    let first = makeSession()
    let ok = await first.completeWebLogin(WebLoginSession(cookies: [cas, ticket, scoped, root], user: user, userAgent: "Saved WebKit UA"))
    precondition(ok && vault.data != nil && first.usesWebSession)
    let saved = vault.load()!
    let decoded = saved.restoredCookies()
    precondition(decoded.count == 4, "没有 Expires 的会话 Cookie 也必须跨进程保存")
    let preserved = decoded.first { $0.value == "scoped-session" }!
    precondition(preserved.path == wrapped.path && preserved.isSecure && preserved.isHTTPOnly)
    precondition(saved.user == user && saved.userAgent == "Saved WebKit UA")

    MockPortalProtocol.handle = { request in
        precondition(request.url == wrapped)
        precondition(request.value(forHTTPHeaderField: "User-Agent") == "Saved WebKit UA")
        let cookies = request.value(forHTTPHeaderField: "Cookie") ?? ""
        precondition(cookies.contains("SESS_ID=scoped-session") && cookies.contains("SESS_ID=root-session"))
        return (200, [:], "<script>const userInfoDSL = \(raw);</script>")
    }
    let restarted = makeSession()
    await restarted.restoreSession()
    precondition(restarted.phase == .loggedIn && restarted.user == user && restarted.client.webvpnOn)
    precondition(restarted.client.browserUserAgent == "Saved WebKit UA")

    MockPortalProtocol.failure = URLError(.notConnectedToInternet)
    let offline = makeSession()
    await offline.restoreSession()
    precondition(offline.phase == .loggedIn && offline.user == user && vault.data != nil)
    MockPortalProtocol.failure = nil
    MockPortalProtocol.handle = { _ in (403, [:], "gateway temporarily unavailable") }
    let blocked = makeSession()
    await blocked.restoreSession()
    precondition(blocked.phase == .loggedIn && blocked.client.hasWebVPNTicket && vault.data != nil)

    restarted.logout()
    precondition(vault.data == nil && !restarted.client.hasLoginSession)
    let loggedOut = makeSession()
    await loggedOut.restoreSession()
    precondition(loggedOut.phase == .loggedOut)

    // Start a separate fixture scenario, not a user-logged-out session.
    defaults.removeObject(forKey: "lumen.session.suppressAutomaticRestore")
    // 学校已给出的到期时间不能因保存而延长。
    let expired = HTTPCookie(properties: [.name:"CASTGC", .value:"old", .domain:"pass.neu.edu.cn", .path:"/tpass", .expires:Date(timeIntervalSinceNow: -60)])!
    try vault.save(SavedWebSession(user: user, userAgent: "Saved WebKit UA", cookies: [expired]))
    let timedOut = makeSession()
    await timedOut.restoreSession()
    precondition(timedOut.phase == .loggedOut && vault.data == nil)

    // 只有真正返回认证页，才废弃保存的会话。
    try vault.save(saved)
    MockPortalProtocol.handle = { request in
        if request.url?.host == "pass.neu.edu.cn" { return (200, [:], "<html>login</html>") }
        return (302, ["Location":CasCrypto.casLoginURL.absoluteString], "")
    }
    let expiredAtServer = makeSession()
    await expiredAtServer.restoreSession()
    precondition(expiredAtServer.phase == .loggedIn && vault.data != nil, "单一路线返回认证页不能丢掉另一个网络的会话")
    // A failed persistent deletion must not log the user back in after restart.
    vault.refuseDeletion = true
    expiredAtServer.logout()
    precondition(vault.data != nil && expiredAtServer.sessionSaveError != nil)
    let residual = makeSession()
    await residual.restoreSession()
    precondition(residual.phase == .loggedOut && residual.user == nil)
    vault.refuseDeletion = false
    vault.clear()

    // A current cookie session can bind an initially unknown identity once the
    // profile endpoint recovers, without borrowing another account's password.
    let pending = makeSession()
    MockPortalProtocol.failure = URLError(.notConnectedToInternet)
    let pendingLogin = await pending.completeWebLogin(WebLoginSession(cookies: [cas, ticket, scoped, root], user: nil, userAgent: "Fixture UA"))
    precondition(pendingLogin && pending.phase == .loggedIn && !pending.hasConfirmedIdentity)
    let identityEpoch = pending.requestEpoch
    MockPortalProtocol.failure = nil
    MockPortalProtocol.handle = { _ in (200, [:], "<script>const userInfoDSL = \(raw);</script>") }
    let bound = await pending.ensureIdentity()
    precondition(bound && pending.user?.isSameAccount(as: user) == true && pending.requestEpoch == identityEpoch)
    print("Web session restart: cookies, UA, offline/403 recovery, expiry, logout barrier and pending identity binding passed")
}
try await verifySessionRestart()

let codeApp = PortalApp(name: "e码通", appId: "ecode", url: "https://ecard.neu.edu.cn/desktop", mobileUrl: "https://ecard.neu.edu.cn/code",
                         iconUrl: "", desc: "", category: "校园生活", visits: 0)
precondition(ServiceCatalog(apps: DemoData.apps + [codeApp]).ecodeURL.absoluteString == codeApp.mobileUrl)
precondition(ServiceCatalog(apps: DemoData.apps).ecodeURL.absoluteString == PortalClient.serviceCard)
precondition(ServiceCatalog(apps: []).ecodeURL.absoluteString == PortalClient.serviceCard)
print("Home e-code shortcut: official mobile entry and Flutter-compatible SSO fallback passed")

// Homepage URLs resolve relative links and never treat a blank mobile URL as a destination.
precondition(PortalLink.from([["form_mobile_url_view":" ", "form_url_view":"/portal/task/42"]])?.absoluteString == PortalClient.portalBase + "/task/42")
precondition(PortalLink.resolve("detail/42")?.absoluteString == PortalClient.portalBase + "/detail/42")
precondition(PortalLink.resolve("/first.jpg")?.absoluteString == "https://personal.neu.edu.cn/first.jpg")
precondition(PortalLink.resolve("first.jpg")?.absoluteString == PortalClient.portalBase + "/first.jpg")
precondition(PortalLink.resolve("//neunews.neu.edu.cn/a.htm")?.host == "neunews.neu.edu.cn")
precondition(PortalLink.resolve("javascript:alert(1)") == nil)
precondition(PortalLink.resolve("data:text/html,x") == nil)
let articleURL = URL(string: "https://neunews.neu.edu.cn/2026/1102/article.htm")!
let articleHTML = #"""
<header><img src="/logo.png"></header><script>const fake='<img src="/fake.jpg">';</script>
<div class="wp_articlecontent"><p>新闻正文</p><img width="1" height="1" src="/counter.gif">
<div><img src="data:image/gif;base64,AAAA" data-src="../../_upload/first.jpg?x=1&amp;y=2"></div>
<img src="/second.jpg"></div><footer><img src="/footer.jpg"></footer>
"""#
precondition(NewsArticle.firstImage(in: articleHTML, base: articleURL)?.absoluteString == "https://neunews.neu.edu.cn/_upload/first.jpg?x=1&y=2")
precondition(NewsArticle.firstImage(in: #"<img src='/logo.png'><div id='vsb_content'><p>无图文章</p></div><img src='/footer.jpg'>"#, base: articleURL) == nil)
precondition(NewsArticle.firstImage(in: #"<meta property='og:image' content='/cover.jpg'><article><img src='/actual-first.jpg'></article>"#, base: articleURL)?.path == "/actual-first.jpg")
print("Homepage links and article images: URL safety, mobile fallback, nested body, lazy image, tracking/header exclusion passed")

@MainActor
func verifyNetworkRoaming() async throws {
    let vault = MemoryWebSessionStore()
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [MockPortalProtocol.self]
    let roamingHTTP = HTTPClient(configuration: config)
    let client = PortalClient(http: roamingHTTP)
    let publicCAS = HTTPCookie(properties: [.name:"CASTGC", .value:"roaming-cas", .domain:"pass.neu.edu.cn", .path:"/tpass", .secure:"TRUE"])!
    try vault.save(SavedWebSession(user: user, userAgent: "Roaming WebKit UA", cookies: [ticket, publicCAS, proxyCASTGC]))
    var campus = true
    var exchanges = 0
    MockPortalProtocol.handle = { request in
        let url = request.url!
        if url.host == "ecard.neu.edu.cn" || url.host == "jwxt.neu.edu.cn" {
            return campus ? (302, ["Location":"/selflogin/login.aspx"], "") : (403, [:], "not on campus")
        }
        if url.host == "webvpn.neu.edu.cn", campus {
            return (403, ["Set-Cookie":"wengine_vpn_ticket=; Max-Age=0; Path=/"], "仅用于我校师生在校外登录")
        }
        if url.host == "pass.neu.edu.cn" {
            exchanges += 1
            precondition(request.value(forHTTPHeaderField: "Cookie")?.contains("roaming-cas") == true)
            let service = URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems!.first { $0.name == "service" }!.value!
            return (302, ["Location":service + "&ticket=ST-roaming"], "")
        }
        if url.path.contains("/manage/common/cas_login/") {
            return (302, ["Set-Cookie":"SESS_ID=campus-portal; Path=/portal; Secure", "Location":PortalClient.portalBase], "")
        }
        if url.host == "personal.neu.edu.cn", request.value(forHTTPHeaderField: "Cookie")?.contains("campus-portal") != true {
            return (302, ["Location":CasCrypto.casLoginURL.absoluteString], "")
        }
        return (200, [:], "<script>const userInfoDSL = \(raw);</script>")
    }
    let session = SessionStore(client: client, webSessions: vault)
    await session.restoreSession()
    precondition(session.phase == .loggedIn && !client.webvpnOn && exchanges == 1)
    precondition(client.hasWebVPNTicket && vault.load()!.cookies.contains { $0.value == "fixture-ticket" }, "校内网关拒绝不能清掉校外会话")
    campus = false
    let outside = await session.silentRelogin()
    precondition(outside && session.phase == .loggedIn && client.webvpnOn && exchanges == 1, "再次出校应复用之前的网关票据")
    campus = true
    let inside = await session.silentRelogin()
    precondition(inside && session.phase == .loggedIn && !client.webvpnOn && client.hasWebVPNTicket && exchanges == 1)
    precondition(vault.load()!.restoredCookies().contains { $0.value == "campus-portal" })
    let initialRevision = session.networkRevision
    let roamingEpoch = session.requestEpoch
    session.networkDidChange(isConnected: false)
    precondition(!session.networkAvailable && session.phase == .loggedIn)
    campus = false
    session.networkDidChange(isConnected: true)
    session.networkDidChange(isConnected: false)
    session.networkDidChange(isConnected: true)
    for _ in 0..<100 where session.recoveringNetwork { try await Task.sleep(for: .milliseconds(50)) }
    precondition(session.networkRevision == initialRevision + 1 && client.webvpnOn && session.requestEpoch == roamingEpoch,
                 "快速断开/重连只恢复最终链路，保留当前账号")
    campus = true
    session.networkDidChange(isConnected: true)
    for _ in 0..<100 where session.recoveringNetwork { try await Task.sleep(for: .milliseconds(50)) }
    precondition(session.networkRevision == initialRevision + 2 && !client.webvpnOn,
                 "10 秒内再次换网也必须恢复，不能被节流丢掉")
    let secondUser = PortalUser(uid: "99", name: "另一账号", sid: "20260099", identity: "本科生", department: "学院", email: "", avatarUrl: "")
    let otherCAS = HTTPCookie(properties: [.name:"CASTGC", .value:"other-account", .domain:"pass.neu.edu.cn", .path:"/tpass", .secure:"TRUE"])!
    let changed = await session.completeWebLogin(WebLoginSession(cookies: [otherCAS], user: secondUser, userAgent: "Other UA"))
    precondition(changed && !client.hasWebVPNTicket && vault.load()!.user == secondUser, "不同账号不能合并旧网络会话")
    session.logout()
    let revisionAfterLogout = session.networkRevision
    session.networkDidChange(isConnected: true)
    try await Task.sleep(for: .milliseconds(800))
    precondition(session.networkRevision == revisionAfterLogout && !session.recoveringNetwork)
    precondition(!client.hasLoginSession && vault.load() == nil)
    print("Network roaming: gateway denial, direct CAS renewal, repeated campus/off-campus transitions, vault retention and account isolation passed")
}
try await verifyNetworkRoaming()

let contentConfig = URLSessionConfiguration.ephemeral
contentConfig.protocolClasses = [MockPortalProtocol.self]
let contentClient = PortalClient(http: HTTPClient(configuration: contentConfig))
MockPortalProtocol.handle = { request in
    if request.url!.path.hasSuffix("/data/items") {
        return (200, [:], #"{"e":0,"d":{"data":[{"id":"book","name":"图书借阅","url":"/portal/fallback"}]}}"#)
    }
    if request.url!.path.hasSuffix("/data/detail") {
        return (200, [:], #"{"e":0,"d":{"data":{"value":3,"mobile_url":"/portal/books/detail"}}}"#)
    }
    precondition(request.url!.path.hasSuffix("/task/apply"))
    return (200, [:], #"{"e":0,"d":{"list":[{"third_app_name":"测试事项","form_mobile_url_view":" ","form_url_view":"/portal/task/42"}]}}"#)
}
let dataCards = try await contentClient.fetchDataCards()
let tasks = try await contentClient.fetchTodos()
precondition(dataCards.first?.value == "3" && dataCards.first?.destination == PortalClient.portalBase + "/books/detail")
precondition(tasks.first?.url == PortalClient.portalBase + "/task/42")
MockPortalProtocol.handle = { _ in
    contentClient.clearSession()
    return (200, ["Set-Cookie":"SESS_ID=late-response; Path=/portal"], "<script>window.userInfoDSL = \(raw);</script>")
}
do { _ = try await contentClient.fetchUserInfo(); preconditionFailure("退出后不能接受旧网络响应") }
catch { precondition(!contentClient.hasLoginSession) }
print("Homepage API links and logout generation: detail links, relative task links and late-cookie isolation passed")

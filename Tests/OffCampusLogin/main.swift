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
    precondition(url.path == "/selfsearch/User/baseinfo.aspx")
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
do {
    _ = try PortalClient.parseCardBalance(fromHTML: #"<input id="ContentPlaceHolder1_txtOddFare" value="***">"#)
    preconditionFailure("掩码余额不能变成假零元")
} catch {}
let missingSubsidy = try PortalClient.parseCardBalance(fromHTML: #"<input id="ContentPlaceHolder1_txtOddFare" value="0.00">"#)
precondition(missingSubsidy.balance == 0 && missingSubsidy.subsidy == nil)
print("Campus grades/card: 302 probes, explicit CAS ST, session cookies, Referer, real balances and masked-data errors passed")


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
    func load() -> SavedWebSession? { data.flatMap { try? JSONDecoder().decode(SavedWebSession.self, from: $0) } }
    func save(_ session: SavedWebSession) throws { data = try JSONEncoder().encode(session) }
    func clear() { data = nil }
}

@MainActor
func verifySessionRestart() async throws {
    let vault = MemoryWebSessionStore()
    func makeSession() -> SessionStore {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockPortalProtocol.self]
        return SessionStore(client: PortalClient(http: HTTPClient(configuration: config)), webSessions: vault)
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
    print("Web session restart: serialization, session-only/HttpOnly/path cookies, UA, offline/403 recovery, expiry and logout passed")
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
    let secondUser = PortalUser(uid: "99", name: "另一账号", sid: "20260099", identity: "本科生", department: "学院", email: "", avatarUrl: "")
    let otherCAS = HTTPCookie(properties: [.name:"CASTGC", .value:"other-account", .domain:"pass.neu.edu.cn", .path:"/tpass", .secure:"TRUE"])!
    let changed = await session.completeWebLogin(WebLoginSession(cookies: [otherCAS], user: secondUser, userAgent: "Other UA"))
    precondition(changed && !client.hasWebVPNTicket && vault.load()!.user == secondUser, "不同账号不能合并旧网络会话")
    session.logout()
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

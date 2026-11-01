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
        return (200, [:], #"<form><input name="username" value="20260042"><input name="timestamp" value="fixture-time"><input name="auid" value="fixture-auid"></form>"#)
    }
    if url.path == "/selfsearch/SSOLogin.aspx" {
        precondition(request.httpMethod == "POST")
        precondition(request.value(forHTTPHeaderField: "Referer") == url.absoluteString)
        return (200, ["Set-Cookie":"ASP.NET_SessionId=card; Path=/selfsearch"], "<html>ok</html>")
    }
    precondition(url.path == "/selfsearch/User/baseinfo.aspx")
    precondition(request.value(forHTTPHeaderField: "Cookie")?.contains("ASP.NET_SessionId=card") == true)
    return (200, [:], #"<input id="ContentPlaceHolder1_txtOddFare" value="52.30"><input id="ContentPlaceHolder1_txtSpecialOddFare" value="7.50">"#)
}
let onCampus = await schoolClient.isCampusNet()
precondition(onCampus && !schoolClient.webvpnOn)
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
    precondition(expiredAtServer.phase == .loggedOut && vault.data == nil)
    print("Web session restart: serialization, session-only/HttpOnly/path cookies, UA, offline/403 recovery, expiry and logout passed")
}
try await verifySessionRestart()

let codeApp = PortalApp(name: "e码通", appId: "ecode", url: "https://ecard.neu.edu.cn/desktop", mobileUrl: "https://ecard.neu.edu.cn/code",
                         iconUrl: "", desc: "", category: "校园生活", visits: 0)
precondition(ServiceCatalog(apps: DemoData.apps + [codeApp]).ecodeURL.absoluteString == codeApp.mobileUrl)
precondition(ServiceCatalog(apps: DemoData.apps).ecodeURL.absoluteString == PortalClient.serviceCard)
precondition(ServiceCatalog(apps: []).ecodeURL.absoluteString == PortalClient.serviceCard)
print("Home e-code shortcut: official mobile entry and Flutter-compatible SSO fallback passed")

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
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
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

import Foundation

/// 一号通门户 + 教务系统客户端：CAS 登录与全部业务接口。
/// 逻辑与 NEUPortal（Flutter 版）portal_client.dart 一致：
/// 手动重定向 + Cookie 罐，保证 CASTGC / SESS_ID 正确跨域传递。
final class PortalClient {
    static let portalBase = "https://personal.neu.edu.cn/portal"
    static let jwxtBase = "https://jwxt.neu.edu.cn"

    private let http: HTTPClient
    private let casGate = CASRequestGate()
    private let newsGate = CASRequestGate(limit: 3)
    private let routeProbeGate = CASRequestGate()
    private var sessionEpoch = UUID()
    var sessionGeneration: UUID { sessionEpoch }

    // MARK: - 校园网 / WebVPN

    /// WebVPN 模式开启后，校内主机的重定向与请求都会改写为网关地址。
    private(set) var webvpnOn = false
    private var routeInvalidated = false
    private var campusProbe: (date: Date, isCampus: Bool)?
    private var accessRouteRevision = UUID()

    init(http: HTTPClient = HTTPClient()) {
        self.http = http
        http.redirectRewriter = { [weak self] url in
            guard let self,
                  self.webvpnOn,
                  WebVPN.isIntranet(url.absoluteString),
                  !WebVPN.isWrapped(url.absoluteString) else { return nil }
            return URL(string: WebVPN.wrap(url.absoluteString))
        }
    }

    /// 是否校园网：ecard:80 或 jwxt:443 任一可达（结果缓存 10 分钟）。
    func invalidateAccessRoute() {
        accessRouteRevision = UUID()
        campusProbe = nil
        routeInvalidated = true
    }

    func networkPathChanged() {
        http.resetTransport(networkChanged: true)
        invalidateAccessRoute()
    }

    func isCampusNet() async -> Bool {
        await routeProbeGate.acquire()
        let value = await readCampusProbe()
        await routeProbeGate.release()
        return value
    }
    private func readCampusProbe() async -> Bool {
        let epoch = sessionEpoch
        let revision = accessRouteRevision
        if let probe = campusProbe, Date().timeIntervalSince(probe.date) < 600 {
            return probe.isCampus
        }
        let ecardReachable = await quickReachable("http://ecard.neu.edu.cn/")
        let ok: Bool
        if ecardReachable {
            ok = true
        } else {
            ok = await quickReachable("https://jwxt.neu.edu.cn/")
        }
        guard epoch == sessionEpoch, revision == accessRouteRevision, !Task.isCancelled else { return ok }
        campusProbe = (Date(), ok)
        routeInvalidated = false
        return ok
    }

    private func quickReachable(_ url: String) async -> Bool {
        guard let requestURL = URL(string: url) else { return false }
        let request = URLRequest(url: requestURL, timeoutInterval: 2.5)
        do {
            let response = try await http.send(request, followRedirects: false, retryTransport: false)
            return CampusAccessProbe.accepts(url: response.finalURL, status: response.status, headers: response.headers, body: response.body)
        } catch {
            return false
        }
    }

    /// 在已有 CAS 会话所在的认证域中换取 WebVPN 票据。
    @discardableResult
    func ensureWebVPN(force: Bool = false) async -> Bool {
        let revision = accessRouteRevision
        if !force && webvpnOn && http.cookies.hasWebVPNTicket() { return true }
        for _ in 0..<2 {
            let url = authenticationURL(for: WebVPN.casService)
            if let resp = try? await http.get(url) {
                guard revision == accessRouteRevision, !Task.isCancelled else { return false }
                let landed = resp.finalURL.absoluteString
                if http.cookies.hasWebVPNTicket() && !landed.contains("/tpass/login") {
                    webvpnOn = true
                    return true
                }
            }
            try? await Task.sleep(nanoseconds: 400_000_000)
        }
        return false
    }

    /// 校外准备：探测校园网，不通则种 WebVPN 票（失败不抛错，由调用方按需处理）。
    func prepareAccess(authenticateGateway: Bool = true) async {
        let epoch = sessionEpoch
        let revision = accessRouteRevision
        let campus = await isCampusNet()
        guard epoch == sessionEpoch, revision == accessRouteRevision, !Task.isCancelled else { return }
        webvpnOn = !campus
        if !campus, authenticateGateway { _ = await ensureWebVPN() }
    }

    private func maybeWrap(_ url: String) -> String {
        guard webvpnOn else { return url }
        if WebVPN.isIntranet(url) { return WebVPN.wrap(url) }
        // 校外门户 HTML 会被学校重定向进网关，门户域的请求统一改走网关
        let host = URL(string: url)?.host?.lowercased()
        if host == "personal.neu.edu.cn" || host == "portal.neu.edu.cn" {
            return WebVPN.wrap(url)
        }
        return url
    }

    /// 是否已持有 WebVPN 网关票据。
    var hasWebVPNTicket: Bool {
        http.cookies.hasWebVPNTicket()
    }

    var hasCasSession: Bool {
        http.cookies.hasCookie(CasCrypto.casLoginURL, "CASTGC")
    }

    var hasLoginSession: Bool { isLoggedIn || hasCasSession || hasWebVPNTicket }

    func setUserAgent(_ value: String) {
        let agent = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if !agent.isEmpty { http.userAgentOverride = agent }
    }

    var browserUserAgent: String? { http.userAgentOverride }

    /// 重启验证只读取门户，不为了补资料销毁旧票据；拦截/断网不等同于退出。
    func validateSavedSession() async throws -> PortalUser? {
        // A login page on one route cannot invalidate the other route's session.
        try await fetchUserInfo()
    }

    /// WebView 会话回收后：若已持有网关票据则直接进入网关模式
    /// （校外门户直连必被网关劫持，门户读取必须经网关）。
    func adoptGatewayTicket() {
        if http.cookies.hasWebVPNTicket(), campusProbe?.isCampus != true {
            webvpnOn = true
            if campusProbe == nil && !routeInvalidated { campusProbe = (Date(), false) }
        }
    }

    /// 用 CASTGC 给指定 service 换 ST 并跟随到业务系统（停留在 CAS 登录页视为会话失效）。
    private func casLand(_ service: String) async throws -> HTTPClient.RawResponse {
        await casGate.acquire()
        do {
            let response = try await performCASLanding(service)
            await casGate.release()
            return response
        } catch {
            await casGate.release()
            throw error
        }
    }

    private func performCASLanding(_ service: String) async throws -> HTTPClient.RawResponse {
        let url = authenticationURL(for: service)
        let resp = try await http.get(url)
        if resp.finalURL.host?.contains("pass.neu.edu.cn") == true
            || resp.finalURL.path.contains("/tpass/login") {
            throw NetworkError.sessionExpired()
        }
        return resp
    }

    // 正则只编译一次。
    private static let ltRegex = try! NSRegularExpression(pattern: #"name="lt"\s+value="([^"]+)""#)
    private static let executionRegex = try! NSRegularExpression(pattern: #"name="execution"\s+value="([^"]+)""#)
    private static let casErrorRegex = try! NSRegularExpression(
        pattern: #"<(?:span|div|p)[^>]*id="(?:errormsg|msg|msg_i18n)"[^>]*>([\s\S]*?)</(?:span|div|p)>"#,
        options: [.caseInsensitive]
    )

    var isLoggedIn: Bool {
        http.cookies.hasCookie(URL(string: Self.portalBase)!, "SESS_ID")
    }

    func clearSession() {
        sessionEpoch = UUID()
        http.cookies.clear()
        secondAuthExecution = nil
        webvpnOn = false
        campusProbe = nil
        routeInvalidated = false
        http.userAgentOverride = nil
    }

    /// 吸收网页方式登录（WKWebView）里完成的会话 Cookie（含 CASTGC / SESS_ID）。
    func absorbCookies(_ cookies: [HTTPCookie]) {
        http.cookies.absorb(cookies)
    }

    /// 供 WebView 注入的会话快照：domain -> {name: value}。
    func cookieSnapshot() -> [String: [String: String]] {
        http.cookies.snapshot()
    }

    // MARK: - CAS 统一身份认证

    /// CAS 登录。成功返回用户信息，失败抛 NetworkError。
    func login(username rawUsername: String, password: String) async throws -> PortalUser {
        sessionEpoch = UUID()
        http.cookies.clear()
        let username = rawUsername
            .replacingOccurrences(of: #"\s+"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        if username.isEmpty || password.isEmpty {
            throw NetworkError(message: "学号/工号或密码不能为空")
        }

        // 1. 取登录页，解析 lt / execution
        let page = try await http.get(CasCrypto.casLoginURL).text
        guard let lt = Self.firstMatch(Self.ltRegex, page),
              let execution = Self.firstMatch(Self.executionRegex, page) else {
            throw NetworkError(message: "【认证页】统一身份认证页加载失败：请检查网络后重试；多次失败可改用「浏览器方式登录」")
        }

        // 2. RSA 加密并提交（学号+密码拼接后整体加密）
        let rsa = try CasCrypto.encrypt(username + password)
        let post = try await http.postForm(CasCrypto.casLoginURL, fields: [
            "rsa": rsa,
            "ul": "\(username.count)",
            "pl": "\(password.count)",
            "lt": lt,
            "execution": execution,
            "_eventId": "submit",
        ])

        // 3. 校验认证结果：最终仍停留在 CAS 登录页说明认证未通过
        if post.finalURL.host?.contains("pass.neu.edu.cn") == true
            || post.finalURL.path.contains("/tpass/login") {
            let html = post.text

            // 新设备二次认证（图形码 + 短信，login_second.js 流程）
            if html.contains("second_auth_form") || html.contains("当前设备需进行身份验证") {
                secondAuthExecution = Self.firstMatch(Self.executionRegex, html) ?? "e1s2"
                throw NetworkError.needSecondAuth()
            }

            if let raw = Self.firstMatch(Self.casErrorRegex, html) {
                let msg = raw
                    .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !msg.isEmpty && !msg.contains("null") {
                    if msg.contains("账号不存在") {
                        throw NetworkError(message: "【密码校验】账号不存在：若当前使用移动网络（4G/5G），学校统一认证会拦截公网直连鉴权。请切换至校园网 WiFi，或改用下方「浏览器方式登录」。")
                    }
                    throw NetworkError(message: "【密码校验】" + msg)
                }
            }
            throw NetworkError(message: "【密码校验】账号或密码错误")
        }

        // 校外门户登录成功后会被学校重定向进 WebVPN 网关（网关无票据时显示
        // 「仅用于我校师生在校外登录」403 页）：此时 CASTGC 已到手，
        // 换网关票据后改经网关读取门户，不要停在网关拦截页。
        if post.finalURL.host?.contains("webvpn.neu.edu.cn") == true {
            guard await ensureWebVPN() else {
                throw NetworkError(message: "校外需经 WebVPN 访问门户，网关登录失败：请稍后重试，或连接校园网后直接登录")
            }
            return try await fetchUserInfo()
        }

        if post.finalURL.absoluteString.hasPrefix(Self.portalBase),
           let user = Self.extractUser(fromHTML: post.text) {
            return user
        }
        do {
            return try await fetchUserInfo()
        } catch let e as NetworkError {
            throw NetworkError(message: "【门户会话】" + e.message)
        }
    }

    // MARK: - 新设备二次认证（图形码 + 短信）

    /// 二次认证挑战页的 execution（e1s2），登录成功或清会话后置空。
    private var secondAuthExecution: String?

    var hasPendingSecondAuth: Bool { secondAuthExecution != nil }

    /// 拉取二次认证图形码（与登录共用 JSESSIONID 会话）。
    func fetchSecondAuthCaptcha() async throws -> Data {
        guard secondAuthExecution != nil else {
            throw NetworkError(message: "当前没有待验证的登录，请先登录")
        }
        let url = URL(string: "https://pass.neu.edu.cn/tpass/code?_=\(Int(Date().timeIntervalSince1970 * 1000))")!
        let resp = try await http.get(url)
        guard resp.status == 200, !resp.body.isEmpty else {
            throw NetworkError(message: "图形码获取失败，请重试")
        }
        return resp.body
    }

    /// 提交图形码，请求下发短信验证码。
    func requestSecondAuthSMS(graphicCode: String) async throws {
        guard secondAuthExecution != nil else {
            throw NetworkError(message: "当前没有待验证的登录，请先登录")
        }
        let url = URL(string: "https://pass.neu.edu.cn/tpass/secondAuthCode")!
        let resp = try await http.postForm(url, fields: [
            "code": graphicCode,
            "method": "mobile",
        ])
        let text = resp.text.lowercased()
        if resp.status != 200 || text.contains("false") || text.contains("验证码错误") || text.contains("失败") {
            throw NetworkError(message: "短信发送失败：请检查图形码是否正确后重试")
        }
    }

    /// 提交短信验证码完成二次认证并继续登录。
    func submitSecondAuth(smsCode: String) async throws -> PortalUser {
        guard let execution = secondAuthExecution else {
            throw NetworkError(message: "当前没有待验证的登录，请先登录")
        }
        let post = try await http.postForm(CasCrypto.casLoginURL, fields: [
            "execution": execution,
            "RelayState": execution,
            "_eventId": "submit",
            "scendAuthCode": smsCode,
        ])
        if post.finalURL.host?.contains("pass.neu.edu.cn") == true
            || post.finalURL.path.contains("/tpass/login") {
            let html = post.text
            if html.contains("second_auth_form") || html.contains("当前设备需进行身份验证") {
                secondAuthExecution = Self.firstMatch(Self.executionRegex, html) ?? execution
                throw NetworkError(message: "短信验证码不正确，请重新输入")
            }
            if let raw = Self.firstMatch(Self.casErrorRegex, html) {
                let msg = raw
                    .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !msg.isEmpty && !msg.contains("null") {
                    throw NetworkError(message: msg)
                }
            }
            throw NetworkError(message: "二次认证失败，请重新登录")
        }
        secondAuthExecution = nil
        // 校外完成二次认证后同样可能被门户重定向进 WebVPN 网关
        if post.finalURL.host?.contains("webvpn.neu.edu.cn") == true {
            guard await ensureWebVPN() else {
                throw NetworkError(message: "校外需经 WebVPN 访问门户，网关登录失败：请稍后重试，或连接校园网后直接登录")
            }
            return try await fetchUserInfo()
        }
        if post.finalURL.absoluteString.hasPrefix(Self.portalBase),
           let user = Self.extractUser(fromHTML: post.text) {
            return user
        }
        return try await fetchUserInfo()
    }

    /// 请求门户首页并解析 window.userInfoDSL。
    /// 校外门户 HTML 会被学校重定向进 WebVPN 网关：直连失败（落到 CAS/网关拦截页）
    /// 时自动切换到网关模式重试一次。
    func fetchUserInfo() async throws -> PortalUser {
        let retained = browserCookies()
        let epoch = sessionEpoch
        defer { if epoch == sessionEpoch { retainMissingCookies(retained) } }
        var lastError = NetworkError(message: "门户暂时无法验证，已保留登录信息")
        for attempt in 0..<3 {
            guard epoch == sessionEpoch, !Task.isCancelled else { throw CancellationError() }
            if attempt == 1 {
                invalidateAccessRoute()
                await prepareAccess()
            }
            if attempt == 2 {
                // Rebuild the portal service session without clearing either CAS cookie realm.
                if webvpnOn { _ = await ensureWebVPN(force: true) }
                guard let service = URLComponents(url: CasCrypto.casLoginURL, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "service" })?.value else { break }
                _ = try? await casLand(service)
            }
            do {
                let response = try await http.get(URL(string: maybeWrap(Self.portalBase))!)
                if !Self.isPortalSessionFailure(response), let user = Self.extractUser(fromHTML: response.text) { return user }
                if response.finalURL.path.contains("/tpass/login") || Self.isSessionLostHTML(response.text) {
                    lastError = .sessionExpired()
                }
            } catch { lastError = NetworkError.from(error) }
        }
        throw lastError
    }

    /// Preserve the other network's cookies; a failed gateway response must not erase its saved realm.
    func retainMissingCookies(_ retained: [HTTPCookie]) {
        let present = Set(browserCookies().map { "\($0.domain)|\($0.path)|\($0.name)" })
        http.cookies.absorb(retained.filter { !present.contains("\($0.domain)|\($0.path)|\($0.name)") })
    }


    /// 直连门户是否失败：落在 CAS 登录页 / 网关拦截页 / 网关域。
    private static func isPortalSessionFailure(_ resp: HTTPClient.RawResponse) -> Bool {
        let onPass = resp.finalURL.host?.contains("pass.neu.edu.cn") == true
            || resp.finalURL.path.contains("/tpass/login")
        let onWebVPN = resp.finalURL.host?.contains("webvpn.neu.edu.cn") == true
        let gate = onWebVPN
            && (resp.status == 403 || resp.text.contains("仅用于我校师生在校外登录"))
        return onPass || gate || resp.text.contains("当前设备需进行身份验证")
    }

    // MARK: - 门户业务接口

    private func api(_ path: String, query: [URLQueryItem] = []) async throws -> [String: Any] {
        var comps = URLComponents(string: Self.portalBase + "/" + path)!
        if !query.isEmpty { comps.queryItems = query }
        let requestURL = URL(string: maybeWrap(comps.url!.absoluteString))!
        let resp = try await http.get(requestURL, xhr: true)
        // Status is checked before parsing: JSON gateway errors are not empty data.
        if resp.status == 401 { throw PortalAPIError.authenticationRequired }
        guard (200..<300).contains(resp.status) else { throw PortalAPIError.httpStatus(resp.status) }
        if resp.finalURL.host?.contains("pass.neu.edu.cn") == true
            || resp.finalURL.path.contains("/tpass/login") {
            throw PortalAPIError.authenticationRequired
        }
        return try PortalEnvelope.data(status: resp.status, body: resp.body)
    }

    /// 某一周（周日起 7 天）的课表/考试/活动事件。传该周任意一天即可。
    func fetchWeek(anyDayInWeek day: Date) async throws -> [CourseOccurrence] {
        let cal = Calendar.current
        let dayStart = cal.startOfDay(for: day)
        let dow = cal.component(.weekday, from: dayStart) // 1=周日
        let start = cal.date(byAdding: .day, value: -(dow - 1), to: dayStart)!
        let startMs = Int(start.timeIntervalSince1970 * 1000)
        let endMs = Int(start.timeIntervalSince1970 * 1000) + 7 * 86400 * 1000 - 1000

        let d = try await api("schedule/frontend/default/week-list", query: [
            URLQueryItem(name: "calendar_id", value: "0"),
            URLQueryItem(name: "classify[]", value: "1"),
            URLQueryItem(name: "classify[]", value: "2"),
            URLQueryItem(name: "classify[]", value: "3"),
            URLQueryItem(name: "classify[]", value: "4"),
            URLQueryItem(name: "classify[]", value: "5"),
            URLQueryItem(name: "classify[]", value: "6"),
            URLQueryItem(name: "start", value: "\(startMs)"),
            URLQueryItem(name: "end", value: "\(endMs)"),
        ])

        let dayMap = try PortalEnvelope.days(d)
        var out: [CourseOccurrence] = []
        out.reserveCapacity(32)
        for (dateStr, slotValue) in dayMap {
            guard let date = PortalDate.day(dateStr), slotValue is [String: Any] || slotValue is [Any] else {
                throw PortalAPIError.invalidPayload("课表")
            }
            // day 的值可能是：事件 / {节次: 事件} / [事件] / {节次: [事件]} 任意嵌套，统一展平
            var events: [[String: Any]] = []
            events.reserveCapacity(12)
            Self.flattenSlots(slotValue, into: &events)
            for e in events {
                let con = e.str("con").trimmingCharacters(in: .whitespaces)
                if con.isEmpty { continue }
                guard let s = PortalDate.dateTime(e.str("start_time")),
                      let endTime = PortalDate.dateTime(e.str("end")) else { continue }
                let sc = cal.dateComponents([.hour, .minute], from: s)
                let ec = cal.dateComponents([.hour, .minute], from: endTime)
                let room = e.str("location").trimmingCharacters(in: .whitespaces)
                out.append(CourseOccurrence(
                    date: date,
                    slot: CourseSlot(
                        weekday: PlannerEvent.mondayBasedWeekday(date),
                        startMinutes: (sc.hour ?? 0) * 60 + (sc.minute ?? 0),
                        endMinutes: (ec.hour ?? 0) * 60 + (ec.minute ?? 0),
                        name: con,
                        room: room.isEmpty ? "待定" : room,
                        kind: con.contains("考试") || con.contains("补考") ? "exam" : "course"
                    )
                ))
            }
        }
        return out
    }

    /// 把 week-list 事件槽位的任意嵌套结构（Map/List 混合）展平成事件数组。
    /// 事件以包含非空 con 字段为标志（与门户前端判断一致）。
    private static func flattenSlots(_ value: Any, into acc: inout [[String: Any]]) {
        if let map = value as? [String: Any] {
            if map["con"] != nil {
                if !map.str("con").isEmpty {
                    acc.append(map)
                }
            } else if map.values.contains(where: { $0 is [String: Any] || $0 is [Any] }) {
                for v in map.values {
                    flattenSlots(v, into: &acc)
                }
            }
        } else if let list = value as? [Any] {
            for v in list {
                flattenSlots(v, into: &acc)
            }
        }
    }

    /// 服务大厅全部应用（含图标/分类/访问量）。
    func fetchApps() async throws -> [PortalApp] {
        let d = try await api("appmarket/frontend/default/getApp", query: [
            URLQueryItem(name: "limit", value: "999"),
            URLQueryItem(name: "type", value: "all"),
            URLQueryItem(name: "cate_id", value: ""),
        ])
        let list = try PortalEnvelope.list(d).compactMap { $0 as? [String: Any] }
        return list.compactMap { a -> PortalApp? in
            let name = a.str("name")
            guard !name.isEmpty else { return nil }
            return PortalApp(
                name: name,
                appId: a.str("id"),
                url: a.str("url"),
                mobileUrl: a.str("mobile_url"),
                iconUrl: a.str("icon"),
                desc: a.str("dsc"),
                category: a.str("category_name").split(separator: ",").first.map(String.init)?.trimmingCharacters(in: .whitespaces) ?? "",
                visits: Int(a.str("fwl")) ?? 0
            )
        }
    }

    /// 校园资讯（东大要闻）。
    func fetchNewsChannels() async throws -> [NewsChannel] {
        let tabs = try await api("news/frontend/default/tabs", query: [
            URLQueryItem(name: "system", value: ""),
            URLQueryItem(name: "need_num", value: "1"),
        ])
        let tabList = try PortalEnvelope.list(tabs).compactMap { $0 as? [String: Any] }
        var seen = Set<String>()
        return tabList.compactMap {
            let id = $0.str("id"), name = $0.str("name")
            guard !id.isEmpty, !name.isEmpty, seen.insert(id).inserted else { return nil }
            return NewsChannel(id: id, name: name)
        }
    }

    func fetchNews(pageSize: Int = 12, channel: NewsChannel? = nil, page: Int = 1, keyword: String = "") async throws -> [NewsItem] {
        let selected: NewsChannel
        if let channel { selected = channel }
        else {
            let channels = try await fetchNewsChannels()
            selected = channels.first(where: { $0.name == "东大要闻" }) ?? channels.first
                ?? NewsChannel(id: "1244bca0563f72ea134e4d78973c6911", name: "东大要闻")
        }
        let d = try await api("news/frontend/default/news-list", query: [
            URLQueryItem(name: "system", value: ""),
            URLQueryItem(name: "cid", value: selected.id),
            URLQueryItem(name: "need_all", value: "0"),
            URLQueryItem(name: "page", value: "\(max(1, page))"),
            URLQueryItem(name: "pageSize", value: "\(min(100, max(1, pageSize)))"),
            URLQueryItem(name: "keyword", value: keyword),
            URLQueryItem(name: "year", value: ""),
            URLQueryItem(name: "month", value: ""),
            URLQueryItem(name: "publisher", value: ""),
        ])
        let list = try PortalEnvelope.list(d).compactMap { $0 as? [String: Any] }
        return list.compactMap { n -> NewsItem? in
            let title = n.str("title")
            guard !title.isEmpty else { return nil }
            let id = n.str("id").isEmpty ? n.str("contentid") : n.str("id")
            return NewsItem(
                id: id,
                title: title,
                date: n.str("publish_time").split(separator: " ").first.map(String.init) ?? "",
                category: selected.name,
                url: PortalLink.from([n])?.absoluteString ?? "",
                picUrl: PortalLink.resolve(n.str("picurl"))?.absoluteString ?? ""
            )
        }
    }

    /// Article-body images load lazily with the same account cookies and route as the article.
    func fetchNewsThumbnail(_ item: NewsItem) async -> Data? {
        await newsGate.acquire()
        let result = await readNewsThumbnail(item)
        await newsGate.release()
        return result
    }

    private func readNewsThumbnail(_ item: NewsItem) async -> Data? {
        guard !Task.isCancelled else { return nil }
        var image: URL?
        var referer: String?
        if let article = PortalLink.resolve(item.url),
           let response = try? await http.get(browserDestination(for: article), extraHeaders: ["Accept": "text/html,application/xhtml+xml"]),
           (200..<300).contains(response.status), response.body.count <= 4_000_000 {
            let base = WebVPN.unwrap(response.finalURL) ?? response.finalURL
            image = NewsArticle.firstImage(in: response.text, base: base)
            referer = response.finalURL.absoluteString
        }
        image = image ?? PortalLink.resolve(item.picUrl)
        guard !Task.isCancelled, let image,
              let response = try? await http.get(browserDestination(for: image), extraHeaders: [
                "Accept": "image/avif,image/webp,image/*,*/*;q=0.8", "Referer": referer ?? item.url
              ]), (200..<300).contains(response.status), !response.body.isEmpty, response.body.count <= 8_000_000 else { return nil }
        return response.body
    }

    func fetchAffairsCatalog(_ query: AffairsCatalogQuery) async throws -> AffairsCatalog {
        let html = try await affairsPage(query.url)
        return try NativeAffairsCatalogParser.catalog(html)
    }

    func fetchAffairsGuide(_ service: AffairsService) async throws -> AffairsServiceGuide {
        guard service.guideURL.path == "/db_portal/guide" else { throw NetworkError(message: "办事指南地址无效") }
        return try NativeAffairsCatalogParser.guide(await affairsPage(service.guideURL))
    }

    /// Protected guide diagrams use the same account cookies and selected route as their guide.
    func fetchAffairsGuideImage(_ url: URL, referer: URL) async throws -> Data {
        guard NativeAffairsCatalogParser.schoolURL(referer.absoluteString) == referer,
              ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
              url.user == nil, url.password == nil, url.host != nil else {
            throw NetworkError(message: "办事图示地址无效")
        }
        await prepareAccess()
        let response = try await http.get(browserDestination(for: url), extraHeaders: [
            "Accept": "image/avif,image/webp,image/*,*/*;q=0.8",
            "Referer": browserDestination(for: referer).absoluteString,
        ])
        let mime = response.headers.first { String(describing: $0.key).lowercased() == "content-type" }.map { String(describing: $0.value).lowercased() } ?? ""
        guard response.status == 200, mime.hasPrefix("image/"), !response.body.isEmpty,
              response.body.count <= 8_000_000 else {
            throw NetworkError(message: "办事图示暂未读取成功，请重试或在学校页面查看")
        }
        return response.body
    }

    private func affairsPage(_ url: URL) async throws -> String {
        guard NativeAffairsCatalogParser.schoolURL(url.absoluteString) == url else {
            throw NetworkError(message: "办事服务地址无效")
        }
        await prepareAccess()
        let response = try await http.get(URL(string: maybeWrap(url.absoluteString))!)
        let landed = WebVPN.unwrap(response.finalURL) ?? response.finalURL
        guard response.status == 200, landed.host == url.host, landed.path == url.path,
              response.body.count <= 5_000_000 else {
            throw NetworkError(message: "办事服务暂时无法读取，请检查网络或学校认证状态")
        }
        return response.text
    }

    /// 办事动态（在办事项），失败时由调用方降级为空。
    func fetchTodos(page: Int = 1, pageSize: Int = 10) async throws -> [TodoItem] {
        guard page > 0, (1...50).contains(pageSize) else { throw NetworkError(message: "办事列表分页参数无效") }
        let d = try await api("personal/frontend/task/apply", query: [
            URLQueryItem(name: "type", value: "all"),
            URLQueryItem(name: "page", value: String(page)),
            URLQueryItem(name: "pageSize", value: String(pageSize)),
        ])
        let list = try PortalEnvelope.list(d).compactMap { $0 as? [String: Any] }
        return list.map { t in
            let nodes = (t["node_name"] as? [Any])?.compactMap { $0 as? String } ?? []
            let destination = PortalLink.from([t]) ?? PortalLink.appURL(id: t.str("third_app_id")) ?? URL(string: Self.portalBase)!
            return TodoItem(
                title: t.str("third_app_name"),
                instance: t.str("third_inst_name"),
                node: nodes.last ?? "处理中",
                percent: t.int("percent") ?? 0,
                time: t.str("inst_created").split(separator: ".").first.map(String.init) ?? "",
                url: destination.absoluteString,
                progressKnown: t.int("percent") != nil
            )
        }
    }

    /// 首页数据条卡片（个人数据 + 明细值）。
    func fetchDataCards() async throws -> [DataCard] {
        let d = try await api("personal/frontend/data/items", query: [
            URLQueryItem(name: "type", value: "personal_data"),
        ])
        let list = try PortalEnvelope.list(d, key: "data").compactMap { $0 as? [String: Any] }
        var out: [DataCard] = []
        out.reserveCapacity(list.count)
        for it in list {
            let name = it.str("name")
            if name.isEmpty { continue }
            var value = "—"
            var metadata = [it]
            let id = it.str("id")
            if !id.isEmpty,
               let det = try? await api("personal/frontend/data/detail", query: [URLQueryItem(name: "id", value: id)]),
               let inner = det["data"] as? [String: Any] {
                metadata.insert(det, at: 0)
                metadata.insert(inner, at: 0)
                // 值在详情接口里，容错解析：value / data / text / 整体
                for cand in [inner["value"], inner["data"], inner["text"], inner] {
                    guard let c = cand, !(c is NSNull) else { continue }
                    let s: String
                    if let str = c as? String {
                        s = str
                    } else if let num = c as? NSNumber {
                        s = num.stringValue
                    } else {
                        s = String(describing: c)
                    }
                    if !s.isEmpty && s.count <= 12 {
                        value = s
                        break
                    }
                }
            }
            let destination = PortalLink.from(metadata) ?? PortalLink.appURL(id: it.str("app_id"))
            out.append(DataCard(name: name, value: value, destination: destination?.absoluteString ?? ""))
        }
        return out
    }

    /// 门户智慧搜索热词。
    func fetchHotSearch(pageSize: Int = 8) async throws -> [String] {
        let data = try await api("frontend/search/hot", query: [URLQueryItem(name: "pageSize", value: "\(pageSize)")])
        let list = try PortalEnvelope.list(data)
        return list.compactMap { v -> String? in
            if let s = v as? String, !s.isEmpty { return s }
            if let n = v as? NSNumber { return n.stringValue }
            return nil
        }
    }

    // MARK: - 教务系统（金智 jwapp）只读查询与真实成绩

    private var jwxtAppBase = PortalClient.jwxtBase + "/jwapp/sys/homeapp"

    /// 从真实的学生首页建立会话，并沿用落地后的协议/网关前缀。
    private func jwxtSSO() async throws {
        let epoch = sessionEpoch
        await prepareAccess()
        guard epoch == sessionEpoch, !Task.isCancelled else { throw CancellationError() }
        let response = try await casLand(Self.jwxtBase + "/jwapp/sys/homeapp/index.do")
        guard epoch == sessionEpoch, !Task.isCancelled else { throw CancellationError() }
        if response.finalURL.host == "pass.neu.edu.cn" { throw NetworkError.sessionExpired() }
        let original = WebVPN.unwrap(response.finalURL) ?? response.finalURL
        guard original.host?.lowercased() == "jwxt.neu.edu.cn" else {
            throw NetworkError(message: "教务认证未落地到学校教务站点，请使用正常网页入口重试")
        }
        let landed = response.finalURL.absoluteString
        if let range = landed.range(of: "/jwapp/") {
            jwxtAppBase = String(landed[..<range.lowerBound]) + "/jwapp/sys/homeapp"
        } else {
            throw NetworkError(message: "教务首页未能建立会话，请打开教务网页完成认证后同步")
        }
        guard (200..<400).contains(response.status) else {
            throw NetworkError(message: "教务认证 HTTP \(response.status)，未能建立教务会话")
        }
        // 与泥洞保持一致：API Referer 是实际学生首页，而非认证入口 index.do。
        _ = try await http.get(URL(string: jwxtReferer)!)
        guard epoch == sessionEpoch, !Task.isCancelled else { throw CancellationError() }
    }

    private var jwxtReferer: String { jwxtAppBase + "/home/index.html?av=&contextPath=/jwapp" }

    private func jwxtGet(_ path: String) async throws -> Any {
        let epoch = sessionEpoch
        let url = URL(string: maybeWrap(jwxtAppBase + "/" + path))!
        let response = try await http.get(url, xhr: true, extraHeaders: [
            "Fetch-Api": "true", "Accept": "application/json", "Referer": jwxtReferer
        ])
        guard epoch == sessionEpoch, !Task.isCancelled else { throw CancellationError() }
        if response.status == 401 || response.finalURL.host == "pass.neu.edu.cn" || response.finalURL.path.contains("/tpass/login") {
            throw NetworkError.sessionExpired()
        }
        guard (200..<300).contains(response.status) else {
            throw NetworkError(message: "教务接口 HTTP \(response.status)，可打开教务网页后同步")
        }
        let originalResponse = WebVPN.unwrap(response.finalURL) ?? response.finalURL
        let originalRequest = WebVPN.unwrap(url) ?? url
        guard AcademicQueryPolicy.acceptsResponseURL(originalResponse, expected: originalRequest) else {
            throw AcademicQueryError.invalid("教务接口来源")
        }
        guard let json = try? http.json(response) else {
            let html = response.text.lowercased()
            if html.contains("tpass/login") || html.contains("name=\"lt\"") { throw NetworkError.sessionExpired() }
            throw NetworkError(message: "教务接口返回了网页，未能取得查询数据。请打开教务网页完成认证后重试")
        }
        return json
    }

    /// 官方静态 JS 已核实的只读 allow-list，HTTP 与业务 envelope 分别校验。
    func fetchAcademicQuery(_ key: AcademicQueryKey, expectedAccount: String) async throws -> AcademicQueryPayload {
        let epoch = sessionEpoch
        let path = try key.path
        func read() async throws -> AcademicQueryPayload {
            try await jwxtSSO()
            guard epoch == sessionEpoch, !Task.isCancelled else { throw CancellationError() }
            do {
                let identity = try await jwxtGet("api/home/currentUser.do")
                try AcademicQueryParser.validateIdentity(identity, expectedAccount: expectedAccount)
                let raw = try await jwxtGet(path)
                let value = try AcademicQueryParser.decode(raw, key: key)
                let finalIdentity = try await jwxtGet("api/home/currentUser.do")
                try AcademicQueryParser.validateIdentity(finalIdentity, expectedAccount: expectedAccount)
                guard epoch == sessionEpoch, !Task.isCancelled else { throw CancellationError() }
                return value
            } catch AcademicQueryError.authenticationRequired { throw NetworkError.sessionExpired() }
        }
        do { return try await read() }
        catch {
            guard epoch == sessionEpoch, !Task.isCancelled, !NetworkError.isCancellation(error) else { throw CancellationError() }
            // 已拿到业务失败 / 未知 JSON 或认证错误时不轮询、不尝试额外接口。
            guard !(error is AcademicQueryError), !NetworkError.from(error).isSessionExpired,
                  !webvpnOn, await ensureWebVPN() else { throw error }
            guard epoch == sessionEpoch, !Task.isCancelled else { throw CancellationError() }
            return try await read()
        }
    }

    func fetchAcademicServiceDirectory(expectedAccount: String) async throws -> [AcademicServiceItem] {
        let epoch = sessionEpoch
        try await jwxtSSO()
        let identity = try await jwxtGet("api/home/currentUser.do")
        try AcademicQueryParser.validateIdentity(identity, expectedAccount: expectedAccount)
        let user = try AcademicQueryParser.payload(identity, title: "教务身份") as? [String: Any]
        var path = "api/home/menus.do"
        if let type = user.flatMap({ AcademicQueryParser.scalar($0["userType"]) }), !type.isEmpty {
            var parts = URLComponents(); parts.queryItems = [URLQueryItem(name: "userType", value: type)]
            path += "?" + (parts.percentEncodedQuery ?? "")
        }
        let result = try AcademicServiceParser.menus(await jwxtGet(path))
        try AcademicQueryParser.validateIdentity(await jwxtGet("api/home/currentUser.do"), expectedAccount: expectedAccount)
        guard sessionEpoch == epoch, !Task.isCancelled else { throw CancellationError() }
        return result
    }

    func fetchAcademicExams(termCode: String, expectedAccount: String) async throws -> [AcademicExam] {
        let epoch = sessionEpoch
        try await jwxtSSO()
        try AcademicQueryParser.validateIdentity(await jwxtGet("api/home/currentUser.do"), expectedAccount: expectedAccount)
        guard case .terms(let terms) = try AcademicQueryParser.decode(await jwxtGet("api/home/student/schoolCalendars.do"), key: .terms),
              terms.contains(where: { $0.code == termCode }) else { throw AcademicQueryError.invalid("考试学期") }
        var query = URLComponents(); query.queryItems = [URLQueryItem(name: "termCode", value: termCode)]
        let exams = try AcademicServiceParser.exams(await jwxtGet("api/home/student/exams.do?" + (query.percentEncodedQuery ?? "")), term: termCode)
        try AcademicQueryParser.validateIdentity(await jwxtGet("api/home/currentUser.do"), expectedAccount: expectedAccount)
        guard sessionEpoch == epoch, !Task.isCancelled else { throw CancellationError() }
        return exams
    }

    // Verified against pyfagl/modules/pyfacxcd/pyfacxcd.js and
    // public/commonpage_PYFAGL/jsmindFrame/{jsmindFrameBS,jsmindSidebar}.js.
    private func personalProgramRows(action: String, fields: [String: String] = [:]) async throws -> [[String: Any]] {
        let modules = ["pyfacdxxcx": "pyfacxcd", "cxpyfa": "pyfaglepg", "pyfakzcx": "pyfaglepg", "pyfakzkccxx": "pyfaglepg"]
        guard let module = modules[action] else { throw AcademicQueryError.invalid("培养方案查询") }
        let epoch = sessionEpoch
        let source = URL(string: Self.jwxtBase + "/jwapp/sys/pyfagl/modules/\(module)/\(action).do")!
        let url = URL(string: maybeWrap(source.absoluteString))!
        var result: [[String: Any]] = []
        for page in 1...20 {
            var parameters = fields
            parameters["pageNumber"] = String(page); parameters["pageSize"] = "500"
            let response = try await http.postForm(url, fields: parameters, extraHeaders: [
                "Accept": "application/json", "X-Requested-With": "XMLHttpRequest", "Referer": Self.jwxtBase + "/jwapp/sys/pyfagl/*default/index.do"
            ])
            guard epoch == sessionEpoch, !Task.isCancelled else { throw CancellationError() }
            let landed = WebVPN.unwrap(response.finalURL) ?? response.finalURL
            if response.status == 401 || landed.host == "pass.neu.edu.cn" { throw NetworkError.sessionExpired() }
            guard response.status == 200, landed == source else { throw AcademicQueryError.invalid("培养方案接口来源") }
            let parsed = try PersonalAcademicProgramParser.rows(http.json(response), action: action)
            result += parsed.rows
            if let total = parsed.total {
                if result.count >= total { return result }
                guard !parsed.rows.isEmpty else { throw AcademicQueryError.invalid("培养方案分页") }
            } else if parsed.rows.count < 500 { return result }
        }
        throw AcademicQueryError.invalid("培养方案分页")
    }

    func fetchPersonalPrograms(expectedAccount: String) async throws -> [PersonalAcademicProgram] {
        try await jwxtSSO()
        try AcademicQueryParser.validateIdentity(await jwxtGet("api/home/currentUser.do"), expectedAccount: expectedAccount)
        let entry = URL(string: maybeWrap(Self.jwxtBase + "/jwapp/sys/pyfagl/*default/index.do?forceApp=pyfagl"))!
        let landing = try await http.get(entry)
        let original = WebVPN.unwrap(landing.finalURL) ?? landing.finalURL
        guard landing.status == 200, original.host == "jwxt.neu.edu.cn", original.path.hasPrefix("/jwapp/sys/pyfagl/") else {
            throw AcademicQueryError.authenticationRequired
        }
        let rows = try await personalProgramRows(action: "pyfacdxxcx")
        let values = try rows.map(PersonalAcademicProgramParser.program)
        guard Set(values.map(\.id)).count == values.count else { throw AcademicQueryError.invalid("个人培养方案") }
        try AcademicQueryParser.validateIdentity(await jwxtGet("api/home/currentUser.do"), expectedAccount: expectedAccount)
        return values
    }

    func fetchPersonalProgramTree(_ program: PersonalAcademicProgram, expectedAccount: String) async throws -> AcademicProgramTree {
        try AcademicQueryParser.validateIdentity(await jwxtGet("api/home/currentUser.do"), expectedAccount: expectedAccount)
        let allowed = try await personalProgramRows(action: "pyfacdxxcx")
        guard allowed.contains(where: { AcademicQueryParser.scalar($0["PYFADM"]) == program.id }) else { throw AcademicQueryError.accountMismatch }
        let fields = ["PYFADM": program.id]
        let details = try await personalProgramRows(action: "cxpyfa", fields: fields)
        guard details.count == 1 else { throw AcademicQueryError.invalid("培养方案详情") }
        let actual = try PersonalAcademicProgramParser.program(details[0])
        guard actual.id == program.id else { throw AcademicQueryError.accountMismatch }
        let groups = try await personalProgramRows(action: "pyfakzcx", fields: fields)
        let tree = try PersonalAcademicProgramParser.tree(program: actual, groups: groups)
        try AcademicQueryParser.validateIdentity(await jwxtGet("api/home/currentUser.do"), expectedAccount: expectedAccount)
        return tree
    }

    func fetchPersonalProgramCourses(_ tree: AcademicProgramTree, node: AcademicProgramNode, expectedAccount: String) async throws -> [AcademicPageCourse] {
        guard tree.nodes.contains(node) else { throw AcademicQueryError.invalid("培养方案课组") }
        try AcademicQueryParser.validateIdentity(await jwxtGet("api/home/currentUser.do"), expectedAccount: expectedAccount)
        var fields = ["PYFADM": tree.program.id, "*order": "+KCH"]
        if node.parentID != nil { fields["KZH"] = node.id }
        let rows = try await personalProgramRows(action: "pyfakzkccxx", fields: fields)
        let courses = try rows.enumerated().map { try PersonalAcademicProgramParser.course($0.element, index: $0.offset) }
        try AcademicQueryParser.validateIdentity(await jwxtGet("api/home/currentUser.do"), expectedAccount: expectedAccount)
        return courses
    }

    func fetchJwxtGrades() async throws -> GradeReport {
        do {
            return try await fetchGradeReport()
        } catch {
            if NetworkError.isCancellation(error) || Task.isCancelled { throw CancellationError() }
            // 可访问登录页不代表可访问校内成绩接口；直连失败后仅尝试一次网关。
            guard !webvpnOn, await ensureWebVPN() else { throw error }
            try Task.checkCancellation()
            return try await fetchGradeReport()
        }
    }

    private func fetchGradeReport() async throws -> GradeReport {
        try await jwxtSSO()
        let raw = try await jwxtGet("api/home/student/schoolCalendars.do")
        let terms = try AcademicResponse.terms(raw)
        var semesters: [GradeSemester] = []
        var failed: [String] = []
        for term in terms {
            try Task.checkCancellation()
            do {
                let raw = try await jwxtGet("api/home/student/scores.do?termCode=\(term.code.urlFormEncoded)")
                try Task.checkCancellation()
                let courses = try AcademicResponse.courses(raw)
                semesters.append(GradeSemester(name: term.name, termCode: term.code, current: term.current, courses: courses))
            } catch {
                if NetworkError.isCancellation(error) || Task.isCancelled { throw CancellationError() }
                if NetworkError.from(error).isSessionExpired { throw error }
                failed.append(term.name)
            }
        }
        try Task.checkCancellation()
        guard !semesters.isEmpty else { throw NetworkError(message: "未获取到成绩数据，请打开教务网页后同步") }
        return GradeReport(semesters: semesters, failedTerms: failed)
    }

    /// Decide before showing any login form, so off-campus users authenticate in one cookie realm.
    func browserLoginEntryURL() async -> URL {
        if webvpnOn || hasWebVPNTicket { return URL(string: WebVPN.casService)! }
        return await isCampusNet() ? CasCrypto.casLoginURL : URL(string: WebVPN.casService)!
    }

    private func authenticationURL(for service: String) -> URL {
        let direct = "https://pass.neu.edu.cn/tpass/login?service=\(service.urlFormEncoded)"
        // Gateway-first browser logins own a proxied CAS session, not a public CASTGC.
        return URL(string: (webvpnOn || hasWebVPNTicket) && !hasCasSession ? WebVPN.wrap(direct) : direct)!
    }

    func browserDestination(for url: URL) -> URL {
        guard webvpnOn else { return url }
        if hasCasSession {
            if let publicCAS = WebVPN.publicCASURL(from: url) { return publicCAS }
            if url.host?.lowercased() == "pass.neu.edu.cn" { return url }
        }
        guard WebVPN.shouldProxyBrowserURL(url) else { return url }
        return URL(string: WebVPN.wrap(url.absoluteString)) ?? url
    }

    func prepareBrowserURL(_ url: URL) async -> URL {
        guard WebVPN.shouldProxyBrowserURL(url) || WebVPN.isWrapped(url.absoluteString) else { return url }
        await prepareAccess()
        return browserDestination(for: url)
    }

    func browserCookies() -> [HTTPCookie] { http.cookies.allCookies() }

    func absorbBrowserCookies(_ cookies: [HTTPCookie]) {
        http.cookies.absorb(cookies)
        adoptGatewayTicket()
    }

    func replaceLearningCookies(_ cookies: [HTTPCookie], platform: LearningPlatform) {
        http.cookies.replace(cookies, matching: platform.ownsCookie)
        absorbBrowserCookies(cookies)
    }

    func restoreLearningCookies(_ cookies: [HTTPCookie]) {
        // The learning snapshot can be newer than the portal snapshot, including logged-out platforms.
        // Keep a freshly renewed gateway ticket from the current portal login.
        http.cookies.replace(cookies) { cookie in
            let domain = cookie.domain.trimmingCharacters(in: CharacterSet(charactersIn: "."))
            return domain != "webvpn.neu.edu.cn" && LearningPlatform.allCases.contains { $0.ownsCookie(cookie) }
        }
        retainMissingCookies(cookies)
    }

    // MARK: - 一卡通 / 网费 / 电费（接口与解析对齐泥洞项目实测实现）

    static let serviceCard = "http://ecard.neu.edu.cn/selflogin/login.aspx"
    static let cardHomePath = "/selfsearch/User/Home.aspx"
    static let servicePay = "https://pay.neu.edu.cn/drCasLogin"
    static let servicePortalTP = "https://portal.neu.edu.cn/tp_up/"

    private static let ecardBase = "http://ecard.neu.edu.cn"

    /// 一卡通余额：CAS 换票 → ecard 自动提交表单 → baseinfo 页解析输入框。
    func fetchCardBalance() async throws -> CardBalance {
        await prepareAccess()
        do { return try await fetchCardBalanceOnce() }
        catch {
            if NetworkError.isCancellation(error) || Task.isCancelled { throw CancellationError() }
            let original = error
            let previousRoute = webvpnOn
            invalidateAccessRoute()
            await prepareAccess()
            guard previousRoute != webvpnOn else { throw original }
            return try await fetchCardBalanceOnce()
        }
    }

    private func fetchCardBalanceOnce() async throws -> CardBalance {
        await prepareAccess()
        let resp = try await casLand(Self.serviceCard)
        let ssoHTML = resp.text
        let form = Self.inputValuesByName(ssoHTML, names: ["username", "timestamp", "auid"])
        if !form.isEmpty {
            guard ["username", "timestamp", "auid"].allSatisfy({ form[$0]?.isEmpty == false }) else {
                throw NetworkError(message: "一卡通单点登录表单不完整")
            }
            if let url = URL(string: maybeWrap(Self.ecardBase + "/selfsearch/SSOLogin.aspx")) {
                let response = try await http.postForm(url, fields: form, extraHeaders: [
                    "Referer": resp.finalURL.absoluteString,
                    "Origin": URLComponents(url: url, resolvingAgainstBaseURL: false).map { "\($0.scheme!)://\($0.host!)" } ?? "",
                    "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8"
                ])
                guard (200..<400).contains(response.status) else {
                    throw NetworkError(message: "一卡通单点登录 HTTP \(response.status)")
                }
            }
        }
        do {
            let page = try await ecardGet(Self.cardHomePath)
            return try Self.parseCardBalance(fromHTML: page)
        } catch {
            if NetworkError.isCancellation(error) || Task.isCancelled { throw CancellationError() }
            let page = try await ecardGet("/selfsearch/User/baseinfo.aspx")
            return try Self.parseCardBalance(fromHTML: page)
        }
    }

    static func parseCardBalance(fromHTML page: String) throws -> CardBalance {
        try CardBalanceDocument.parse(page)
    }

    /// 某自然月的一卡通流水（单月最多 10 页，超出返回 truncated）。
    func fetchCardBills(year: Int, month: Int) async throws -> (bills: [CardBill], truncated: Bool) {
        do { _ = try await fetchCardBalance() }
        catch { if NetworkError.isCancellation(error) || Task.isCancelled { throw CancellationError() } }
        var html = try await ecardGet("/selfsearch/User/ConsumeInfo.aspx")

        let fields = Self.cardBillSearchFields(html: html, year: year, month: month)

        var response = try await postToEcard("/selfsearch/User/ConsumeInfo.aspx", fields)
        html = response.text
        var bills = try Self.parseBillTable(html)
        var pages: Set<[CardBill]> = [bills]
        var truncated = false

        for page in 2...10 {
            guard Self.hasNextPage(html, page) else { break }
            var pageFields = Self.cardBillSearchFields(html: html, year: year, month: month, includeSearchButton: false)
            pageFields["__EVENTTARGET"] = "ctl00$ContentPlaceHolder1$AspNetPager1"
            pageFields["__EVENTARGUMENT"] = "\(page)"
            response = try await postToEcard("/selfsearch/User/ConsumeInfo.aspx", pageFields)
            html = response.text
            let more = try Self.parseBillTable(html)
            guard !more.isEmpty, pages.insert(more).inserted else {
                throw NetworkError(message: "一卡通流水翻页未推进，请在网页核对后重试")
            }
            bills.append(contentsOf: more)
            if page == 10 && Self.hasNextPage(html, 11) { truncated = true }
        }
        return (bills, truncated)
    }

    /// 网费：门户用量 JSON + 缴费大厅余额（两路对拍，余额优先取缴费大厅）。
    func fetchNetInfo(sid: String) async throws -> NetUsageInfo {
        var balance: Double?
        var bytes: Int64?
        var seconds: Int64?
        var times: Int64?
        var lastError = "网费查询失败"
        for attempt in 0..<2 {
            do {
                if let value = try await portalWlzz() {
                    balance = Self.findDouble(value, keys: ["user_balance", "userBalance", "balance"])
                    bytes = Self.findInt(value, keys: ["sum_bytes", "sumBytes", "SUM_BYTES", "used_bytes", "usedBytes", "usedFlow", "used_flow"])
                    seconds = Self.findInt(value, keys: ["sum_seconds", "sumSeconds", "SUM_SECONDS"])
                    times = Self.findInt(value, keys: ["sum_times", "sumTimes", "SUM_TIMES"])
                    if bytes != nil { break }
                    lastError = "门户网费没有流量字段"
                } else {
                    lastError = "门户网费还停在登录页"
                }
            } catch let e as NetworkError {
                lastError = e.message
                if e.message.contains("访问被拒绝") { break }
            } catch {
                lastError = error.localizedDescription
            }
            if attempt == 0 { try? await Task.sleep(nanoseconds: 500_000_000) }
        }
        do {
            _ = try await casLand(Self.servicePay)
        } catch let e as NetworkError where e.isSessionExpired {
            throw e
        } catch {}
        if let url = URL(string: "https://pay.neu.edu.cn/queryNetAccBalance") {
            let resp = try? await http.postForm(url, fields: [
                "netNo": sid,
                "netType": "1",
                "factorycode": "N005",
            ])
            if let resp, let json = try? http.json(resp) as? [String: Any] {
                balance = json.dbl("netaccbal") ?? balance
            }
        }
        guard let finalBalance = balance else { throw NetworkError(message: lastError) }
        return NetUsageInfo.fromPortal(balance: finalBalance, bytes: bytes, seconds: seconds, times: times)
    }

    /// 电费：缴费大厅 queryRommInfo，房间码为宿舍 3 位 + 寝室 4 位。
    func fetchElectric(room rawRoom: String) async throws -> ElectricInfo {
        let room = ElectricRoomKey.normalize(rawRoom)
        if room.isEmpty {
            return ElectricInfo(unbound: true, remainKwh: nil, roomNo: nil, roomLabel: nil, lastReadAt: nil)
        }
        guard ElectricRoomKey.isValid(room) else { throw NetworkError(message: "房间码应为 7 位数字") }
        try Task.checkCancellation()
        do {
            _ = try await casLand(Self.servicePay)
        } catch let e as NetworkError where e.isSessionExpired {
            throw e
        } catch {}
        if let url = URL(string: "https://pay.neu.edu.cn/checkProCouldPay") {
            _ = try? await http.postForm(url, fields: ["id": "414"])
        }
        guard let queryURL = URL(string: "https://pay.neu.edu.cn/queryRommInfo") else {
            throw NetworkError(message: "查电费失败")
        }
        let resp = try await http.postForm(queryURL, fields: [
            "elecroomno": room,
            "factorycode": "E039",
        ])
        try Task.checkCancellation()
        if resp.status == 401 { throw PortalAPIError.authenticationRequired }
        guard (200..<300).contains(resp.status) else { throw PortalAPIError.httpStatus(resp.status) }
        let text = resp.text
        guard let json = try? http.json(resp) as? [String: Any] else {
            if text.contains("维护") { throw NetworkError(message: "电费系统维护中，请稍后再试") }
            throw NetworkError(message: "查电费失败")
        }
        guard json.str("returncode") == "SUCCESS" else {
            let msg = json.str("returnmsg")
            throw NetworkError(message: msg.isEmpty ? "查电费失败" : msg)
        }
        let remainText = json.str("elecRemain")
        guard remainText.contains(where: { $0.isNumber }), let remain = Self.parseMoneyLoose(remainText) else {
            throw NetworkError(message: "电费余量暂时读不到")
        }
        return ElectricInfo(
            unbound: false,
            remainKwh: remain,
            roomNo: room,
            roomLabel: json.str("elecroominfo"),
            lastReadAt: json.str("lastReadTime")
        )
    }

    // MARK: - 一卡通 / 缴费大厅辅助

    private func ecardGet(_ path: String) async throws -> String {
        guard let url = URL(string: maybeWrap(Self.ecardBase + path)) else {
            throw NetworkError(message: "一卡通地址无效")
        }
        let resp = try await http.get(url, extraHeaders: ["Accept": "text/html,application/xhtml+xml,*/*;q=0.8",
            "Referer": maybeWrap(Self.ecardBase + "/selfsearch/")])
        guard (200..<300).contains(resp.status) else {
            throw NetworkError(message: "一卡通接口 HTTP \(resp.status)")
        }
        guard String(data: resp.body, encoding: .utf8) != nil else {
            throw NetworkError(message: "一卡通页面需要使用网页会话解码")
        }
        if Self.isSessionLostHTML(resp.text) {
            throw NetworkError(message: "一卡通需要重新建立网页会话")
        }
        return resp.text
    }

    private func postToEcard(_ path: String, _ fields: [String: String]) async throws -> HTTPClient.RawResponse {
        guard let url = URL(string: maybeWrap(Self.ecardBase + path)) else {
            throw NetworkError(message: "一卡通地址无效")
        }
        let response = try await http.postForm(url, fields: fields)
        guard (200..<300).contains(response.status), String(data: response.body, encoding: .utf8) != nil,
              !Self.isSessionLostHTML(response.text) else {
            throw NetworkError(message: "一卡通查询 HTTP \(response.status)，请使用网页会话同步")
        }
        return response
    }

    /// 门户 tp_up 网费用量：先种会话再 POST。返回 nil 表示还停在登录页。
    private func portalWlzz() async throws -> Any? {
        do {
            _ = try await casLand(Self.servicePortalTP)
        } catch let e as NetworkError where e.message.contains("访问被拒绝") {
            throw e
        } catch {}
        _ = try? await http.get(URL(string: "https://portal.neu.edu.cn/tp_up/view?m=up")!)
        guard let url = URL(string: "https://portal.neu.edu.cn/tp_up/up/subgroup/getWlzzList") else { return nil }
        var request = URLRequest(url: url, timeoutInterval: HTTPClient.timeout)
        request.httpMethod = "POST"
        request.setValue("application/json;charset=UTF-8", forHTTPHeaderField: "Content-Type")
        request.setValue("https://portal.neu.edu.cn/tp_up/view?m=up", forHTTPHeaderField: "Referer")
        request.setValue("https://portal.neu.edu.cn", forHTTPHeaderField: "Origin")
        request.httpBody = Data("{}".utf8)
        let resp = try await http.send(request)
        let text = resp.text
        if Self.isAccessDeniedHTML(text) {
            throw NetworkError(message: "一号通访问被拒绝：当前网络被拦截，请换校园网或关闭代理后重试")
        }
        if Self.isSessionLostHTML(text) || text.contains("tpass/login") { return nil }
        return try? http.json(resp)
    }

    private static func isSessionLostHTML(_ html: String) -> Bool {
        html.contains("当前设备需进行身份验证")
            || html.contains("second_auth_form")
            || (html.contains("id=\"un\"") && html.contains("id=\"pd\"") && html.contains("index_login_btn"))
    }

    private static func isAccessDeniedHTML(_ html: String) -> Bool {
        html.contains("访问被拒绝") || html.contains("Access Denied") || html.contains("403 Forbidden")
            || html.contains("请求被拒绝") || html.contains("您的访问被拦截") || html.contains("非法访问")
    }

    static func cardBillSearchFields(html: String, year: Int, month: Int, includeSearchButton: Bool = true) -> [String: String] {
        let lastDay = daysInMonth(year: year, month: month)
        let start = String(format: "%04d-%02d-01", year, month)
        let end = String(format: "%04d-%02d-%02d", year, month, lastDay)

        var fields = hiddenFields(html)
        fields["ctl00$ContentPlaceHolder1$rbtnType"] = "0"
        fields["ctl00$ContentPlaceHolder1$txtStartDate"] = start
        fields["ctl00$ContentPlaceHolder1$txtEndDate"] = end
        if includeSearchButton {
            let button = inputTags(html).first { $0["name"] == "ctl00$ContentPlaceHolder1$btnSearch" }
            fields["ctl00$ContentPlaceHolder1$btnSearch"] = button?["value"] ?? "查  询"
        }

        return fields
    }

    static func daysInMonth(year: Int, month: Int) -> Int {
        var comps = DateComponents()
        comps.year = year
        comps.month = month
        comps.day = 1
        guard let first = Calendar.current.date(from: comps),
              let range = Calendar.current.range(of: .day, in: .month, for: first) else { return 30 }
        return range.count
    }

    // MARK: - 一卡通 HTML 解析（ASP.NET 页面，容错优先）

    private static let trRegex = try! NSRegularExpression(pattern: #"<tr\b[^>]*>[\s\S]*?</tr>"#, options: [.caseInsensitive])
    private static let tableRegex = try! NSRegularExpression(pattern: #"<table\b[^>]*>(?:(?!<table\b)[\s\S])*?</table>"#, options: [.caseInsensitive])
    private static let tdRegex = try! NSRegularExpression(pattern: #"<t[dh]\b[^>]*>[\s\S]*?</t[dh]>"#, options: [.caseInsensitive])
    private static let tagStripRegex = try! NSRegularExpression(pattern: #"<[^>]*>"#)
    private static let billDateRegex = try! NSRegularExpression(pattern: #"\d{4}[-/年]\d{1,2}[-/月]\d{1,2}"#)
    private static let junkDateSubjectRegex = try! NSRegularExpression(pattern: #"^\d{4}\s*[-/年.]\s*\d{1,2}\s*[-/月.]\s*\d{1,2}"#)
    private static let numberRegex = try! NSRegularExpression(pattern: #"[0-9]+(?:\.[0-9]+)?"#)

    private static func inputTags(_ html: String) -> [[String: String]] {
        HTMLInputFields.parse(html)
    }

    /// type=hidden 输入框：name -> value（ASP.NET 回发必需）。
    static func hiddenFields(_ html: String) -> [String: String] {
        var out: [String: String] = [:]
        for attrs in inputTags(html) where attrs["hidden"] == "1" {
            if let name = attrs["name"], !name.isEmpty {
                out[name] = attrs["value"] ?? ""
            }
        }
        return out
    }

    private static func inputValuesByName(_ html: String, names: [String]) -> [String: String] {
        var out: [String: String] = [:]
        for attrs in inputTags(html) {
            if let name = attrs["name"], names.contains(name) {
                out[name] = attrs["value"] ?? ""
            }
        }
        return out
    }

    private static func parseMoney(_ raw: String) -> Double? {
        let cleaned = raw
            .replacingOccurrences(of: "元", with: "")
            .replacingOccurrences(of: "￥", with: "")
            .replacingOccurrences(of: "¥", with: "")
            .replacingOccurrences(of: ",", with: "")
            .trimmingCharacters(in: .whitespaces)
        return Double(cleaned)
    }

    private static func parseMoneyLoose(_ raw: String) -> Double? {
        guard let m = numberRegex.firstMatch(in: raw, range: NSRange(raw.startIndex..., in: raw)),
              let r = Range(m.range, in: raw) else { return nil }
        return Double(String(raw[r]))
    }

    static func hasNextPage(_ html: String, _ page: Int) -> Bool {
        let text = HTMLInputFields.decode(html.replacingOccurrences(of: #"<[^>]*>"#, with: " ", options: .regularExpression))
        let count = try! NSRegularExpression(pattern: #"共\s*(\d+)\s*页"#)
        if let match = count.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
           let range = Range(match.range(at: 1), in: text), let total = Int(text[range]) {
            return page <= total
        }
        let pattern = #"(?is)(?:AspNetPager[^'"<>]*['"]\s*,\s*['"]\#(page)['"]|<a\b[^>]*>\s*\#(page)\s*</a>)"#
        return HTMLInputFields.decode(html).range(of: pattern, options: .regularExpression) != nil
    }

    private static func cellText(_ html: String, _ range: Range<String.Index>) -> String {
        let cell = String(html[range])
        let stripped = tagStripRegex.stringByReplacingMatches(
            in: cell,
            range: NSRange(cell.startIndex..., in: cell),
            withTemplate: ""
        )
        return HTMLInputFields.decode(stripped).replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func isJunkSubject(_ subject: String) -> Bool {
        let s = subject.trimmingCharacters(in: .whitespaces)
        if s.isEmpty { return false }
        if s.contains("物联网采集") { return true }
        return junkDateSubjectRegex.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) != nil
    }

    static func parseBillTable(_ html: String) throws -> [CardBill] {
        var out: [CardBill] = []
        var recognized = false
        for table in tableRegex.matches(in: html, range: NSRange(html.startIndex..., in: html)) {
            var columns: [String]?
            for m in trRegex.matches(in: html, range: table.range) {
                guard let rowRange = Range(m.range, in: html) else { continue }
                let cells = tdRegex
                    .matches(in: html, range: NSRange(rowRange, in: html))
                    .compactMap { tm in Range(tm.range, in: html).map { cellText(html, $0) } }
                func index(_ pattern: String) -> Int? {
                    columns?.firstIndex { $0.range(of: pattern, options: .regularExpression) != nil }
                }
                if cells.contains(where: { $0.range(of: "时间|日期", options: .regularExpression) != nil }),
                   cells.contains(where: { $0.range(of: "金额|发生额", options: .regularExpression) != nil }) {
                    columns = cells
                    recognized = true
                    continue
                }
                func value(_ column: Int?) -> String {
                    guard let column, cells.indices.contains(column) else { return "" }
                    return cells[column]
                }
                // Older pages omit headers and use the original fixed column order.
                guard columns != nil || cells.count >= 5 else { continue }
                let timeText = value(columns == nil ? 0 : index("时间|日期"))
                guard billDateRegex.firstMatch(in: timeText, range: NSRange(timeText.startIndex..., in: timeText)) != nil else {
                    continue
                }
                recognized = true
                let subject = value(columns == nil ? 1 : index("交易类型|交易名称|摘要|类型|项目"))
                guard !isJunkSubject(subject) else { continue }
                guard var amount = parseMoney(value(columns == nil ? 2 : index("交易金额|发生额|金额"))), amount.isFinite else {
                    throw NetworkError(message: "一卡通流水金额未能识别，请在网页核对")
                }
                let station = value(columns == nil ? (cells.count > 7 ? 7 : 6) : index("站点|终端|商户|地点"))
                if abs(amount) < 0.005 && station.contains("物联网采集") { continue }
                let isRecharge = subject.contains("充值") || subject.contains("转账") || subject.contains("补助")
                if amount > 0 && !isRecharge { amount = -amount }
                if amount < 0 && isRecharge { amount = abs(amount) }
                let fee = parseMoney(value(columns == nil ? 3 : index("手续费")))
                let balanceAfter = parseMoney(value(columns == nil ? 4 : index("余额")))
                let time = PortalDate.dateTime(normalizeBillTime(timeText))
                out.append(CardBill(
                    time: time,
                    timeText: timeText,
                    subject: subject,
                    amount: amount,
                    fee: fee,
                    balanceAfter: balanceAfter,
                    station: station
                ))
            }
        }
        guard recognized || html.range(of: "暂无|没有.*记录|无记录|共\\s*0\\s*条", options: .regularExpression) != nil else {
            throw NetworkError(message: "一卡通流水页面结构未识别，请打开网页认证后同步")
        }
        return out
    }

    /// 「2026/9/8 12:30」「2026年9月8日 12:30」等 → 「2026-09-08 12:30:00」。
    private static let billTimeRegex = try! NSRegularExpression(pattern: #"(\d{4})-(\d{1,2})-(\d{1,2})(?:[^0-9]{0,4}(\d{1,2}):(\d{2})(?::(\d{2}))?)?"#)

    private static func normalizeBillTime(_ raw: String) -> String {
        let replaced = raw
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: "年", with: "-")
            .replacingOccurrences(of: "月", with: "-")
            .replacingOccurrences(of: "日", with: " ")
        guard let cm = billTimeRegex.firstMatch(in: replaced, range: NSRange(replaced.startIndex..., in: replaced)),
              cm.numberOfRanges >= 4,
              let yr = Range(cm.range(at: 1), in: replaced),
              let mr = Range(cm.range(at: 2), in: replaced),
              let dr = Range(cm.range(at: 3), in: replaced) else {
            return String(replaced.prefix(32))
        }
        func pad(_ s: String) -> String { s.count == 1 ? "0" + s : s }
        let y = String(replaced[yr])
        let mo = pad(String(replaced[mr]))
        let d = pad(String(replaced[dr]))
        let hh = cm.range(at: 4).location != NSNotFound ? pad(String(replaced[Range(cm.range(at: 4), in: replaced)!])) : "00"
        let mi = cm.range(at: 5).location != NSNotFound ? pad(String(replaced[Range(cm.range(at: 5), in: replaced)!])) : "00"
        let ss = cm.range(at: 6).location != NSNotFound ? pad(String(replaced[Range(cm.range(at: 6), in: replaced)!])) : "00"
        return "\(y)-\(mo)-\(d) \(hh):\(mi):\(ss)"
    }

    private static func numberFrom(_ v: Any) -> Double? {
        if let n = v as? NSNumber { return n.doubleValue }
        if let s = v as? String {
            return Double(s.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ""))
        }
        return nil
    }

    private static func findValue(_ value: Any, keys: [String]) -> Any? {
        if let map = value as? [String: Any] {
            for k in keys {
                if let v = map[k], !(v is NSNull) { return v }
            }
            for v in map.values {
                if let found = findValue(v, keys: keys) { return found }
            }
        } else if let arr = value as? [Any] {
            for v in arr {
                if let found = findValue(v, keys: keys) { return found }
            }
        }
        return nil
    }

    private static func findDouble(_ value: Any, keys: [String]) -> Double? {
        findValue(value, keys: keys).flatMap(numberFrom)
    }

    private static func findInt(_ value: Any, keys: [String]) -> Int64? {
        findValue(value, keys: keys).flatMap { numberFrom($0).flatMap { Int64(exactly: $0) } }
    }

    // MARK: - HTML 解析

    /// 从门户首页 HTML 中提取 window.userInfoDSL（括号配对扫描，一次遍历）。
    static func extractUser(fromHTML html: String) -> PortalUser? {
        guard let dslRange = html.range(of: "userInfoDSL") else { return nil }
        guard let eqRange = html.range(of: "=", range: dslRange.upperBound..<html.endIndex) else { return nil }
        guard let braceRange = html.range(of: "{", range: eqRange.upperBound..<html.endIndex) else { return nil }

        var depth = 0
        var inString = false
        var escape = false
        var i = braceRange.lowerBound
        while i < html.endIndex {
            let ch = html[i]
            if escape {
                escape = false
            } else if ch == "\\" {
                escape = true
            } else if ch == "\"" {
                inString.toggle()
            } else if !inString {
                if ch == "{" {
                    depth += 1
                } else if ch == "}" {
                    depth -= 1
                    if depth == 0 {
                        let jsonStr = String(html[braceRange.lowerBound...i])
                        guard let data = jsonStr.data(using: .utf8),
                              let obj = (try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])) as? [String: Any] else {
                            return nil
                        }
                        let user = PortalUser.fromInfoJson(obj)
                        return user.hasProfile ? user : nil
                    }
                }
            }
            i = html.index(after: i)
        }
        return nil
    }

    private static func firstMatch(_ regex: NSRegularExpression, _ text: String) -> String? {
        let range = NSRange(text.startIndex..., in: text)
        guard let m = regex.firstMatch(in: text, range: range), m.numberOfRanges > 1,
              let r = Range(m.range(at: 1), in: text) else { return nil }
        return String(text[r])
    }
}

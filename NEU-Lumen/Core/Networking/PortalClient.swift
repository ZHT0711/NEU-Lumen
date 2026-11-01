import Foundation

/// 一号通门户 + 教务系统客户端：CAS 登录与全部业务接口。
/// 逻辑与 NEUPortal（Flutter 版）portal_client.dart 一致：
/// 手动重定向 + Cookie 罐，保证 CASTGC / SESS_ID 正确跨域传递。
final class PortalClient {
    static let portalBase = "https://personal.neu.edu.cn/portal"
    static let jwxtBase = "https://jwxt.neu.edu.cn"

    private let http: HTTPClient

    // MARK: - 校园网 / WebVPN

    /// WebVPN 模式开启后，校内主机的重定向与请求都会改写为网关地址。
    private(set) var webvpnOn = false
    private var campusProbe: (date: Date, isCampus: Bool)?

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
    func isCampusNet() async -> Bool {
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
        campusProbe = (Date(), ok)
        if ok { webvpnOn = false }
        return ok
    }

    private func quickReachable(_ url: String) async -> Bool {
        guard let requestURL = URL(string: url) else { return false }
        var request = URLRequest(url: requestURL, timeoutInterval: 2.5)
        do {
            _ = try await http.send(request, maxHops: 1)
            return true
        } catch {
            return false
        }
    }

    /// 用一号通 CASTGC 给 WebVPN 网关换票（必须走公网 pass，不能先开 webvpn 首页）。
    @discardableResult
    func ensureWebVPN() async -> Bool {
        if webvpnOn && http.cookies.hasWebVPNTicket() { return true }
        for _ in 0..<2 {
            let login = "https://pass.neu.edu.cn/tpass/login?service=\(WebVPN.casService.urlFormEncoded)"
            if let url = URL(string: login),
               let resp = try? await http.get(url) {
                let landed = resp.finalURL.absoluteString
                if http.cookies.hasWebVPNTicket()
                    || (landed.contains("webvpn.neu.edu.cn") && !landed.contains("tpass/login")) {
                    webvpnOn = true
                    return true
                }
            }
            try? await Task.sleep(nanoseconds: 400_000_000)
        }
        return false
    }

    /// 校外准备：探测校园网，不通则种 WebVPN 票（失败不抛错，由调用方按需处理）。
    func prepareAccess() async {
        if await isCampusNet() { return }
        _ = await ensureWebVPN()
    }

    private func maybeWrap(_ url: String) -> String {
        guard webvpnOn else { return url }
        if WebVPN.isIntranet(url) { return WebVPN.wrap(url) }
        // 校外门户 HTML 会被学校重定向进网关，门户域的请求统一改走网关
        let lowered = url.lowercased()
        if lowered.contains("personal.neu.edu.cn") || lowered.contains("portal.neu.edu.cn") {
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

    /// WebView 会话回收后：若已持有网关票据则直接进入网关模式
    /// （校外门户直连必被网关劫持，门户读取必须经网关）。
    func adoptGatewayTicket() {
        if http.cookies.hasWebVPNTicket() {
            webvpnOn = true
        }
    }

    /// 用 CASTGC 给指定 service 换 ST 并跟随到业务系统（停留在 CAS 登录页视为会话失效）。
    private func casLand(_ service: String) async throws -> HTTPClient.RawResponse {
        let login = "https://pass.neu.edu.cn/tpass/login?service=\(service.urlFormEncoded)"
        guard let url = URL(string: login) else {
            throw NetworkError(message: "认证地址无效")
        }
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
        http.cookies.clear()
        secondAuthExecution = nil
        webvpnOn = false
        campusProbe = nil
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
        // 三级自愈：直连 → 网关（现有票据）→ 丢弃票据强制重换（UA 绑定兜底）
        for attempt in 0..<3 {
            if attempt == 2 {
                // 没有 CAS 就无法重换票据，不能为了补资料丢掉浏览器的可用会话。
                guard hasCasSession else { break }
                webvpnOn = false
                http.cookies.removeWebVPNTickets()
            } else {
                adoptGatewayTicket()
            }
            if attempt >= 1 {
                let gatewayReady = await ensureWebVPN()
                if !gatewayReady { throw NetworkError.sessionExpired() }
            }
            guard let requestURL = URL(string: maybeWrap(Self.portalBase)) else {
                throw NetworkError(message: "门户地址无效")
            }
            let resp = try await http.get(requestURL)
            if !Self.isPortalSessionFailure(resp), let user = Self.extractUser(fromHTML: resp.text) {
                return user
            }
        }
        throw NetworkError.sessionExpired()
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
        if resp.finalURL.host?.contains("pass.neu.edu.cn") == true
            || resp.finalURL.path.contains("/tpass/login") {
            throw NetworkError.sessionExpired()
        }
        if resp.body.isEmpty {
            throw NetworkError(message: "接口返回为空")
        }
        let json = try http.json(resp)
        guard let j = json as? [String: Any] else {
            throw NetworkError(message: "接口返回格式异常")
        }
        if let code = j["e"] as? Int, code != 0 {
            let m = j.str("m")
            throw NetworkError(message: "\(m.isEmpty ? "接口错误" : m)（代码 \(code)）")
        }
        return j.obj("d")
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

        let dayMap = d.obj("data").obj("day")
        var out: [CourseOccurrence] = []
        out.reserveCapacity(32)
        for (dateStr, slotValue) in dayMap {
            guard let date = PortalDate.day(dateStr) else { continue }
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
                        room: room.isEmpty ? "待定" : room
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
        let list = (d["list"] as? [Any])?.compactMap { $0 as? [String: Any] } ?? []
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
    func fetchNews(pageSize: Int = 12) async throws -> [NewsItem] {
        let tabs = try await api("news/frontend/default/tabs", query: [
            URLQueryItem(name: "system", value: ""),
            URLQueryItem(name: "need_num", value: "1"),
        ])
        var cid = "1244bca0563f72ea134e4d78973c6911"
        var cname = "东大要闻"
        let tabList = (tabs["list"] as? [Any])?.compactMap { $0 as? [String: Any] } ?? []
        if let first = tabList.first(where: { $0.str("name") == "东大要闻" }) ?? tabList.first {
            cid = first.str("id")
            cname = first.str("name")
        }
        let d = try await api("news/frontend/default/news-list", query: [
            URLQueryItem(name: "system", value: ""),
            URLQueryItem(name: "cid", value: cid),
            URLQueryItem(name: "need_all", value: "0"),
            URLQueryItem(name: "page", value: "1"),
            URLQueryItem(name: "pageSize", value: "\(pageSize)"),
            URLQueryItem(name: "keyword", value: ""),
            URLQueryItem(name: "year", value: ""),
            URLQueryItem(name: "month", value: ""),
            URLQueryItem(name: "publisher", value: ""),
        ])
        let list = (d["list"] as? [Any])?.compactMap { $0 as? [String: Any] } ?? []
        return list.compactMap { n -> NewsItem? in
            let title = n.str("title")
            guard !title.isEmpty else { return nil }
            let id = n.str("id").isEmpty ? n.str("contentid") : n.str("id")
            return NewsItem(
                id: id,
                title: title,
                date: n.str("publish_time").split(separator: " ").first.map(String.init) ?? "",
                category: cname,
                url: n.str("url"),
                picUrl: n.str("picurl")
            )
        }
    }

    /// 办事动态（在办事项），失败时由调用方降级为空。
    func fetchTodos() async throws -> [TodoItem] {
        let d = try await api("personal/frontend/task/apply", query: [
            URLQueryItem(name: "type", value: "all"),
            URLQueryItem(name: "page", value: "1"),
            URLQueryItem(name: "pageSize", value: "10"),
        ])
        let list = (d["list"] as? [Any])?.compactMap { $0 as? [String: Any] } ?? []
        return list.map { t in
            let nodes = (t["node_name"] as? [Any])?.compactMap { $0 as? String } ?? []
            let mobileUrl = t.str("form_mobile_url_view")
            return TodoItem(
                title: t.str("third_app_name"),
                instance: t.str("third_inst_name"),
                node: nodes.last ?? "处理中",
                percent: t.int("percent") ?? 0,
                time: t.str("inst_created").split(separator: ".").first.map(String.init) ?? "",
                url: mobileUrl.isEmpty ? t.str("form_url_view") : mobileUrl
            )
        }
    }

    /// 首页数据条卡片（个人数据 + 明细值）。
    func fetchDataCards() async throws -> [DataCard] {
        let d = try await api("personal/frontend/data/items", query: [
            URLQueryItem(name: "type", value: "personal_data"),
        ])
        let list = (d["data"] as? [Any])?.compactMap { $0 as? [String: Any] } ?? []
        var out: [DataCard] = []
        out.reserveCapacity(list.count)
        for it in list {
            let name = it.str("name")
            if name.isEmpty { continue }
            var value = "—"
            let id = it.str("id")
            if !id.isEmpty,
               let det = try? await api("personal/frontend/data/detail", query: [URLQueryItem(name: "id", value: id)]),
               let inner = det["data"] as? [String: Any] {
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
            out.append(DataCard(name: name, value: value))
        }
        return out
    }

    /// 门户智慧搜索热词。
    func fetchHotSearch(pageSize: Int = 8) async throws -> [String] {
        let resp = try await http.get(URL(string: "\(Self.portalBase)/frontend/search/hot?pageSize=\(pageSize)")!)
        let json = try http.json(resp)
        guard let j = json as? [String: Any], (j["e"] as? Int) == 0 else { return [] }
        let list = j.obj("d")["list"] as? [Any] ?? []
        return list.compactMap { v -> String? in
            if let s = v as? String, !s.isEmpty { return s }
            if let n = v as? NSNumber { return n.stringValue }
            return nil
        }
    }

    // MARK: - 教务系统（金智 jwapp）真实成绩

    private var jwxtAppBase = PortalClient.jwxtBase + "/jwapp/sys/homeapp"

    /// 从真实的学生首页建立会话，并沿用落地后的协议/网关前缀。
    private func jwxtSSO() async throws {
        await prepareAccess()
        let response = try await http.get(URL(string: maybeWrap(Self.jwxtBase + "/jwapp/sys/homeapp/index.do"))!)
        if response.finalURL.host == "pass.neu.edu.cn" { throw NetworkError.sessionExpired() }
        let landed = response.finalURL.absoluteString
        if let range = landed.range(of: "/jwapp/") {
            jwxtAppBase = String(landed[..<range.lowerBound]) + "/jwapp/sys/homeapp"
        } else {
            throw NetworkError(message: "教务首页未能建立会话，请打开教务网页完成认证后同步")
        }
    }

    private func jwxtGet(_ path: String) async throws -> Any {
        let url = URL(string: maybeWrap(jwxtAppBase + "/" + path))!
        let response = try await http.get(url, xhr: true, extraHeaders: [
            "Fetch-Api": "true", "Accept": "application/json", "Referer": jwxtAppBase + "/index.do"
        ])
        if response.finalURL.host == "pass.neu.edu.cn" || response.finalURL.path.contains("/tpass/login") {
            throw NetworkError.sessionExpired()
        }
        guard (200..<300).contains(response.status) else {
            throw NetworkError(message: "教务接口 HTTP \(response.status)，可打开教务网页后同步")
        }
        guard let json = try? http.json(response) else {
            let html = response.text.lowercased()
            if html.contains("tpass/login") || html.contains("name=\"lt\"") { throw NetworkError.sessionExpired() }
            throw NetworkError(message: "教务接口返回了网页，未能取得成绩数据。请打开教务网页完成认证后同步")
        }
        return json
    }

    func fetchJwxtGrades() async throws -> GradeReport {
        do {
            return try await fetchGradeReport()
        } catch {
            // 可访问登录页不代表可访问校内成绩接口；直连失败后仅尝试一次网关。
            guard !webvpnOn, await ensureWebVPN() else { throw error }
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
            do {
                let raw = try await jwxtGet("api/home/student/scores.do?termCode=\(term.code.urlFormEncoded)")
                let courses = try AcademicResponse.courses(raw)
                semesters.append(GradeSemester(name: term.name, termCode: term.code, current: term.current, courses: courses))
            } catch {
                if NetworkError.from(error).isSessionExpired { throw error }
                failed.append(term.name)
            }
        }
        guard !semesters.isEmpty else { throw NetworkError(message: "未获取到成绩数据，请打开教务网页后同步") }
        return GradeReport(semesters: semesters, failedTerms: failed)
    }

    func prepareBrowserURL(_ url: URL) async -> URL {
        guard WebVPN.isIntranet(url.absoluteString) else { return url }
        await prepareAccess()
        return URL(string: maybeWrap(url.absoluteString)) ?? url
    }

    func browserCookies() -> [HTTPCookie] { http.cookies.allCookies() }

    func absorbBrowserCookies(_ cookies: [HTTPCookie]) { http.cookies.absorb(cookies) }

    // MARK: - 一卡通 / 网费 / 电费（接口与解析对齐泥洞项目实测实现）

    static let serviceCard = "http://ecard.neu.edu.cn/selflogin/login.aspx"
    static let servicePay = "https://pay.neu.edu.cn/drCasLogin"
    static let servicePortalTP = "https://portal.neu.edu.cn/tp_up/"

    private static let ecardBase = "http://ecard.neu.edu.cn"

    /// 一卡通余额：CAS 换票 → ecard 自动提交表单 → baseinfo 页解析输入框。
    func fetchCardBalance() async throws -> CardBalance {
        await prepareAccess()
        let resp = try await casLand(Self.serviceCard)
        let ssoHTML = resp.text
        if ssoHTML.contains("username") && ssoHTML.contains("auid") {
            let form = Self.inputValuesByName(ssoHTML, names: ["username", "timestamp", "auid"])
            if let url = URL(string: maybeWrap(Self.ecardBase + "/selfsearch/SSOLogin.aspx")) {
                _ = try? await http.postForm(url, fields: form)
            }
        }
        let page = try await ecardGet("/selfsearch/User/baseinfo.aspx")
        guard let odd = Self.inputValue(page, id: "ContentPlaceHolder1_txtOddFare")
            ?? Self.inputValue(page, name: "ctl00$ContentPlaceHolder1$txtOddFare") else {
            throw NetworkError(message: "一卡通页面上没有主钱包余额")
        }
        let subsidyValue = Self.inputValue(page, id: "ContentPlaceHolder1_txtSpecialOddFare")
            ?? Self.inputValue(page, id: "ContentPlaceHolder1_txtSpecialOddfare")
            ?? Self.inputValue(page, id: "ContentPlaceHolder1_txtSubsidy")
        let status = Self.inputValue(page, id: "ContentPlaceHolder1_txtStatus") ?? "正常"
        return CardBalance(
            balance: Self.parseMoney(odd),
            subsidy: subsidyValue.map(Self.parseMoney) ?? 0,
            status: status
        )
    }

    /// 某自然月的一卡通流水（单月最多 10 页，超出返回 truncated）。
    func fetchCardBills(year: Int, month: Int) async throws -> (bills: [CardBill], truncated: Bool) {
        _ = try? await fetchCardBalance() // 建立 ecard 会话（失败则复用现有会话）
        var html = try await ecardGet("/selfsearch/User/ConsumeInfo.aspx")

        let cal = Calendar.current
        let comps = cal.dateComponents([.year, .month, .day], from: Date())
        let lastDay = Self.daysInMonth(year: year, month: month)
        let start = String(format: "%04d-%02d-01", year, month)
        let end: String
        if comps.year == year && comps.month == month {
            end = String(format: "%04d-%02d-%02d", year, month, comps.day ?? lastDay)
        } else {
            end = String(format: "%04d-%02d-%02d", year, month, lastDay)
        }

        var fields = Self.hiddenFields(html)
        fields["ctl00$ContentPlaceHolder1$rbtnType"] = "0"
        fields["ctl00$ContentPlaceHolder1$txtStartDate"] = start
        fields["ctl00$ContentPlaceHolder1$txtEndDate"] = end
        fields["ctl00$ContentPlaceHolder1$btnSearch"] = "查  询"

        var response = try await postToEcard("/selfsearch/User/ConsumeInfo.aspx", fields)
        html = response.text
        var bills = Self.parseBillTable(html)
        var truncated = false

        for page in 2...10 {
            guard html.contains("AspNetPager"), Self.hasNextPage(html, page) else { break }
            var pageFields = Self.hiddenFields(html)
            pageFields["__EVENTTARGET"] = "ctl00$ContentPlaceHolder1$AspNetPager1"
            pageFields["__EVENTARGUMENT"] = "\(page)"
            response = try await postToEcard("/selfsearch/User/ConsumeInfo.aspx", pageFields)
            html = response.text
            let more = Self.parseBillTable(html)
            if more.isEmpty { break }
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
        return NetUsageInfo(
            balance: finalBalance,
            monthBytes: bytes ?? 0,
            monthSeconds: seconds ?? 0,
            monthTimes: times ?? 0,
            flowFromPortal: bytes != nil
        )
    }

    /// 电费：缴费大厅 queryRommInfo，房间码为宿舍 3 位 + 寝室 4 位。
    func fetchElectric(room rawRoom: String) async throws -> ElectricInfo {
        let room = rawRoom.trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: " ", with: "")
        if room.isEmpty {
            return ElectricInfo(unbound: true, remainKwh: nil, roomNo: nil, roomLabel: nil, lastReadAt: nil)
        }
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
        let resp = try await http.get(url)
        if Self.isSessionLostHTML(resp.text) {
            throw NetworkError(message: "一卡通会话未建立，请重试（校外需走 WebVPN）")
        }
        return resp.text
    }

    private func postToEcard(_ path: String, _ fields: [String: String]) async throws -> HTTPClient.RawResponse {
        guard let url = URL(string: maybeWrap(Self.ecardBase + path)) else {
            throw NetworkError(message: "一卡通地址无效")
        }
        return try await http.postForm(url, fields: fields)
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

    private static let inputTagRegex = try! NSRegularExpression(pattern: #"<input\b[^>]*>"#, options: [.caseInsensitive])
    private static let attrNameRegex = try! NSRegularExpression(pattern: #"\bname\s*=\s*(?:"([^"]*)"|'([^']*)')"#, options: [.caseInsensitive])
    private static let attrValueRegex = try! NSRegularExpression(pattern: #"\bvalue\s*=\s*(?:"([^"]*)"|'([^']*)')"#, options: [.caseInsensitive])
    private static let attrIDRegex = try! NSRegularExpression(pattern: #"\bid\s*=\s*(?:"([^"]*)"|'([^']*)')"#, options: [.caseInsensitive])
    private static let attrHiddenRegex = try! NSRegularExpression(pattern: #"\btype\s*=\s*(?:"hidden"|'hidden'|hidden\b)"#, options: [.caseInsensitive])
    private static let trRegex = try! NSRegularExpression(pattern: #"<tr\b[^>]*>[\s\S]*?</tr>"#, options: [.caseInsensitive])
    private static let tdRegex = try! NSRegularExpression(pattern: #"<td\b[^>]*>[\s\S]*?</td>"#, options: [.caseInsensitive])
    private static let tagStripRegex = try! NSRegularExpression(pattern: #"<[^>]*>"#)
    private static let billDateRegex = try! NSRegularExpression(pattern: #"\d{4}[-/]\d{1,2}[-/]\d{1,2}"#)
    private static let junkDateSubjectRegex = try! NSRegularExpression(pattern: #"^\d{4}\s*[-/年.]\s*\d{1,2}\s*[-/月.]\s*\d{1,2}"#)
    private static let numberRegex = try! NSRegularExpression(pattern: #"[0-9]+(?:\.[0-9]+)?"#)

    private static func attr(_ tag: String, _ regex: NSRegularExpression) -> String? {
        guard let m = regex.firstMatch(in: tag, range: NSRange(tag.startIndex..., in: tag)),
              m.numberOfRanges > 1,
              let r = Range(m.range(at: 1), in: tag) else { return nil }
        return String(tag[r])
    }

    private static func inputTags(_ html: String) -> [[String: String]] {
        let range = NSRange(html.startIndex..., in: html)
        let matches = inputTagRegex.matches(in: html, range: range)
        var out: [[String: String]] = []
        out.reserveCapacity(matches.count)
        for m in matches {
            guard let tagRange = Range(m.range, in: html) else { continue }
            let tag = String(html[tagRange])
            var attrs: [String: String] = [:]
            attrs["name"] = attr(tag, attrNameRegex)
            attrs["value"] = attr(tag, attrValueRegex)
            attrs["id"] = attr(tag, attrIDRegex)
            attrs["hidden"] = attr(tag, attrHiddenRegex) != nil ? "1" : "0"
            out.append(attrs)
        }
        return out
    }

    /// type=hidden 输入框：name -> value（ASP.NET 回发必需）。
    private static func hiddenFields(_ html: String) -> [String: String] {
        var out: [String: String] = [:]
        for attrs in inputTags(html) where attrs["hidden"] == "1" {
            if let name = attrs["name"], !name.isEmpty {
                out[name] = attrs["value"] ?? ""
            }
        }
        return out
    }

    private static func inputValue(_ html: String, id: String) -> String? {
        let value = inputTags(html).first { $0["id"] == id }?["value"]
        return (value?.isEmpty == false) ? value : nil
    }

    private static func inputValue(_ html: String, name: String) -> String? {
        let value = inputTags(html).first { $0["name"] == name }?["value"]
        return (value?.isEmpty == false) ? value : nil
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

    private static func parseMoney(_ raw: String) -> Double {
        let cleaned = raw
            .replacingOccurrences(of: "元", with: "")
            .replacingOccurrences(of: "￥", with: "")
            .replacingOccurrences(of: ",", with: "")
            .trimmingCharacters(in: .whitespaces)
        return Double(cleaned) ?? 0
    }

    private static func parseMoneyLoose(_ raw: String) -> Double? {
        guard let m = numberRegex.firstMatch(in: raw, range: NSRange(raw.startIndex..., in: raw)),
              let r = Range(m.range, in: raw) else { return nil }
        return Double(String(raw[r]))
    }

    private static func hasNextPage(_ html: String, _ page: Int) -> Bool {
        html.contains("'\(page)'") || html.contains(">\(page)<")
    }

    private static func decodeEntities(_ text: String) -> String {
        var s = text
        s = s.replacingOccurrences(of: "&nbsp;", with: " ")
        s = s.replacingOccurrences(of: "&amp;", with: "&")
        s = s.replacingOccurrences(of: "&lt;", with: "<")
        s = s.replacingOccurrences(of: "&gt;", with: ">")
        s = s.replacingOccurrences(of: "&quot;", with: "\"")
        s = s.replacingOccurrences(of: "&#39;", with: "'")
        return s
    }

    private static func cellText(_ html: String, _ range: Range<String.Index>) -> String {
        let stripped = tagStripRegex.stringByReplacingMatches(
            in: html,
            range: NSRange(range, in: html),
            withTemplate: ""
        )
        return decodeEntities(stripped).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func isJunkSubject(_ subject: String) -> Bool {
        let s = subject.trimmingCharacters(in: .whitespaces)
        if s.isEmpty { return false }
        if s.contains("物联网采集") { return true }
        return junkDateSubjectRegex.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) != nil
    }

    private static func parseBillTable(_ html: String) -> [CardBill] {
        var out: [CardBill] = []
        for m in trRegex.matches(in: html, range: NSRange(html.startIndex..., in: html)) {
            guard let rowRange = Range(m.range, in: html) else { continue }
            let cells = tdRegex
                .matches(in: html, range: NSRange(rowRange, in: html))
                .compactMap { tm in Range(tm.range, in: html).map { cellText(html, $0) } }
            guard cells.count >= 5 else { continue }
            let timeText = cells[0]
            guard billDateRegex.firstMatch(in: timeText, range: NSRange(timeText.startIndex..., in: timeText)) != nil else {
                continue
            }
            let subject = cells[1]
            guard !isJunkSubject(subject) else { continue }
            var amount = parseMoney(cells[2])
            let station = cells.count > 7 ? cells[7] : (cells.count > 6 ? cells[6] : "")
            if abs(amount) < 0.005 && station.contains("物联网采集") { continue }
            let isRecharge = subject.contains("充值") || subject.contains("转账") || subject.contains("补助")
            if amount > 0 && !isRecharge { amount = -amount }
            if amount < 0 && isRecharge { amount = abs(amount) }
            let fee = parseMoney(cells[3])
            let balanceAfter = parseMoney(cells[4])
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
        findValue(value, keys: keys).flatMap { numberFrom($0).map { Int64($0) } }
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

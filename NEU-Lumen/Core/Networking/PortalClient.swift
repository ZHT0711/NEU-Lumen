import Foundation

/// 一号通门户 + 教务系统客户端：CAS 登录与全部业务接口。
/// 逻辑与 NEUPortal（Flutter 版）portal_client.dart 一致：
/// 手动重定向 + Cookie 罐，保证 CASTGC / SESS_ID 正确跨域传递。
final class PortalClient {
    static let portalBase = "https://personal.neu.edu.cn/portal"
    static let jwxtBase = "https://jwxt.neu.edu.cn"

    private let http = HTTPClient()

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
            throw NetworkError(message: "统一身份认证页加载失败，请检查网络或校园 VPN 后重试")
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
            if let raw = Self.firstMatch(Self.casErrorRegex, html) {
                let msg = raw
                    .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !msg.isEmpty && !msg.contains("null") {
                    if msg.contains("账号不存在") {
                        throw NetworkError(message: "账号不存在：若当前使用移动网络或在校外，学校统一认证会拦截公网直连鉴权（返回账号不存在）。请切换至校园网 WiFi，或先连接校园 WebVPN。")
                    }
                    throw NetworkError(message: msg)
                }
            }
            throw NetworkError(message: "账号或密码错误（如需二次短信验证，请先在网页端完成设备信任绑定）")
        }

        if post.finalURL.absoluteString.hasPrefix(Self.portalBase),
           let user = Self.extractUser(fromHTML: post.text) {
            return user
        }
        return try await fetchUserInfo()
    }

    /// 请求门户首页并解析 window.userInfoDSL。
    func fetchUserInfo() async throws -> PortalUser {
        let resp = try await http.get(URL(string: Self.portalBase)!)
        if resp.finalURL.host?.contains("pass.neu.edu.cn") == true
            || resp.finalURL.path.contains("/tpass/login") {
            throw NetworkError.sessionExpired()
        }
        guard let user = Self.extractUser(fromHTML: resp.text) else {
            throw NetworkError(message: "会话未能正常建立，请重新登录")
        }
        return user
    }

    // MARK: - 门户业务接口

    private func api(_ path: String, query: [URLQueryItem] = []) async throws -> [String: Any] {
        var comps = URLComponents(string: Self.portalBase + "/" + path)!
        if !query.isEmpty { comps.queryItems = query }
        let resp = try await http.get(comps.url!, xhr: true)
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

    /// 跟随重定向 SSO 进入教务系统（CASTGC 被 CAS 识别，建立 jwapp 会话）。
    /// 注意：教务的 302 会跳 http:// 明文地址（ATS 例外已在 Info.plist 放开），与 Flutter 版行为一致。
    private func jwxtSSO() async throws {
        _ = try await http.get(URL(string: Self.jwxtBase + "/")!)
    }

    private static let jwxtHeaders = ["Fetch-Api": "true"]

    /// jwapp JSON 接口：若被重定向回 CAS 登录页说明会话未建立，抛会话失效以触发静默重登。
    private func jwxtGet(_ urlString: String) async throws -> Any {
        let resp = try await http.get(URL(string: urlString)!, extraHeaders: Self.jwxtHeaders)
        if resp.finalURL.host?.contains("pass.neu.edu.cn") == true
            || resp.finalURL.path.contains("/tpass/login") {
            throw NetworkError.sessionExpired()
        }
        do {
            return try http.json(resp)
        } catch {
            throw NetworkError(message: "教务系统返回异常，请稍后重试")
        }
    }

    /// 全部学期的真实成绩（成绩可能为数字或五级制文本，如「良」）。
    func fetchJwxtGrades() async throws -> [GradeSemester] {
        try await jwxtSSO()
        let cal = try await jwxtGet("\(Self.jwxtBase)/jwapp/sys/homeapp/api/home/student/schoolCalendars.do")
        guard let calJ = cal as? [String: Any], calJ.str("code") == "0" else {
            throw NetworkError(message: "学期列表获取失败")
        }
        let terms = (calJ["datas"] as? [Any])?.compactMap { $0 as? [String: Any] } ?? []
        var out: [GradeSemester] = []
        out.reserveCapacity(terms.count)
        for t in terms {
            let code = t.str("itemCode").trimmingCharacters(in: .whitespaces)
            let name0 = t.str("itemName").trimmingCharacters(in: .whitespaces)
            let name = name0.isEmpty ? code : name0
            if code.isEmpty { continue }
            let raw = try await jwxtGet("\(Self.jwxtBase)/jwapp/sys/homeapp/api/home/student/scores.do?termCode=\(code.urlFormEncoded)")
            guard let jJ = raw as? [String: Any], jJ.str("code") == "0" else { continue }
            let list = (jJ["datas"] as? [Any])?.compactMap { $0 as? [String: Any] } ?? []
            let courses = list.compactMap { c -> GradeCourse? in
                let courseName = c.str("courseName")
                guard !courseName.isEmpty else { return nil }
                let scoreRawText = c.str("score").trimmingCharacters(in: .whitespaces)
                let scoreNum = Double(scoreRawText)
                return GradeCourse(
                    name: courseName,
                    credit: c.dbl("credit") ?? 0,
                    category: c.str("courseType"),
                    score: scoreNum,
                    scoreRaw: scoreNum == nil ? scoreRawText : ""
                )
            }
            out.append(GradeSemester(name: name, termCode: code, current: t.bool("selected") == true, courses: courses))
        }
        if out.isEmpty {
            throw NetworkError(message: "未获取到成绩数据")
        }
        return out
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
                        return PortalUser.fromInfoJson(obj)
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

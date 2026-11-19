import Foundation
import WebKit
import CryptoKit
import JavaScriptCore

/// Public learning platforms share only the current browser's account-scoped cookie jar.
/// Native requests allow the platform's course and homework subdomains to communicate.
@MainActor
final class LearningWebReader {
    private static let moocHome = URL(string: "https://www.icourse163.org/home.htm")!
    private static let courseListMethod = "learnerCourseRpcBean.getMyLearnedCoursePanelList.rpc"
    // The platform's web client uses these to detect an existing session. The
    // anonymous CSRF cookie does not establish one on its own.
    private static let moocSessionNames: Set<String> = ["STUDY_INFO", "STUDY_SESS", "NTES_SESS"]
    private let http: HTTPClient
    private let webView: WKWebView?
    private lazy var moocJavaScript = JSContext()
    private lazy var moocCourseParser = moocJavaScript?.evaluateScript("(function(html, responses, course) {\n\(MOOCScripts.readCourse)\n})")
    private lazy var moocAccountParser = moocJavaScript?.evaluateScript("(function(html) {\n\(MOOCScripts.readAccount)\n})")

    init(webView: WKWebView? = nil, configuration: URLSessionConfiguration = .ephemeral) {
        self.webView = webView
        self.http = HTTPClient(configuration: configuration)
    }

    var moocCookies: [HTTPCookie] {
        http.cookies.allCookies().filter(LearningPlatform.mooc.ownsCookie)
    }

    static func hasMOOCSessionCookie(in cookies: [HTTPCookie]) -> Bool {
        cookies.contains {
            guard moocSessionNames.contains($0.name), !$0.value.isEmpty,
                  $0.expiresDate.map({ $0 > Date() }) ?? true,
                  let origin = cookieOrigin($0) else { return false }
            return LearningPlatform.mooc.accepts(origin)
        }
    }

    func readMOOC(cookies: [HTTPCookie], userAgent: String?, previous: LearningAssignmentReport? = nil) async throws -> LearningAssignmentReport {
        try Task.checkCancellation()
        http.cookies.replace(cookies, matching: LearningPlatform.mooc.ownsCookie)
        http.userAgentOverride = userAgent
        let savedCookies = moocCookies
        let identity = cookieSignature(savedCookies, platform: .mooc)
        guard !identity.isEmpty else { throw MOOCReadError.authenticationRequired }
        // Preserve existing cached keys while using fresh server evidence below.
        let legacyIdentity = cookieSignature(savedCookies.filter { $0.name == "NTESSTUDYSI" }, platform: .mooc)
        let key = accountKey(legacyIdentity.isEmpty ? identity : legacyIdentity)
        let known = previous?.accountKey == key ? previous?.courses ?? [] : []
        var report = try await readMOOCCourses(known: known)
        try Task.checkCancellation()
        report.accountKey = key
        return report
    }

    func read(_ platform: LearningPlatform, previous: LearningAssignmentReport? = nil) async throws -> LearningAssignmentReport {
        guard let webView else { throw NetworkError(message: "请从学习平台网页同步") }
        let store = webView.configuration.websiteDataStore.httpCookieStore
        let cookies = await store.allCookies()
        let identity = cookieSignature(cookies, platform: platform)
        var report: LearningAssignmentReport
        switch platform {
        case .mooc:
            report = try await readMOOC(cookies: cookies, userAgent: webView.customUserAgent, previous: previous)
        case .chaoxing:
            http.cookies.replace(cookies, matching: platform.ownsCookie)
            http.userAgentOverride = webView.customUserAgent
            report = try await readChaoxing(in: webView)
            report.accountKey = accountKey(identity)
        case .cg: throw NetworkError(message: "请通过 CG 实验平台同步")
        }
        let currentCookies = await store.allCookies()
        guard cookieSignature(currentCookies, platform: platform) == identity, !Task.isCancelled else { throw CancellationError() }
        let existing = Set(currentCookies.map(SavedWebSession.Cookie.init))
        for cookie in http.cookies.allCookies() where platform.ownsCookie(cookie) {
            guard !existing.contains(SavedWebSession.Cookie(cookie)) else { continue }
            if let origin = Self.cookieOrigin(cookie), platform.accepts(origin) {
                await store.setCookie(cookie)
            }
        }
        return report
    }

    private static func cookieOrigin(_ cookie: HTTPCookie) -> URL? {
        URL(string: "https://" + cookie.domain.trimmingCharacters(in: CharacterSet(charactersIn: ".")))
    }

    private func cookieSignature(_ cookies: [HTTPCookie], platform: LearningPlatform) -> String {
        // Compare all scoped MOOC cookies before writing responses back to WebKit.
        cookies.filter {
            guard let origin = Self.cookieOrigin($0), platform.accepts(origin) else { return false }
            return platform == .mooc || ["_uid", "UID"].contains($0.name)
        }.map { "\($0.domain)|\($0.path)|\($0.name)=\($0.value)" }.sorted().joined(separator: "|")
    }

    private func accountKey(_ identity: String) -> String {
        SHA256.hash(data: Data(identity.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private func get(_ url: URL) async throws -> HTTPClient.RawResponse {
        try Task.checkCancellation()
        let response = try await http.get(url)
        guard (200..<300).contains(response.status) else { throw NetworkError(message: "平台返回 HTTP \(response.status)") }
        return response
    }

    private func queryURL(_ base: String, _ fields: [String: String]) -> URL {
        var components = URLComponents(string: base)!
        components.queryItems = fields.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        return components.url!
    }

    private func readMOOCCourses(known: [LearningCourse]) async throws -> LearningAssignmentReport {
        var home: HTTPClient.RawResponse?
        if moocCSRF(at: moocRPCURL(Self.courseListMethod)) == nil {
            home = try await get(Self.moocHome)
        }
        let discovery = try await discoverMOOCCourses()
        var warnings = discovery.warnings
        var courses = discovery.courses
        if courses.isEmpty {
            if discovery.authenticationFailures == 2 { throw MOOCReadError.authenticationRequired }
            let confirmed = try await confirmMOOCAccount(home: home, allowHomeRequest: discovery.readEmptyPage)
            guard confirmed else {
                throw NetworkError(message: warnings.isEmpty
                    ? "慕课未返回可核对的账号或课程，已保留上次同步"
                    : warnings.joined(separator: "\n"))
            }
        }
        for index in courses.indices {
            courses[index].activeTermID = known.first { $0.key == courses[index].key }?.activeTermID
        }
        if let webView, let url = webView.url, LearningPlatform.mooc.accepts(url),
           let rows = try? await webView.callAsyncJavaScript(MOOCScripts.discover, arguments: [:], in: nil, contentWorld: .page) as? [[String: String]] {
            try Task.checkCancellation()
            for row in rows {
                guard let id = row["id"], let term = row["termID"], let link = row["url"],
                      let url = URL(string: link), LearningPlatform.mooc.accepts(url) else { continue }
                let course = LearningCourse(id: id, termID: term, title: row["title"] ?? id, url: url, activeTermID: row["activeTermID"])
                if let index = courses.firstIndex(where: { $0.key == course.key }) {
                    courses[index].activeTermID = course.activeTermID ?? courses[index].activeTermID
                } else { courses.append(course) }
            }
        }
        if !warnings.isEmpty {
            if let webView, let url = webView.url, LearningPlatform.mooc.accepts(url), url.path == "/home.htm" {
                do {
                    let cards = try await MOOCCourseNavigator(source: webView).discover()
                    for course in cards where !courses.contains(where: { $0.key == course.key }) { courses.append(course) }
                } catch {
                    if NetworkError.isCancellation(error) { throw error }
                    warnings.append(NetworkError.from(error).message)
                }
            }
            for course in known where !courses.contains(where: { $0.key == course.key }) { courses.append(course) }
        }
        guard !courses.isEmpty else {
            if !warnings.isEmpty { throw NetworkError(message: warnings.joined(separator: "\n")) }
            return LearningAssignmentReport(courses: [], assignments: [], warnings: [], refreshedCourseKeys: [])
        }
        var report = LearningAssignmentReport(courses: courses, assignments: [], warnings: warnings, refreshedCourseKeys: [])
        // Bound in-flight courses while preserving course order and partial-sync recovery.
        try await withThrowingTaskGroup(of: (Int, LearningAssignmentReport).self) { group in
            var next = 0
            func enqueue() {
                let index = next
                let course = courses[index]
                next += 1
                group.addTask { @MainActor in
                    (index, try await self.readMOOCCourse(course))
                }
            }
            for _ in 0..<min(3, courses.count) { enqueue() }
            var results: [Int: LearningAssignmentReport] = [:]
            while let (index, result) = try await group.next() {
                results[index] = result
                if next < courses.count { enqueue() }
            }
            for index in courses.indices {
                guard let result = results[index] else { continue }
                report.courses[index] = result.courses[0]
                report.assignments += result.assignments
                report.refreshedCourseKeys.formUnion(result.refreshedCourseKeys)
                report.warnings += result.warnings
            }
        }
        if report.refreshedCourseKeys.isEmpty { throw NetworkError(message: report.warnings.joined(separator: "\n")) }
        return report
    }

    private func readMOOCCourse(_ course: LearningCourse) async throws -> LearningAssignmentReport {
        var course = course
        var result = LearningAssignmentReport(courses: [course], assignments: [], warnings: [], refreshedCourseKeys: [])
        do {
            try Task.checkCancellation()
            var html = ""
            if course.url.path.contains("/spoc/"), course.activeTermID == nil {
                let page = try await get(course.url)
                guard LearningPlatform.mooc.accepts(page.finalURL) else { throw NetworkError(message: "慕课课程跳转到其它页面") }
                html = page.text
                let metadata = try parseMOOC(course, html: html, responses: [])
                if let active = metadata["activeTermID"] as? String, !active.isEmpty { course.activeTermID = active }
            }
            let responses = try await termResponses(course.activeTermID ?? course.termID, referer: course.url)
            var parsed = try parseMOOC(course, html: html, responses: responses)
            if parsed["recognized"] as? Bool != true {
                var target = URLComponents(url: course.url, resolvingAgainstBaseURL: false)!
                if !course.url.path.contains("/spoc/"), target.path.range(of: #"/learn/[^/]+/"#, options: .regularExpression) != nil {
                    target.path = target.path.replacingOccurrences(of: #"(/learn/[^/]+)/.*"#, with: "$1/assessments", options: .regularExpression)
                }
                target.fragment = "/learn/testlist"
                let page = try await get(target.url!)
                guard LearningPlatform.mooc.accepts(page.finalURL) else { throw NetworkError(message: "慕课课程跳转到其它页面") }
                let resolved = LearningCourse(id: course.id, termID: course.termID, title: course.title, url: page.finalURL)
                parsed = try parseMOOC(resolved, html: page.text, responses: responses)
            }
            guard parsed["recognized"] as? Bool == true else {
                throw NetworkError(message: "未读取到课程的测验与作业列表")
            }
            result.courses = [course]
            result.assignments = try LearningAssignmentReport.decodeRows(parsed["assignments"] ?? [], platform: .mooc)
            result.refreshedCourseKeys.insert(course.key)
        } catch {
            if NetworkError.isCancellation(error) { throw error }
            result.warnings.append("\(course.title) · \(NetworkError.from(error).message)")
        }
        return result
    }

    private func confirmMOOCAccount(home initial: HTTPClient.RawResponse?, allowHomeRequest: Bool) async throws -> Bool {
        if let webView, let url = webView.url, LearningPlatform.mooc.accepts(url),
           let id = try? await webView.evaluateJavaScript("String(window.webUser?.id ?? '')") as? String,
           Self.validMOOCAccountID(id) {
            return true
        }
        try Task.checkCancellation()
        guard initial != nil || allowHomeRequest else { return false }
        let home: HTTPClient.RawResponse
        if let initial { home = initial }
        else { home = try await get(Self.moocHome) }
        guard home.finalURL.scheme == "https", LearningPlatform.mooc.accepts(home.finalURL),
              home.finalURL.path == Self.moocHome.path else { return false }
        let id = moocAccountParser?.call(withArguments: [home.text])?.toString()
        return Self.validMOOCAccountID(id)
    }

    private static func validMOOCAccountID(_ id: String?) -> Bool {
        id?.range(of: #"^[1-9]\d{0,19}$"#, options: .regularExpression) != nil
    }

    private func moocRPCURL(_ method: String) -> URL {
        URL(string: "/web/j/" + method, relativeTo: Self.moocHome)!.absoluteURL
    }

    private func moocCSRF(at url: URL) -> String? {
        let prefix = "NTESSTUDYSI="
        guard let field = http.cookies.headerFor(url)?.components(separatedBy: "; ")
            .first(where: { $0.hasPrefix(prefix) }), field.count > prefix.count else { return nil }
        return String(field.dropFirst(prefix.count))
    }

    private func moocRPC(_ method: String, fields: [String: String], referer: URL) async throws -> HTTPClient.RawResponse {
        let target = moocRPCURL(method)
        guard let csrf = moocCSRF(at: target) else {
            throw NetworkError(message: "慕课未返回接口校验凭据，已保留上次同步")
        }
        var components = URLComponents(url: target, resolvingAgainstBaseURL: false)!
        components.percentEncodedQuery = "csrfKey=" + csrf.urlFormEncoded
        let response = try await http.postForm(components.url!, fields: fields, extraHeaders: [
            "Content-Type": "application/x-www-form-urlencoded",
            "Referer": referer.absoluteString,
            "Origin": "https://www.icourse163.org",
            "X-Requested-With": "XMLHttpRequest"
        ], allowPostRedirects: false)
        if response.status == 401 { throw MOOCReadError.authenticationRequired }
        if response.status == 415 { throw MOOCReadError.unsupportedContentType }
        guard response.status == 200 else { throw NetworkError(message: "慕课课程接口返回 HTTP \(response.status)") }
        guard LearningPlatform.mooc.accepts(response.finalURL), response.finalURL.path == target.path else {
            throw MOOCReadError.invalidCourseList
        }
        return response
    }

    private func discoverMOOCCourses() async throws -> (courses: [LearningCourse], warnings: [String], authenticationFailures: Int, readEmptyPage: Bool) {
        var courses: [LearningCourse] = []
        var warnings: [String] = []
        var authenticationFailures = 0
        var readEmptyPage = false
        for type in [1, 2] {
            do {
                for page in 1...20 {
                    try Task.checkCancellation()
                    let response = try await moocRPC(Self.courseListMethod,
                        fields: ["type": "30", "p": String(page), "psize": "50", "courseType": String(type)], referer: Self.moocHome)
                    let result = try MOOCCoursePage.decode(response.body, page: page, pageSize: 50, courseType: type)
                    readEmptyPage = readEmptyPage || result.requiresAccountConfirmation
                    for course in result.courses where !courses.contains(where: { $0.key == course.key }) { courses.append(course) }
                    if !result.hasMore { break }
                    if page == 20 { throw NetworkError(message: "课程列表超过 20 页，尚未取全") }
                }
            } catch {
                if NetworkError.isCancellation(error) { throw error }
                if (error as? MOOCReadError) == .authenticationRequired { authenticationFailures += 1 }
                warnings.append("\(type == 1 ? "普通课程" : "学校 SPOC")列表未取全 · \(NetworkError.from(error).message)")
            }
        }
        return (courses, warnings, authenticationFailures, readEmptyPage)
    }

    private func termResponses(_ term: String, referer: URL) async throws -> [[String: String]] {
        let methods = ["courseBean.getLastLearnedMocTermDto.rpc", "courseBean.getMocTermDto.rpc"]
        var responses: [[String: String]] = []
        var authenticationError: MOOCReadError?
        for method in methods {
            do {
                var fields = ["termId": term]
                if method == "courseBean.getMocTermDto.rpc" { fields["gatewayType"] = "3" }
                let response = try await moocRPC(method, fields: fields, referer: referer)
                if response.text.contains("chapters") {
                    responses.append(["raw": response.text, "termID": term])
                }
            } catch {
                if NetworkError.isCancellation(error) { throw error }
                if (error as? MOOCReadError) == .authenticationRequired { authenticationError = .authenticationRequired }
            }
        }
        if responses.isEmpty, let authenticationError { throw authenticationError }
        return responses
    }

    private func parseMOOC(_ course: LearningCourse, html: String, responses: [[String: String]]) throws -> [String: Any] {
        var target = URLComponents(url: course.url, resolvingAgainstBaseURL: false)!
        let pagePath = target.path
        if pagePath.range(of: #"/learn/[^/]+/"#, options: .regularExpression) != nil {
            target.path = pagePath.replacingOccurrences(of: #"(/learn/[^/]+)/.*"#, with: "$1/assessments", options: .regularExpression)
            target.fragment = nil
        } else {
            target.fragment = "/learn/testlist"
        }
        let data = [
            "id": course.id, "termID": course.termID, "title": course.title, "url": course.url.absoluteString,
            "path": pagePath, "assignmentURL": target.url!.absoluteString
        ]
        guard let parsed = moocCourseParser?.call(withArguments: [html, responses, data])?.toDictionary() as? [String: Any] else {
            throw NetworkError(message: "慕课作业解析失败，已保留上次同步")
        }
        return parsed
    }

    private func readChaoxing(in webView: WKWebView) async throws -> LearningAssignmentReport {
        let response = try await get(URL(string: "https://mooc1-api.chaoxing.com/mycourse/backclazzdata?view=json&rss=1")!)
        guard let payload = try JSONSerialization.jsonObject(with: response.body) as? [String: Any],
              let channels = payload["channelList"] as? [[String: Any]] else {
            throw NetworkError(message: "请在学习通网页登录后再同步作业")
        }
        var report = LearningAssignmentReport(courses: [], assignments: [], warnings: [], refreshedCourseKeys: [])
        for channel in channels {
            guard let content = channel["content"] as? [String: Any],
                  let clazz = numericID(content["id"]), let cpi = numericID(content["cpi"]),
                  let group = content["course"] as? [String: Any], let courses = group["data"] as? [[String: Any]] else { continue }
            for item in courses {
                guard let id = numericID(item["id"]) else { continue }
                let entry = queryURL("https://mooc1.chaoxing.com/visit/stucoursemiddle",
                    ["courseid": id, "clazzid": clazz, "cpi": cpi, "ismooc2": "1", "v": "2"])
                var course = LearningCourse(id: id, termID: clazz, title: item["name"] as? String ?? "课程 \(id)", url: entry,
                    deadline: LearningCourseProgress.chaoxingDeadline(content["endDate"]))
                async let landingResponse = get(entry)
                do {
                    let fields = "id,course.fields(id,knowledge.fields(id,parentnodeid,layer,finishcount,unfinishcount,jobcount).type(video))"
                    let progressURL = queryURL("https://mooc1-api.chaoxing.com/gas/clazz",
                        ["id": clazz, "personid": cpi, "fields": fields, "view": "json"])
                    let response = try await get(progressURL)
                    course.progress = try LearningCourseProgress.chaoxing(JSONSerialization.jsonObject(with: response.body), courseID: id)
                } catch {
                    if NetworkError.isCancellation(error) { throw error }
                    course.progressWarning = "课程进度未读取 · " + NetworkError.from(error).message
                }
                report.courses.append(course)
                do {
                    let landing = try await landingResponse
                    let inputs = HTMLInputFields.parse(landing.text)
                    guard let enc = inputs.first(where: { $0["id"] == "workEnc" || $0["name"] == "workEnc" })?["value"], !enc.isEmpty else {
                        throw NetworkError(message: "课程作业入口未就绪，请在网页打开该课程后重试")
                    }
                    var page = 1
                    var lastPage = 1
                    var courseRows: [LearningAssignment] = []
                    repeat {
                        try Task.checkCancellation()
                        let listURL = queryURL("https://mooc1.chaoxing.com/mooc-ans/mooc2/work/list",
                            ["courseId": id, "classId": clazz, "cpi": cpi, "enc": enc, "pageNum": String(page)])
                        let list = try await get(listURL)
                        let raw = try await webView.callAsyncJavaScript(ChaoxingAssignments.pageScript,
                            arguments: ["html": list.text, "pageURL": list.finalURL.absoluteString,
                                "courseKey": course.key, "courseTitle": course.title], in: nil, contentWorld: .page)
                        guard let parsed = raw as? [String: Any], parsed["recognized"] as? Bool == true else {
                            throw NetworkError(message: "作业列表未能读取，请在网页完成认证后重试")
                        }
                        courseRows += try LearningAssignmentReport.decodeRows(parsed["assignments"] ?? [], platform: .chaoxing)
                        lastPage = max(lastPage, parsed["pages"] as? Int ?? 1)
                        if lastPage > 100 { throw NetworkError(message: "作业页数超过同步上限，请在网页查看") }
                        page += 1
                    } while page <= lastPage
                    report.assignments += courseRows
                    report.refreshedCourseKeys.insert(course.key)
                } catch {
                    if NetworkError.isCancellation(error) { throw error }
                    report.warnings.append("\(course.title) · \(NetworkError.from(error).message)")
                }
            }
        }
        guard !report.courses.isEmpty else { throw NetworkError(message: "学习通未返回课程，请确认登录的是已选课账号") }
        if report.refreshedCourseKeys.isEmpty && !report.courses.contains(where: { $0.progress != nil || $0.deadline != nil }) {
            throw NetworkError(message: report.warnings.joined(separator: "\n"))
        }
        return report
    }

    private func numericID(_ raw: Any?) -> String? {
        guard let raw else { return nil }
        let value = String(describing: raw)
        return value.range(of: #"^\d+$"#, options: .regularExpression) != nil ? value : nil
    }
}

@MainActor
private final class MOOCCourseNavigator: NSObject, WKUIDelegate {
    private let browser: WKWebView
    private let listURL: URL
    private static let cardsScript = #"""
    return [...document.querySelectorAll('#j-coursewrap a')].filter(el => {
      const href = el.getAttribute('href') || '';
      return (!href || href.startsWith('javascript:')) && el.querySelector('img[alt]');
    }).map((el, index) => ({index, title: el.querySelector('img[alt]').alt}));
    """#

    init(source: WKWebView) {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = source.configuration.websiteDataStore
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = true
        browser = WKWebView(frame: .zero, configuration: configuration)
        browser.customUserAgent = source.customUserAgent
        listURL = source.url!
        super.init()
        browser.uiDelegate = self
    }

    func discover() async throws -> [LearningCourse] {
        defer { browser.stopLoading() }
        var courses: [LearningCourse] = []
        let cards = try await loadList()
        for card in cards {
            try Task.checkCancellation()
            if !courses.isEmpty { _ = try await loadList() }
            guard let title = card["title"] as? String else { continue }
            _ = try await browser.callAsyncJavaScript(#"""
            const cards = [...document.querySelectorAll('#j-coursewrap a')].filter(el => {
              const href = el.getAttribute('href') || '';
              return (!href || href.startsWith('javascript:')) && el.querySelector('img[alt]');
            });
            const matching = cards.filter(el => el.querySelector('img[alt]')?.getAttribute('alt') === title);
            if (matching.length !== 1) throw new Error('课程卡片名称重复或已变化，请重新同步');
            matching[0].click();
            """#, arguments: ["title": title], in: nil, contentWorld: .page)
            var resolved: LearningCourse?
            for _ in 0..<75 {
                try Task.checkCancellation()
                if !browser.isLoading, let url = browser.url, LearningPlatform.mooc.accepts(url),
                   let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
                   let tid = components.queryItems?.first(where: { $0.name == "tid" })?.value,
                   let range = url.path.range(of: #"(?<=/learn/)[^/]+"#, options: .regularExpression) {
                    resolved = LearningCourse(id: String(url.path[range]), termID: tid, title: card["title"] as? String ?? "慕课课程", url: url)
                    break
                }
                try await Task.sleep(for: .milliseconds(200))
            }
            guard var resolved else { throw NetworkError(message: "慕课课程卡片未能打开，请在网页进入课程后同步") }
            if resolved.url.path.contains("/spoc/") {
                for _ in 0..<15 {
                    try Task.checkCancellation()
                    let active = try? await browser.evaluateJavaScript("String(window.moocTermDto?.id || window.termDto?.id || '')")
                    if let id = active as? String, !id.isEmpty { resolved.activeTermID = id; break }
                    try await Task.sleep(for: .milliseconds(200))
                }
            }
            courses.append(resolved)
        }
        return courses
    }

    private func loadList() async throws -> [[String: Any]] {
        browser.load(URLRequest(url: listURL))
        for _ in 0..<60 {
            try Task.checkCancellation()
            if !browser.isLoading, browser.url?.path == listURL.path,
               let raw = try? await browser.callAsyncJavaScript(Self.cardsScript, arguments: [:], in: nil, contentWorld: .page),
               let cards = raw as? [[String: Any]], !cards.isEmpty { return cards }
            try await Task.sleep(for: .milliseconds(200))
        }
        return []
    }

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for action: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if action.targetFrame == nil { webView.load(action.request) }
        return nil
    }
}

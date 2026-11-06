import Foundation
import WebKit
import CryptoKit

/// Public learning platforms share only the current browser's account-scoped cookie jar.
/// Native requests allow the platform's course and homework subdomains to communicate.
@MainActor
final class LearningWebReader {
    private let http: HTTPClient
    private let webView: WKWebView

    init(webView: WKWebView, configuration: URLSessionConfiguration = .ephemeral) {
        self.webView = webView
        self.http = HTTPClient(configuration: configuration)
    }

    func read(_ platform: LearningPlatform, previous: LearningAssignmentReport? = nil) async throws -> LearningAssignmentReport {
        http.cookies.absorb(await webView.configuration.websiteDataStore.httpCookieStore.allCookies())
        http.userAgentOverride = webView.customUserAgent
        let identityNames = platform == .mooc ? ["NTESSTUDYSI"] : ["_uid", "UID"]
        func signature(_ cookies: [HTTPCookie]) -> String {
            cookies.filter {
                identityNames.contains($0.name) && platform.accepts(URL(string: "https://" + $0.domain.trimmingCharacters(in: CharacterSet(charactersIn: ".")))!)
            }.sorted { $0.name < $1.name }.map { $0.name + "=" + $0.value }.joined(separator: "|")
        }
        let identity = signature(http.cookies.allCookies())
        let accountKey = SHA256.hash(data: Data(identity.utf8)).map { String(format: "%02x", $0) }.joined()
        var report: LearningAssignmentReport
        switch platform {
        case .mooc: report = try await readMOOC(known: previous?.accountKey == accountKey ? previous?.courses ?? [] : [])
        case .chaoxing: report = try await readChaoxing()
        case .cg: throw NetworkError(message: "请通过 CG 实验平台同步")
        }
        report.accountKey = accountKey
        let currentCookies = await webView.configuration.websiteDataStore.httpCookieStore.allCookies()
        guard signature(currentCookies) == identity, !Task.isCancelled else { throw CancellationError() }
        for cookie in http.cookies.allCookies() {
            if let origin = URL(string: "https://" + cookie.domain.trimmingCharacters(in: CharacterSet(charactersIn: "."))), platform.accepts(origin) {
                await webView.configuration.websiteDataStore.httpCookieStore.setCookie(cookie)
            }
        }
        return report
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

    private func readMOOC(known: [LearningCourse]) async throws -> LearningAssignmentReport {
        guard let csrf = http.cookies.allCookies().first(where: {
            $0.name == "NTESSTUDYSI" && LearningPlatform.mooc.accepts(URL(string: "https://" + $0.domain.trimmingCharacters(in: CharacterSet(charactersIn: ".")))!)
        })?.value, !csrf.isEmpty else {
            throw NetworkError(message: "请先打开慕课完成登录，再同步全部作业")
        }
        let discovery = try await discoverMOOCCourses(csrf: csrf)
        var courses = discovery.courses
        let raw = try await webView.callAsyncJavaScript(MOOCScripts.discover, arguments: [:], in: nil, contentWorld: .page)
        if let rows = raw as? [[String: String]] {
            for row in rows {
                guard let id = row["id"], let term = row["termID"], let link = row["url"],
                      let url = URL(string: link), LearningPlatform.mooc.accepts(url) else { continue }
                let course = LearningCourse(id: id, termID: term, title: row["title"] ?? id, url: url, activeTermID: row["activeTermID"])
                if let index = courses.firstIndex(where: { $0.key == course.key }) {
                    courses[index].activeTermID = course.activeTermID ?? courses[index].activeTermID
                } else { courses.append(course) }
            }
        }
        var warnings = discovery.warnings
        if !warnings.isEmpty {
            if webView.url?.path == "/home.htm" {
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
            throw NetworkError(message: warnings.isEmpty ? "慕课未返回已选课程，请确认登录账号" : warnings.joined(separator: "\n"))
        }
        var report = LearningAssignmentReport(courses: courses, assignments: [], warnings: warnings, refreshedCourseKeys: [])
        for course in courses {
            try Task.checkCancellation()
            do {
                let page = try await get(course.url)
                guard LearningPlatform.mooc.accepts(page.finalURL) else { throw NetworkError(message: "课程已跳转，请重新登录慕课") }
                let resolvedCourse = LearningCourse(id: course.id, termID: course.termID, title: course.title, url: page.finalURL, activeTermID: course.activeTermID)
                var html = page.text
                // The new shell may land on lessons. Read its assessment outline as well.
                if !resolvedCourse.url.path.contains("/spoc/"), resolvedCourse.url.path.range(of: #"/learn/[^/]+/"#, options: .regularExpression) != nil,
                   !resolvedCourse.url.path.hasSuffix("/assessments") {
                    var assessments = URLComponents(url: resolvedCourse.url, resolvingAgainstBaseURL: false)!
                    assessments.path = assessments.path.replacingOccurrences(of: #"(/learn/[^/]+)/.*"#, with: "$1/assessments", options: .regularExpression)
                    assessments.fragment = nil
                    do { html += try await get(assessments.url!).text }
                    catch {
                        if NetworkError.isCancellation(error) { throw error }
                        report.warnings.append("\(course.title)的作业与测验列表未读取")
                    }
                }
                var responses = try await termResponses(course.termID, csrf: csrf, referer: course.url)
                var parsed = try await parseMOOC(resolvedCourse, html: html, responses: responses)
                if let active = course.activeTermID ?? parsed["activeTermID"] as? String, !active.isEmpty, active != course.termID {
                    responses += try await termResponses(active, csrf: csrf, referer: course.url)
                    parsed = try await parseMOOC(resolvedCourse, html: html, responses: responses)
                }
                guard parsed["recognized"] as? Bool == true else {
                    throw NetworkError(message: "未读取到课程大纲，请打开课程完成登录后重试")
                }
                report.assignments += try LearningAssignmentReport.decodeRows(parsed["assignments"] ?? [], platform: .mooc)
                report.refreshedCourseKeys.insert(course.key)
            } catch {
                if NetworkError.isCancellation(error) { throw error }
                report.warnings.append("\(course.title) · \(NetworkError.from(error).message)")
            }
        }
        if report.refreshedCourseKeys.isEmpty { throw NetworkError(message: report.warnings.joined(separator: "\n")) }
        return report
    }

    private func discoverMOOCCourses(csrf: String) async throws -> (courses: [LearningCourse], warnings: [String]) {
        var courses: [LearningCourse] = []
        var warnings: [String] = []
        for type in [1, 2] {
            do {
                for page in 1...20 {
                    try Task.checkCancellation()
                    var request = URLRequest(url: queryURL("https://www.icourse163.org/web/j/learnerCourseRpcBean.getMyLearnedCoursePanelList.rpc", ["csrfKey": csrf]))
                    request.httpMethod = "POST"
                    request.setValue("https://www.icourse163.org/home.htm", forHTTPHeaderField: "Referer")
                    request.setValue("application/json;charset=UTF-8", forHTTPHeaderField: "Content-Type")
                    request.httpBody = try JSONSerialization.data(withJSONObject: ["type": 30, "p": page, "psize": 50, "courseType": type])
                    let response = try await http.send(request)
                    guard response.status == 200 else { throw NetworkError(message: "课程列表返回 HTTP \(response.status)") }
                    let result = try MOOCCoursePage.decode(response.body, page: page, pageSize: 50, courseType: type)
                    for course in result.courses where !courses.contains(where: { $0.key == course.key }) { courses.append(course) }
                    if !result.hasMore { break }
                    if page == 20 { throw NetworkError(message: "课程列表超过 20 页，尚未取全") }
                    try await Task.sleep(for: .milliseconds(250))
                }
            } catch {
                if NetworkError.isCancellation(error) { throw error }
                warnings.append("\(type == 1 ? "普通课程" : "学校 SPOC")列表未取全 · \(NetworkError.from(error).message)")
            }
        }
        return (courses, warnings)
    }

    private func termResponses(_ term: String, csrf: String, referer: URL) async throws -> [[String: String]] {
        let methods = ["courseBean.getLastLearnedMocTermDto.rpc", "courseBean.getMocTermDto.rpc"]
        var responses: [[String: String]] = []
        for method in methods {
            do {
                var request = URLRequest(url: queryURL("https://www.icourse163.org/web/j/" + method, ["csrfKey": csrf]))
                request.httpMethod = "POST"
                request.setValue(referer.absoluteString, forHTTPHeaderField: "Referer")
                if method.contains("LastLearned") {
                    request.setValue("application/json;charset=UTF-8", forHTTPHeaderField: "Content-Type")
                    request.httpBody = try JSONSerialization.data(withJSONObject: ["termId": Int64(term) ?? 0])
                } else {
                    request.setValue("application/x-www-form-urlencoded;charset=UTF-8", forHTTPHeaderField: "Content-Type")
                    request.httpBody = Data("termId=\(term.urlFormEncoded)&gatewayType=3".utf8)
                }
                let response = try await http.send(request)
                if response.status == 200, response.text.contains("chapters") {
                    responses.append(["raw": response.text, "termID": term])
                }
            } catch { if NetworkError.isCancellation(error) { throw error } }
        }
        return responses
    }

    private func parseMOOC(_ course: LearningCourse, html: String, responses: [[String: String]]) async throws -> [String: Any] {
        let raw = try await webView.callAsyncJavaScript(MOOCScripts.readCourse,
            arguments: ["html": html, "responses": responses,
                "course": ["id": course.id, "termID": course.termID, "title": course.title, "url": course.url.absoluteString]],
            in: nil, contentWorld: .page)
        return raw as? [String: Any] ?? [:]
    }

    private func readChaoxing() async throws -> LearningAssignmentReport {
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
                    let landing = try await get(entry)
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
                        try await Task.sleep(for: .milliseconds(500))
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

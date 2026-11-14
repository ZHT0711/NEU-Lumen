import Foundation

/// 门户 HTTP 客户端底层：单个 URLSession 复用连接，
/// 阻断自动重定向后在代码里逐跳跟随，吸收每一跳的 Set-Cookie。
final class HTTPClient {
    static let timeout: TimeInterval = 15
    static let userAgent =
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) "
            + "Chrome/122.0.0.0 Safari/537.36"

    struct RawResponse {
        let status: Int
        let headers: [AnyHashable: Any]
        let body: Data
        let finalURL: URL

        var text: String {
            String(data: body, encoding: .utf8) ?? String(decoding: body, as: UTF8.self)
        }
    }

    private var session: URLSession
    private let configuration: URLSessionConfiguration
    private let transportLock = NSLock()
    private var transportRevision = UUID()
    private var networkRevision = UUID()
    let cookies = CookieJar()

    /// 重定向目标改写钩子：WebVPN 模式下把校内主机 Location 改写为网关地址。
    /// 返回 nil 表示不改写。
    var redirectRewriter: ((URL) -> URL?)?
    var userAgentOverride: String?

    init(configuration: URLSessionConfiguration = .ephemeral) {
        let config = configuration
        config.httpShouldSetCookies = false
        config.timeoutIntervalForRequest = Self.timeout
        config.timeoutIntervalForResource = 60
        config.urlCache = nil
        config.allowsCellularAccess = true
        config.allowsExpensiveNetworkAccess = true
        config.allowsConstrainedNetworkAccess = true
        config.waitsForConnectivity = false
        self.configuration = config.copy() as! URLSessionConfiguration
        session = URLSession(configuration: config, delegate: RedirectSuppressor(), delegateQueue: nil)
    }

    private func transport() -> (session: URLSession, revision: UUID, network: UUID) {
        transportLock.lock(); defer { transportLock.unlock() }
        return (session, transportRevision, networkRevision)
    }
    func resetTransport(networkChanged: Bool = false) {
        let replacement = URLSession(configuration: configuration, delegate: RedirectSuppressor(), delegateQueue: nil)
        transportLock.lock()
        let previous = session
        session = replacement; transportRevision = UUID()
        if networkChanged { networkRevision = UUID() }
        transportLock.unlock()
        // Do not replay writes or erase cookies. New reads use a fresh connection pool/DNS path.
        if networkChanged {
            previous.getAllTasks { tasks in
                for task in tasks {
                    let method = (task.currentRequest?.httpMethod ?? task.originalRequest?.httpMethod ?? "GET").uppercased()
                    if ["GET", "HEAD"].contains(method) { task.cancel() }
                }
                previous.finishTasksAndInvalidate()
            }
        } else { previous.finishTasksAndInvalidate() }
    }

    /// 手动跟随重定向（最多 10 跳），每跳吸收 Set-Cookie。
    @discardableResult
    func send(_ request: URLRequest, maxHops: Int = 10, followRedirects: Bool = true, retryTransport: Bool = true) async throws -> RawResponse {
        let generation = cookies.generation
        let network = transport().network
        var current = request
        for _ in 0..<maxHops {
            guard generation == cookies.generation, !Task.isCancelled else { throw CancellationError() }
            guard network == transport().network else { throw URLError(.networkConnectionLost) }
            if current.value(forHTTPHeaderField: "User-Agent") == nil {
                current.setValue(userAgentOverride ?? Self.userAgent, forHTTPHeaderField: "User-Agent")
            }
            if current.value(forHTTPHeaderField: "Accept") == nil {
                current.setValue("application/json, text/html, */*", forHTTPHeaderField: "Accept")
            }
            if current.value(forHTTPHeaderField: "Accept-Language") == nil {
                current.setValue("zh-CN,zh;q=0.9,en;q=0.8", forHTTPHeaderField: "Accept-Language")
            }
            if let url = current.url, let cookie = cookies.headerFor(url) {
                current.setValue(cookie, forHTTPHeaderField: "Cookie")
            }

            var outcome: (Data, URLResponse)?
            for attempt in 0..<2 {
                let connection = transport()
                guard generation == cookies.generation, !Task.isCancelled else { throw CancellationError() }
                guard connection.network == network else { throw URLError(.networkConnectionLost) }
                if let url = current.url, let freshCookie = cookies.headerFor(url) { current.setValue(freshCookie, forHTTPHeaderField: "Cookie") }
                do { outcome = try await connection.session.data(for: current); break }
                catch {
                    guard generation == cookies.generation, !Task.isCancelled else { throw CancellationError() }
                    guard network == transport().network else { throw URLError(.networkConnectionLost) }
                    guard attempt == 0, retryTransport,
                          CampusTransportRetry.allows(method: current.httpMethod, error: error, userCancelled: Task.isCancelled,
                              connectionReplaced: connection.revision != transport().revision) else { throw error }
                    resetTransport()
                    try await Task.sleep(for: .milliseconds(350))
                }
            }
            guard generation == cookies.generation, !Task.isCancelled else { throw CancellationError() }
            guard network == transport().network else { throw URLError(.networkConnectionLost) }
            guard let (data, response) = outcome else { throw NetworkError(message: "网络请求未完成，请重试") }
            guard let http = response as? HTTPURLResponse else {
                throw NetworkError(message: "网络响应异常")
            }
            if let sc = http.allHeaderFields["Set-Cookie"] as? String,
               let origin = http.url ?? current.url {
                cookies.absorbRaw(origin, sc)
            }

            let status = http.statusCode
            if followRedirects, (300..<400).contains(status),
               let loc = http.allHeaderFields["Location"] as? String,
               let base = http.url ?? current.url,
               let resolved = URL(string: loc, relativeTo: base)?.absoluteURL {
                let next = redirectRewriter?(resolved) ?? resolved
                var nextReq = URLRequest(url: next, timeoutInterval: Self.timeout)
                let keepMethod = (status == 307 || status == 308) && current.httpMethod == "POST"
                if keepMethod {
                    nextReq.httpMethod = "POST"
                    nextReq.httpBody = current.httpBody
                    if let ct = current.value(forHTTPHeaderField: "Content-Type") {
                        nextReq.setValue(ct, forHTTPHeaderField: "Content-Type")
                    }
                } else {
                    nextReq.httpMethod = "GET"
                }
                // 同主机重定向保留接口语义；Cookie 总是根据目标重新计算。
                if next.host == current.url?.host {
                    for name in ["Accept", "X-Requested-With", "Fetch-Api", "Referer", "User-Agent"] {
                        if let value = current.value(forHTTPHeaderField: name) { nextReq.setValue(value, forHTTPHeaderField: name) }
                    }
                }
                current = nextReq
                continue
            }

            return RawResponse(
                status: status,
                headers: http.allHeaderFields,
                body: data,
                finalURL: http.url ?? current.url!
            )
        }
        throw NetworkError(message: "重定向次数过多")
    }

    func get(_ url: URL, xhr: Bool = false, extraHeaders: [String: String] = [:]) async throws -> RawResponse {
        var req = URLRequest(url: url, timeoutInterval: Self.timeout)
        if xhr {
            req.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
        }
        for (key, value) in extraHeaders {
            req.setValue(value, forHTTPHeaderField: key)
        }
        return try await send(req)
    }

    func postForm(_ url: URL, fields: [String: String], extraHeaders: [String: String] = [:]) async throws -> RawResponse {
        var req = URLRequest(url: url, timeoutInterval: Self.timeout)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded; charset=UTF-8", forHTTPHeaderField: "Content-Type")
        req.setValue(url.absoluteString, forHTTPHeaderField: "Referer")
        for (key, value) in extraHeaders { req.setValue(value, forHTTPHeaderField: key) }
        let body = fields
            .map { "\($0.key.urlFormEncoded)=\($0.value.urlFormEncoded)" }
            .joined(separator: "&")
        req.httpBody = Data(body.utf8)
        return try await send(req)
    }

    func json(_ response: RawResponse) throws -> Any {
        do {
            return try JSONSerialization.jsonObject(with: response.body, options: [.fragmentsAllowed])
        } catch {
            throw NetworkError(message: "接口返回格式异常")
        }
    }

    private final class RedirectSuppressor: NSObject, URLSessionTaskDelegate {
        func urlSession(
            _ session: URLSession,
            task: URLSessionTask,
            willPerformHTTPRedirection response: HTTPURLResponse,
            newRequest request: URLRequest,
            completionHandler: @escaping (URLRequest?) -> Void
        ) {
            completionHandler(nil)
        }
    }
}

extension String {
    /// x-www-form-urlencoded 编码（与 Dart Uri.encodeComponent 行为一致）。
    var urlFormEncoded: String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return addingPercentEncoding(withAllowedCharacters: allowed) ?? self
    }
}

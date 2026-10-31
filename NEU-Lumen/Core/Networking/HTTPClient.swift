import Foundation

/// 门户 HTTP 客户端底层：单个 URLSession 复用连接，
/// 阻断自动重定向后在代码里逐跳跟随，吸收每一跳的 Set-Cookie。
final class HTTPClient {
    static let timeout: TimeInterval = 15
    static let userAgent =
        "Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 (KHTML, like Gecko) "
            + "Chrome/126.0 Mobile Safari/537.36"

    struct RawResponse {
        let status: Int
        let headers: [AnyHashable: Any]
        let body: Data
        let finalURL: URL

        var text: String {
            String(data: body, encoding: .utf8) ?? String(decoding: body, as: UTF8.self)
        }
    }

    private let session: URLSession
    let cookies = CookieJar()

    init() {
        let config = URLSessionConfiguration.ephemeral
        config.httpShouldSetCookies = false
        config.timeoutIntervalForRequest = Self.timeout
        config.timeoutIntervalForResource = 60
        config.urlCache = nil
        session = URLSession(configuration: config, delegate: RedirectSuppressor(), delegateQueue: nil)
    }

    /// 手动跟随重定向（最多 10 跳），每跳吸收 Set-Cookie。
    @discardableResult
    func send(_ request: URLRequest, maxHops: Int = 10) async throws -> RawResponse {
        var current = request
        for _ in 0..<maxHops {
            if current.value(forHTTPHeaderField: "User-Agent") == nil {
                current.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
            }
            if current.value(forHTTPHeaderField: "Accept") == nil {
                current.setValue("application/json, text/html, */*", forHTTPHeaderField: "Accept")
            }
            if let url = current.url, let cookie = cookies.headerFor(url) {
                current.setValue(cookie, forHTTPHeaderField: "Cookie")
            }

            let (data, response) = try await session.data(for: current)
            guard let http = response as? HTTPURLResponse else {
                throw NetworkError(message: "网络响应异常")
            }
            if let sc = http.allHeaderFields["Set-Cookie"] as? String,
               let origin = http.url ?? current.url {
                cookies.absorbRaw(origin, sc)
            }

            let status = http.statusCode
            if (300..<400).contains(status),
               let loc = http.allHeaderFields["Location"] as? String,
               let base = http.url ?? current.url,
               let next = URL(string: loc, relativeTo: base)?.absoluteURL {
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

    func postForm(_ url: URL, fields: [String: String]) async throws -> RawResponse {
        var req = URLRequest(url: url, timeoutInterval: Self.timeout)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded; charset=UTF-8", forHTTPHeaderField: "Content-Type")
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

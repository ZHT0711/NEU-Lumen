import Foundation

/// 保留 Cookie 的域、路径、Secure 与有效期，HTTP 与 WebKit 共用会话。
final class CookieJar {
    private struct Entry {
        let cookie: HTTPCookie
        let hostOnly: Bool
    }
    private var store: [String: Entry] = [:]
    private let lock = NSLock()

    private func locked<T>(_ work: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return work()
    }

    /// 只在逗号后确实开始 name=value 时拆分，不截断 Expires 中的日期。
    static func splitSetCookie(_ raw: String) -> [String] {
        let regex = try! NSRegularExpression(pattern: #",(?=\s*[^\s=;,]+\s*=)"#)
        let range = NSRange(raw.startIndex..., in: raw)
        var result: [String] = []
        var start = raw.startIndex
        for match in regex.matches(in: raw, range: range) {
            guard let comma = Range(match.range, in: raw) else { continue }
            result.append(String(raw[start..<comma.lowerBound]).trimmingCharacters(in: .whitespaces))
            start = comma.upperBound
        }
        result.append(String(raw[start...]).trimmingCharacters(in: .whitespaces))
        return result.filter { !$0.isEmpty }
    }

    private func key(_ cookie: HTTPCookie) -> String {
        "\(cookie.domain.lowercased())|\(cookie.path)|\(cookie.name)"
    }

    func absorbRaw(_ uri: URL, _ setCookie: String?) {
        guard let raw = setCookie else { return }
        for item in Self.splitSetCookie(raw) {
            let hostOnly = item.range(of: #";\s*domain\s*="#, options: [.regularExpression, .caseInsensitive]) == nil
            for cookie in HTTPCookie.cookies(withResponseHeaderFields: ["Set-Cookie": item], for: uri) {
                let domain = cookie.domain.trimmingCharacters(in: CharacterSet(charactersIn: ".")).lowercased()
                guard let host = uri.host?.lowercased(), host == domain || host.hasSuffix("." + domain) else { continue }
                save(cookie, hostOnly: hostOnly)
            }
        }
    }

    private func save(_ cookie: HTTPCookie, hostOnly: Bool) {
        locked {
            let id = key(cookie)
            if cookie.value.isEmpty || (cookie.expiresDate.map { $0 <= Date() } ?? false) {
                store[id] = nil
            } else {
                store[id] = Entry(cookie: cookie, hostOnly: hostOnly)
            }
        }
    }

    func absorb(_ cookies: [HTTPCookie]) {
        for cookie in cookies { save(cookie, hostOnly: !cookie.domain.hasPrefix(".")) }
    }

    func clear() { locked { store.removeAll() } }

    func allCookies() -> [HTTPCookie] {
        locked { store.values.map(\.cookie).filter { !($0.expiresDate.map { $0 <= Date() } ?? false) } }
    }

    func headerFor(_ uri: URL) -> String? {
        guard let host = uri.host?.lowercased() else { return nil }
        let path = uri.path.isEmpty ? "/" : uri.path
        let cookies: [HTTPCookie] = locked {
            var matching: [HTTPCookie] = []
            for entry in store.values {
                let cookie = entry.cookie
                let domain = cookie.domain.trimmingCharacters(in: CharacterSet(charactersIn: ".")).lowercased()
                guard host == domain || (!entry.hostOnly && host.hasSuffix("." + domain)) else { continue }
                let cookiePath = cookie.path
                let exactPath = path == cookiePath
                var descendantPath = false
                if path.hasPrefix(cookiePath) {
                    if cookiePath.hasSuffix("/") {
                        descendantPath = true
                    } else {
                        let remainder = path.dropFirst(cookiePath.count)
                        descendantPath = remainder.hasPrefix("/")
                    }
                }
                guard exactPath || descendantPath else { continue }
                if cookie.isSecure && uri.scheme != "https" { continue }
                if let expires = cookie.expiresDate, expires <= Date() { continue }
                matching.append(cookie)
            }
            return matching.sorted {
                $0.path.count == $1.path.count ? $0.name < $1.name : $0.path.count > $1.path.count
            }
        }
        return cookies.isEmpty ? nil : cookies.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
    }

    func hasCookie(_ uri: URL, _ name: String) -> Bool {
        headerFor(uri)?.components(separatedBy: "; ").contains { $0.hasPrefix(name + "=") } == true
    }

    func hasWebVPNTicket() -> Bool {
        allCookies().contains {
            let domain = $0.domain.trimmingCharacters(in: CharacterSet(charactersIn: "."))
            let name = $0.name.lowercased()
            return domain == "webvpn.neu.edu.cn" && (name.contains("wengine") || name.contains("vpn_ticket") || name.contains("webvpn"))
        }
    }

    func snapshot() -> [String: [String: String]] {
        var result: [String: [String: String]] = [:]
        for cookie in allCookies() { result[cookie.domain, default: [:]][cookie.name] = cookie.value }
        return result
    }
}

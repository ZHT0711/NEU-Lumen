import Foundation

/// RFC 风格 Cookie 罐：domain -> (name -> entry)。
/// 从 NEUPortal 的 Dart 实现移植，保证 CASTGC / SESS_ID 全程正确跨域传递。
struct CookieJar {
    private struct Entry {
        let value: String
        let path: String
        let expires: Date?
    }

    private var store: [String: [String: Entry]] = [:]

    /// 处理 Set-Cookie 头：同一个头里可能以逗号合并多条 Cookie，
    /// 需要跳过 expires= 值内部的逗号。
    static func splitSetCookie(_ raw: String) -> [String] {
        var result: [String] = []
        var start = raw.startIndex
        var inExpires = false
        var i = raw.startIndex
        while i < raw.endIndex {
            if raw.distance(from: raw.startIndex, to: i) >= 8 {
                let prev = raw.index(i, offsetBy: -8)
                if raw[prev..<i].lowercased() == "expires=" { inExpires = true }
            }
            if raw[i] == ";" { inExpires = false }
            if raw[i] == "," {
                if !inExpires {
                    let part = String(raw[start..<i]).trimmingCharacters(in: .whitespaces)
                    if !part.isEmpty { result.append(part) }
                    start = raw.index(after: i)
                }
            }
            i = raw.index(after: i)
        }
        let last = String(raw[start...]).trimmingCharacters(in: .whitespaces)
        if !last.isEmpty { result.append(last) }
        return result
    }

    mutating func absorbRaw(_ uri: URL, _ setCookie: String?) {
        guard let sc = setCookie, !sc.isEmpty else { return }
        for rawCookie in Self.splitSetCookie(sc) {
            let parts = rawCookie.split(separator: ";", omittingEmptySubsequences: false)
            guard let first = parts.first else { continue }
            let pair = first.trimmingCharacters(in: .whitespaces)
            guard let eq = pair.firstIndex(of: "="), eq != pair.startIndex else { continue }
            let name = String(pair[pair.startIndex..<eq]).trimmingCharacters(in: .whitespaces)
            let value = String(pair[pair.index(after: eq)...]).trimmingCharacters(in: .whitespaces)
            if name.isEmpty { continue }

            var domain = (uri.host ?? "").lowercased()
            var path = "/"
            var expires: Date?
            var expired = value.isEmpty

            for attrPart in parts.dropFirst() {
                let attr = attrPart.trimmingCharacters(in: .whitespaces)
                let attrEq = attr.firstIndex(of: "=")
                let attrName = attrEq.map { String(attr[attr.startIndex..<$0]).trimmingCharacters(in: .whitespaces).lowercased() }
                    ?? attr.lowercased()
                let attrVal = attrEq.map { String(attr[attr.index(after: $0)...]).trimmingCharacters(in: .whitespaces) } ?? ""
                switch attrName {
                case "domain" where !attrVal.isEmpty:
                    domain = attrVal.lowercased()
                    if domain.hasPrefix(".") { domain.removeFirst() }
                case "path" where !attrVal.isEmpty:
                    path = attrVal
                case "max-age":
                    if let sec = Int(attrVal) {
                        if sec <= 0 {
                            expired = true
                        } else {
                            expires = Date().addingTimeInterval(TimeInterval(sec))
                        }
                    }
                default:
                    break
                }
            }

            if expired {
                store[domain]?[name] = nil
            } else {
                store[domain, default: [:]][name] = Entry(value: value, path: path, expires: expires)
            }
        }
    }

    private func matchesDomain(host: String, domain: String) -> Bool {
        let h = host.lowercased()
        let d = domain.lowercased()
        return h == d || h.hasSuffix("." + d)
    }

    mutating func clear() { store.removeAll() }

    func headerFor(_ uri: URL) -> String? {
        guard let host = uri.host?.lowercased() else { return nil }
        let path = uri.path.isEmpty ? "/" : uri.path
        let now = Date()
        var pairs: [String] = []
        for (domain, cookies) in store where matchesDomain(host: host, domain: domain) {
            for (name, entry) in cookies {
                if let exp = entry.expires, now > exp { continue }
                if entry.path == "/" || path.hasPrefix(entry.path) {
                    pairs.append("\(name)=\(entry.value)")
                }
            }
        }
        return pairs.isEmpty ? nil : pairs.joined(separator: "; ")
    }

    func hasCookie(_ uri: URL, _ name: String) -> Bool {
        guard let host = uri.host?.lowercased() else { return false }
        for (domain, cookies) in store where matchesDomain(host: host, domain: domain) {
            if let entry = cookies[name], !(entry.expires.map { Date() > $0 } ?? false), !entry.value.isEmpty {
                return true
            }
        }
        return false
    }

    /// 供 WebView 注入的会话快照：domain -> {name: value}。
    func snapshot() -> [String: [String: String]] {
        var out: [String: [String: String]] = [:]
        let now = Date()
        for (domain, cookies) in store {
            var m: [String: String] = [:]
            for (name, entry) in cookies {
                if let exp = entry.expires, now > exp { continue }
                m[name] = entry.value
            }
            if !m.isEmpty {
                out[domain] = m
                out["." + domain] = m
            }
        }
        return out
    }
}

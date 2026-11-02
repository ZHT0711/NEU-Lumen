import CommonCrypto
import Foundation

/// 东北大学 WebVPN（Wengine 网关）URL 编码与判定。
///
/// 校外访问 `ecard` / `jwxt` 这类校园网专属主机时，把原 URL 编成
/// `https://webvpn.neu.edu.cn/http(s)/<hex(密钥)+AES-CFB密文主机>/<路径>`，由网关代访校内。
/// 编码算法：AES-128-CFB128，IV = 密钥本身，密文 hex 拼在密钥 hex 之后。
enum WebVPN {
    static let base = "https://webvpn.neu.edu.cn"
    /// 学校当前网关用的密钥（来自 WebVPN 前端，旧默认值 wrdvpnisthebest! 已弃用）。
    /// 会随学校前端更换，失效时按新版前端更新此处。
    static let key = Array("b0A58a69394ce73@".utf8)
    /// WebVPN 的 CAS 登录 service：用公网一号通的 CASTGC 直接换网关票据。
    static let casService = "https://webvpn.neu.edu.cn/login?cas_login=true"

    static func isWrapped(_ raw: String) -> Bool {
        guard let url = URL(string: raw), ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { return false }
        return url.host?.lowercased() == "webvpn.neu.edu.cn"
    }

    /// Native APIs with a known campus-only endpoint; auth and payment keep their own routes.
    static func isIntranet(_ raw: String) -> Bool {
        guard let host = URL(string: raw)?.host?.lowercased() else { return false }
        return ["ecard.neu.edu.cn", "jwxt.neu.edu.cn", "219.216.96.4"].contains(host)
    }

    /// Route the complete campus service catalog, including new subdomains and campus IP entries.
    /// Foreign sites, device-local URLs and non-web schemes retain their original destination.
    static func shouldProxyBrowserURL(_ url: URL) -> Bool {
        guard ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
              let host = url.host?.lowercased(), host != "webvpn.neu.edu.cn" else { return false }
        if host == "neu.edu.cn" || host.hasSuffix(".neu.edu.cn") { return true }
        let segments = host.split(separator: ".", omittingEmptySubsequences: false)
        let parts = segments.compactMap { Int($0) }
        guard segments.count == 4, parts.count == 4, parts.allSatisfy({ (0...255).contains($0) }) else { return false }
        return parts[0] == 10 || (parts[0] == 172 && (16...31).contains(parts[1])) ||
            (parts[0] == 192 && parts[1] == 168) ||
            (parts[0] == 219 && parts[1] == 216) || (parts[0] == 210 && parts[1] == 30)
    }

    /// Decode only the known CAS origin, so a native CAS session can serve gateway application redirects.
    static func publicCASURL(from url: URL) -> URL? {
        var result: URLComponents
        if url.host?.lowercased() == "pass.neu.edu.cn", url.path.hasPrefix("/tpass/") {
            guard let direct = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
            result = direct
        } else {
            guard isWrapped(url.absoluteString), let prefix = URL(string: wrap("https://pass.neu.edu.cn"))?.path,
                  url.path.hasPrefix(prefix + "/tpass/"),
                  let source = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
            result = URLComponents()
            result.scheme = "https"
            result.host = "pass.neu.edu.cn"
            result.percentEncodedPath = String(source.percentEncodedPath.dropFirst(prefix.count))
            result.percentEncodedQuery = source.percentEncodedQuery
            result.percentEncodedFragment = source.percentEncodedFragment
        }
        // CAS registers the original service, while the gateway may have rewritten the callback.
        if var items = result.queryItems {
            for index in items.indices where items[index].name == "service" {
                if let value = items[index].value, let service = URL(string: value), let original = unwrap(service) {
                    items[index].value = original.absoluteString
                }
            }
            result.queryItems = items
        }
        return result.url
    }

    /// Inverse of the gateway codec, used only to recover CAS service callbacks.
    static func unwrap(_ url: URL) -> URL? {
        guard isWrapped(url.absoluteString), let source = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        let segments = source.percentEncodedPath.split(separator: "/", omittingEmptySubsequences: true)
        guard segments.count >= 2 else { return nil }
        let proto = segments[0].split(separator: "-", omittingEmptySubsequences: false)
        guard proto.count <= 2, ["http", "https"].contains(String(proto[0])) else { return nil }
        var port: Int?
        if proto.count == 2 {
            guard let value = Int(proto[1]), (1...65535).contains(value) else { return nil }
            port = value
        }
        let encoded = String(segments[1])
        let keyHex = hexEncode(key)
        guard encoded.hasPrefix(keyHex), encoded.count > keyHex.count, encoded.count <= keyHex.count + 506 else { return nil }
        let hex = Array(encoded.dropFirst(keyHex.count))
        guard hex.count.isMultiple(of: 2) else { return nil }
        var cipher: [UInt8] = []
        for index in stride(from: 0, to: hex.count, by: 2) {
            guard let byte = UInt8(String(hex[index...index + 1]), radix: 16) else { return nil }
            cipher.append(byte)
        }
        var previous = key
        var plain: [UInt8] = []
        for offset in stride(from: 0, to: cipher.count, by: 16) {
            let chunk = Array(cipher[offset..<min(offset + 16, cipher.count)])
            let stream = aesEncryptBlock(previous)
            plain += chunk.enumerated().map { $0.element ^ stream[$0.offset] }
            if chunk.count == 16 { previous = chunk }
        }
        guard let host = String(bytes: plain, encoding: .utf8),
              host.range(of: #"^[a-zA-Z0-9.-]+$"#, options: .regularExpression) != nil else { return nil }
        var result = URLComponents()
        result.scheme = String(proto[0]); result.host = host; result.port = port
        let prefix = "/\(segments[0])/\(segments[1])"
        guard source.percentEncodedPath.hasPrefix(prefix) else { return nil }
        result.percentEncodedPath = String(source.percentEncodedPath.dropFirst(prefix.count))
        result.percentEncodedQuery = source.percentEncodedQuery
        result.percentEncodedFragment = source.percentEncodedFragment
        return result.url
    }

    /// Preserve ports, encoded paths, queries and SPA fragments without double-wrapping gateway URLs.
    static func wrap(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if isWrapped(trimmed) { return trimmed }
        let absolute = trimmed.hasPrefix("//") ? "http:" + trimmed :
            (trimmed.contains("://") ? trimmed : "http://" + trimmed)
        guard let source = URLComponents(string: absolute),
              let scheme = source.scheme?.lowercased(), ["http", "https"].contains(scheme),
              let host = source.host?.lowercased(), !host.isEmpty else { return raw }
        let proto = source.port.map { "\(scheme)-\($0)" } ?? scheme
        let query = source.percentEncodedQuery.map { "?" + $0 } ?? ""
        let fragment = source.percentEncodedFragment.map { "#" + $0 } ?? ""
        return "\(base)/\(proto)/\(encryptHost(host))\(source.percentEncodedPath)\(query)\(fragment)"
    }

    /// AES-128-CFB128（IV = key）加密主机名 → hex(密钥) + hex(密文)。
    static func encryptHost(_ host: String) -> String {
        let data = Array(host.utf8)
        var prev = key
        var out: [UInt8] = []
        out.reserveCapacity(data.count)
        var offset = 0
        while offset < data.count {
            let chunkLength = min(16, data.count - offset)
            let keystream = aesEncryptBlock(prev)
            var cipher = [UInt8](repeating: 0, count: chunkLength)
            for j in 0..<chunkLength {
                cipher[j] = data[offset + j] ^ keystream[j]
            }
            if chunkLength == 16 { prev = cipher }
            out.append(contentsOf: cipher)
            offset += chunkLength
        }
        return hexEncode(key) + hexEncode(out)
    }

    /// 单块 AES-ECB 加密，用作 CFB keystream（CommonCrypto 不直接暴露 CFB）。
    private static func aesEncryptBlock(_ block: [UInt8]) -> [UInt8] {
        var input = block
        var output = [UInt8](repeating: 0, count: 16)
        var outputLength = 0
        let status = CCCrypt(
            CCOperation(kCCEncrypt),
            CCAlgorithm(kCCAlgorithmAES),
            CCOptions(kCCOptionECBMode),
            key, key.count,
            nil,
            &input, input.count,
            &output, output.count,
            &outputLength
        )
        if status != kCCSuccess {
            // 密钥长度固定 16 字节，正常不会走到这里
            return [UInt8](repeating: 0, count: 16)
        }
        return output
    }

    static func hexEncode(_ bytes: [UInt8]) -> String {
        bytes.map { String(format: "%02x", $0) }.joined()
    }
}

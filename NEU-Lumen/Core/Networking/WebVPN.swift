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

    static func isWrapped(_ url: String) -> Bool {
        url.contains("webvpn.neu.edu.cn")
    }

    /// 校园网专属主机（portal / pass / pay / personal 校外可直连，不在改写范围）。
    static func isIntranet(_ url: String) -> Bool {
        let u = url.lowercased()
        return u.contains("ecard.neu.edu.cn")
            || u.contains("jwxt.neu.edu.cn")
            || u.contains("219.216.96.4")
    }

    /// 把内网 URL 编成 WebVPN 网关地址；已是网关地址则原样返回。
    static func wrap(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        if isWrapped(trimmed) { return trimmed }

        var scheme = "http"
        var rest = trimmed
        if trimmed.hasPrefix("https://") {
            scheme = "https"
            rest = String(trimmed.dropFirst(8))
        } else if trimmed.hasPrefix("http://") {
            rest = String(trimmed.dropFirst(7))
        } else if trimmed.hasPrefix("//") {
            rest = String(trimmed.dropFirst(2))
        }

        var query = ""
        if let q = rest.firstIndex(of: "?") {
            query = String(rest[q...])
            rest = String(rest[..<q])
        }

        var hostPort = rest
        var path = ""
        if let slash = rest.firstIndex(of: "/") {
            hostPort = String(rest[..<slash])
            path = String(rest[slash...])
        }

        var host = hostPort
        var port: String?
        if let colon = hostPort.lastIndex(of: ":") {
            let p = String(hostPort[colon...].dropFirst())
            let h = String(hostPort[..<colon])
            if !h.isEmpty && p.allSatisfy(\.isNumber) {
                host = h
                port = p
            }
        }

        let proto = port.map { "\(scheme)-\($0)" } ?? scheme
        return "\(base)/\(proto)/\(encryptHost(host))\(path)\(query)"
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

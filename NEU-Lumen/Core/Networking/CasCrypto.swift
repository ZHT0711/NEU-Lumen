import Foundation
import Security

/// 东北大学统一身份认证（CAS）密码加密。
/// 与门户前端 JSEncrypt 一致：RSA PKCS#1 v1.5，公钥来自 login_neu.js。
/// 使用系统 Security 框架硬件加速，不再自行实现大数运算。
enum CasCrypto {
    static let casLoginURL = URL(
        string: "https://pass.neu.edu.cn/tpass/login?service="
            + "https%3A%2F%2Fpersonal.neu.edu.cn%2Fportal%2Fmanage%2Fcommon%2Fcas_login%2F1"
            + "%3Fredirect%3Dhttps%253A%252F%252Fpersonal.neu.edu.cn%252Fportal"
    )!

    /// login_neu.js 中 publicKeyStr 的模数（2048-bit），指数固定 65537。公钥会随登录页 JS 更新。
    private static let modulusHex =
        "009e3036f032ca5d9cf16ca9a8f7fd569152dfd66afec2d2d72d7b7ab02e168810adb1bcc5"
        + "e5ec26ec0459780752de266daa560f9fa21c5283b0e361fc9c02bfb5f15c21be9d6752b46a"
        + "d9f4537f6858218fcd8b8ab4b25e32e3598835d5b805eda23adc90e8cb5bd0778149da3462"
        + "ee231d1f61eeba974a3d5a35367062cd6507e2231b36874d33d4403d21d4a7571895416483"
        + "fa5b0fdc96578764d3dbcee56b8638eb4dd240d2932bf42f5df72671cc1311dd485ba1f01b"
        + "10fa42b9089c18878ac296c66bde37b50349a41167f27dec6d180b7da90f7f164f9de2cd77"
        + "8ad29fe453f5f7ed53f9e79ba6d7055616f3c8b9cf48ee030fd7e86ae5af97e9cfbeb5"

    private static let exponentBytes: [UInt8] = [0x01, 0x00, 0x01] // 65537

    private static let publicKey: SecKey? = {
        guard let modulus = Self.modulusBytes else { return nil }
        let der = Self.pkcs1RSAPublicKey(modulus: modulus, exponent: exponentBytes)
        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeyClass as String: kSecAttrKeyClassPublic,
            kSecAttrKeySizeInBits as String: 2048,
        ]
        var error: Unmanaged<CFError>?
        return SecKeyCreateWithData(Data(der) as CFData, attributes as CFDictionary, &error)
    }()

    private static var modulusBytes: [UInt8]? {
        guard modulusHex.count % 2 == 0 else { return nil }
        var bytes: [UInt8] = []
        bytes.reserveCapacity(modulusHex.count / 2)
        var index = modulusHex.startIndex
        while index < modulusHex.endIndex {
            let next = modulusHex.index(index, offsetBy: 2)
            guard let byte = UInt8(modulusHex[index..<next], radix: 16) else { return nil }
            bytes.append(byte)
            index = next
        }
        return bytes
    }

    /// DER INTEGER：去多余前导 0，最高位为 1 时补符号 0。
    private static func derInteger(_ value: [UInt8]) -> [UInt8] {
        var v = value
        while v.count > 1, v.first == 0x00 { v.removeFirst() }
        if let first = v.first, first & 0x80 != 0 { v.insert(0x00, at: 0) }
        if v.isEmpty { v = [0x00] }
        var out: [UInt8] = [0x02]
        out += derLength(v.count)
        out += v
        return out
    }

    private static func derLength(_ n: Int) -> [UInt8] {
        if n < 0x80 { return [UInt8(n)] }
        if n <= 0xFF { return [0x81, UInt8(n)] }
        return [0x82, UInt8((n >> 8) & 0xFF), UInt8(n & 0xFF)]
    }

    /// PKCS#1 RSAPublicKey = SEQUENCE(INTEGER modulus, INTEGER exponent)。
    private static func pkcs1RSAPublicKey(modulus: [UInt8], exponent: [UInt8]) -> [UInt8] {
        let body = derInteger(modulus) + derInteger(exponent)
        var out: [UInt8] = [0x30]
        out += derLength(body.count)
        out += body
        return out
    }

    /// RSA-PKCS1v15(utf8(username + password)) → base64。
    static func encrypt(_ plaintext: String) throws -> String {
        guard let key = publicKey else {
            throw NetworkError(message: "认证公钥初始化失败")
        }
        let data = Data(plaintext.utf8)
        guard data.count <= 245 else {
            throw NetworkError(message: "认证凭据过长")
        }
        var error: Unmanaged<CFError>?
        guard let cipher = SecKeyCreateEncryptedData(key, .rsaEncryptionPKCS1, data as CFData, &error) as Data? else {
            let detail = error?.takeRetainedValue().localizedDescription ?? "未知错误"
            throw NetworkError(message: "认证加密失败：\(detail)")
        }
        return cipher.base64EncodedString()
    }
}

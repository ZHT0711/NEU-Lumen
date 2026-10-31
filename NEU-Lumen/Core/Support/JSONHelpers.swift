import Foundation

// MARK: - 容错 JSON 取值（对齐 Dart 动态解析习惯）

extension [String: Any] {
    /// 取字符串：nil/NSNull → ""，数字/布尔 → 文本。
    func str(_ key: String) -> String {
        guard let v = self[key], !(v is NSNull) else { return "" }
        if let s = v as? String { return s }
        if let n = v as? NSNumber { return n.stringValue }
        return String(describing: v)
    }

    func dbl(_ key: String) -> Double? {
        guard let v = self[key], !(v is NSNull) else { return nil }
        if let n = v as? NSNumber { return n.doubleValue }
        if let s = v as? String { return Double(s.trimmingCharacters(in: .whitespaces)) }
        return nil
    }

    func int(_ key: String) -> Int? {
        guard let v = self[key], !(v is NSNull) else { return nil }
        if let n = v as? NSNumber { return n.intValue }
        if let s = v as? String { return Int(s.trimmingCharacters(in: .whitespaces)) }
        return nil
    }

    func bool(_ key: String) -> Bool? {
        guard let v = self[key], !(v is NSNull) else { return nil }
        if let b = v as? Bool { return b }
        if let n = v as? NSNumber { return n.boolValue }
        return nil
    }

    func arr(_ key: String) -> [[String: Any]] {
        (self[key] as? [Any])?.compactMap { $0 as? [String: Any] } ?? []
    }

    func obj(_ key: String) -> [String: Any] {
        self[key] as? [String: Any] ?? [:]
    }
}

// MARK: - 日期解析（格式器静态缓存，只创建一次）

enum PortalDate {
    private static func formatter(_ format: String) -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = format
        return f
    }

    private static let dateTimeFull = formatter("yyyy-MM-dd HH:mm:ss")
    private static let dateTimeShort = formatter("yyyy-MM-dd HH:mm")
    private static let isoDateTime = formatter("yyyy-MM-dd'T'HH:mm:ss")
    private static let dayFormatter = formatter("yyyy-MM-dd")

    static func dateTime(_ raw: String) -> Date? {
        let s = raw.trimmingCharacters(in: .whitespaces)
        if s.isEmpty { return nil }
        return dateTimeFull.date(from: s)
            ?? dateTimeShort.date(from: s)
            ?? isoDateTime.date(from: s)
    }

    static func day(_ raw: String) -> Date? {
        dayFormatter.date(from: raw.trimmingCharacters(in: .whitespaces))
    }

    static func isoDay(_ date: Date) -> String {
        dayFormatter.string(from: date)
    }
}

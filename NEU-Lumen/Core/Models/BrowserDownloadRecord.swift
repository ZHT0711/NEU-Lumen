import Foundation

/// No URL, request headers, cookie, account name or resumeData is persisted here.
struct BrowserDownloadRecord: Codable, Identifiable, Equatable {
    enum State: String, Codable { case downloading, completed, failed, cancelled, interrupted }
    enum Kind: String, Codable { case original, webpagePDF }
    enum Failure: String, Codable {
        case network, storage, response, notPDF, missingFile
        var message: String {
            switch self {
            case .network: return "下载失败，请回原网页重新下载。"
            case .storage: return "无法保存文件，请检查可用空间后重试。"
            case .response: return "服务器未返回可下载的文件，可能需要重新登录或授权。"
            case .notPDF: return "响应不是有效的 PDF，未保存为原始 PDF。请在网页中重新登录后重试。"
            case .missingFile: return "文件已不存在，请回原网页重新下载。"
            }
        }
    }

    let id: UUID
    var filename: String
    var mimeType: String?
    var state: State
    var kind: Kind
    var receivedBytes: Int64
    var totalBytes: Int64?
    let createdAt: Date
    var finishedAt: Date?
    var failure: Failure?

    init(id: UUID = UUID(), filename: String = "下载文件", kind: Kind = .original) {
        self.id = id
        self.filename = BrowserDownloadNames.sanitize(filename)
        self.kind = kind
        state = .downloading
        receivedBytes = 0
        createdAt = Date()
    }

    var fraction: Double? {
        guard let totalBytes, totalBytes > 0 else { return nil }
        return min(1, max(0, Double(receivedBytes) / Double(totalBytes)))
    }
}

enum BrowserDownloadNames {
    /// A single NFC component, capped by UTF-8 bytes (not Character count).
    /// Removes path separators, control/bidi/format characters and hidden-dot names.
    static func sanitize(_ suggested: String, pdf: Bool = false) -> String {
        let normalized = suggested.precomposedStringWithCanonicalMapping
        let forbidden = CharacterSet.controlCharacters.union(.illegalCharacters)
        var text = String(String.UnicodeScalarView(normalized.unicodeScalars.map { scalar in
            if forbidden.contains(scalar) || scalar.properties.generalCategory == .format ||
                "/\\:".unicodeScalars.contains(scalar) { return UnicodeScalar(95)! }
            return scalar
        }))
        text = text.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: ".")))
        if text.isEmpty { text = "下载文件" }
        if pdf, !text.lowercased().hasSuffix(".pdf") { text += ".pdf" }
        let ext = (text as NSString).pathExtension
        let suffix = !ext.isEmpty && ext.utf8.count <= 20 ? "." + ext : ""
        let stem = suffix.isEmpty ? text : String(text.dropLast(suffix.count))
        var result = ""
        for character in stem {
            let next = String(character)
            if result.utf8.count + next.utf8.count > 180 - suffix.utf8.count { break }
            result += next
        }
        if result.isEmpty { result = "下载文件" }
        return result + suffix
    }

    static func mime(_ value: String?) -> String? {
        guard let value else { return nil }
        let type = value.split(separator: ";", maxSplits: 1).first.map(String.init)?
            .trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        guard !type.isEmpty, type.utf8.count < 128,
              type.unicodeScalars.allSatisfy({ $0.isASCII && !CharacterSet.controlCharacters.contains($0) }) else { return nil }
        return type
    }

    static func isPDF(_ mime: String?) -> Bool { self.mime(mime) == "application/pdf" }
    static func isHTML(_ mime: String?) -> Bool {
        ["text/html", "application/xhtml+xml"].contains(self.mime(mime) ?? "")
    }
}

struct BrowserDownloadManifest: Codable {
    var version = 1
    var records: [BrowserDownloadRecord]

    func encoded() throws -> Data {
        try validate()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(self)
    }

    static func decode(_ data: Data) throws -> Self {
        guard data.count <= 8_000_000 else { throw CocoaError(.fileReadCorruptFile) }
        let result = try JSONDecoder().decode(Self.self, from: data)
        try result.validate()
        return result
    }

    private func validate() throws {
        guard version == 1, records.count <= 10_000,
              Set(records.map(\.id)).count == records.count,
              records.allSatisfy({ record in
                  record.filename == BrowserDownloadNames.sanitize(record.filename) &&
                  !record.filename.isEmpty && record.receivedBytes >= 0 &&
                  (record.totalBytes == nil || record.totalBytes! > 0) &&
                  (record.mimeType == nil || record.mimeType == BrowserDownloadNames.mime(record.mimeType)) &&
                  record.createdAt.timeIntervalSince1970.isFinite &&
                  (record.finishedAt == nil || record.finishedAt!.timeIntervalSince1970.isFinite)
              }) else { throw CocoaError(.fileReadCorruptFile) }
    }

    /// A process restart never promises that a WebKit download can be resumed.
    mutating func interruptUnfinished() -> [UUID] {
        var interrupted: [UUID] = []
        for index in records.indices where records[index].state == .downloading {
            interrupted.append(records[index].id)
            records[index].state = .interrupted
            records[index].finishedAt = Date()
        }
        return interrupted
    }
}

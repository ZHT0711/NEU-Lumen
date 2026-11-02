import Foundation

/// ASP.NET / CAS forms use mixed quoting, attribute order and HTML entities.
enum HTMLInputFields {
    private static let inputs = try! NSRegularExpression(pattern: #"<input\b(?:[^>"']|"[^"]*"|'[^']*')*>"#, options: .caseInsensitive)
    private static let attributeRegex = try! NSRegularExpression(pattern: #"(?:^|\s)([\w:$-]+)\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s>]+))"#)
    private static let entities = try! NSRegularExpression(pattern: #"&#(x[0-9a-f]+|[0-9]+);"#, options: .caseInsensitive)

    static func decode(_ value: String) -> String {
        var result = value
        for match in entities.matches(in: value, range: NSRange(value.startIndex..., in: value)).reversed() {
            guard let digits = Range(match.range(at: 1), in: value), let range = Range(match.range, in: result) else { continue }
            let raw = String(value[digits])
            let number = raw.lowercased().hasPrefix("x") ? UInt32(raw.dropFirst(), radix: 16) : UInt32(raw)
            if let number, let scalar = UnicodeScalar(number) { result.replaceSubrange(range, with: String(scalar)) }
        }
        return result.replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
    }

    static func parse(_ html: String) -> [[String: String]] {
        inputs.matches(in: html, range: NSRange(html.startIndex..., in: html)).compactMap { match in
            guard let range = Range(match.range, in: html) else { return nil }
            let tag = String(html[range])
            var result = attributes(in: tag)
            result["hidden"] = result["type"]?.lowercased() == "hidden" ? "1" : "0"
            return result
        }
    }

    static func attributes(in tag: String) -> [String: String] {
        var result: [String: String] = [:]
        for attr in attributeRegex.matches(in: tag, range: NSRange(tag.startIndex..., in: tag)) {
            guard let name = Range(attr.range(at: 1), in: tag) else { continue }
            for index in 2...4 where attr.range(at: index).location != NSNotFound {
                if let value = Range(attr.range(at: index), in: tag) {
                    result[String(tag[name]).lowercased()] = decode(String(tag[value]))
                }
            }
        }
        return result
    }
}

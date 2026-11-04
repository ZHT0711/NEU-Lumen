import Foundation

/// The card site renders wallet amounts as input values, ASP.NET labels or visible text.
enum CardBalanceDocument {
    private static let number = #"[+-]?(?:[0-9]{1,3}(?:,[0-9]{3})+|[0-9]+)(?:\.[0-9]{1,2})?"#

    static func parse(_ html: String) throws -> CardBalance {
        let page = html.replacingOccurrences(of: #"(?is)<!--.*?-->|<script\b[^>]*>.*?</script\s*>|<style\b[^>]*>.*?</style\s*>"#,
                                             with: " ", options: .regularExpression)
        let text = plainText(page)
        let wallet = field(in: page, names: ["txtOddFare", "lblOddFare", "labOddFare"])
            ?? labelledAmount(in: text, labels: "主钱包余额|主钱包|校园卡余额|卡内余额")
        guard let wallet, let amount = money(wallet) else {
            throw NetworkError(message: "一卡通网页尚未提供可读取的主钱包余额，请进入“个人基本信息”页后同步")
        }
        let subsidy = field(in: page, names: ["txtSpecialOddFare", "lblSpecialOddFare", "txtSubsidy", "lblSubsidy"])
            ?? labelledAmount(in: text, labels: "补助余额|补助钱包余额|补贴余额")
        let status = field(in: page, names: ["txtStatus", "lblStatus", "labStatus"])
            ?? capture(#"卡状态\s*[:：]\s*([^\s]+)"#, in: text) ?? ""
        return CardBalance(balance: amount, subsidy: subsidy.flatMap(money), status: status)
    }

    private static func field(in html: String, names: [String]) -> String? {
        func matches(_ attributes: [String: String]) -> Bool {
            [attributes["id"], attributes["name"]].compactMap { $0?.lowercased() }.contains { value in
                names.contains { name in
                    let suffix = name.lowercased()
                    return value == suffix || value.hasSuffix("_" + suffix) || value.hasSuffix("$" + suffix)
                }
            }
        }
        for attributes in HTMLInputFields.parse(html) where matches(attributes) {
            if let value = attributes["value"], !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return value }
        }
        let regex = try! NSRegularExpression(pattern: #"<(span|label|output)\b([^>]*)>(.*?)</\1\s*>"#,
                                             options: [.caseInsensitive, .dotMatchesLineSeparators])
        for match in regex.matches(in: html, range: NSRange(html.startIndex..., in: html)) {
            guard let attributes = Range(match.range(at: 2), in: html), let body = Range(match.range(at: 3), in: html),
                  matches(HTMLInputFields.attributes(in: String(html[attributes]))) else { continue }
            let value = plainText(String(html[body]))
            if !value.isEmpty { return value }
        }
        return nil
    }

    private static func plainText(_ html: String) -> String {
        HTMLInputFields.decode(html.replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression))
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func labelledAmount(in text: String, labels: String) -> String? {
        capture("(?:\(labels))\\s*[:：]?\\s*[￥¥]?\\s*(\(number))(?![0-9.,*＊])", in: text)
    }

    private static func money(_ text: String) -> Double? {
        let normalized = text.replacingOccurrences(of: #"[￥¥元\s]"#, with: "", options: .regularExpression)
        guard normalized.range(of: "^\(number)$", options: .regularExpression) != nil else { return nil }
        return Double(normalized.replacingOccurrences(of: ",", with: ""))
    }

    private static func capture(_ pattern: String, in text: String) -> String? {
        let regex = try! NSRegularExpression(pattern: pattern)
        guard let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[range])
    }

    /// outerHTML alone omits live input properties and documents inside frames.
    static let browserScript = #"""
    (() => {
      const pages = [];
      const visited = new Set();
      function snapshot(doc, depth) {
        if (!doc || !doc.documentElement || visited.has(doc) || depth > 4 || visited.size >= 16) return;
        visited.add(doc);
        const copy = doc.documentElement.cloneNode(true);
        const live = doc.querySelectorAll('input');
        copy.querySelectorAll('input').forEach((input, index) => input.setAttribute('value', live[index].value));
        pages.push(copy.outerHTML);
        for (const frame of doc.querySelectorAll('iframe,frame')) {
          try { snapshot(frame.contentDocument, depth + 1); } catch (_) {}
        }
      }
      snapshot(document, 0);
      return pages.join('\n');
    })()
    """#
}

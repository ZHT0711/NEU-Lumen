import Foundation

struct AffairsCatalogFilter: Identifiable, Hashable {
    let id: String
    let title: String
}

struct AffairsCatalogQuery: Hashable {
    var audience = "1"
    var category = "0"
    var department = "0"
    var initial = "0"
    var keyword = ""

    var url: URL {
        var parts = URLComponents(string: "https://ehall.neu.edu.cn/db_portal/service")!
        parts.queryItems = [
            URLQueryItem(name: "object", value: audience),
            URLQueryItem(name: "type", value: category),
            URLQueryItem(name: "organize", value: department),
            URLQueryItem(name: "english", value: initial),
            URLQueryItem(name: "keyword", value: keyword),
        ]
        return parts.url!
    }
}

struct AffairsService: Identifiable, Hashable {
    let id: String
    let title: String
    let department: String
    let guideURL: URL
}

struct AffairsCatalog {
    let audiences: [AffairsCatalogFilter]
    let categories: [AffairsCatalogFilter]
    let departments: [AffairsCatalogFilter]
    let initials: [AffairsCatalogFilter]
    let services: [AffairsService]
}

struct AffairsGuideSection: Identifiable {
    let id: String
    let title: String
    let text: String
    let links: [AffairsGuideLink]
    let images: [URL]
}

struct AffairsGuideLink: Identifiable {
    let title: String
    let url: URL
    var id: String { url.absoluteString }
}

struct AffairsServiceGuide {
    let title: String
    let facts: [String]
    let sections: [AffairsGuideSection]
    let applicationURL: URL?
}

/// The server-rendered directory is the source of truth, including new services
/// and departments. No per-service list is compiled into the app.
enum NativeAffairsCatalogParser {
    static let origin = URL(string: "https://ehall.neu.edu.cn/")!

    static func catalog(_ html: String) throws -> AffairsCatalog {
        let audiences = filters(html, className: "object_class")
        let categories = filters(html, className: "type_class")
        let departments = filters(html, className: "organize_class")
        let initials = filters(html, className: "english_class")
        guard !audiences.isEmpty, !categories.isEmpty, !departments.isEmpty, !initials.isEmpty else {
            throw NetworkError(message: "办事目录格式已变化，请稍后重试")
        }
        var services: [AffairsService] = []
        var seen = Set<String>()
        for card in captures(#"<div\b[^>]*class=["']alk-service-nav["'][^>]*>([\s\S]*?)</div>"#, in: html) {
            let anchors = captures(#"<a\b([^>]*)>([\s\S]*?)</a>"#, in: card[0])
            guard let first = anchors.first, let last = anchors.last,
                  let raw = HTMLInputFields.attributes(in: last[0])["href"],
                  let url = schoolURL(raw), url.path == "/db_portal/guide",
                  let id = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "id" })?.value,
                  !id.isEmpty, id.count <= 128, !plain(last[1]).isEmpty else {
                throw NetworkError(message: "办事目录含有暂不支持的事项，读取未完成")
            }
            if seen.insert(id).inserted {
                services.append(AffairsService(id: id, title: plain(last[1]), department: plain(first[1]), guideURL: url))
            }
        }
        return AffairsCatalog(audiences: audiences, categories: categories, departments: departments,
                              initials: initials, services: services)
    }

    static func guide(_ html: String) throws -> AffairsServiceGuide {
        guard let title = captures(#"<h2\b[^>]*class=["']title-h2["'][^>]*>([\s\S]*?)</h2>"#, in: html).first?.first,
              !plain(title).isEmpty else { throw NetworkError(message: "暂未读取到办事指南") }
        let factsHTML = captures(#"<div\b[^>]*class=["']top-nav-box["'][^>]*>([\s\S]*?)</div>"#, in: html).first?.first ?? ""
        let facts = captures(#"<p\b[^>]*>([\s\S]*?)</p>"#, in: factsHTML).map { plain($0[0]) }.filter { !$0.isEmpty }
        var sections: [AffairsGuideSection] = []
        for (index, row) in captures(#"<li\b[^>]*class=["'](?:left-nav|right-nav)["'][^>]*>([\s\S]*?)(?=<li\b|</ul>)"#, in: html).enumerated() {
            guard let heading = captures(#"<h3\b[^>]*>([\s\S]*?)</h3>"#, in: row[0]).first?.first,
                  let end = row[0].range(of: "</h3>", options: .caseInsensitive) else { continue }
            sections.append(section(id: "fact-\(index)", title: plain(heading), html: String(row[0][end.upperBound...])))
        }
        let tabNames = ["办事流程", "公告信息", "所需材料", "文件规定", "常见问题", "关联事项"]
        for (index, name) in tabNames.enumerated() {
            let pattern = #"<div\b[^>]*id=["']cont_one_"# + String(index + 1) + #"["'][^>]*>([\s\S]*?)(?=<div\b[^>]*id=["']cont_one_|<!--relevance-->)"#
            if let content = captures(pattern, in: html).first?.first {
                sections.append(section(id: "tab-\(index)", title: name, html: content))
            }
        }
        let application = captures(#"jump_open\(['"]([^'"]+)['"]\)"#, in: html).first.flatMap { row in
            row.first.flatMap { resourceURL($0) }
        }
        return AffairsServiceGuide(title: plain(title), facts: facts, sections: sections, applicationURL: application)
    }

    static func schoolURL(_ raw: String) -> URL? {
        guard let url = URL(string: HTMLInputFields.decode(raw), relativeTo: origin)?.absoluteURL,
              url.scheme == "https", url.host?.lowercased() == origin.host,
              url.user == nil, url.password == nil, url.port == nil || url.port == 443 else { return nil }
        return url
    }

    private static func section(id: String, title: String, html: String) -> AffairsGuideSection {
        let links = captures(#"<a\b([^>]*)>([\s\S]*?)</a>"#, in: html).compactMap { row -> AffairsGuideLink? in
            guard let raw = HTMLInputFields.attributes(in: row[0])["href"], let url = resourceURL(raw) else { return nil }
            let title = plain(row[1])
            return AffairsGuideLink(title: title.isEmpty ? url.lastPathComponent : title, url: url)
        }
        let images = captures(#"<img\b([^>]*)>"#, in: html).compactMap { row in
            HTMLInputFields.attributes(in: row[0])["src"].flatMap(resourceURL)
        }
        let paragraphs = html.replacingOccurrences(of: #"<br\s*/?>|</(?:p|li|h[1-6]|tr)>"#, with: "\n", options: [.regularExpression, .caseInsensitive])
            .components(separatedBy: .newlines).map(plain).filter { !$0.isEmpty }.joined(separator: "\n")
        return AffairsGuideSection(id: id, title: title, text: paragraphs, links: links, images: images)
    }

    private static func resourceURL(_ raw: String) -> URL? {
        guard let url = URL(string: HTMLInputFields.decode(raw), relativeTo: origin)?.absoluteURL,
              ["https", "http"].contains(url.scheme?.lowercased() ?? ""), url.host != nil,
              url.user == nil, url.password == nil else { return nil }
        return url
    }

    private static func filters(_ html: String, className: String) -> [AffairsCatalogFilter] {
        var seen = Set<String>()
        return captures(#"<a\b([^>]*)>([\s\S]*?)</a>"#, in: html).compactMap { row in
            let attrs = HTMLInputFields.attributes(in: row[0])
            guard (attrs["class"] ?? "").split(whereSeparator: \.isWhitespace).contains(Substring(className)),
                  let id = attrs["id"]?.split(separator: "_", maxSplits: 1).last.map(String.init),
                  !id.isEmpty, seen.insert(id).inserted else { return nil }
            return AffairsCatalogFilter(id: id, title: plain(row[1]))
        }
    }

    private static func plain(_ html: String) -> String {
        let stripped = html.replacingOccurrences(of: #"<(script|style)\b[^>]*>[\s\S]*?</\1>"#, with: "", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)
        return HTMLInputFields.decode(stripped).components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.joined(separator: " ")
    }

    private static func captures(_ pattern: String, in text: String) -> [[String]] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return [] }
        return regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).map { match in
            (1..<match.numberOfRanges).map { index in Range(match.range(at: index), in: text).map { String(text[$0]) } ?? "" }
        }
    }
}

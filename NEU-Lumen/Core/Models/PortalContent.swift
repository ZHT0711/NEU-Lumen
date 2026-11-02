import Foundation

enum PortalLink {
    static func resolve(_ raw: String, base: URL = URL(string: PortalClient.portalBase + "/")!) -> URL? {
        let value = HTMLInputFields.decode(raw).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, !value.hasPrefix("#") else { return nil }
        let fileExtensions: Set<String> = ["jpg", "jpeg", "png", "gif", "webp", "avif", "svg", "bmp", "heic", "htm", "html", "aspx", "jsp", "php", "do", "pdf"]
        let isFile = fileExtensions.contains(URL(string: value)?.pathExtension.lowercased() ?? "")
        let absolute: URL?
        if value.hasPrefix("//") { absolute = URL(string: (base.scheme ?? "https") + ":" + value) }
        else if value.contains("://") { absolute = URL(string: value) }
        else if value.range(of: #"^[a-zA-Z][a-zA-Z0-9+.-]*:"#, options: .regularExpression) != nil { return nil }
        else if value.split(separator: "/").first?.contains(".") == true && !value.hasPrefix(".") && !value.hasPrefix("/") && !isFile {
            absolute = URL(string: withScheme(value))
        } else { absolute = URL(string: value, relativeTo: base)?.absoluteURL }
        guard let url = absolute, ["http", "https"].contains(url.scheme?.lowercased() ?? ""), url.host != nil else { return nil }
        return url
    }

    static func from(_ objects: [[String: Any]]) -> URL? {
        for object in objects {
            for key in ["form_mobile_url_view", "mobile_url", "mobileUrl", "form_url_view", "detail_url", "url", "href", "link", "target_url", "app_url"] {
                if let raw = object[key] as? String, let url = resolve(raw) { return url }
                if let nested = object[key] as? [String: Any], let url = from([nested]) { return url }
            }
        }
        return nil
    }

    static func appURL(id: String) -> URL? {
        guard !id.isEmpty else { return nil }
        var parts = URLComponents(string: PortalClient.portalBase + "/pages/mimipath/mimipath")!
        parts.queryItems = [URLQueryItem(name: "appId", value: id)]
        return parts.url
    }
}

enum NewsArticle {
    private static let tags = try! NSRegularExpression(pattern: #"</?[a-zA-Z][a-zA-Z0-9]*\b(?:[^>"']|"[^"]*"|'[^']*')*>"#)
    private static let ignored = try! NSRegularExpression(pattern: #"<!--[\s\S]*?-->|<(script|style)\b[^>]*>[\s\S]*?</\1\s*>"#, options: .caseInsensitive)
    private static let tagName = try! NSRegularExpression(pattern: #"^</?([a-zA-Z][a-zA-Z0-9]*)"#)
    private static let contentNames: Set<String> = ["vsb_content", "vsb_content_2", "wp_articlecontent", "article_content", "article-content", "rich_media_content", "article-body", "v_news_content"]

    static func firstImage(in html: String, base: URL) -> URL? {
        let source = ignored.stringByReplacingMatches(in: html, range: NSRange(html.startIndex..., in: html), withTemplate: "")
        var stack: [(name: String, content: Bool)] = []
        var declaredImage: URL?
        var bodyImage: URL?
        let voids: Set<String> = ["img", "input", "br", "hr", "meta", "link", "source", "base", "area", "embed", "wbr", "col", "param", "track"]
        for match in tags.matches(in: source, range: NSRange(source.startIndex..., in: source)) {
            guard let range = Range(match.range, in: source) else { continue }
            let tag = String(source[range])
            guard let nameMatch = tagName.firstMatch(in: tag, range: NSRange(tag.startIndex..., in: tag)),
                  let nameRange = Range(nameMatch.range(at: 1), in: tag) else { continue }
            let name = tag[nameRange].lowercased()
            if tag.hasPrefix("</") {
                if let index = stack.lastIndex(where: { $0.name == name }) { stack.removeSubrange(index...) }
                continue
            }
            let attrs = HTMLInputFields.attributes(in: tag)
            let names = ((attrs["id"] ?? "") + " " + (attrs["class"] ?? "")).lowercased().split(whereSeparator: \.isWhitespace).map(String.init)
            let content = name == "article" || name == "main" || names.contains { contentNames.contains($0) }
            let inContent = content || stack.contains { $0.content }
            if name == "meta", ["og:image", "twitter:image"].contains((attrs["property"] ?? attrs["name"] ?? "").lowercased()) {
                declaredImage = declaredImage ?? PortalLink.resolve(attrs["content"] ?? "", base: base)
            }
            if name == "img", inContent {
                if let width = Int(attrs["width"] ?? ""), width <= 16 { continue }
                if let height = Int(attrs["height"] ?? ""), height <= 16 { continue }
                for key in ["data-src", "data-original", "data-lazy-src", "src"] {
                    if let url = PortalLink.resolve(attrs[key] ?? "", base: base) { bodyImage = url; break }
                }
                if bodyImage != nil { return bodyImage }
            }
            if !voids.contains(name) && !tag.hasSuffix("/>") { stack.append((name, content)) }
        }
        return declaredImage
    }
}

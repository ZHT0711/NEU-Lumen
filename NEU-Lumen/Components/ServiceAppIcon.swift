import SwiftUI

/// 门户应用使用学校提供的图标；原生工具不替换门户应用。
struct ServiceAppIcon: View {
    let app: PortalApp
    @State private var loaded: (url: URL, image: UIImage)?

    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 25
        return URLSession(configuration: configuration)
    }()

    var body: some View {
        let url = Self.resolve(app.iconUrl)
        Group {
            if let loaded, loaded.url == url {
                Image(uiImage: loaded.image).resizable().scaledToFit()
            } else {
                Image(systemName: "square.grid.2x2").resizable().scaledToFit().foregroundStyle(.tertiary)
            }
        }
        .accessibilityHidden(true)
        .task(id: url) {
            guard let url, loaded?.url != url else { return }
            loaded = nil
            let image = await CampusImageCache.serviceIcons.image(at: url) { try await Self.fetch($0) }
            guard !Task.isCancelled, let image else { return }
            loaded = (url, image)
        }
    }

    private static func fetch(_ url: URL) async throws -> Data {
        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        return data
    }

    private static func resolve(_ raw: String) -> URL? {
        let path = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty else { return nil }
        let address: String
        if path.hasPrefix("//") { address = "https:" + path }
        else if path.hasPrefix("/") { address = PortalClient.portalBase + path }
        else { address = withScheme(path) }
        guard let url = URL(string: address), let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme), url.host != nil, url.user == nil, url.password == nil else { return nil }
        return url
    }
}

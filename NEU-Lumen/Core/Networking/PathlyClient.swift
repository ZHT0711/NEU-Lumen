import Foundation

/// A separate public-data transport: campus authentication cookies never enter Pathly requests.
final class PathlyClient: Sendable {
    static let shared = PathlyClient()

    private let session: URLSession
    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.allowsCellularAccess = true
        configuration.allowsExpensiveNetworkAccess = true
        configuration.allowsConstrainedNetworkAccess = true
        configuration.timeoutIntervalForRequest = 25
        configuration.timeoutIntervalForResource = 40
        session = URLSession(configuration: configuration)
    }
    func route(building: IndoorBuilding, start: String, end: String, preference: IndoorRoutePreference) async throws -> IndoorRoute {
        let fields = try IndoorRoute.request(building: building, start: start, end: end, preference: preference)
        var request = URLRequest(url: URL(string: "https://pathly.top/api/v1.0/book-manage-api/path/query")!)
        request.httpMethod = "POST"
        request.httpBody = try JSONSerialization.data(withJSONObject: fields)
        request.setValue("application/json;charset=UTF-8", forHTTPHeaderField: "Content-Type")
        request.setValue("https://pathly.top/user/user-path", forHTTPHeaderField: "Referer")
        let (data, response) = try await session.data(for: request)
        try validate(response, expectedPath: request.url!.path)
        return try IndoorRoute.parse(JSONSerialization.jsonObject(with: data), building: building)
    }
    func image(_ url: URL) async throws -> Data {
        guard url.scheme == "https", url.host == "pathly.top", url.path.hasPrefix("/images/"),
              url.query == nil, url.fragment == nil, url.user == nil, url.password == nil else { throw IndoorNavigationError.incompatibleMap }
        let (data, response) = try await session.data(from: url)
        try validate(response, expectedPath: url.path)
        guard data.count <= 20_000_000, !data.isEmpty else { throw IndoorNavigationError.response }
        return data
    }
    private func validate(_ response: URLResponse, expectedPath: String) throws {
        guard let response = response as? HTTPURLResponse, response.statusCode == 200,
              response.url?.scheme == "https", response.url?.host == "pathly.top", response.url?.path == expectedPath else {
            throw IndoorNavigationError.unavailable
        }
    }
}

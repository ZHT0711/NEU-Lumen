import Foundation

private final class StubProtocol: URLProtocol, @unchecked Sendable {
    struct Reply {
        let status: Int
        var headers: [String: String] = [:]
        var body = Data()
    }

    private static let lock = NSLock()
    private static var handler: ((URLRequest) -> Reply)?

    static func respond(_ handler: @escaping (URLRequest) -> Reply) {
        lock.lock()
        self.handler = handler
        lock.unlock()
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lock.lock()
        let handler = Self.handler
        Self.lock.unlock()
        guard let handler, let url = request.url, let client else {
            preconditionFailure("Missing WebDAV test configuration")
        }
        let reply = handler(request)
        let response = HTTPURLResponse(url: url, statusCode: reply.status, httpVersion: "HTTP/1.1", headerFields: reply.headers)!
        client.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        if !reply.body.isEmpty { client.urlProtocol(self, didLoad: reply.body) }
        client.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

@main
private struct WebDAVBackupTransportTests {
    static func main() async throws {
        let address = "https://backup.example:8443/remote.php/dav/files/student"
        let config = try WebDAVConfiguration(collectionURL: " \(address)\n", username: "student", password: "dav:app:password")
        precondition(config.collectionURL.absoluteString == address + "/")
        try await expect(.invalidCredentials) {
            _ = try WebDAVConfiguration(collectionURL: address, username: "student:other", password: "password")
        }
        for url in ["http://backup.example/dav", "https://user:password@backup.example/dav",
                    "https://backup.example/dav?key=value", "https://backup.example/dav#section",
                    "https://backup.example:65536/dav", "https://backup.example\\other.example/dav"] {
            try await expect(.invalidURL) {
                _ = try WebDAVConfiguration(collectionURL: url, username: "student", password: "password")
            }
        }

        let session = URLSessionConfiguration.ephemeral
        session.protocolClasses = [StubProtocol.self]
        let client = WebDAVBackupClient(configuration: session)
        let backup = Data("{\"version\":1}".utf8)
        let expectedFileURL = address + "/NEU-Lumen-backup.json"
        let expectedAuth = "Basic " + Data("student:dav:app:password".utf8).base64EncodedString()
        StubProtocol.respond { request in
            precondition(request.url?.absoluteString == expectedFileURL)
            precondition(request.httpMethod == "GET")
            precondition(request.value(forHTTPHeaderField: "Authorization") == expectedAuth)
            precondition(request.value(forHTTPHeaderField: "Cookie") == nil)
            return .init(status: 200, headers: ["ETag": "\"original\"", "Set-Cookie": "canary=1"], body: backup)
        }
        let remote = try await client.download(using: config)
        precondition(remote?.data == backup && remote?.etag == "\"original\"")

        StubProtocol.respond { request in
            precondition(request.url?.absoluteString == expectedFileURL)
            precondition(request.httpMethod == "PUT")
            precondition(request.value(forHTTPHeaderField: "Authorization") == expectedAuth)
            precondition(request.value(forHTTPHeaderField: "Cookie") == nil)
            precondition(request.value(forHTTPHeaderField: "If-None-Match") == "*")
            precondition(request.value(forHTTPHeaderField: "If-Match") == nil)
            precondition(request.value(forHTTPHeaderField: "Content-Type") == "application/json; charset=utf-8")
            return .init(status: 201)
        }
        try await client.upload(backup, using: config, condition: .createOnly)

        StubProtocol.respond { request in
            precondition(request.httpMethod == "PUT")
            precondition(request.value(forHTTPHeaderField: "If-Match") == "\"original\"")
            precondition(request.value(forHTTPHeaderField: "If-None-Match") == nil)
            return .init(status: 412)
        }
        try await expect(.conflict) { try await client.upload(backup, using: config, condition: .matching("\"original\"")) }
        try await expect(.invalidRevision) {
            try await client.upload(backup, using: config, condition: .matching("\"valid\"\r\nAuthorization: injected"))
        }

        StubProtocol.respond { _ in .init(status: 200, headers: ["ETag": "W/\"weak\""], body: backup) }
        let weakRemote = try await client.download(using: config)
        precondition(weakRemote?.data == backup && weakRemote?.etag == nil)
        StubProtocol.respond { _ in .init(status: 404) }
        let missing = try await client.download(using: config)
        precondition(missing == nil)
        StubProtocol.respond { request in
            precondition(request.url?.absoluteString == expectedFileURL)
            return .init(status: 307, headers: ["Location": "https://elsewhere.example/moved"])
        }
        try await expect(.redirected) { _ = try await client.download(using: config) }
        StubProtocol.respond { _ in .init(status: 401) }
        try await expect(.unauthorized) { _ = try await client.download(using: config) }

        let oversized = WebDAVBackupClient.maximumBackupSize + 1
        StubProtocol.respond { _ in .init(status: 200, headers: ["Content-Length": "\(oversized)"]) }
        try await expect(.backupTooLarge) { _ = try await client.download(using: config) }
        StubProtocol.respond { _ in .init(status: 200, body: Data(repeating: 0, count: oversized)) }
        try await expect(.backupTooLarge) { _ = try await client.download(using: config) }
        print("PASS: WebDAV HTTPS configuration, authentication isolation, conditional PUT, status mapping and download limits")
    }

    private static func expect(_ expected: WebDAVBackupError, operation: () async throws -> Void) async throws {
        do {
            try await operation()
            preconditionFailure("Expected WebDAV error: \(expected)")
        } catch let actual as WebDAVBackupError {
            precondition(expected == actual, "Unexpected WebDAV error: \(actual)")
        }
    }
}

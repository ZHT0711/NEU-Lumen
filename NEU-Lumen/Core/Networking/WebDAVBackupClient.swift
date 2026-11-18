import Foundation

struct WebDAVConfiguration: Equatable, Sendable {
    let collectionURL: URL
    let username: String
    let password: String

    init(collectionURL: String, username: String, password: String) throws {
        let address = collectionURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard address.rangeOfCharacter(from: .controlCharacters) == nil,
              !address.contains("\\"),
              var components = URLComponents(string: address),
              components.scheme?.lowercased() == "https",
              let host = components.host, !host.isEmpty,
              components.user == nil, components.password == nil,
              components.query == nil, components.fragment == nil,
              components.port.map({ (1...65535).contains($0) }) ?? true else {
            throw WebDAVBackupError.invalidURL
        }
        components.scheme = "https"
        if !components.percentEncodedPath.hasSuffix("/") {
            components.percentEncodedPath += "/"
        }
        guard let url = components.url else { throw WebDAVBackupError.invalidURL }
        guard !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !username.contains(":"), !password.isEmpty,
              username.rangeOfCharacter(from: .controlCharacters) == nil,
              password.rangeOfCharacter(from: .controlCharacters) == nil else {
            throw WebDAVBackupError.invalidCredentials
        }
        self.collectionURL = url
        self.username = username
        self.password = password
    }
}

enum WebDAVBackupError: LocalizedError, Equatable {
    case invalidURL, invalidCredentials, emptyBackup, backupTooLarge
    case invalidResponse, invalidRevision, conflict, redirected
    case unauthorized, forbidden, folderNotFound, methodNotAllowed, locked, insufficientStorage
    case insecureConnection, connectionFailed, serverError(Int)

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "请输入 HTTPS WebDAV 文件夹地址，地址中不能包含账号、密码、查询参数或片段。"
        case .invalidCredentials: return "请输入有效的 WebDAV 用户名和密码。用户名不能包含冒号。"
        case .emptyBackup: return "备份文件为空。"
        case .backupTooLarge: return "备份文件超过 8 MB。"
        case .invalidResponse: return "服务器响应格式异常。"
        case .invalidRevision: return "服务器返回的备份版本无效，请重新检查远端备份。"
        case .conflict: return "远端备份已变化。请重新检查后再上传。"
        case .redirected: return "服务器要求重定向。请填写最终的 HTTPS WebDAV 文件夹地址。"
        case .unauthorized: return "WebDAV 登录失败。请检查用户名和密码或应用专用密码。"
        case .forbidden: return "当前账号无权访问此 WebDAV 文件夹或备份。"
        case .folderNotFound: return "WebDAV 备份目录不存在。请先在服务器上创建该目录。"
        case .methodNotAllowed: return "此地址不支持所需的 WebDAV 操作。请核对文件夹地址及权限。"
        case .locked: return "服务器上的备份文件已锁定，请稍后重试。"
        case .insufficientStorage: return "WebDAV 服务器存储空间不足。"
        case .insecureConnection: return "无法建立安全连接。请检查服务器的 HTTPS 证书。"
        case .connectionFailed: return "无法连接 WebDAV 服务器。请检查网络和服务器地址后重试。"
        case .serverError(let status): return "WebDAV 服务器返回 HTTP \(status)。"
        }
    }
}

final class WebDAVBackupClient: Sendable {
    static let filename = "NEU-Lumen-backup.json"
    static let maximumBackupSize = 8 * 1024 * 1024

    struct RemoteBackup: Sendable {
        let data: Data
        let etag: String?
    }

    enum UploadCondition: Sendable {
        case createOnly
        case matching(String)
        /// Use only after the user confirms overwriting a backup without a strong ETag.
        case replace
    }

    private let session: URLSession

    init(configuration: URLSessionConfiguration = .ephemeral) {
        configuration.httpShouldSetCookies = false
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 60
        session = URLSession(configuration: configuration, delegate: RedirectSuppressor(), delegateQueue: nil)
    }

    deinit { session.invalidateAndCancel() }

    func download(using configuration: WebDAVConfiguration) async throws -> RemoteBackup? {
        let request = request(method: "GET", using: configuration)
        let result = try await transfer(request, acceptedStatuses: [200, 404], downloadStatus: 200)
        guard result.response.statusCode != 404 else { return nil }
        let etag = result.response.value(forHTTPHeaderField: "ETag")
        return RemoteBackup(data: result.data, etag: etag.flatMap(Self.strongETag))
    }

    func upload(_ data: Data, using configuration: WebDAVConfiguration, condition: UploadCondition) async throws {
        guard !data.isEmpty else { throw WebDAVBackupError.emptyBackup }
        guard data.count <= Self.maximumBackupSize else { throw WebDAVBackupError.backupTooLarge }
        var request = request(method: "PUT", using: configuration)
        request.httpBody = data
        request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        switch condition {
        case .createOnly:
            request.setValue("*", forHTTPHeaderField: "If-None-Match")
        case .matching(let etag):
            guard let etag = Self.strongETag(etag) else { throw WebDAVBackupError.invalidRevision }
            request.setValue(etag, forHTTPHeaderField: "If-Match")
        case .replace:
            break
        }
        _ = try await transfer(request, acceptedStatuses: [200, 201, 204])
    }

    private func request(method: String, using configuration: WebDAVConfiguration) -> URLRequest {
        let url = configuration.collectionURL.appendingPathComponent(Self.filename, isDirectory: false)
        let credentials = Data("\(configuration.username):\(configuration.password)".utf8).base64EncodedString()
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        request.httpMethod = method
        request.setValue("Basic \(credentials)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    private func transfer(_ request: URLRequest, acceptedStatuses: Set<Int>, downloadStatus: Int? = nil) async throws
        -> (data: Data, response: HTTPURLResponse) {
        do {
            try Task.checkCancellation()
            let (bytes, response) = try await session.bytes(for: request)
            defer { bytes.task.cancel() }
            try Task.checkCancellation()
            guard let response = response as? HTTPURLResponse else { throw WebDAVBackupError.invalidResponse }
            guard acceptedStatuses.contains(response.statusCode) else { throw Self.statusError(response.statusCode) }
            guard response.statusCode == downloadStatus else { return (Data(), response) }
            guard response.expectedContentLength <= Int64(Self.maximumBackupSize) else {
                throw WebDAVBackupError.backupTooLarge
            }
            var data = Data()
            if response.expectedContentLength > 0 { data.reserveCapacity(Int(response.expectedContentLength)) }
            for try await byte in bytes {
                guard data.count < Self.maximumBackupSize else { throw WebDAVBackupError.backupTooLarge }
                data.append(byte)
            }
            try Task.checkCancellation()
            return (data, response)
        } catch let error as WebDAVBackupError {
            throw error
        } catch {
            if Task.isCancelled || error is CancellationError || (error as? URLError)?.code == .cancelled {
                throw CancellationError()
            }
            switch (error as? URLError)?.code {
            case .userAuthenticationRequired:
                throw WebDAVBackupError.unauthorized
            case .appTransportSecurityRequiresSecureConnection, .secureConnectionFailed,
                 .serverCertificateHasBadDate, .serverCertificateUntrusted,
                 .serverCertificateHasUnknownRoot, .serverCertificateNotYetValid:
                throw WebDAVBackupError.insecureConnection
            default:
                throw WebDAVBackupError.connectionFailed
            }
        }
    }

    private static func strongETag(_ value: String) -> String? {
        let bytes = value.utf8
        guard bytes.count >= 2, bytes.first == 34, bytes.last == 34,
              bytes.dropFirst().dropLast().allSatisfy({ $0 == 33 || (35...126).contains($0) }) else { return nil }
        return value
    }

    private static func statusError(_ status: Int) -> WebDAVBackupError {
        switch status {
        case 300...399: return .redirected
        case 401: return .unauthorized
        case 403: return .forbidden
        case 404, 409: return .folderNotFound
        case 405, 501: return .methodNotAllowed
        case 412: return .conflict
        case 413: return .backupTooLarge
        case 423: return .locked
        case 507: return .insufficientStorage
        default: return .serverError(status)
        }
    }

    private final class RedirectSuppressor: NSObject, URLSessionTaskDelegate {
        func urlSession(_ session: URLSession, task: URLSessionTask,
                        willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                        completionHandler: @escaping (URLRequest?) -> Void) {
            completionHandler(nil)
        }
    }
}

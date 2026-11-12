import Foundation

/// A business request is owned by an identity epoch, not by the latest visible user.
/// Session recovery may renew transport cookies without changing this identity epoch.
struct RepositoryRequestContext: Equatable {
    let account: String
    let epoch: UUID
    let generation: UUID

    func matches(account: String?, epoch: UUID, generation: UUID) -> Bool {
        !self.account.isEmpty && self.account == account && self.epoch == epoch && self.generation == generation
    }
}

enum DataFreshness {
    static let wallet: TimeInterval = 60
    static let electric: TimeInterval = 120
    static let apps: TimeInterval = 600

    static func isFresh(_ updatedAt: Date?, for lifetime: TimeInterval, now: Date = Date()) -> Bool {
        guard let updatedAt else { return false }
        let age = now.timeIntervalSince(updatedAt)
        return age >= 0 && age < lifetime
    }
}

struct ElectricRoomKey: Hashable {
    let account: String
    let room: String

    init(account: String, room: String) {
        self.account = account
        self.room = Self.normalize(room)
    }

    static func normalize(_ raw: String) -> String {
        raw.folding(options: .widthInsensitive, locale: Locale(identifier: "en_US_POSIX"))
            .filter { !$0.isWhitespace && $0 != "-" }
    }

    static func isValid(_ raw: String) -> Bool {
        let room = normalize(raw)
        return room.utf8.count == 7 && room.utf8.allSatisfy { (48...57).contains($0) }
    }
}

/// Distinguishes unread/failed/partially read schedules from a confirmed empty day.
enum ScheduleReadStatus: Equatable {
    case unread, loading, loaded
    case failed(String), partial(String)

    static func summarize(_ states: [LoadState], hasData: Bool = false) -> Self {
        guard !states.isEmpty else { return .unread }
        if states.allSatisfy({ $0 == .loaded }) { return .loaded }
        let known = hasData || states.contains(.loaded)
        let errors = states.compactMap { state -> String? in
            if case .failed(let message) = state { return message }
            return nil
        }
        if !errors.isEmpty {
            let message = Array(Set(errors)).sorted().joined(separator: "；")
            return known ? .partial(message) : .failed(message)
        }
        if states.contains(.loading) { return known ? .partial("其余课表正在同步") : .loading }
        return known ? .partial("部分日期的课表尚未读取") : .unread
    }

    static func loadState(_ states: [LoadState]) -> LoadState {
        let errors = states.compactMap { state -> String? in
            if case .failed(let message) = state { return message }
            return nil
        }
        if !errors.isEmpty { return .failed(Array(Set(errors)).sorted().joined(separator: "；")) }
        if states.contains(.loading) { return .loading }
        return !states.isEmpty && states.allSatisfy { $0 == .loaded } ? .loaded : .idle
    }
}

/// Structured portal failures. In particular HTTP 403 is NOT an authentication
/// failure: a campus/WebVPN gateway denial must not log out the whole account.
enum PortalAPIError: LocalizedError {
    case authenticationRequired
    case httpStatus(Int)
    case invalidEnvelope
    case invalidPayload(String)
    case business(Int, String)

    var requiresAuthentication: Bool {
        if case .authenticationRequired = self { return true }
        return false
    }

    var errorDescription: String? {
        switch self {
        case .authenticationRequired: return "门户认证需要恢复，请重试"
        case .httpStatus(403): return "门户访问被拒绝（HTTP 403），请检查校园网或 WebVPN"
        case .httpStatus(let status): return "门户接口 HTTP \(status)，请稍后重试"
        case .invalidEnvelope: return "门户接口返回格式异常，未覆盖上次结果"
        case .invalidPayload(let resource): return "\(resource)数据格式异常，未覆盖上次结果"
        case .business(let code, let message): return "\(message.isEmpty ? "门户接口错误" : message)（代码 \(code)）"
        }
    }
}

enum PortalEnvelope {
    static func data(status: Int, body: Data) throws -> [String: Any] {
        if status == 401 { throw PortalAPIError.authenticationRequired }
        guard (200..<300).contains(status) else { throw PortalAPIError.httpStatus(status) }
        guard let object = try? JSONSerialization.jsonObject(with: body),
              let envelope = object as? [String: Any], let rawCode = envelope["e"] else {
            throw PortalAPIError.invalidEnvelope
        }
        let code: Int?
        if let text = rawCode as? String { code = Int(text) }
        else if let number = rawCode as? NSNumber, String(cString: number.objCType) != "c",
                number.doubleValue.isFinite, number.doubleValue.rounded() == number.doubleValue {
            code = Int(number.stringValue)
        } else { code = nil }
        guard let code else { throw PortalAPIError.invalidEnvelope }
        if code == 401 { throw PortalAPIError.authenticationRequired }
        guard code == 0 else { throw PortalAPIError.business(code, envelope["m"] as? String ?? "") }
        guard let data = envelope["d"] as? [String: Any] else { throw PortalAPIError.invalidEnvelope }
        return data
    }

    static func list(_ data: [String: Any], key: String = "list") throws -> [Any] {
        guard let list = data[key] as? [Any] else { throw PortalAPIError.invalidPayload("门户列表") }
        return list
    }

    static func days(_ data: [String: Any]) throws -> [String: Any] {
        guard let inner = data["data"] as? [String: Any], let raw = inner["day"] else {
            throw PortalAPIError.invalidPayload("课表")
        }
        if let days = raw as? [String: Any] { return days }
        // PHP may encode an empty associative array as [] rather than {}.
        if let list = raw as? [Any], list.isEmpty { return [:] }
        throw PortalAPIError.invalidPayload("课表")
    }
}

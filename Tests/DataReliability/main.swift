import Foundation

let wifiPath = CampusNetworkPath(connected: true, interfaces: ["en0:true", "pdp_ip0:false"], gateways: ["192.0.2.1"], expensive: false, constrained: false)
let cellPath = CampusNetworkPath(connected: true, interfaces: ["en0:false", "pdp_ip0:true"], gateways: ["192.0.2.1"], expensive: false, constrained: false)
let otherWiFi = CampusNetworkPath(connected: true, interfaces: wifiPath.interfaces, gateways: ["192.0.2.2"], expensive: false, constrained: false)
precondition(wifiPath != cellPath && wifiPath != otherWiFi, "同一可用网卡列表里的链路与网关变化必须触发恢复")

// Native, offline Foundation tests. Compile with LoadState.swift and DataReliability.swift.
var checks = 0
func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    precondition(condition(), message)
    checks += 1
}
func rejected(_ status: Int, _ json: String, authentication: Bool = false) {
    do {
        _ = try PortalEnvelope.data(status: status, body: Data(json.utf8))
        preconditionFailure("Invalid portal response was accepted: \(status)")
    } catch let error as PortalAPIError {
        expect(error.requiresAuthentication == authentication, "Wrong authentication classification")
    } catch { preconditionFailure("Unstructured portal error: \(error)") }
}

let epoch = UUID(), generation = UUID()
let account = RepositoryRequestContext(account: "fixture-A", epoch: epoch, generation: generation)
expect(account.matches(account: "fixture-A", epoch: epoch, generation: generation), "Current account rejected")
expect(!account.matches(account: "fixture-B", epoch: epoch, generation: generation), "Cross-account write accepted")
expect(!account.matches(account: "fixture-A", epoch: UUID(), generation: generation), "A-B-A epoch accepted")
expect(!account.matches(account: "fixture-A", epoch: epoch, generation: UUID()), "Stale repository accepted")
expect(!account.matches(account: nil, epoch: epoch, generation: generation), "Logged-out write accepted")
let roomA = ElectricRoomKey(account: "fixture-A", room: " １２３-４５６７\n")
expect(roomA.room == "1234567", "Room normalization differs from request normalization")
expect(roomA == ElectricRoomKey(account: "fixture-A", room: "1234567"), "Same room not reused")
expect(roomA != ElectricRoomKey(account: "fixture-B", room: "1234567"), "Room cache crosses accounts")
expect(roomA != ElectricRoomKey(account: "fixture-A", room: "1234568"), "Different room reused")
expect(ElectricRoomKey.isValid("123-4567"), "Valid room rejected")
for value in ["", "123456", "12345678", "123a567", "١٢٣٤٥٦٧"] {
    expect(!ElectricRoomKey.isValid(value), "Invalid room accepted")
}
let now = Date(timeIntervalSince1970: 1_000)
expect(DataFreshness.isFresh(now.addingTimeInterval(-59), for: 60, now: now), "Fresh cache missed")
expect(!DataFreshness.isFresh(now.addingTimeInterval(-60), for: 60, now: now), "Expired cache reused")
expect(!DataFreshness.isFresh(now.addingTimeInterval(1), for: 60, now: now), "Future timestamp reused")
expect(!DataFreshness.isFresh(nil, for: 60, now: now), "Missing timestamp reused")
expect(ScheduleReadStatus.summarize([.idle, .idle]) == .unread, "Unread is not empty")
expect(ScheduleReadStatus.summarize([.loading, .idle]) == .loading, "Loading is not empty")
expect(ScheduleReadStatus.summarize([.loaded, .loaded]) == .loaded, "Valid empty weeks not loaded")
let stateCases: [[LoadState]] = [[.failed("week failed"), .loaded], [.loaded, .failed("week failed")]]
for states in stateCases {
    expect(ScheduleReadStatus.loadState(states) == .failed("week failed"), "Success hides other week's failure")
    expect(ScheduleReadStatus.summarize(states) == .partial("week failed"), "Partial week became complete")
}
expect(ScheduleReadStatus.summarize([.failed("failed")]) == .failed("failed"), "Failure became empty")
expect(ScheduleReadStatus.summarize([.failed("failed")], hasData: true) == .partial("failed"), "Cached failure hidden")
expect(ScheduleReadStatus.loadState([.loaded, .loaded, .failed("replacement")]) == .failed("replacement"), "Make-up source ignored")
for status in [401, 403, 429, 503] { rejected(status, #"{"error":"unavailable"}"#, authentication: status == 401) }
for json in [#"{}"#, #"{"e":0}"#, #"{"d":{}}"#, #"{"e":false,"d":{}}"#, #"{"e":"bad","d":{}}"#, #"{"e":0,"d":null}"#, ""] {
    rejected(200, json)
}
rejected(200, #"{"e":"401","m":"authentication"}"#, authentication: true)
rejected(200, #"{"e":403,"m":"gateway denied"}"#)
for json in [#"{"e":0,"d":{"data":{"day":{}}}}"#, #"{"e":"0","d":{"data":{"day":[]}}}"#] {
    let data = try PortalEnvelope.data(status: 200, body: Data(json.utf8))
    let days = try PortalEnvelope.days(data)
    expect(days.isEmpty, "Legal empty timetable rejected")
}
let invalidDays: [[String: Any]] = [[:], ["data": [:]], ["data": ["day": NSNull()]], ["data": ["day": [1]]]]
for data in invalidDays {
    do { _ = try PortalEnvelope.days(data); preconditionFailure("Missing day became empty") }
    catch { checks += 1 }
}
let emptyList = try PortalEnvelope.list(["list": []])
expect(emptyList.isEmpty, "Legal empty list rejected")
print("DataReliability: \(checks) native assertions passed")
let probe = URL(string: "http://ecard.neu.edu.cn/")!
expect(!CampusAccessProbe.accepts(url: probe, status: 200, headers: [:], body: Data("<html>移动网络登录</html>".utf8)), "Generic HTTP 200 became a campus route")
expect(!CampusAccessProbe.accepts(url: probe, status: 200, headers: [:], body: Data("<html>Access Denied</html>".utf8)), "200 denial became a campus route")
expect(!CampusAccessProbe.accepts(url: probe, status: 302, headers: ["Location":"http://carrier.invalid/login"], body: Data()), "Captive redirect became a campus route")
expect(CampusAccessProbe.accepts(url: probe, status: 302, headers: ["Location":"/selflogin/login.aspx"], body: Data()), "School card redirect must remain direct")
expect(CampusAccessProbe.accepts(url: probe, status: 200, headers: [:], body: Data("<title>一卡通</title><form action='/selflogin/login.aspx'></form>".utf8)), "Recognized card page rejected")
expect(CampusTransportRetry.allows(method: "GET", error: URLError(.networkConnectionLost), userCancelled: false, connectionReplaced: false), "Safe GET must recover once at transport layer")
expect(!CampusTransportRetry.allows(method: "POST", error: URLError(.networkConnectionLost), userCancelled: false, connectionReplaced: false), "Writes must never replay automatically")
expect(!CampusTransportRetry.allows(method: "GET", error: URLError(.cancelled), userCancelled: true, connectionReplaced: true), "User cancellation must not retry")
expect(!CampusTransportRetry.allows(method: "GET", error: URLError(.serverCertificateUntrusted), userCancelled: false, connectionReplaced: false), "Certificate failure must not retry")
print("Campus routing/transport: recognized school responses, denial/captive rejection and safe-read-only recovery passed")

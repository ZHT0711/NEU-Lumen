// Only copied into the disposable simulator validation app. Synthetic mail and session only.
import Foundation
import WebKit

@MainActor
func verifyNativeMailReader(client: PortalClient, base: URL) async throws {
    let browser = PortalBrowser()
    let downloads = BrowserDownloadStore.shared
    downloads.activate(account: "native-mail-fixture")
    defer { browser.close() }
    let index = base.appendingPathComponent("dl/mail/coremail/XT/index.jsp")
    await browser.start(index, client: client)
    func require(_ condition: Bool, _ message: String) throws {
        if !condition { throw NetworkError(message: "Native mail WebKit: " + message) }
    }
    for _ in 0..<200 {
        if browser.title == "Native mail fixture", !browser.isLoading { break }
        try await Task.sleep(for: .milliseconds(50))
    }
    try require(browser.title == "Native mail fixture", "synthetic mail page loaded")
    let prologue = #"""
    let identityCalls=0;
    const fetch=async(input,init)=>{
        const url=new URL(input),func=url.searchParams.get('func');
        let value;
        if(func==='user:getAttrs')value={email:identityCalls++>=changeAfter?'other@stu.neu.edu.cn':'synth-a@stu.neu.edu.cn'};
        else if(url.pathname.endsWith('readMessage.jsp'))value={
            mail:{subject:'合成正文',from:'fixture@example.invalid',to:['synth-a@stu.neu.edu.cn'],
                content:'<p>合成邮件 &amp; 正文</p><img src="https://tracking.invalid/pixel"><a href="https://example.invalid/notice">合成通知</a><a href="javascript:alert(1)">不支持链接</a>',
                attachments:[{name:'synthetic-mail.bin',type:'internal',mid:'SYNTH-MAIL-1',part:'2',size:33}]},
            mailInfo:{sentDate:2000000000000,flags:{read:true}}};
        else throw new Error('unexpected synthetic operation');
        return {ok:true,url:url.href,json:async()=>({code:'S_OK',var:value})};
    };
    """#
    let world = WKContentWorld.world(name: "NEULumen.NativeMail")
    func call(_ command: String, changeAfter: Int = 99, name: String = "synthetic-mail.bin") async throws -> [String: Any] {
        let raw = try await browser.webView.callAsyncJavaScript(prologue + NativeMailProtocol.reader,
            arguments: ["rootURL": base.appendingPathComponent("dl/mail/coremail/").absoluteString,
                        "command": command, "expectedEmail": "synth-a@stu.neu.edu.cn", "expectedSID": "SYNTH-A",
                        "folderID": "1", "start": 0, "includeFolders": false, "messageID": "SYNTH-MAIL-1",
                        "searchText": "", "searchFields": [:], "messageIDs": [], "attributes": [:],
                        "composeKind": "normal", "attachmentID": "part:2:0", "attachmentName": name,
                        "changeAfter": changeAfter], in: nil, contentWorld: world)
        return raw as? [String: Any] ?? [:]
    }
    let read = try await call("read")
    let body = read["body"] as? [String: Any] ?? [:]
    try require((body["text"] as? String)?.contains("合成邮件 & 正文") == true, "real textarea entity decoding")
    try require((body["links"] as? [[String: Any]])?.count == 1, "only safe explicit body links are exposed")
    try require((body["recipients"] as? String) == "synth-a@stu.neu.edu.cn", "native recipient metadata")
    let attachments = body["attachments"] as? [[String: Any]] ?? []
    try require(attachments.first?["downloadable"] as? Bool == true, "verified internal attachment enables native download")
    try require(!String(describing: read).contains("SYNTH-MAIL-TOKEN-ONLY"), "native metadata never exposes session token")

    let before = Set(downloads.records.map(\.id))
    let mismatched = try await call("download", name: "changed.bin")
    try require(mismatched["error"] as? String == "format", "a changed attachment cannot be downloaded")
    let changedIdentity = try await call("download", changeAfter: 1)
    try require(changedIdentity["error"] as? String == "identity", "identity change blocks the download activation")
    try require(Set(downloads.records.map(\.id)) == before, "rejected attachment performs no transfer")
    let requested = try await call("download")
    try require(requested["downloadRequested"] as? Bool == true, "explicit native attachment action is dispatched")
    for _ in 0..<300 {
        if downloads.records.contains(where: { !before.contains($0.id) && ($0.state == .completed || $0.state == .failed) }) { break }
        try await Task.sleep(for: .milliseconds(50))
    }
    guard let record = downloads.records.first(where: { !before.contains($0.id) && $0.state == .completed }),
          let url = downloads.previewURL(for: record.id) else { throw NetworkError(message: "Native mail authenticated attachment did not finish") }
    let bytes = try Data(contentsOf: url)
    try require(bytes == Data("NEU-Lumen native mail attachment".utf8), "same-WebKit cookie/Referer download retains original bytes")
    print("PASS: native mail actual WebKit text, recipients, safe links, internal attachments, identity/stale metadata gates and authenticated WKDownload")
}

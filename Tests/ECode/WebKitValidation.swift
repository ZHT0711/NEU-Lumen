// Copied only into the disposable simulator validation app. All pixels and accounts are synthetic.
import Foundation
import WebKit

@MainActor
func verifyECodeDocument(browser: PortalBrowser, base: URL) async throws {
    let web = browser.webView
    let oldFrame = web.frame
    web.frame = CGRect(x: 0, y: 0, width: 390, height: 700)
    defer { web.frame = oldFrame }
    let world = WKContentWorld.world(name: "NEULumen.ECode")
    func require(_ condition: Bool, _ message: String) throws {
        if !condition { throw NetworkError(message: "ECode document: " + message) }
    }
    // A black/white test pattern, deliberately not a valid QR code or a credential.
    let paint = #"""
    window.syntheticDraw=offset=>{
      for(const canvas of document.querySelectorAll('canvas')) {
        const ctx=canvas.getContext('2d');ctx.fillStyle='#fff';ctx.fillRect(0,0,128,128);
        ctx.fillStyle='#000';
        for(let y=0;y<16;y++) for(let x=0;x<16;x++) if((x*3+y*5+offset)%7<3) ctx.fillRect(x*8,y*8,8,8);
      }
    };
    window.syntheticDraw(0);
    """#
    let code = #"<div id="qrcode"><canvas id="synthetic-code" width="128" height="128"></canvas></div>"#
    let identity = #"<p id="synthetic-identity">学号：SYNTH-A</p>"#
    func load(_ body: String, title: String = "e码通", draw: Bool = true) async throws {
        let marker = UUID().uuidString
        let html = "<!doctype html><meta charset=utf-8><title>" + title + "</title>" + body +
            "<script>" + (draw ? paint : "") + "window.syntheticEcodeReady='" + marker + "';</script>"
        web.loadHTMLString(html, baseURL: base.appendingPathComponent("ecode-document"))
        for _ in 0..<200 {
            if !web.isLoading,
               let ready = try? await web.evaluateJavaScript("window.syntheticEcodeReady==='" + marker + "'"),
               ready as? Bool == true { return }
            try await Task.sleep(for: .milliseconds(50))
        }
        throw NetworkError(message: "ECode synthetic document did not load")
    }
    func read(account: String = "SYNTH-A") async throws -> ECodeDocument {
        let raw = try await web.callAsyncJavaScript(ECodeDocument.reader,
            arguments: ["expectedAccount": account], in: nil, contentWorld: world)
        return try JSONDecoder().decode(ECodeDocument.self, from: JSONSerialization.data(withJSONObject: raw ?? [:]))
    }
    func rejects(_ message: String) async throws {
        let result = try await read()
        try require(result.state != "ready" && result.png == nil, message)
    }

    try await load(identity + code)
    var result = try await read()
    try require(result.state == "ready" && result.png?.hasPrefix("data:image/png;base64,") == true,
        "correct rendered account and visible canvas are read")
    try require(result.facts.contains(where: { $0.label == "学工号" && $0.value == "SYNTH-A" }), "rendered account is preserved")
    let original = result.png
    result = try await read(account: "SYNTH-B")
    try require(result.state == "account" && result.png == nil, "different current account never receives the code")

    // Replacing the school's live DOM must replace the pixels, without keeping the old code.
    _ = try await web.evaluateJavaScript(#"document.getElementById('qrcode').innerHTML='<canvas width="128" height="128"></canvas>';window.syntheticDraw(1);"#)
    result = try await read()
    try require(result.state == "ready" && result.png != original, "replaced school canvas produces the new image")
    _ = try await web.evaluateJavaScript("document.getElementById('synthetic-identity').textContent='学号：SYNTH-B'")
    result = try await read()
    try require(result.state == "account" && result.png == nil, "a school account change removes all code pixels")

    try await load(code)
    try await rejects("a code without a rendered account is not accepted")
    try await load(identity + "<p>工号：SYNTH-B</p>" + code)
    result = try await read()
    try require(result.state == "account" && result.png == nil, "all labeled account identifiers are checked")
    try await load(identity + code, title: "e码通 · 扫码登录")
    try await rejects("login QR page is not a campus code")
    try await load(identity + #"<div id="qrcode"><p>扫码登录</p><canvas width="128" height="128"></canvas></div>"#)
    try await rejects("a locally labeled login QR is not a campus code")
    try await load(identity + code + "<input type=password>")
    result = try await read()
    try require(result.state == "login" && result.png == nil, "visible authentication controls block code presentation")
    try await load(identity + code + "<input type=password hidden>")
    result = try await read()
    try require(result.state == "ready", "an inactive hidden login template does not hide the actual campus code")

    for attribute in ["style='display:none'", "style='opacity:0'", "aria-hidden='true'", "hidden"] {
        try await load(identity + "<section " + attribute + ">" + code + "</section>")
        try await rejects("hidden ancestor blocks code: " + attribute)
    }
    try await load(identity + code, draw: false)
    try await rejects("blank canvas is not a usable code")
    try await load(identity + #"<div id="qrcode"><canvas width="128" height="128"></canvas><div class="qrcode-mask" role="status">二维码已过期</div></div>"#)
    try await rejects("school expiry overlay blocks stale code")
    try await load(identity + #"<div id="qrcode"><canvas width="128" height="128"></canvas><div role="alert">校园码已失效，请刷新</div></div>"#)
    try await rejects("school invalidation status blocks stale code")
    try await load(identity + code + "<p>校园码已过期时请在学校页面刷新。</p>")
    result = try await read()
    try require(result.state == "ready", "unrelated help text outside the code container does not reject valid school pixels")
    try await load(identity + #"<div id="qrcode"><canvas width="128" height="128"></canvas><div class="qrcode-mask" style="opacity:0">二维码已过期</div></div>"#)
    result = try await read()
    try require(result.state == "ready", "an inactive invisible expiry overlay does not reject the current school code")
    print("PASS: ECode actual WebKit DOM, rendered identity/conflicts, code replacement, login QR, ancestor visibility, blank pixels and local expiry overlays")
}

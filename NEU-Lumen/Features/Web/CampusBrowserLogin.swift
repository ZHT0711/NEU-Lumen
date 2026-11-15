import WebKit

@MainActor
enum CampusBrowserLogin {
    static let world = WKContentWorld.world(name: "NEULumen.CampusLogin")

    static func checkForRejection(in webView: WKWebView, session: SessionStore, stillCurrent: () -> Bool) async {
        guard stillCurrent(), let url = webView.url, CampusCredentialBridge.isLoginURL(url) else { return }
        let epoch = session.requestEpoch
        let rejected = try? await webView.callAsyncJavaScript(CampusCredentialBridge.rejectionScript,
            arguments: [:], in: nil, contentWorld: world) as? Bool
        guard rejected == true, stillCurrent(), webView.url == url,
              session.requestEpoch == epoch, !Task.isCancelled else { return }
        session.pauseRejectedBrowserPasswordLogin()
    }

    /// Callers retain their own one-attempt limit and account/document lifetime.
    static func attempt(in webView: WKWebView, session: SessionStore, stillCurrent: () -> Bool) async {
        guard session.phase == .loggedIn, stillCurrent(), let url = webView.url,
              CampusCredentialBridge.canResume(url) else { return }
        let epoch = session.requestEpoch
        let document = PortalLoginDocument.decode(try? await webView.evaluateJavaScript(PortalLoginDocument.script))
        guard document.hasLoginForm, stillCurrent(), webView.url == url,
              session.requestEpoch == epoch, !Task.isCancelled,
              let saved = session.beginBrowserPasswordLogin() else { return }
        _ = try? await webView.callAsyncJavaScript(CampusCredentialBridge.autofillScript,
            arguments: ["username": saved.username, "password": saved.password],
            in: nil, contentWorld: world)
    }
}

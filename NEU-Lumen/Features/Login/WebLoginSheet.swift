import SwiftUI
import WebKit

/// 网页方式登录：在真实浏览器页面完成统一认证
/// （学校的 JS 风控、设备信任、短信二次认证全部由学校页面自己处理），
/// 成功抵达门户后把会话 Cookie 吸收回 App，等效于登录完成。
///
/// 使用一次性（nonPersistent）Cookie 存储：每次打开都是干净的认证页，
/// 不会被残留的旧票据带进自动跳转；登录失败时面板保持打开可重试。
struct WebLoginSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppEnvironment.self) private var environment
    @State private var preparing = true
    @State private var gatewayOverride: Bool?
    @State private var rememberCredentials: Bool
    var onCookies: (WebLoginSession) async -> Bool

    init(rememberCredentials: Bool = true, onCookies: @escaping (WebLoginSession) async -> Bool) {
        _rememberCredentials = State(initialValue: rememberCredentials)
        self.onCookies = onCookies
    }

    var body: some View {
        NavigationStack {
            WebLoginWebView(client: environment.session.client,
                            reuseSession: environment.session.phase == .loggedIn && environment.session.canAutomaticallySignIn,
                            rememberCredentials: rememberCredentials,
                            automaticCredentials: { environment.session.beginBrowserPasswordLogin() },
                            onPasswordRejected: { environment.session.pauseRejectedBrowserPasswordLogin() },
                            gatewayOverride: gatewayOverride, onPrepared: { preparing = false }) { session in
                let ok = await onCookies(session)
                if ok { dismiss() }
                // 失败时保持面板打开：页面内可重试，或左上角取消
                return ok
            }
            .id(gatewayOverride)
            .ignoresSafeArea(edges: .bottom)
            .overlay {
                if preparing {
                    ProgressView("正在选择校内 / 校外登录入口…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color(.systemBackground))
                }
            }
            .navigationTitle("统一身份认证")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu("登录入口", systemImage: "network") {
                        Button("自动检测") { changeRoute(nil) }
                        Button("校内直连") { changeRoute(false) }
                        Button("校外 WebVPN") { changeRoute(true) }
                    }
                }
            }
            .safeAreaInset(edge: .top) {
                Toggle(isOn: $rememberCredentials) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("本机自动登录").font(.subheadline)
                        Text("认证成功后将账号密码保存到钥匙串，会话过期时自动续登")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 16).padding(.vertical, 8)
                .background(.regularMaterial)
                if let error = environment.session.lastError {
                    Text(error)
                        .font(.caption2)
                        .foregroundStyle(.orange)
                        .lineLimit(2)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.ultraThinMaterial)
                }
            }
        }
    }

    private func changeRoute(_ gateway: Bool?) {
        guard gatewayOverride != gateway else { return }
        preparing = true
        gatewayOverride = gateway
    }
}

struct WebLoginWebView: UIViewRepresentable {
    let client: PortalClient
    var reuseSession: Bool
    var rememberCredentials: Bool
    var automaticCredentials: () -> CampusLoginCredentials?
    var onPasswordRejected: () -> Void
    var gatewayOverride: Bool?
    var onPrepared: () -> Void
    var onPortalLanding: (WebLoginSession) async -> Bool

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        // 一次性存储：每次网页登录从干净的认证页开始，避免残留票据引起瞬时跳转
        configuration.websiteDataStore = WKWebsiteDataStore.nonPersistent()
        context.coordinator.rememberCredentials = rememberCredentials
        context.coordinator.automaticCredentials = automaticCredentials
        context.coordinator.onPasswordRejected = onPasswordRejected
        configuration.userContentController.add(context.coordinator, contentWorld: Coordinator.credentialWorld,
                                                name: CampusCredentialBridge.handler)
        configuration.userContentController.addUserScript(WKUserScript(
            source: "window.__lumenRememberLogin = \(rememberCredentials ? "true" : "false");\n" + CampusCredentialBridge.script,
            injectionTime: .atDocumentStart, forMainFrameOnly: true, in: Coordinator.credentialWorld))
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.customUserAgent = client.browserUserAgent
        webView.navigationDelegate = context.coordinator
        context.coordinator.onPortalLanding = onPortalLanding
        context.coordinator.begin(webView, client: client, reuseSession: reuseSession, gatewayOverride: gatewayOverride, onPrepared: onPrepared)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        guard context.coordinator.rememberCredentials != rememberCredentials else { return }
        context.coordinator.rememberCredentials = rememberCredentials
        if !rememberCredentials { context.coordinator.credentials = nil }
        webView.configuration.userContentController.removeAllUserScripts()
        webView.configuration.userContentController.addUserScript(WKUserScript(
            source: "window.__lumenRememberLogin = \(rememberCredentials ? "true" : "false");\n" + CampusCredentialBridge.script,
            injectionTime: .atDocumentStart, forMainFrameOnly: true, in: Coordinator.credentialWorld))
        Task { @MainActor [weak webView] in
            _ = try? await webView?.callAsyncJavaScript("window.__lumenRememberLogin = enabled;",
                arguments: ["enabled": rememberCredentials], in: nil, contentWorld: Coordinator.credentialWorld)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        coordinator.captureTask?.cancel()
        coordinator.credentials = nil
        webView.configuration.userContentController.removeScriptMessageHandler(forName: CampusCredentialBridge.handler,
                                                                               contentWorld: Coordinator.credentialWorld)
        webView.navigationDelegate = nil
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        static let credentialWorld = WKContentWorld.world(name: "NEULumen.CampusLogin")
        var rememberCredentials = true
        var credentials: CampusLoginCredentials?
        var automaticCredentials: (() -> CampusLoginCredentials?)?
        var onPasswordRejected: (() -> Void)?
        private var attemptedAutomaticLogin = false
        var onPortalLanding: ((WebLoginSession) async -> Bool)?
        var captureTask: Task<Void, Never>?
        private var flow = PortalLoginFlow()
        private var gatewayFirst = false
        private var completed = false
        private var capturing = false

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard rememberCredentials, !completed, message.name == CampusCredentialBridge.handler,
                  message.frameInfo.isMainFrame, message.frameInfo.securityOrigin.host == "pass.neu.edu.cn",
                  let url = message.frameInfo.request.url, CampusCredentialBridge.isLoginURL(url),
                  let value = message.body as? [String: Any],
                  let username = value["username"] as? String, let password = value["password"] as? String else { return }
            credentials = CampusLoginCredentials(username: username, password: password)
        }

        func begin(_ webView: WKWebView, client: PortalClient, reuseSession: Bool, gatewayOverride: Bool?, onPrepared: @escaping () -> Void) {
            captureTask = Task { @MainActor [weak self, weak webView] in
                let entry: URL
                if let gatewayOverride { entry = gatewayOverride ? URL(string: WebVPN.casService)! : CasCrypto.casLoginURL }
                else { entry = await client.browserLoginEntryURL() }
                guard !Task.isCancelled, let self, let webView else { return }
                self.gatewayFirst = WebVPN.isWrapped(entry.absoluteString)
                self.flow = PortalLoginFlow(gatewayFirst: self.gatewayFirst)
                if reuseSession {
                    for cookie in client.browserCookies() { await webView.configuration.websiteDataStore.httpCookieStore.setCookie(cookie) }
                }
                guard !Task.isCancelled else { return }
                onPrepared()
                webView.load(URLRequest(url: entry))
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            guard !completed, !capturing, onPortalLanding != nil else { return }
            capturing = true
            captureTask = Task { @MainActor [weak self, weak webView] in
                guard let self, let webView else { return }
                defer { self.capturing = false }
                let initial = await self.readDocument(webView)
                guard !Task.isCancelled, let url = webView.url else { return }
                switch self.flow.action(for: url, hasLoginForm: initial.hasLoginForm) {
                case .wait:
                    if self.attemptedAutomaticLogin, CampusCredentialBridge.isLoginURL(url) {
                        let rejected = try? await webView.callAsyncJavaScript(CampusCredentialBridge.rejectionScript,
                            arguments: [:], in: nil, contentWorld: Self.credentialWorld) as? Bool
                        if rejected == true, webView.url == url, !Task.isCancelled { self.onPasswordRejected?() }
                    }
                    if initial.hasLoginForm, self.rememberCredentials, !self.attemptedAutomaticLogin,
                       CampusCredentialBridge.canResume(url), let saved = self.automaticCredentials?() {
                        self.attemptedAutomaticLogin = true
                        _ = try? await webView.callAsyncJavaScript(CampusCredentialBridge.autofillScript,
                            arguments: ["username": saved.username, "password": saved.password],
                            in: nil, contentWorld: Self.credentialWorld)
                    }
                    return
                case .navigate(let destination):
                    webView.load(URLRequest(url: destination))
                case .capture:
                    await self.capture(webView, initial: initial)
                }
            }
        }

        private func readDocument(_ webView: WKWebView) async -> PortalLoginDocument {
            PortalLoginDocument.decode(try? await webView.evaluateJavaScript(PortalLoginDocument.script))
        }

        private func capture(_ webView: WKWebView, initial: PortalLoginDocument) async {
            var user = initial.user
            for _ in 0..<6 {
                guard !Task.isCancelled else { return }
                guard let url = webView.url, PortalLoginFlow.isPersonalPortal(url) else { break }
                let document = await readDocument(webView)
                guard !document.hasLoginForm else { return }
                if let next = document.user { user = user?.merging(next) ?? next }
                if user?.hasCoreProfile == true { break }
                try? await Task.sleep(nanoseconds: 700_000_000)
            }
            guard !Task.isCancelled, let url = webView.url,
                  ["personal.neu.edu.cn", "webvpn.neu.edu.cn", "portal.neu.edu.cn"].contains(url.host ?? "") else { return }
            let current = await readDocument(webView)
            let cookies = await webView.configuration.websiteDataStore.httpCookieStore.allCookies()
            guard PortalLoginDocument.canComplete(user: user, cookies: cookies, hasLoginForm: current.hasLoginForm) else { return }
            let agent = (try? await webView.evaluateJavaScript("navigator.userAgent")) as? String ?? ""
            guard !Task.isCancelled, let handler = onPortalLanding else { return }
            completed = await handler(WebLoginSession(cookies: cookies, user: user, userAgent: agent,
                                                      hasLoginForm: current.hasLoginForm,
                                                      credentials: rememberCredentials ? credentials : nil,
                                                      rememberCredentials: rememberCredentials))
            if completed { credentials = nil }
            if !completed { flow = PortalLoginFlow(gatewayFirst: gatewayFirst) }
        }

    }
}

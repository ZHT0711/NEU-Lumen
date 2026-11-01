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
    var onCookies: (WebLoginSession) async -> Bool

    var body: some View {
        NavigationStack {
            WebLoginWebView { session in
                let ok = await onCookies(session)
                if ok { dismiss() }
                // 失败时保持面板打开：页面内可重试，或左上角取消
                return ok
            }
            .ignoresSafeArea(edges: .bottom)
            .navigationTitle("统一身份认证")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
            .safeAreaInset(edge: .top) {
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
}

struct WebLoginWebView: UIViewRepresentable {
    var onPortalLanding: (WebLoginSession) async -> Bool

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        // 一次性存储：每次网页登录从干净的认证页开始，避免残留票据引起瞬时跳转
        configuration.websiteDataStore = WKWebsiteDataStore.nonPersistent()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        context.coordinator.onPortalLanding = onPortalLanding
        webView.load(URLRequest(url: CasCrypto.casLoginURL))
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        coordinator.captureTask?.cancel()
        webView.navigationDelegate = nil
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate {
        var onPortalLanding: ((WebLoginSession) async -> Bool)?
        var captureTask: Task<Void, Never>?
        private var flow = PortalLoginFlow()
        private var completed = false
        private var capturing = false

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            guard !completed, !capturing, onPortalLanding != nil, let url = webView.url else { return }
            switch flow.action(for: url) {
            case .wait:
                return
            case .navigate(let destination):
                webView.load(URLRequest(url: destination))
            case .capture:
                capture(webView)
            }
        }

        private func capture(_ webView: WKWebView) {
            capturing = true
            captureTask = Task { @MainActor [weak self, weak webView] in
                guard let self, let webView else { return }
                defer { self.capturing = false }
                var user: PortalUser?
                // SPA 会先提供不完整 DSL；必须 await，并继续合并后续非空字段。
                for _ in 0..<6 {
                    guard !Task.isCancelled else { return }
                    guard let url = webView.url, PortalLoginFlow.isPersonalPortal(url) else { break }
                    if let raw = try? await webView.evaluateJavaScript("JSON.stringify(window.userInfoDSL || {})") as? String,
                       let next = PortalUser.fromBrowserJSON(raw) {
                        user = user?.merging(next) ?? next
                        if user?.hasCoreProfile == true { break }
                    }
                    try? await Task.sleep(nanoseconds: 700_000_000)
                }
                guard !Task.isCancelled, let url = webView.url,
                      ["personal.neu.edu.cn", "webvpn.neu.edu.cn", "portal.neu.edu.cn"].contains(url.host ?? "") else { return }
                // 在门户加载完成后再收 Cookie，保留代理路径上的 SESS_ID。
                let cookies = await webView.configuration.websiteDataStore.httpCookieStore.allCookies()
                let agent = (try? await webView.evaluateJavaScript("navigator.userAgent")) as? String ?? ""
                guard !Task.isCancelled, let handler = self.onPortalLanding else { return }
                self.completed = await handler(WebLoginSession(cookies: cookies, user: user, userAgent: agent))
                if !self.completed { self.flow = PortalLoginFlow() }
            }
        }
    }
}

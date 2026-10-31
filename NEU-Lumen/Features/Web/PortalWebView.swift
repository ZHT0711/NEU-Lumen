import SwiftUI
import WebKit

/// 应用内浏览器页：注入 CAS 会话 Cookie，各业务系统 SSO 免登录直达。
struct PortalWebViewScreen: View {
    let url: URL
    @Environment(AppEnvironment.self) private var environment
    @State private var progress: Double = 0
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(spacing: 0) {
            if progress > 0.01 && progress < 0.99 {
                ProgressView(value: progress)
                    .progressViewStyle(.linear)
                    .frame(height: 2)
            }
            PortalWebView(
                url: url,
                cookies: environment.session.client.cookieSnapshot(),
                progress: $progress
            )
        }
        .background(Color(.systemBackground))
        .ignoresSafeArea(edges: .bottom)
        .navigationTitle(url.host ?? "校园网页")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    openURL(url)
                } label: {
                    Image(systemName: "arrow.up.forward.app")
                }
            }
        }
    }
}

struct PortalWebView: UIViewRepresentable {
    let url: URL
    let cookies: [String: [String: String]]
    @Binding var progress: Double

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = WKWebsiteDataStore.default()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        context.coordinator.observe(webView, progress: $progress)

        let snapshot = cookies
        Task { @MainActor in
            await Self.injectCookies(snapshot, into: webView)
            webView.load(URLRequest(url: url))
        }
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    /// 把会话快照写入 WKHTTPCookieStore（跳过已存在的同名同值 Cookie）。
    @MainActor
    static func injectCookies(_ snapshot: [String: [String: String]], into webView: WKWebView) async {
        let store = webView.configuration.websiteDataStore.httpCookieStore
        let existing = await store.allCookies()
        for (domain, map) in snapshot {
            for (name, value) in map {
                let duplicated = existing.contains {
                    $0.domain == domain && $0.name == name && $0.value == value
                }
                guard !duplicated,
                      let cookie = HTTPCookie(properties: [
                          .domain: domain,
                          .path: "/",
                          .name: name,
                          .value: value,
                      ]) else { continue }
                await store.setCookie(cookie)
            }
        }
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate {
        private var observation: NSKeyValueObservation?
        private var progressBinding: Binding<Double>?

        func observe(_ webView: WKWebView, progress: Binding<Double>) {
            progressBinding = progress
            observation = webView.observe(\.estimatedProgress, options: [.new]) { [weak self] web, _ in
                self?.progressBinding?.wrappedValue = web.estimatedProgress
            }
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
            .allow
        }
    }
}

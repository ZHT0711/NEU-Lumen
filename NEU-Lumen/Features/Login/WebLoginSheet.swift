import SwiftUI
import WebKit

/// 网页方式登录：在真实浏览器页面完成统一认证
/// （学校的 JS 风控、设备信任、短信二次认证全部由学校页面自己处理），
/// 成功抵达门户后把会话 Cookie 吸收回 App，等效于登录完成。
struct WebLoginSheet: View {
    @Environment(\.dismiss) private var dismiss
    var onCookies: ([HTTPCookie]) -> Void

    var body: some View {
        NavigationStack {
            WebLoginWebView(onPortalLanding: { cookies in
                onCookies(cookies)
                dismiss()
            })
            .ignoresSafeArea(edges: .bottom)
            .navigationTitle("统一身份认证")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
        }
    }
}

struct WebLoginWebView: UIViewRepresentable {
    var onPortalLanding: ([HTTPCookie]) -> Void

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = WKWebsiteDataStore.default()
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

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate {
        var onPortalLanding: (([HTTPCookie]) -> Void)?
        private var completed = false

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            guard !completed, onPortalLanding != nil else { return }
            guard let host = webView.url?.host?.lowercased() else { return }
            // 两种成功/半成功落地都收会话：
            // - personal：直连门户成功；
            // - webvpn：校外门户被学校重定向进网关（CAS 已成功，CASTGC 已到手，
            //   由 SessionStore 换网关票据后经网关完成登录），不要停在网关拦截页。
            let landedPortal = host == "personal.neu.edu.cn"
            let landedWebVPN = host == "webvpn.neu.edu.cn"
            guard landedPortal || landedWebVPN else { return }
            completed = true
            let store = webView.configuration.websiteDataStore.httpCookieStore
            store.getAllCookies { [weak self] cookies in
                Task { @MainActor in
                    self?.onPortalLanding?(cookies)
                    self?.onPortalLanding = nil
                }
            }
        }
    }
}

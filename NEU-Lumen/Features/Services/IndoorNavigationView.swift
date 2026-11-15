import SwiftUI
import WebKit
import Observation

/// Pathly owns the floor plans and routing. Keep its website in a separate WebKit session.
struct IndoorNavigationView: View {
    var destination = ""
    @Environment(\.openURL) private var openURL
    @State private var browser = IndoorNavigationBrowser()
    @State private var copied = false

    private var room: String { destination.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        VStack(spacing: 0) {
            if !room.isEmpty {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("课程地点").font(.caption).foregroundStyle(.secondary)
                        Text(room).font(.subheadline.weight(.medium)).textSelection(.enabled)
                    }
                    Spacer(minLength: 8)
                    Button(copied ? "已复制" : "复制地点", systemImage: copied ? "checkmark" : "doc.on.doc") {
                        UIPasteboard.general.string = room
                        copied = true
                    }.font(.subheadline)
                }.padding(16).background(Color(.secondarySystemBackground))
            }
            HStack(spacing: 6) {
                Label("Pathly · 楼内导航", systemImage: "point.topleft.down.curvedto.point.bottomright.up")
                Spacer()
                Text("pathly.top")
            }
            .font(.caption).foregroundStyle(.secondary)
            .padding(.horizontal, 16).padding(.vertical, 10)
            if browser.loading { ProgressView().frame(maxWidth: .infinity).padding(.bottom, 6) }
            IndoorNavigationWebView(browser: browser)
                .overlay {
                    if let error = browser.error {
                        ErrorStateView(message: error, retryTitle: "重新加载") { browser.reload() }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(.regularMaterial)
                    }
                }
            HStack {
                Button("后退", systemImage: "chevron.left") { browser.webView.goBack() }
                    .disabled(!browser.canGoBack)
                Spacer()
                Button("前进", systemImage: "chevron.right") { browser.webView.goForward() }
                    .disabled(!browser.canGoForward)
                Spacer()
                Button("刷新", systemImage: "arrow.clockwise") { browser.reload() }
                Spacer()
                Button("浏览器打开", systemImage: "safari") { openURL(browser.webView.url ?? IndoorNavigationBrowser.home) }
            }
            .labelStyle(.iconOnly).padding(16).background(.bar)
        }
        .navigationTitle("楼内导航")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .onAppear { browser.start() }
        .onDisappear { browser.webView.stopLoading() }
    }
}

@MainActor @Observable
final class IndoorNavigationBrowser: NSObject, WKNavigationDelegate, WKUIDelegate {
    static let home = URL(string: "https://pathly.top/user/user-path")!
    let webView: WKWebView
    private(set) var loading = false
    private(set) var canGoBack = false
    private(set) var canGoForward = false
    private(set) var error: String?
    @ObservationIgnored private var observations: [NSKeyValueObservation] = []

    override init() {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init()
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        observations = [
            webView.observe(\.isLoading) { [weak self] _, _ in Task { @MainActor in self?.updateState() } },
            webView.observe(\.canGoBack) { [weak self] _, _ in Task { @MainActor in self?.updateState() } },
            webView.observe(\.canGoForward) { [weak self] _, _ in Task { @MainActor in self?.updateState() } }
        ]
    }

    func start() {
        guard webView.url == nil else { return }
        webView.load(URLRequest(url: Self.home))
    }

    func reload() {
        error = nil
        if webView.url == nil { start() } else { webView.reload() }
    }

    private func updateState() {
        loading = webView.isLoading
        canGoBack = webView.canGoBack
        canGoForward = webView.canGoForward
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) { error = nil }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { updateState() }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError failure: Error) { report(failure) }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError failure: Error) { report(failure) }

    private func report(_ failure: Error) {
        guard (failure as NSError).code != NSURLErrorCancelled else { return }
        error = "楼内导航暂时无法加载，请检查网络后重试。"
        updateState()
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) { error = "导航页面已停止，请重新加载。" }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url else { decisionHandler(.cancel); return }
        if url.scheme == "https" || url.scheme == "http" { decisionHandler(.allow) }
        else if navigationAction.navigationType == .linkActivated {
            UIApplication.shared.open(url)
            decisionHandler(.cancel)
        } else { decisionHandler(.cancel) }
    }

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if navigationAction.targetFrame == nil, let url = navigationAction.request.url,
           ["https", "http"].contains(url.scheme ?? "") { webView.load(navigationAction.request) }
        return nil
    }
}

private struct IndoorNavigationWebView: UIViewRepresentable {
    let browser: IndoorNavigationBrowser
    func makeUIView(context: Context) -> WKWebView { browser.webView }
    func updateUIView(_ view: WKWebView, context: Context) {}
}

import SwiftUI
import WebKit
import Observation

/// 独立、临时网页同步窗口；不把网页壳描述为完整原生培养计划。
struct AcademicWebSyncSheet: View {
    static let entryURL = URL(string: PortalClient.jwxtBase + "/jwapp/sys/homeapp/index.do")!
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss
    @State private var browser = AcademicReadOnlyBrowser()
    @State private var syncError: String?
    @State private var didSync = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                AcademicNotice(text: "正常认证后，手动进入获准的培养 / 学业课程表。同步只解析当前可见表格；不点击选课、报名、翻页或提交。此窗口 Cookie 不回写应用。")
                    .padding(12)
                if browser.loading { ProgressView().padding(.bottom, 8) }
                if let message = syncError ?? browser.error {
                    Text(message).font(.footnote).foregroundStyle(.red).padding(12)
                        .accessibilityLabel("同步错误：\(message)")
                }
                if didSync { Text("已同步当前课程表到原生页面").font(.footnote).foregroundStyle(.secondary).padding(8) }
                AcademicWebCanvas(browser: browser)
                HStack {
                    Button("后退", systemImage: "chevron.left") { browser.webView.goBack() }.disabled(!browser.canGoBack)
                    Spacer()
                    Button("重新加载", systemImage: "arrow.clockwise") { browser.webView.reload() }
                }.padding(12)
            }
            .navigationTitle("教务只读网页同步").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("关闭") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("同步当前课程表") {
                        Task {
                            syncError = nil; didSync = false
                            do {
                                let (snapshot, context) = try await browser.readCurrentPage(session: environment.session, repo: environment.repository)
                                try environment.repository.applyAcademicPageSnapshot(snapshot, context: context)
                                didSync = true
                            } catch {
                                if !NetworkError.isCancellation(error) { syncError = NetworkError.from(error).message }
                            }
                        }
                    }.disabled(browser.loading || browser.syncing || browser.context == nil)
                }
            }
        }
        .task(id: environment.session.requestEpoch) {
            await browser.start(session: environment.session, repo: environment.repository)
        }
        .onChange(of: environment.session.requestEpoch) { _, epoch in
            if browser.context?.epoch != epoch { browser.close() }
        }
        .onDisappear { browser.close() }
    }
}

private struct AcademicWebCanvas: UIViewRepresentable {
    let browser: AcademicReadOnlyBrowser
    func makeUIView(context: Context) -> WKWebView { browser.webView }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}

@MainActor
@Observable
final class AcademicReadOnlyBrowser: NSObject, WKNavigationDelegate, WKUIDelegate {
    let webView: WKWebView
    /// Independent JS globals, same WebKit cookies and DOM. Page scripts cannot
    /// replace the identity fetch/JSON used by the reader.
    static let readerWorld = WKContentWorld.world(name: "NEULumen.AcademicReader")
    private(set) var loading = false
    private(set) var syncing = false
    private(set) var canGoBack = false
    private(set) var error: String?
    private(set) var context: RepositoryRequestContext?
    private weak var session: SessionStore?
    private weak var client: PortalClient?
    private var clientEpoch: UUID?
    private var active = false
    private var browserGeneration = UUID()
    private var pageGeneration = UUID()
    private var syncRequest: UUID?

    override init() {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        config.userContentController.addUserScript(WKUserScript(source: AcademicPageReader.readOnlyPageGuard,
            injectionTime: .atDocumentStart, forMainFrameOnly: false))
        config.defaultWebpagePreferences.preferredContentMode = .mobile
        webView = WKWebView(frame: .zero, configuration: config)
        super.init()
        webView.navigationDelegate = self; webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = true
    }

    func start(session: SessionStore, repo: PortalRepository) async {
        if active {
            if valid(session: session, repo: repo) { return }
            close()
        }
        let epoch = session.requestEpoch
        await repo.ensureLoadedForCurrentUser()
        guard epoch == session.requestEpoch, !Task.isCancelled else { return }
        guard let scope = repo.academicRequestContext, session.user?.sid == scope.account else {
            error = "尚未确认当前学号，请先在应用内完成正常认证"; return
        }
        let generation = UUID()
        browserGeneration = generation
        self.session = session; client = session.client; clientEpoch = session.client.sessionGeneration
        context = scope; active = true; loading = true; error = nil
        let url = await session.client.prepareBrowserURL(AcademicWebSyncSheet.entryURL)
        guard browserGeneration == generation else { return }
        guard valid(session: session, repo: repo), !Task.isCancelled else { close(); return }
        webView.customUserAgent = session.client.browserUserAgent ?? HTTPClient.userAgent
        // A reused sheet must not keep cookies from its previous temporary login.
        let store = webView.configuration.websiteDataStore.httpCookieStore
        let previous = await store.allCookies()
        for cookie in previous {
            guard browserGeneration == generation else { return }
            guard valid(session: session, repo: repo), !Task.isCancelled else { close(); return }
            await store.deleteCookie(cookie)
        }
        // 单向复制当前账号 Cookie；不会吸收网页可能切换到的其他账号。
        for cookie in session.client.browserCookies() {
            guard browserGeneration == generation else { return }
            guard valid(session: session, repo: repo), !Task.isCancelled else { close(); return }
            await store.setCookie(cookie)
        }
        guard browserGeneration == generation else { return }
        guard valid(session: session, repo: repo), !Task.isCancelled else { close(); return }
        webView.load(URLRequest(url: url))
    }

    private func valid(session: SessionStore, repo: PortalRepository) -> Bool {
        active && session.phase == .loggedIn && context == repo.academicRequestContext
            && context?.account == session.user?.sid && clientEpoch == session.client.sessionGeneration
    }

    func readCurrentPage(session: SessionStore, repo: PortalRepository) async throws -> (AcademicPageSnapshot, RepositoryRequestContext) {
        guard valid(session: session, repo: repo), let context, let current = webView.url, !loading, !syncing else {
            throw AcademicQueryError.accountMismatch
        }
        let original = WebVPN.unwrap(current) ?? current
        guard original.host?.lowercased() == "jwxt.neu.edu.cn", original.path.contains("/jwapp/") else {
            throw AcademicQueryError.invalid("当前教务页面")
        }
        let originalRoot = URL(string: "/jwapp/sys/homeapp/", relativeTo: original)!.absoluteURL
        let root = WebVPN.isWrapped(current.absoluteString) ? WebVPN.wrap(originalRoot.absoluteString) : originalRoot.absoluteString
        let generation = browserGeneration, page = pageGeneration, request = UUID()
        syncRequest = request; syncing = true
        defer { if syncRequest == request { syncRequest = nil; syncing = false } }
        let raw = try await webView.callAsyncJavaScript(AcademicPageReader.browserScript,
            arguments: ["rootURL": root, "expectedAccount": context.account], in: nil, contentWorld: Self.readerWorld)
        try Task.checkCancellation()
        guard browserGeneration == generation, pageGeneration == page, syncRequest == request,
              !loading, valid(session: session, repo: repo), webView.url == current else {
            throw AcademicQueryError.accountMismatch
        }
        return (try AcademicPageReader.decode(raw ?? [:], expectedAccount: context.account, expectedSourceURL: current), context)
    }

    func close() {
        browserGeneration = UUID(); pageGeneration = UUID(); syncRequest = nil
        active = false; context = nil; loading = false; syncing = false
        webView.stopLoading(); client = nil; session = nil
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        pageGeneration = UUID(); loading = true; error = nil
    }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { loading = false; canGoBack = webView.canGoBack }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { show(error) }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { show(error) }
    private func show(_ failure: Error) {
        if NetworkError.isCancellation(failure) { return }
        loading = false; error = NetworkError.from(failure).message
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard active, let session, session.phase == .loggedIn, session.requestEpoch == context?.epoch,
              session.client.sessionGeneration == clientEpoch else { decisionHandler(.cancel); return }
        // 仅学校正常 GET 跳转沿用 WebVPN 路由；不重放 POST 或自动填表。
        if navigationAction.targetFrame?.isMainFrame != false,
           (navigationAction.request.httpMethod ?? "GET") == "GET", let url = navigationAction.request.url,
           let destination = client?.browserDestination(for: url), destination != url {
            var request = navigationAction.request; request.url = destination
            decisionHandler(.cancel); webView.load(request); return
        }
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if navigationAction.targetFrame == nil { webView.load(navigationAction.request) }
        return nil
    }
}

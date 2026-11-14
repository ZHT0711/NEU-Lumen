import SwiftUI
import WebKit
import Observation

/// 校园浏览器：保留网页当前地址、历史和会话，提供原生导航与页面工具。
struct PortalWebViewScreen: View {
    let url: URL
    var nativeService: NativeCampusService?
    var academicMode = false
    var cardMode = false
    var cgMode = false
    var learningPlatform: LearningPlatform?
    var cardQuery: String?
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.openURL) private var openURL
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var browser = PortalBrowser()
    @State private var syncError: String?
    @State private var isSyncingCard = false
    @State private var showPermissionsHelp = false
    @State private var showNativeDocument = true
    private var presentsNativeDocument: Bool {
        guard let nativeService, showNativeDocument, let current = browser.currentURL else { return false }
        let source = WebVPN.unwrap(current) ?? current
        return nativeService.owns(host: source.host?.lowercased() ?? "") &&
            !["/tologin.html", "/drCasLogin"].contains(source.path)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 7) {
                Image(systemName: browser.currentURL?.scheme == "https" ? "lock.fill" : "network")
                Text(browser.currentURL?.host ?? url.host ?? "校园网页")
                    .lineLimit(1).truncationMode(.middle)
                Spacer(minLength: 0)
                if browser.downloadCount > 0 {
                    Button { browser.showsDownloads = true } label: {
                        Label("\(browser.downloadCount) 个下载", systemImage: "arrow.down.circle")
                    }
                    .accessibilityLabel("正在下载，打开下载管理")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 16).padding(.vertical, 8)
            if browser.isLoading {
                ProgressView(value: browser.progress)
                    .tint(AppTheme.accent)
                    .frame(height: 2)
            }
            if let notice = browser.electricityPrefillNotice {
                Text(notice).font(.footnote).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16).padding(.vertical, 8)
                    .privacySensitive()
            }
            ZStack {
                PortalWebView(browser: browser)
                .id(ObjectIdentifier(browser.webView))
                .opacity(presentsNativeDocument ? 0 : 1)
                .allowsHitTesting(!presentsNativeDocument)
                .accessibilityHidden(presentsNativeDocument)
                if let nativeService, presentsNativeDocument {
                    NativeServiceDocumentView(browser: browser, service: nativeService) { showNativeDocument = false }
                }
            }
                .ignoresSafeArea(.container, edges: .bottom)
                .overlay {
                    if let error = browser.error {
                        ErrorStateView(message: error, retryTitle: "重新加载") { browser.reload() }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(.regularMaterial)
                    }
                }
        }
        .background(Color(.systemBackground))
        .navigationTitle(browser.title.isEmpty ? "校园网页" : browser.title)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .tabBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    if nativeService != nil && !showNativeDocument {
                        Button("原生表单与订单", systemImage: "rectangle.on.rectangle") {
                            showNativeDocument = true
                        }
                    }
                    Button("前进", systemImage: "chevron.right") { browser.webView.goForward() }
                        .disabled(!browser.canGoForward)
                    Button("在页面中查找", systemImage: "doc.text.magnifyingglass") {
                        browser.webView.findInteraction?.presentFindNavigator(showingReplace: false)
                    }
                    Menu {
                        ForEach([0.8, 1.0, 1.15, 1.3, 1.5], id: \.self) { zoom in
                            Button {
                                browser.zoom = zoom
                                browser.webView.pageZoom = zoom
                            } label: {
                                if browser.zoom == zoom { Label("\(Int(zoom * 100))%", systemImage: "checkmark") }
                                else { Text("\(Int(zoom * 100))%") }
                            }
                        }
                    } label: { Label("页面缩放", systemImage: "textformat.size") }
                    Button(browser.desktopMode ? "请求移动版网页" : "请求桌面版网页",
                           systemImage: browser.desktopMode ? "iphone" : "desktopcomputer") { browser.toggleDesktop() }
                    Button("复制当前链接", systemImage: "link") { UIPasteboard.general.url = browser.currentURL ?? url }
                    Button("在 Safari 中打开", systemImage: "safari") { openURL(browser.currentURL ?? url) }
                    Button("定位与网页权限", systemImage: "hand.raised") { showPermissionsHelp = true }
                    Button("下载管理", systemImage: "arrow.down.circle") { browser.showsDownloads = true }
                    Button(browser.isCurrentPDF ? "下载原始PDF" : "下载当前文件", systemImage: "arrow.down.doc") {
                        browser.downloadCurrentFile()
                    }.disabled(browser.isLoading)
                    if !browser.isCurrentPDF {
                        Button("导出网页为 PDF", systemImage: "doc.richtext") {
                            Task { await browser.exportPDF() }
                        }
                    }
                    Button("回到应用入口", systemImage: "house") { browser.goToEntry() }
                } label: { Image(systemName: "line.3.horizontal.decrease").foregroundStyle(.primary) }
                .accessibilityLabel("网页工具")
            }
            ToolbarItem(placement: .topBarLeading) {
                Button { dismiss() } label: { Image(systemName: "xmark").foregroundStyle(.primary) }
                    .accessibilityLabel("关闭网页")
            }
        }
        .overlay(alignment: .bottom) { floatingControls }
        .onPreferenceChange(BrowserControlsHeightKey.self) { height in
            Task { @MainActor in
                browser.webView.scrollView.contentInset.bottom = height + 12
                browser.webView.scrollView.verticalScrollIndicatorInsets.bottom = height + 12
            }
        }
        .sheet(isPresented: $browser.showsDownloads) {
            BrowserDownloadsView(store: BrowserDownloadStore.shared)
        }
        .alert("下载提示", isPresented: $browser.showsDownloadNotice) {
            Button("好", role: .cancel) {}
        } message: { Text(browser.downloadNotice) }
        .alert("定位与网页权限", isPresented: $showPermissionsHelp) {
            Button("打开系统设置") {
                if let settings = URL(string: UIApplication.openSettingsURLString) { openURL(settings) }
            }
            Button("好", role: .cancel) {}
        } message: {
            Text("网页使用定位、相机、麦克风或运动传感器时会请求授权。若已拒绝应用权限，可在系统设置中重新允许。校园乐跑请开启定位服务并允许精确位置，返回后刷新网页，再允许该网站使用位置。")
        }
        .task {
            await browser.start(url, client: environment.session.client, session: environment.session, service: nativeService)
            if let cardQuery {
                do { try await browser.openCardQuery(cardQuery) }
                catch { if !NetworkError.isCancellation(error) { syncError = NetworkError.from(error).message } }
            }
        }
        .onDisappear {
            browser.close()
            Task { await browser.saveSession() }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { Task { await browser.saveSession() } }
        }
        .onChange(of: environment.session.networkRevision) { _, _ in
            Task { await browser.recoverAfterNetworkChange() }
        }
    }

    private var floatingControls: some View {
        VStack(spacing: 10) {
            if let platform = learningPlatform {
                GlassCard(cornerRadius: 22) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(syncError ?? (platform == .mooc
                            ? "登录后可一键同步全部普通课程与学校 SPOC 的作业，无需逐门打开。"
                            : "登录后可一键同步全部课程的作业、任务点进度和课程截止日期。"))
                            .font(.caption).foregroundStyle(.secondary)
                        if platform == .mooc {
                            HStack {
                                Button("普通课程") { browser.webView.load(URLRequest(url: platform.entryURL)) }
                                Button("学校 SPOC") { browser.webView.load(URLRequest(url: URL(string: "https://www.icourse163.org/home.htm#/home/spocCourse")!)) }
                            }.font(.caption).disabled(browser.isSyncing)
                        }
                        Button(browser.isSyncing ? "正在读取全部课程…" : "同步全部课程到学习") {
                            Task {
                                syncError = nil
                                do {
                                    let report = try await browser.syncAssignments(platform, previous: environment.repository.assignmentReports[platform])
                                    environment.repository.applyAssignments(report, platform: platform)
                                    dismiss()
                                } catch {
                                    if !NetworkError.isCancellation(error) { syncError = NetworkError.from(error).message }
                                }
                            }
                        }.buttonStyle(.borderedProminent).disabled(browser.isLoading || browser.isSyncing)
                    }.padding(12)
                }
            }
            if cgMode {
                GlassCard(cornerRadius: 22) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(syncError ?? "在 CG 平台完成登录后，同步全部作业、截止日期与每题完成情况。")
                            .font(.caption).foregroundStyle(.secondary)
                        Button("同步作业到学习") {
                            Task {
                                syncError = nil
                                do {
                                    let report = try await browser.syncCGAssignments()
                                    environment.repository.applyCGReport(report)
                                    dismiss()
                                } catch {
                                    if !NetworkError.isCancellation(error) { syncError = NetworkError.from(error).message }
                                }
                            }
                        }.buttonStyle(.borderedProminent).disabled(browser.isLoading || browser.isSyncing)
                    }.padding(12)
                }
            }
            if cardMode {
                GlassCard(cornerRadius: 22) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(syncError ?? "完成一卡通认证后，同步真实余额与所选月份流水到应用。")
                            .font(.caption).foregroundStyle(.secondary)
                        Button("同步校园卡到应用") {
                            isSyncingCard = true
                            Task {
                                defer { isSyncingCard = false }
                                syncError = nil
                                let epoch = environment.session.client.sessionGeneration
                                do {
                                    let balance = try await browser.syncCardBalance()
                                    guard epoch == environment.session.client.sessionGeneration else { return }
                                    environment.repository.cardWebBridge.use(store: browser.webView.configuration.websiteDataStore,
                                        currentURL: browser.webView.url)
                                    environment.repository.applyCardBalance(balance)
                                    await environment.repository.loadBills(year: environment.repository.billsYear,
                                        month: environment.repository.billsMonth, force: true)
                                    guard epoch == environment.session.client.sessionGeneration else { return }
                                    dismiss()
                                } catch { syncError = NetworkError.from(error).message }
                            }
                        }.buttonStyle(.borderedProminent).disabled(browser.isLoading || browser.isSyncing || isSyncingCard)
                    }.padding(12)
                }
            }
            if academicMode {
                GlassCard(cornerRadius: 22) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(syncError ?? "进入教务学生首页后，将网页中的成绩同步到应用。")
                            .font(.caption).foregroundStyle(syncError == nil ? Color.secondary : Color.orange)
                        Button {
                            Task {
                                syncError = nil
                                do {
                                    let report = try await browser.syncGrades()
                                    environment.repository.applyGradeReport(report)
                                    dismiss()
                                } catch { syncError = NetworkError.from(error).message }
                            }
                        } label: {
                            HStack {
                                if browser.isSyncing { ProgressView().tint(.white) }
                                Text(browser.isSyncing ? "正在同步全部学期…" : "同步成绩到应用")
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(AppTheme.accent)
                        .disabled(browser.isSyncing || browser.isLoading)
                    }
                    .padding(12)
                }
            }
            browserDock
        }
        .padding(.horizontal, 22)
        .padding(.bottom, 12)
        .background {
            GeometryReader { geometry in
                Color.clear.preference(key: BrowserControlsHeightKey.self, value: geometry.size.height)
            }
        }
    }

    @ViewBuilder
    private var browserDock: some View {
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: 12) { dockButtons }
        } else {
            dockButtons
        }
    }

    /// 与参考图一致：独立返回圆钮 + 分享/停止或刷新/Safari 的短胶囊。
    private var dockButtons: some View {
        HStack(spacing: 16) {
            toolButton("后退", icon: "chevron.left", disabled: !browser.canGoBack) { browser.webView.goBack() }
                .padding(4)
                .modifier(BrowserCapsuleStyle())
            Spacer(minLength: 12)
            HStack(spacing: 6) {
                ShareLink(item: browser.currentURL ?? url) {
                    Image(systemName: "square.and.arrow.up")
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("分享当前网页")
                toolButton(browser.isLoading ? "停止" : "刷新", icon: browser.isLoading ? "xmark" : "arrow.clockwise") {
                    if browser.isLoading { browser.webView.stopLoading() } else { browser.reload() }
                }
                toolButton("在 Safari 中打开", icon: "safari") { openURL(browser.currentURL ?? url) }
            }
            .padding(.horizontal, 8)
            .frame(height: 52)
            .modifier(BrowserCapsuleStyle())
        }
        .font(.system(size: 22, weight: .regular))
        .foregroundStyle(.primary)
    }

    private func toolButton(_ title: String, icon: String, disabled: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: icon).frame(width: 44, height: 44) }
            .buttonStyle(.plain)
            .disabled(disabled)
            .opacity(disabled ? 0.3 : 1)
            .accessibilityLabel(title)
    }

}

private struct BrowserControlsHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

private struct BrowserCapsuleStyle: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
                .glassEffect(.regular.interactive(), in: Capsule())
        } else {
            content
                .background(.regularMaterial, in: Capsule())
                .overlay(Capsule().strokeBorder(Color.primary.opacity(0.08), lineWidth: 1))
                .shadow(color: .black.opacity(0.05), radius: 8, y: 3)
        }
    }
}

struct PortalWebView: UIViewRepresentable {
    let browser: PortalBrowser
    func makeUIView(context: Context) -> WKWebView { browser.webView }
    func updateUIView(_ view: WKWebView, context: Context) {}
}

struct BrowserSharedFile: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}

@MainActor
@Observable
final class PortalBrowser: NSObject, WKNavigationDelegate, WKUIDelegate, WKHTTPCookieStoreObserver {
    private(set) var webView: WKWebView
    var currentURL: URL?
    var title = ""
    var progress = 0.0
    var isLoading = false
    var canGoBack = false
    var canGoForward = false
    var error: String?
    var desktopMode = false
    var zoom = 1.0
    var isSyncing = false
    var showsDownloads = false
    var showsDownloadNotice = false
    var downloadNotice = ""
    private(set) var electricityPrefillNotice: String?
    var documentMIMEType: String?
    var isCurrentPDF: Bool { BrowserDownloadNames.isPDF(documentMIMEType) }
    var downloadCount: Int { BrowserDownloadStore.shared.activeCount }
    @ObservationIgnored private var observations: [NSKeyValueObservation] = []
    @ObservationIgnored private weak var client: PortalClient?
    @ObservationIgnored private weak var session: SessionStore?
    @ObservationIgnored private var learningPlatform: LearningPlatform?
    @ObservationIgnored private var cookieSaveTask: Task<Void, Never>?
    @ObservationIgnored private var clientEpoch: UUID?
    @ObservationIgnored private var entryURL: URL?
    @ObservationIgnored private var started = false
    @ObservationIgnored private var attemptedCGLogin = false
    @ObservationIgnored private var downloadScope: UUID?
    @ObservationIgnored private var downloadSessionEpoch: UUID?
    @ObservationIgnored private var pendingDocumentRequest: URLRequest?
    @ObservationIgnored private var documentRequest: URLRequest?
    @ObservationIgnored private var documentResponseURL: URL?
    @ObservationIgnored private var provisionalUnsafeMethod = false
    @ObservationIgnored private var documentUnsafeMethod = false
    @ObservationIgnored private var service: NativeCampusService?
    @ObservationIgnored private var electricityResume = false
    @ObservationIgnored private var electricityResumeAttempted = false
    @ObservationIgnored private var electricityPrefillTask: Task<Void, Never>?
    @ObservationIgnored private var electricityPrefillStatus = "unavailable"
    private static let electricityWorld = WKContentWorld.world(name: "NEULumen.ElectricityRoom")

    override init() {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        config.defaultWebpagePreferences.preferredContentMode = .mobile
        webView = WKWebView(frame: .zero, configuration: config)
        super.init()
        observeWebView()
    }

    private func observeWebView() {
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        webView.isFindInteractionEnabled = true
        webView.scrollView.keyboardDismissMode = .interactive
        observations = [
            webView.observe(\.estimatedProgress, options: [.new]) { [weak self] _, _ in
                Task { @MainActor [weak self] in self?.updateState() }
            },
            webView.observe(\.isLoading, options: [.new]) { [weak self] _, _ in
                Task { @MainActor [weak self] in self?.updateState() }
            },
            webView.observe(\.canGoBack, options: [.new]) { [weak self] _, _ in
                Task { @MainActor [weak self] in self?.updateState() }
            },
            webView.observe(\.canGoForward, options: [.new]) { [weak self] _, _ in
                Task { @MainActor [weak self] in self?.updateState() }
            },
            webView.observe(\.url, options: [.new]) { [weak self] _, _ in
                Task { @MainActor [weak self] in self?.updateState() }
            },
            webView.observe(\.title, options: [.new]) { [weak self] _, _ in
                Task { @MainActor [weak self] in self?.updateState() }
            },
        ]
    }

    private func useLearningProfile(_ identifier: UUID) {
        guard webView.configuration.websiteDataStore.identifier != identifier else { return }
        observations.removeAll()
        let previous = webView
        previous.stopLoading()
        previous.navigationDelegate = nil
        previous.uiDelegate = nil
        let configuration = previous.configuration
        configuration.websiteDataStore = WKWebsiteDataStore(forIdentifier: identifier)
        webView = WKWebView(frame: .zero, configuration: configuration)
        webView.scrollView.contentInset = previous.scrollView.contentInset
        webView.scrollView.verticalScrollIndicatorInsets = previous.scrollView.verticalScrollIndicatorInsets
        observeWebView()
    }

    func start(_ url: URL, client: PortalClient, session: SessionStore? = nil, service: NativeCampusService? = nil) async {
        guard !started else {
            webView.configuration.websiteDataStore.httpCookieStore.add(self)
            return
        }
        started = true
        self.client = client
        self.session = session
        let source = WebVPN.unwrap(url) ?? url
        electricityResume = CampusPaymentEntry.isElectricity(source)
        let service = service ?? (source.host?.lowercased() == "pay.neu.edu.cn" ? NativeCampusService.payment : nil)
        self.service = service
        if let session {
            guard session.phase == .loggedIn, let user = session.user else { return }
            BrowserDownloadStore.shared.activate(account: user.sid.isEmpty ? user.uid : user.sid, epoch: session.requestEpoch)
            downloadSessionEpoch = session.requestEpoch
        }
        downloadScope = BrowserDownloadStore.shared.scope
        learningPlatform = LearningPlatform.allCases.first { $0.accepts(WebVPN.unwrap(url) ?? url) }
        if let learningPlatform, let identifier = session?.learningBrowserIdentifier(for: learningPlatform) {
            useLearningProfile(identifier)
        } else if let service, let user = session?.user,
                  let identifier = LearningBrowserProfiles().identifier(account: user.sid.isEmpty ? user.uid : user.sid, service: service) {
            useLearningProfile(identifier)
        }
        Task { await session?.cleanRetiredLearningBrowsers() }
        session?.restoreLearningSession()
        clientEpoch = client.sessionGeneration
        webView.customUserAgent = client.browserUserAgent ?? HTTPClient.userAgent
        isLoading = true
        let destination = service == .payment ? source : await client.prepareBrowserURL(url)
        let store = webView.configuration.websiteDataStore.httpCookieStore
        if let learningPlatform, webView.configuration.websiteDataStore.isPersistent {
            let existing = await store.allCookies()
            guard !Task.isCancelled, client.sessionGeneration == clientEpoch else { return }
            // Durable WebKit cookies may have renewed after the last Keychain snapshot.
            client.absorbBrowserCookies(existing.filter(learningPlatform.ownsCookie))
            let saved = Set(existing.map(SavedWebSession.Cookie.init))
            for cookie in client.browserCookies() where learningPlatform.ownsCookie(cookie) {
                if !saved.contains(SavedWebSession.Cookie(cookie)) { await store.setCookie(cookie) }
            }
        } else if let service, webView.configuration.websiteDataStore.isPersistent {
            let existing = await store.allCookies()
            guard !Task.isCancelled, client.sessionGeneration == clientEpoch else { return }
            for cookie in client.browserCookies() {
                let host = cookie.domain.trimmingCharacters(in: CharacterSet(charactersIn: ".")).lowercased()
                let preserved = service.owns(host: host) && existing.contains {
                    $0.name == cookie.name && $0.domain == cookie.domain && $0.path == cookie.path
                }
                if !preserved { await store.setCookie(cookie) }
            }
        } else {
            for cookie in client.browserCookies() { await store.setCookie(cookie) }
        }
        guard !Task.isCancelled, client.sessionGeneration == clientEpoch else { return }
        store.add(self)
        entryURL = destination
        currentURL = destination
        if UIApplication.shared.applicationState == .background { webView.frame = CGRect(x: 0, y: 0, width: 390, height: 844) }
        webView.load(URLRequest(url: destination))
    }

    private func updateState() {
        currentURL = webView.url ?? entryURL
        title = webView.title ?? ""
        progress = webView.estimatedProgress
        isLoading = webView.isLoading
        canGoBack = webView.canGoBack
        canGoForward = webView.canGoForward
    }

    func reload() {
        error = nil
        if webView.url != nil { webView.reload() } else { goToEntry() }
    }

    /// Automatic consumers may only reload a completed, confirmed GET document.
    /// WebKit's generic reload can replay a school authentication or business POST.
    @discardableResult
    func reloadReadOnlyDocument() -> Bool {
        guard !isLoading, pendingDocumentRequest == nil,
              !documentUnsafeMethod, !provisionalUnsafeMethod,
              let request = documentRequest, (request.httpMethod ?? "GET").uppercased() == "GET",
              let current = webView.url, current == documentResponseURL,
              ["http", "https"].contains(current.scheme?.lowercased() ?? "") else { return false }
        reload()
        return true
    }

    func goToEntry() {
        guard let entryURL else { return }
        error = nil
        webView.load(URLRequest(url: entryURL))
    }

    func toggleDesktop() {
        desktopMode.toggle()
        webView.configuration.defaultWebpagePreferences.preferredContentMode = desktopMode ? .desktop : .mobile
        reload()
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 preferences: WKWebpagePreferences, decisionHandler: @escaping (WKNavigationActionPolicy, WKWebpagePreferences) -> Void) {
        preferences.preferredContentMode = desktopMode ? .desktop : .mobile
        guard let url = navigationAction.request.url else { decisionHandler(.cancel, preferences); return }
        // Gateway HTML rewrites most links; handle absolute links and popups that escape that rewriting.
        // Never replay a POST: WebKit may not expose its body, and reloading it could lose a login form.
        if navigationAction.targetFrame?.isMainFrame != false,
           (navigationAction.request.httpMethod ?? "GET") == "GET",
           let destination = routedDestination(url), destination != url {
            decisionHandler(.cancel, preferences)
            var request = navigationAction.request
            request.url = destination
            request.setValue(nil, forHTTPHeaderField: "Cookie")
            request.setValue(nil, forHTTPHeaderField: "Authorization")
            webView.load(request)
            return
        }
        let scheme = url.scheme?.lowercased() ?? ""
        if ["http", "https", "about", "blob", "data"].contains(scheme) {
            if navigationAction.targetFrame?.isMainFrame == true, !navigationAction.shouldPerformDownload {
                if pendingDocumentRequest == nil { provisionalUnsafeMethod = false }
                var request = navigationAction.request
                provisionalUnsafeMethod = provisionalUnsafeMethod || (request.httpMethod ?? "GET").uppercased() != "GET"
                if request.value(forHTTPHeaderField: "Referer") == nil,
                   let source = navigationAction.sourceFrame.request.url {
                    request.setValue(Self.downloadReferer(from: source, to: url), forHTTPHeaderField: "Referer")
                }
                pendingDocumentRequest = request
            }
            decisionHandler(navigationAction.shouldPerformDownload ? .download : .allow, preferences)
        } else {
            if ["tel", "mailto", "sms", "weixin", "alipay", "alipays"].contains(scheme) {
                UIApplication.shared.open(url)
            } else { error = "当前链接需要其他应用打开，可从菜单复制链接" }
            decisionHandler(.cancel, preferences)
        }
    }

    private func routedDestination(_ url: URL) -> URL? {
        if service == .payment {
            let source = WebVPN.unwrap(url) ?? url
            if ["pay.neu.edu.cn", "pass.neu.edu.cn"].contains(source.host?.lowercased() ?? "") { return source }
            return url
        }
        return client?.browserDestination(for: url)
    }

    func recoverAfterNetworkChange() async {
        guard let client, let session, session.phase == .loggedIn, session.requestEpoch == downloadSessionEpoch,
              client.sessionGeneration == clientEpoch, error != nil || isLoading,
              !documentUnsafeMethod, !provisionalUnsafeMethod else { return }
        if webView.url != nil {
            let dirty = try? await webView.callAsyncJavaScript(#"""
            return Array.from(document.querySelectorAll('input,textarea,select,[contenteditable=true]')).some(el=> {
                if (el.isContentEditable) return true;
                if (el.type==='hidden') return false;
                if (el.type==='checkbox'||el.type==='radio') return el.checked!==el.defaultChecked;
                if (el.tagName==='SELECT') {
                    const options=Array.from(el.options);
                    return options.some(o=>o.defaultSelected) || el.multiple
                        ? options.some(o=>o.selected!==o.defaultSelected) : el.selectedIndex!==options.findIndex(o=>!o.disabled);
                }
                return el.value!==el.defaultValue;
            });
            """#, arguments: [:], in: nil, contentWorld: .world(name: "NEULumen.NetworkRecovery")) as? Bool
            guard dirty == false else { return }
        }
        guard let current = currentURL ?? entryURL else { return }
        let epoch = session.requestEpoch
        let source = WebVPN.unwrap(current) ?? current
        let destination = service == .payment ? source : await client.prepareBrowserURL(source)
        guard session.requestEpoch == epoch, client.sessionGeneration == clientEpoch, !Task.isCancelled else { return }
        webView.stopLoading(); error = nil
        webView.load(URLRequest(url: destination))
    }

    func webView(_ webView: WKWebView, decidePolicyFor response: WKNavigationResponse) async -> WKNavigationResponsePolicy {
        let disposition = (response.response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Disposition") ?? ""
        let attachment = disposition.split(separator: ";", maxSplits: 1).first?
            .trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "attachment"
        if !response.canShowMIMEType || attachment { return .download }
        if response.isForMainFrame {
            documentMIMEType = BrowserDownloadNames.mime(response.response.mimeType)
            documentResponseURL = response.response.url
            documentRequest = pendingDocumentRequest
            documentUnsafeMethod = provisionalUnsafeMethod || pendingDocumentRequest == nil
        }
        return .allow
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        error = nil
        electricityPrefillTask?.cancel()
        electricityPrefillNotice = nil
    }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        pendingDocumentRequest = nil
        updateState()
        Task {
            await syncCookies()
            await resumeElectricityAfterLogin()
            await clickCampusUnifiedLoginIfNeeded()
            startElectricityPrefill()
        }
    }

    /// Reuses this account's saved query, including after the normal school login.
    /// Delayed form rendering is retried only while the same document and identity remain active.
    private func startElectricityPrefill() {
        electricityPrefillTask?.cancel()
        guard let session, session.phase == .loggedIn, let user = session.user,
              let url = webView.url, CampusPaymentEntry.isElectricity(url) else { return }
        let account = user.sid.isEmpty ? user.uid : user.sid
        let room = UserDefaults.standard.string(forKey: "lumen.electric.room." + account) ?? ""
        let epoch = session.requestEpoch
        electricityPrefillTask = Task { [weak self] in
            for _ in 0..<24 {
                guard let self, !Task.isCancelled, self.webView.url == url, session.requestEpoch == epoch else { return }
                await self.prefillElectricityRoom(room)
                if self.electricityPrefillStatus != "unavailable" { return }
                do { try await Task.sleep(for: .milliseconds(250)) } catch { return }
            }
        }
    }

    func prefillElectricityRoom(_ rawRoom: String) async {
        let room = ElectricRoomKey.normalize(rawRoom)
        guard ElectricRoomKey.isValid(room), let session, session.phase == .loggedIn, let user = session.user,
              session.requestEpoch == downloadSessionEpoch,
              let client, client.sessionGeneration == clientEpoch,
              let url = webView.url, url.user == nil, url.password == nil, url.port == nil || url.port == 443,
              CampusPaymentEntry.isElectricity(url) else { return }
        let account = user.sid.isEmpty ? user.uid : user.sid
        guard ElectricRoomKey.normalize(UserDefaults.standard.string(forKey: "lumen.electric.room." + account) ?? "") == room else { return }
        let epoch = session.requestEpoch
        let result = try? await webView.callAsyncJavaScript(ElectricityPaymentPrefill.script,
            arguments: ["room": room], in: nil, contentWorld: Self.electricityWorld) as? [String: Any]
        guard session.phase == .loggedIn, session.requestEpoch == epoch,
              client.sessionGeneration == clientEpoch, webView.url == url, !Task.isCancelled else { return }
        electricityPrefillStatus = result?["status"] as? String ?? "unavailable"
        switch electricityPrefillStatus {
        case "filled": electricityPrefillNotice = "已沿用查询房间码 \(room)，请核对房间后缴费。"
        case "kept": electricityPrefillNotice = "学校页面已有房间信息，请核对后缴费；本机查询房间码为 \(room)。"
        case "edited": electricityPrefillNotice = "已保留你修改的房间信息，请核对后缴费。"
        default: electricityPrefillNotice = "查询房间码 \(room)，请在学校表单核对房间。"
        }
    }

    private func resumeElectricityAfterLogin() async {
        guard electricityResume, !electricityResumeAttempted, let current = webView.url,
              let client, client.sessionGeneration == clientEpoch else { return }
        let source = WebVPN.unwrap(current) ?? current
        guard source.host == "pay.neu.edu.cn", ["/openPortal", "/openPortal/", "/portal.html", "/index.html", "/", "/openApplication"].contains(source.path) else { return }
        // The normal school CAS landing succeeded. Resume one verified read-only destination once.
        electricityResumeAttempted = true
        webView.load(URLRequest(url: CampusPaymentEntry.electricity))
    }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { show(error) }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { show(error) }
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) { error = "网页进程已停止，请重新加载" }

    private func show(_ failure: Error) {
        let nsError = failure as NSError
        // Attachment conversion is a navigation policy interruption, not a page-load failure.
        if nsError.code == NSURLErrorCancelled || (nsError.domain == "WebKitErrorDomain" && nsError.code == 102) { return }
        pendingDocumentRequest = nil
        error = NetworkError.from(failure).message
        isLoading = false
    }

    private func syncCookies() async {
        let cookies = await webView.configuration.websiteDataStore.httpCookieStore.allCookies()
        guard let client, client.sessionGeneration == clientEpoch else { return }
        if let learningPlatform {
            client.replaceLearningCookies(cookies, platform: learningPlatform)
            session?.persistLearningSession()
        } else { client.absorbBrowserCookies(cookies) }
    }

    /// At most one automatic sign-in attempt per browser, including redirect failures.
    private func clickCampusUnifiedLoginIfNeeded() async {
        guard !attemptedCGLogin, let current = webView.url,
              (WebVPN.unwrap(current) ?? current).host == "neucsecg.neu.edu.cn" else { return }
        attemptedCGLogin = true
        _ = try? await webView.callAsyncJavaScript(CGAssignmentReport.campusLoginScript,
            arguments: [:], in: nil, contentWorld: .page)
    }

    func cookiesDidChange(in cookieStore: WKHTTPCookieStore) {
        cookieSaveTask?.cancel()
        cookieSaveTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .milliseconds(250)) }
            catch { return }
            await self?.syncCookies()
        }
    }

    func close() {
        webView.stopLoading()
        electricityPrefillTask?.cancel()
        electricityPrefillTask = nil
        cookieSaveTask?.cancel()
        webView.configuration.websiteDataStore.httpCookieStore.remove(self)
        // BrowserDownloadStore, not this screen, owns ongoing WKDownload instances.
    }

    func saveSession() async {
        cookieSaveTask?.cancel()
        await syncCookies()
        session?.persistWebSession()
    }

    func syncCardBalance() async throws -> CardBalance {
        guard let client, client.sessionGeneration == clientEpoch, let current = webView.url else {
            throw NetworkError(message: "登录状态已更新，请关闭并重新打开一卡通网页后同步")
        }
        let original = WebVPN.unwrap(current) ?? current
        guard original.host == "ecard.neu.edu.cn" else {
            throw NetworkError(message: "请先完成认证并进入一卡通网页")
        }
        isSyncing = true
        defer { isSyncing = false }
        if let visible = try? await CardWebBridge.readBalance(in: webView, attempts: 1) {
            guard client.sessionGeneration == clientEpoch, !Task.isCancelled else { throw CancellationError() }
            await syncCookies()
            return visible
        }
        try Task.checkCancellation()
        let base = URL(string: PortalClient.cardHomePath, relativeTo: original)!.absoluteURL
        let target = WebVPN.isWrapped(current.absoluteString) ? URL(string: WebVPN.wrap(base.absoluteString))! : base
        let raw = try await webView.callAsyncJavaScript(#"""
        const response = await fetch(url, {credentials:'include'});
        if (!response.ok || response.url.includes('/tpass/login')) throw new Error('一卡通网页尚未完成认证');
        return await response.text();
        """#, arguments: ["url": target.absoluteString], in: nil, contentWorld: .page)
        guard client.sessionGeneration == clientEpoch, !Task.isCancelled else { throw CancellationError() }
        await syncCookies()
        if let balance = try? PortalClient.parseCardBalance(fromHTML: raw as? String ?? "") { return balance }
        var request = URLRequest(url: target)
        request.setValue(current.absoluteString, forHTTPHeaderField: "Referer")
        webView.load(request)
        let balance = try await CardWebBridge.readBalance(in: webView)
        guard client.sessionGeneration == clientEpoch, !Task.isCancelled else { throw CancellationError() }
        await syncCookies()
        return balance
    }

    func syncGrades() async throws -> GradeReport {
        let gatewayPrefixes = ["https://jwxt.neu.edu.cn/", "http://jwxt.neu.edu.cn/"].map { WebVPN.wrap($0) }
        guard let url = webView.url,
              url.host == "jwxt.neu.edu.cn" || gatewayPrefixes.contains(where: { url.absoluteString.hasPrefix($0) }) else {
            throw NetworkError(message: "请先完成认证，进入教务系统学生首页")
        }
        isSyncing = true
        defer { isSyncing = false }
        let raw = try await webView.callAsyncJavaScript(AcademicResponse.browserScript, arguments: [:], in: nil, contentWorld: .page)
        await syncCookies()
        return try AcademicResponse.browserReport(raw ?? [:])
    }

    func syncCGAssignments() async throws -> CGAssignmentReport {
        isSyncing = true
        defer { isSyncing = false }
        for _ in 0..<200 {
            try Task.checkCancellation()
            if webView.url != nil && !webView.isLoading { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        guard let client, client.sessionGeneration == clientEpoch, let current = webView.url else { throw CancellationError() }
        let original = WebVPN.unwrap(current) ?? current
        guard original.host == "neucsecg.neu.edu.cn" else {
            throw NetworkError(message: "请先打开 CG 实验平台并完成登录")
        }
        let direct = URL(string: "/assignment/", relativeTo: original)!.absoluteURL
        let root = WebVPN.isWrapped(current.absoluteString) ? URL(string: WebVPN.wrap(direct.absoluteString))! : direct
        let raw = try await webView.callAsyncJavaScript(CGAssignmentReport.browserScript,
            arguments: ["rootURL": root.absoluteString, "originalRootURL": direct.absoluteString], in: nil, contentWorld: .page)
        guard client.sessionGeneration == clientEpoch, !Task.isCancelled else { throw CancellationError() }
        let report = try CGAssignmentReport.decode(raw ?? [:])
        await syncCookies()
        return report
    }

    func syncAssignments(_ platform: LearningPlatform, previous: LearningAssignmentReport? = nil) async throws -> LearningAssignmentReport {
        isSyncing = true
        defer { isSyncing = false }
        for _ in 0..<200 {
            try Task.checkCancellation()
            if webView.url != nil && !webView.isLoading { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        guard let client, client.sessionGeneration == clientEpoch else { throw CancellationError() }
        guard let current = webView.url, platform.accepts(current) else {
            throw NetworkError(message: "请先进入\(platform.title)网页并完成登录")
        }
        let report = try await LearningWebReader(webView: webView).read(platform, previous: previous)
        guard client.sessionGeneration == clientEpoch, !Task.isCancelled else { throw CancellationError() }
        await syncCookies()
        return report
    }

    func openCardQuery(_ title: String) async throws {
        for _ in 0..<200 {
            try Task.checkCancellation()
            if !webView.isLoading, webView.url != nil {
                let found = try? await webView.callAsyncJavaScript(#"""
                const wanted = title.replace(/\s/g, '');
                function visit(doc, depth) {
                  if (!doc || depth > 4) return false;
                  for (const link of doc.querySelectorAll('a')) {
                    const name = link.textContent.replace(/\s/g, '').replace('检到卡', '捡到卡');
                    if (name === wanted) { link.click(); return true; }
                  }
                  for (const frame of doc.querySelectorAll('iframe,frame')) {
                    try { if (visit(frame.contentDocument, depth + 1)) return true; } catch (_) {}
                  }
                  return false;
                }
                return visit(document, 0);
                """#, arguments: ["title": title], in: nil, contentWorld: .page)
                if found as? Bool == true { return }
            }
            try await Task.sleep(for: .milliseconds(100))
        }
        throw NetworkError(message: "请完成一卡通认证后，在网页菜单中选择“\(title)”")
    }

    func exportPDF() async {
        guard let token = validDownloadScope() else { notifyDownload("登录状态已改变，请关闭并重新打开网页。"); return }
        guard !isCurrentPDF else { downloadCurrentFile(); return }
        do {
            let data = try await webView.pdf(configuration: WKPDFConfiguration())
            guard validDownloadScope() == token else { return }
            if BrowserDownloadStore.shared.saveWebpagePDF(data, title: title.isEmpty ? "网页导出" : title, scope: token) {
                showsDownloads = true
            } else { notifyDownload("PDF 保存失败，请在下载管理中查看存储提示。") }
        } catch { notifyDownload("PDF 导出失败，请等待网页加载完成后重试。") }
    }

    func downloadCurrentFile() {
        guard let token = validDownloadScope() else { notifyDownload("登录状态已改变，请关闭并重新打开网页。"); return }
        guard !webView.isLoading, let mime = documentMIMEType, !BrowserDownloadNames.isHTML(mime),
              let target = documentResponseURL, ["http", "https", "blob", "data"].contains(target.scheme?.lowercased() ?? "") else {
            notifyDownload("当前是普通网页或尚未识别到文件。网页请使用“导出网页为 PDF”，嵌入文档请先用网页中的原文件链接打开。"); return
        }
        guard !documentUnsafeMethod, let original = documentRequest,
              (original.httpMethod ?? "GET").uppercased() == "GET" else {
            notifyDownload("此文档来自 POST 提交或无法确认的请求，不能安全地改为 GET 重放。请返回原网页使用下载按钮；原网页的附件响应可直接保存，不会重新提交表单。"); return
        }
        // Keep the actual WebKit/gateway URL. Credentials stay in this WKWebsiteDataStore.
        // Do not copy Authorization, Cookie, Range or signed headers across redirects.
        var request = URLRequest(url: target)
        if let value = original.value(forHTTPHeaderField: "Referer"), let source = URL(string: value) {
            request.setValue(Self.downloadReferer(from: source, to: target), forHTTPHeaderField: "Referer")
        }
        BrowserDownloadStore.shared.start(request, in: webView, scope: token, requirePDF: isCurrentPDF)
        showsDownloads = true
    }

    private func validDownloadScope() -> UUID? {
        guard let downloadScope, BrowserDownloadStore.shared.accepts(downloadScope),
              client?.sessionGeneration == clientEpoch else { return nil }
        if let session {
            guard session.phase == .loggedIn, session.requestEpoch == downloadSessionEpoch,
                  let user = session.user else { return nil }
            let identity = user.sid.isEmpty ? user.uid : user.sid
            guard BrowserDownloadFiles.accountKey(identity.trimmingCharacters(in: .whitespacesAndNewlines)) == BrowserDownloadStore.shared.accountKey else { return nil }
        }
        return downloadScope
    }

    private func notifyDownload(_ text: String) {
        downloadNotice = text
        showsDownloadNotice = true
    }

    /// Same-origin Referer is preserved; cross-origin is origin-only, downgrade sends none.
    private static func downloadReferer(from source: URL, to target: URL) -> String? {
        guard ["http", "https"].contains(source.scheme?.lowercased() ?? ""),
              ["http", "https"].contains(target.scheme?.lowercased() ?? ""),
              !(source.scheme == "https" && target.scheme == "http"),
              var parts = URLComponents(url: source, resolvingAgainstBaseURL: false) else { return nil }
        parts.user = nil
        parts.password = nil
        parts.fragment = nil
        if source.scheme != target.scheme || source.host != target.host || source.port != target.port {
            parts.path = "/"
            parts.query = nil
        }
        return parts.url?.absoluteString
    }

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for action: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if action.targetFrame == nil { webView.load(action.request) }
        return nil
    }

    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) {
        guard let token = validDownloadScope() else { download.cancel(nil); return }
        BrowserDownloadStore.shared.adopt(download, from: webView, scope: token)
        pendingDocumentRequest = nil
    }
    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
        guard let token = validDownloadScope() else { download.cancel(nil); return }
        BrowserDownloadStore.shared.adopt(download, from: webView, scope: token,
            requirePDF: BrowserDownloadNames.isPDF(navigationResponse.response.mimeType))
        pendingDocumentRequest = nil
    }

    static func present(_ alert: UIAlertController, in webView: WKWebView, fallback: () -> Void) {
        guard UIApplication.shared.applicationState != .background else { fallback(); return }
        guard var controller = webView.window?.rootViewController else { fallback(); return }
        while let presented = controller.presentedViewController { controller = presented }
        guard !(controller is UIAlertController) else { fallback(); return }
        controller.present(alert, animated: true)
    }

    // 定位由 WebKit 按需发起系统与网站两层授权，Info.plist 提供使用期间定位说明。
    // 媒体和运动权限也交由 WebKit 显示来源明确的授权提示。
    func webView(_ webView: WKWebView, requestMediaCapturePermissionFor origin: WKSecurityOrigin,
                 initiatedByFrame frame: WKFrameInfo, type: WKMediaCaptureType,
                 decisionHandler: @escaping (WKPermissionDecision) -> Void) {
        decisionHandler(UIApplication.shared.applicationState == .background ? .deny : .prompt)
    }

    func webView(_ webView: WKWebView, requestDeviceOrientationAndMotionPermissionFor origin: WKSecurityOrigin,
                 initiatedByFrame frame: WKFrameInfo, decisionHandler: @escaping (WKPermissionDecision) -> Void) {
        decisionHandler(.prompt)
    }
    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
        let alert = UIAlertController(title: webView.url?.host, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "好", style: .default) { _ in completionHandler() })
        Self.present(alert, in: webView, fallback: completionHandler)
    }
    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
        let alert = UIAlertController(title: webView.url?.host, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "取消", style: .cancel) { _ in completionHandler(false) })
        alert.addAction(UIAlertAction(title: "确定", style: .default) { _ in completionHandler(true) })
        Self.present(alert, in: webView) { completionHandler(false) }
    }
    func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String, defaultText: String?,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (String?) -> Void) {
        let alert = UIAlertController(title: webView.url?.host, message: prompt, preferredStyle: .alert)
        alert.addTextField { $0.text = defaultText }
        alert.addAction(UIAlertAction(title: "取消", style: .cancel) { _ in completionHandler(nil) })
        alert.addAction(UIAlertAction(title: "确定", style: .default) { [weak alert] _ in completionHandler(alert?.textFields?.first?.text) })
        Self.present(alert, in: webView) { completionHandler(nil) }
    }
}

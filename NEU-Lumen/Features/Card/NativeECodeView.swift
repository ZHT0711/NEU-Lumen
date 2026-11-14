import SwiftUI
import WebKit

struct NativeECodeView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.scenePhase) private var scenePhase
    @State private var browser = PortalBrowser()
    @State private var document: ECodeDocument?
    @State private var image: UIImage?
    @State private var observedAt: Date?
    @State private var loadedAt: Date?
    @State private var showWebsite = false
    @State private var message: String?
    @State private var owner = UUID()
    @State private var needsSchoolRefresh = false
    private static let world = WKContentWorld.world(name: "NEULumen.ECode")

    var body: some View {
        ZStack {
            PortalWebView(browser: browser)
                .id(ObjectIdentifier(browser.webView))
                .opacity(showWebsite ? 1 : 0)
                .allowsHitTesting(showWebsite)
                .accessibilityHidden(!showWebsite)
            if !showWebsite {
                ScrollView {
                    VStack(spacing: 22) {
                        HStack(spacing: 12) {
                            Image("NEUEmblem").renderingMode(.template).resizable().scaledToFit().frame(width: 48, height: 48)
                            NEUCalligraphy()
                            Spacer(minLength: 0)
                        }.foregroundStyle(AppTheme.accent).accessibilityElement(children: .combine)
                        if browser.isLoading { ProgressView("正在读取学校校园码…") }
                        if let image, let observedAt, scenePhase == .active, environment.session.networkAvailable {
                            VStack(spacing: 14) {
                                Image(uiImage: image).interpolation(.none).resizable().scaledToFit()
                                    .frame(maxWidth: 300).padding(18).background(.white)
                                    .accessibilityLabel("学校当前账号的校园码")
                                Text(environment.session.user?.name ?? "").font(.title2.bold())
                                ForEach(document?.facts ?? []) { fact in
                                    LabeledContent(fact.label, value: fact.value)
                                }
                                Text("读取于 \(observedAt.formatted(date: .omitted, time: .standard))")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            .padding(20).background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 22))
                        } else if !browser.isLoading {
                            ContentUnavailableView("校园码尚未就绪", systemImage: "qrcode",
                                description: Text(message ?? "请在学校页面完成认证或进入出码页面，校园码就绪后会自动显示。"))
                        }
                        if let error = browser.error { Text(error).font(.callout).foregroundStyle(.secondary) }
                        ForEach(document?.links ?? []) { link in
                            Button(link.title, systemImage: "qrcode") { Task { await open(link.url) } }
                                .buttonStyle(.borderedProminent)
                        }
                        HStack {
                            Button("刷新校园码", systemImage: "arrow.clockwise") { refresh() }.disabled(browser.isLoading)
                            Spacer()
                            Button("学校页面", systemImage: "arrow.up.right.square") { showWebsite = true }
                        }.buttonStyle(.bordered)
                        Text("校园码由学校实时提供，保持联网。付款、通行权限和办理结果以学校系统为准。")
                            .font(.footnote).foregroundStyle(.secondary)
                    }.padding(20)
                }
                .background(Color(.systemGroupedBackground))
            }
        }
        .navigationTitle("e码通").navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(showWebsite ? "校园码" : "学校页面") { showWebsite.toggle() }
            }
        }
        .privacySensitive()
        .task(id: environment.session.requestEpoch) { await run() }
        .onChange(of: browser.isLoading) { _, loading in
            clearCode()
            if !loading { loadedAt = Date(); needsSchoolRefresh = false }
        }
        .onChange(of: browser.currentURL) { _, _ in clearCode() }
        .onChange(of: scenePhase) { _, phase in
            clearCode()
            if phase == .active { refresh() }
        }
        .onChange(of: environment.session.networkAvailable) { _, available in
            clearCode()
            if available { refresh() }
        }
        .onChange(of: environment.session.networkRevision) { _, _ in
            clearCode()
            if scenePhase == .active, environment.session.networkAvailable { refresh() }
        }
        .onChange(of: showWebsite) { _, website in
            clearCode()
            if !website { refresh() }
        }
        .onDisappear { owner = UUID(); clearCode(); document = nil; browser.close() }
    }

    private func clearCode() { image = nil; observedAt = nil }
    private func refresh() {
        clearCode(); document = nil; loadedAt = nil
        needsSchoolRefresh = false
        // Foreground/network callbacks may precede the first GET or arrive while
        // it is loading. Let that request finish instead of treating it as POST.
        guard !browser.isLoading, !browser.webView.isLoading, browser.webView.url != nil else { return }
        needsSchoolRefresh = !browser.reloadReadOnlyDocument()
        if needsSchoolRefresh { message = "请在学校页面刷新或重新进入校园码，再返回查看。" }
    }

    private func open(_ url: URL) async {
        guard ECodeDocument.allows(url) else { return }
        let session = environment.session, epoch = session.requestEpoch
        let requestOwner = owner, browser = self.browser
        let destination = await session.client.prepareBrowserURL(url)
        guard owner == requestOwner, session.requestEpoch == epoch, !Task.isCancelled else { return }
        clearCode(); document = nil
        browser.webView.load(URLRequest(url: destination))
    }

    private func run() async {
        let runOwner = UUID()
        owner = runOwner
        let session = environment.session, epoch = session.requestEpoch
        let account = session.user?.sid.isEmpty == false ? session.user!.sid : (session.user?.uid ?? "")
        clearCode(); document = nil; message = nil
        needsSchoolRefresh = false
        browser.close()
        let browser = PortalBrowser()
        self.browser = browser
        defer {
            browser.close()
            if owner == runOwner { clearCode(); document = nil }
        }
        await environment.repository.ensureLoadedForCurrentUser()
        _ = await environment.repository.loadAppsIfNeeded()
        guard owner == runOwner, session.requestEpoch == epoch, session.phase == .loggedIn, !Task.isCancelled else { return }
        await browser.start(environment.repository.ecodeEntryURL, client: session.client, session: session)
        guard owner == runOwner, !Task.isCancelled else { return }
        while owner == runOwner, !Task.isCancelled, session.requestEpoch == epoch, session.phase == .loggedIn {
            if !showWebsite, !needsSchoolRefresh, scenePhase == .active, session.networkAvailable, !browser.isLoading, browser.error == nil,
               let url = browser.webView.url, ECodeDocument.allows(WebVPN.unwrap(url) ?? url) {
                // A conservative display limit is not a claim about the school's token validity.
                // Re-read from the server instead of indefinitely presenting an unchanged DOM code.
                if document?.state == "ready", let loadedAt, Date().timeIntervalSince(loadedAt) >= 30 {
                    refresh()
                } else {
                    do {
                        let raw = try await browser.webView.callAsyncJavaScript(ECodeDocument.reader,
                            arguments: ["expectedAccount": account], in: nil, contentWorld: Self.world)
                        guard owner == runOwner, session.requestEpoch == epoch,
                              session.phase == .loggedIn, !Task.isCancelled else { return }
                        guard browser.webView.url == url, !browser.isLoading,
                              scenePhase == .active, session.networkAvailable else {
                            clearCode()
                            do { try await Task.sleep(for: .milliseconds(200)) } catch { return }
                            continue
                        }
                        let next = try JSONDecoder().decode(ECodeDocument.self, from: JSONSerialization.data(withJSONObject: raw ?? [:]))
                        document = next
                        if next.state == "ready", let png = next.png, png.hasPrefix("data:image/png;base64,"),
                           let data = Data(base64Encoded: String(png.dropFirst(22))), let decoded = UIImage(data: data) {
                            image = decoded; observedAt = Date(); message = nil
                            if loadedAt == nil { loadedAt = Date() }
                        } else {
                            clearCode()
                            message = next.state == "account" ? "学校页面账号与当前账号不一致，请核对学校登录。" :
                                next.state == "login" ? "请先完成学校认证。" : "请在学校页面进入校园码，完成认证后会自动读取。"
                        }
                    } catch {
                        guard owner == runOwner, session.requestEpoch == epoch, !Task.isCancelled else { return }
                        clearCode()
                        if !NetworkError.isCancellation(error) { message = "校园码暂未读取成功，请重试或在学校页面查看。" }
                    }
                }
            } else { clearCode() }
            do { try await Task.sleep(for: .seconds(1)) } catch { return }
        }
    }
}

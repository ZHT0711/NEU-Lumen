import Foundation
import WebKit
import UIKit
import Observation

@MainActor @Observable
final class NativeMailStore: NSObject, WKNavigationDelegate, WKUIDelegate {
    private(set) var webView: WKWebView?
    private(set) var email = ""
    private(set) var folders: [NativeMailFolder] = []
    private(set) var messages: [NativeMailMessage] = []
    private(set) var folderID = "1"
    private(set) var nextStart = 0
    private(set) var hasMore = false
    private(set) var busy = false
    private(set) var loadingWeb = false
    private(set) var loaded = false
    private(set) var needsLogin = false
    private(set) var bindingCandidate: String?
    private(set) var error: String?
    private(set) var persistenceWarning: String?
    private var subjectSearch = ""
    private var advancedSearch = NativeMailSearch()
    private var boundEmail = ""
    private weak var session: SessionStore?
    private var ownerEpoch: UUID?
    private var ownerAccount = ""
    private var generation = UUID()
    private var currentOperation: UUID?
    private var entryURL: URL?
    private var lastSaved: SavedWebSession?
    private var lastRefresh: Date?
    private var pageGeneration = UUID()
    private var verifiedPage: UUID?
    private static let world = WKContentWorld.world(name: "NEULumen.NativeMail")

    private var current: Bool {
        guard let session else { return false }
        return session.phase == .loggedIn && session.requestEpoch == ownerEpoch &&
            ownerAccount == (session.user?.sid.isEmpty == false ? session.user?.sid : session.user?.uid)
    }
    private var vault: KeychainWebSessionStore { KeychainWebSessionStore(account: "service.mail." + ownerAccount) }

    func invalidateIfNeeded(session: SessionStore) {
        if ownerEpoch != session.requestEpoch { close() }
    }

    func connect(session: SessionStore, apps: [PortalApp], server: URL? = nil) async {
        guard session.phase == .loggedIn, let user = session.user else { close(); return }
        let account = user.sid.isEmpty ? user.uid : user.sid
        guard !account.isEmpty else { return }
        if ownerEpoch == session.requestEpoch, webView != nil, server == nil {
            if lastRefresh.map({ Date().timeIntervalSince($0) > 60 }) ?? false { await refresh() }
            return
        }
        close()
        ownerAccount = account; ownerEpoch = session.requestEpoch; self.session = session
        let token = generation
        await session.cleanRetiredLearningBrowsers()
        guard current, token == generation, !Task.isCancelled else { return }
        let saved = vault.load().flatMap { $0.user.isSameAccount(as: user) ? $0 : nil }
        boundEmail = saved?.user.email ?? ""
        if boundEmail.isEmpty, user.email.lowercased().hasSuffix("neu.edu.cn") { boundEmail = user.email.lowercased() }
        let config = WKWebViewConfiguration()
        if let id = LearningBrowserProfiles().identifier(account: account, service: .mail) {
            config.websiteDataStore = WKWebsiteDataStore(forIdentifier: id)
        } else { config.websiteDataStore = .nonPersistent() }
        config.defaultWebpagePreferences.preferredContentMode = .mobile
        let view = WKWebView(frame: .zero, configuration: config)
        webView = view; view.navigationDelegate = self; view.uiDelegate = self
        view.allowsBackForwardNavigationGestures = true
        view.customUserAgent = session.client.browserUserAgent ?? HTTPClient.userAgent
        let source = server ?? NativeCampusService.mail.entryURL(apps: apps)
        entryURL = source; loadingWeb = true
        let destination = await session.client.prepareBrowserURL(source)
        guard current, token == generation, !Task.isCancelled else { return }
        let store = config.websiteDataStore.httpCookieStore
        for cookie in saved?.restoredCookies() ?? [] { await store.setCookie(cookie) }
        for cookie in session.client.browserCookies() {
            let host = cookie.domain.trimmingCharacters(in: CharacterSet(charactersIn: ".")).lowercased()
            if NativeCampusService.mail.owns(host: host) || ["pass.neu.edu.cn", "webvpn.neu.edu.cn"].contains(host) {
                await store.setCookie(cookie)
            }
        }
        guard current, token == generation, !Task.isCancelled else { return }
        view.load(URLRequest(url: destination))
    }

    func reloadLogin() {
        guard current, let entryURL, let session else { return }
        error = nil
        Task { @MainActor in
            let token = generation
            let destination = await session.client.prepareBrowserURL(entryURL)
            guard current, token == generation else { return }
            webView?.load(URLRequest(url: destination))
        }
    }

    private func execute(command: String, start: Int = 0, includeFolders: Bool = false, messageID: String = "",
                         messageIDs: [String] = [], attributes: [String: Any] = [:], composeKind: String = "normal") async throws -> [String: Any] {
        guard current, let view = webView, let url = view.url, let user = session?.user else {
            throw NetworkError(message: "请先登录学校邮箱")
        }
        let original = WebVPN.unwrap(url) ?? url
        guard original.scheme == "https", original.port == nil || original.port == 443,
              let host = original.host?.lowercased(), NativeCampusService.mail.owns(host: host), original.path.contains("/coremail/") else {
            throw NetworkError(message: "请完成学校邮箱认证后再读取邮件")
        }
        let sourceRoot = URL(string: "/coremail/", relativeTo: original)!.absoluteURL
        let root = WebVPN.isWrapped(url.absoluteString) ? WebVPN.wrap(sourceRoot.absoluteString) : sourceRoot.absoluteString
        let token = generation, page = pageGeneration
        let raw = try await view.callAsyncJavaScript(NativeMailProtocol.reader, arguments: [
            "rootURL": root, "command": command, "expectedEmail": boundEmail, "expectedSID": user.sid,
            "folderID": folderID, "start": start, "includeFolders": includeFolders, "messageID": messageID,
            "searchText": subjectSearch,
            "searchFields": advancedSearch.parameters, "messageIDs": messageIDs, "attributes": attributes,
            "composeKind": composeKind,
        ], in: nil, contentWorld: Self.world)
        // Coremail changes its SPA fragment while initializing; only a document
        // navigation or account change invalidates this isolated-world response.
        var before = URLComponents(url: url, resolvingAgainstBaseURL: false)
        var after = view.url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) }
        before?.fragment = nil; after?.fragment = nil
        guard current, token == generation, page == pageGeneration, !Task.isCancelled, before?.url == after?.url else { throw CancellationError() }
        guard let result = raw as? [String: Any] else { throw NetworkError(message: "学校邮箱响应格式暂不支持") }
        if let failure = result["error"] as? String {
            if failure == "network" { throw NetworkError(message: "邮箱连接暂时失败，请检查网络后重试") }
            if failure == "format" { throw NetworkError(message: "学校邮箱当前版本的响应暂不支持，可在学校网页查看") }
            if failure == "operation" { throw NetworkError(message: "学校邮箱未确认操作成功，请刷新核对邮件状态") }
            needsLogin = true
            messages = []; folders = []; loaded = false; email = ""; verifiedPage = nil
            if failure == "binding" {
                bindingCandidate = try NativeMailProtocol.identity(result)
                messages = []; folders = []; loaded = false
                throw NetworkError(message: "请确认将当前邮箱关联到这个校园账号")
            }
            throw NetworkError(message: "邮箱登录已失效或页面尚未就绪，请完成认证后重试")
        }
        let identity = try NativeMailProtocol.identity(result)
        guard boundEmail.isEmpty || identity == boundEmail.lowercased() else { throw AcademicQueryError.accountMismatch }
        email = identity; boundEmail = identity; bindingCandidate = nil; needsLogin = false; verifiedPage = page
        return result
    }

    func refresh(reset: Bool = true, search: String? = nil, advanced: NativeMailSearch? = nil) async {
        guard current, !busy, !loadingWeb, reset || hasMore else { return }
        busy = true
        let token = UUID(); currentOperation = token
        defer { if currentOperation == token { busy = false; currentOperation = nil } }
        if let search { subjectSearch = search.trimmingCharacters(in: .whitespacesAndNewlines) }
        if let advanced { advancedSearch = advanced; subjectSearch = advanced.subject }
        do {
            let raw = try await execute(command: "list", start: reset ? 0 : nextStart, includeFolders: folders.isEmpty || reset)
            guard current, currentOperation == token else { return }
            let rows = try NativeMailProtocol.messages(raw["messages"])
            if let folderRows = raw["folders"] as? [[String: Any]], !folderRows.isEmpty {
                var seen = Set<String>()
                folders = folderRows.compactMap { row in
                    guard let id = row["id"] as? String, let name = row["name"] as? String, seen.insert(id).inserted else { return nil }
                    return NativeMailFolder(id: id, name: name, total: row["total"] as? Int, unread: row["unread"] as? Int)
                }
            }
            var seen = Set<String>()
            messages = ((reset ? [] : messages) + rows).filter { seen.insert($0.id).inserted }
            folderID = raw["folderID"] as? String ?? folderID
            nextStart = raw["nextStart"] as? Int ?? (reset ? rows.count : nextStart + rows.count)
            hasMore = raw["hasMore"] as? Bool ?? false; loaded = true; error = nil; lastRefresh = Date()
            await persist()
        } catch {
            if current, currentOperation == token, !NetworkError.isCancellation(error) { self.error = NetworkError.from(error).message }
        }
    }

    func selectFolder(_ folder: NativeMailFolder) async {
        guard !busy else { return }
        folderID = folder.id; subjectSearch = ""; messages = []; loaded = false
        advancedSearch = NativeMailSearch()
        await refresh()
    }

    func update(_ ids: Set<String>, mutation: NativeMailMutation) async -> Bool {
        guard current, !busy, !loadingWeb, !ids.isEmpty,
              ids.isSubset(of: Set(messages.map(\.id))) else { return false }
        if case .move(let destination) = mutation {
            guard destination != folderID, folders.contains(where: { $0.id == destination }) else { return false }
        }
        busy = true
        let token = UUID(); currentOperation = token
        do {
            let identifiers = ids.sorted()
            for start in stride(from: 0, to: identifiers.count, by: 100) {
                guard current, currentOperation == token else { throw CancellationError() }
                let batch = Array(identifiers[start..<min(start + 100, identifiers.count)])
                let result = try await execute(command: "update", messageIDs: batch, attributes: mutation.attributes)
                guard current, currentOperation == token, result["updated"] as? Bool == true else { throw CancellationError() }
            }
            busy = false; currentOperation = nil
            await refresh()
            return true
        } catch {
            if current, currentOperation == token {
                busy = false; currentOperation = nil
                if !NetworkError.isCancellation(error) {
                    self.error = NetworkError.from(error).message + "。请先刷新核对，再决定是否重试。"
                }
            }
            return false
        }
    }

    func confirmBinding() async {
        guard let candidate = bindingCandidate, current else { return }
        boundEmail = candidate; email = candidate; bindingCandidate = nil; needsLogin = false; error = nil
        await persist(); await refresh()
    }

    func read(_ message: NativeMailMessage) async throws -> NativeMailBody {
        guard current, !busy else { throw NetworkError(message: "邮箱正在同步，请稍后打开邮件") }
        busy = true
        let token = UUID(); currentOperation = token
        defer { if currentOperation == token { busy = false; currentOperation = nil } }
        let raw = try await execute(command: "read", messageID: message.id)
        guard current, currentOperation == token, let row = raw["body"] as? [String: Any],
              let id = row["id"] as? String, id == message.id else { throw CancellationError() }
        return NativeMailBody(id: id, subject: (row["subject"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? message.subject,
            sender: (row["sender"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? message.sender,
            text: row["text"] as? String ?? "此邮件暂未提供可读取正文，请在学校邮箱查看。",
            attachments: row["attachments"] as? [String] ?? [])
    }

    func showWebMail(messageID: String? = nil, compose: Bool = false, reply: String? = nil) async {
        guard current, !busy, let view = webView else { return }
        let token = generation
        let operation = UUID(); currentOperation = operation
        busy = true
        defer { if currentOperation == operation { busy = false; currentOperation = nil } }
        do {
            var identifier = messageID ?? ""
            if compose {
                let result = try await execute(command: "compose", messageID: identifier, composeKind: reply ?? "normal")
                guard let id = result["composeID"] as? String else { throw NetworkError(message: "学校邮箱未返回写信标识") }
                identifier = id
            }
            guard current, generation == token, currentOperation == operation else { throw CancellationError() }
            _ = try await view.callAsyncJavaScript("location.hash = module + '?' + new URLSearchParams(parameters).toString();",
                arguments: ["module": compose ? "mail.compose" : "mail.read", "parameters": compose ? ["id": identifier] : ["mid": identifier]],
                in: nil, contentWorld: Self.world)
            error = nil
        } catch {
            if current, generation == token, currentOperation == operation, !NetworkError.isCancellation(error) { self.error = NetworkError.from(error).message }
        }
    }

    func persist() async {
        guard current, verifiedPage == pageGeneration, !email.isEmpty, !needsLogin,
              let user = session?.user, let view = webView else { return }
        let token = generation
        let cookies = await view.configuration.websiteDataStore.httpCookieStore.allCookies()
        guard current, token == generation else { return }
        let owner = PortalUser(uid: user.uid, name: user.name, sid: user.sid, identity: user.identity,
            department: user.department, email: boundEmail, avatarUrl: user.avatarUrl)
        let snapshot = SavedWebSession(user: owner, userAgent: view.customUserAgent ?? HTTPClient.userAgent, cookies: cookies)
        guard lastSaved != snapshot else { return }
        do { try vault.save(snapshot); lastSaved = snapshot; persistenceWarning = nil }
        catch { persistenceWarning = "邮箱登录信息未能保存，重启后可能需要重新认证" }
    }

    func close() {
        generation = UUID(); currentOperation = nil
        webView?.stopLoading(); webView?.navigationDelegate = nil; webView?.uiDelegate = nil; webView = nil
        session = nil; ownerEpoch = nil; ownerAccount = ""; boundEmail = ""; email = ""
        folders = []; messages = []; busy = false; loadingWeb = false; loaded = false; needsLogin = false
        bindingCandidate = nil; error = nil; lastSaved = nil; subjectSearch = ""; folderID = "1"; nextStart = 0; hasMore = false
        verifiedPage = nil; pageGeneration = UUID(); lastRefresh = nil; persistenceWarning = nil
        advancedSearch = NativeMailSearch()
    }
    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        loadingWeb = true; pageGeneration = UUID(); verifiedPage = nil
        currentOperation = nil; busy = false
    }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        loadingWeb = false
        Task { @MainActor in await refresh() }
    }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError failure: Error) { failed(failure) }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError failure: Error) { failed(failure) }
    private func failed(_ failure: Error) {
        guard current, !NetworkError.isCancellation(failure) else { return }
        loadingWeb = false; needsLogin = true; error = NetworkError.from(failure).message
    }
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if navigationAction.targetFrame == nil { webView.load(navigationAction.request) }
        return nil
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse,
                 decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        guard current else { decisionHandler(.cancel); return }
        let disposition = (navigationResponse.response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Disposition") ?? ""
        decisionHandler(!navigationResponse.canShowMIMEType || disposition.lowercased().contains("attachment") ? .download : .allow)
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard current else { decisionHandler(.cancel); return }
        decisionHandler(navigationAction.shouldPerformDownload ? .download : .allow)
    }

    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) {
        adopt(download, from: webView)
    }

    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
        adopt(download, from: webView)
    }

    private func adopt(_ download: WKDownload, from view: WKWebView) {
        guard current, let session else { download.cancel(nil); return }
        let downloads = BrowserDownloadStore.shared
        downloads.activate(account: ownerAccount, epoch: session.requestEpoch)
        downloads.adopt(download, from: view, scope: downloads.scope)
    }

    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
        guard current else { completionHandler(); return }
        let alert = UIAlertController(title: frame.securityOrigin.host, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "好", style: .default) { _ in completionHandler() })
        PortalBrowser.present(alert, in: webView, fallback: completionHandler)
    }

    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
        guard current else { completionHandler(false); return }
        let epoch = ownerEpoch
        let alert = UIAlertController(title: frame.securityOrigin.host, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "取消", style: .cancel) { _ in completionHandler(false) })
        alert.addAction(UIAlertAction(title: "确定", style: .default) { [weak self] _ in
            completionHandler(self?.current == true && self?.ownerEpoch == epoch)
        })
        PortalBrowser.present(alert, in: webView) { completionHandler(false) }
    }

    func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String, defaultText: String?,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (String?) -> Void) {
        guard current else { completionHandler(nil); return }
        let epoch = ownerEpoch
        let alert = UIAlertController(title: frame.securityOrigin.host, message: prompt, preferredStyle: .alert)
        alert.addTextField { $0.text = defaultText }
        alert.addAction(UIAlertAction(title: "取消", style: .cancel) { _ in completionHandler(nil) })
        alert.addAction(UIAlertAction(title: "确定", style: .default) { [weak self, weak alert] _ in
            completionHandler(self?.current == true && self?.ownerEpoch == epoch ? alert?.textFields?.first?.text : nil)
        })
        PortalBrowser.present(alert, in: webView) { completionHandler(nil) }
    }
}

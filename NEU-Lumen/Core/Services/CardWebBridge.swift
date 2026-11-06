import Foundation
import WebKit

/// Use the same WebKit transport as the working card website when URLSession is rejected by the site.
@MainActor
final class CardWebBridge: NSObject, WKNavigationDelegate {
    private var webView: WKWebView?
    private let gate = CASRequestGate()
    private var epoch = UUID()
    private var finished = false
    private var failure: Error?
    private var status = 0
    private weak var client: PortalClient?
    private var hasEstablishedSession = false
    private var refererURL: URL?
    private let baseURL: URL
    private let entryURL: URL

    init(baseURL: URL = URL(string: "http://ecard.neu.edu.cn")!, entryURL: URL = URL(string: PortalClient.serviceCard)!) {
        self.baseURL = baseURL
        self.entryURL = entryURL
        super.init()
    }

    func reset() {
        epoch = UUID()
        webView?.stopLoading()
        webView?.navigationDelegate = nil
        webView = nil
        client = nil
        hasEstablishedSession = false
        refererURL = nil
    }

    func use(store: WKWebsiteDataStore, currentURL: URL? = nil) {
        reset()
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = store
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.navigationDelegate = self
        webView = view
        hasEstablishedSession = true
        refererURL = currentURL
    }

    func balance(client: PortalClient) async throws -> CardBalance {
        let epoch = self.epoch
        let clientEpoch = client.sessionGeneration
        await gate.acquire()
        do {
            guard epoch == self.epoch, clientEpoch == client.sessionGeneration else { throw CancellationError() }
            try await establish(client: client)
            guard let view = webView else { throw CancellationError() }
            let value: CardBalance
            do { value = try await Self.readBalance(in: view) }
            catch {
                if NetworkError.isCancellation(error) || Task.isCancelled { throw CancellationError() }
                let legacy = client.browserDestination(for: URL(string: "/selfsearch/User/baseinfo.aspx", relativeTo: baseURL)!.absoluteURL)
                _ = try await navigate(legacy)
                value = try await Self.readBalance(in: view)
            }
            guard epoch == self.epoch, clientEpoch == client.sessionGeneration, !Task.isCancelled else { throw CancellationError() }
            await gate.release()
            return value
        } catch { await gate.release(); throw error }
    }

    func bills(client: PortalClient, year: Int, month: Int) async throws -> (bills: [CardBill], truncated: Bool) {
        let epoch = self.epoch
        let clientEpoch = client.sessionGeneration
        await gate.acquire()
        do {
            guard epoch == self.epoch, clientEpoch == client.sessionGeneration else { throw CancellationError() }
            try await establish(client: client)
            let url = await client.prepareBrowserURL(URL(string: "/selfsearch/User/ConsumeInfo.aspx", relativeTo: baseURL)!.absoluteURL)
            var html = try await navigate(url)
            var fields = PortalClient.cardBillSearchFields(html: html, year: year, month: month)
            html = try await post(url, fields: fields)
            var bills = try PortalClient.parseBillTable(html)
            var pages: Set<[CardBill]> = [bills]
            var truncated = false
            for page in 2...10 {
                guard PortalClient.hasNextPage(html, page) else { break }
                fields = PortalClient.cardBillSearchFields(html: html, year: year, month: month, includeSearchButton: false)
                fields["__EVENTTARGET"] = "ctl00$ContentPlaceHolder1$AspNetPager1"
                fields["__EVENTARGUMENT"] = "\(page)"
                html = try await post(url, fields: fields)
                let more = try PortalClient.parseBillTable(html)
                guard !more.isEmpty, pages.insert(more).inserted else {
                    throw NetworkError(message: "一卡通流水翻页未推进，请在网页核对后重试")
                }
                bills += more
                if page == 10 { truncated = PortalClient.hasNextPage(html, 11) }
            }
            await syncCookies(client, expected: clientEpoch)
            guard epoch == self.epoch, clientEpoch == client.sessionGeneration, !Task.isCancelled else { throw CancellationError() }
            await gate.release()
            return (bills, truncated)
        } catch { await gate.release(); throw error }
    }

    private func establish(client: PortalClient) async throws {
        let epoch = self.epoch
        let clientEpoch = client.sessionGeneration
        self.client = client
        // Route preparation can acquire a new gateway ticket. Copy cookies afterwards.
        let entry = await client.prepareBrowserURL(entryURL)
        guard epoch == self.epoch, clientEpoch == client.sessionGeneration, !Task.isCancelled else { throw CancellationError() }
        if webView == nil {
            let configuration = WKWebViewConfiguration()
            configuration.websiteDataStore = .nonPersistent()
            let view = WKWebView(frame: .zero, configuration: configuration)
            view.navigationDelegate = self
            webView = view
        }
        guard let view = webView else { throw CancellationError() }
        view.customUserAgent = client.browserUserAgent ?? HTTPClient.userAgent
        // Keep the authenticated website session when refreshing or querying another month.
        if hasEstablishedSession,
           (try? await navigateWalletPage(client: client)) != nil {
            await syncCookies(client, expected: clientEpoch)
            guard epoch == self.epoch, clientEpoch == client.sessionGeneration, !Task.isCancelled else { throw CancellationError() }
            return
        }
        guard epoch == self.epoch, clientEpoch == client.sessionGeneration, !Task.isCancelled else { throw CancellationError() }
        hasEstablishedSession = false
        for cookie in client.browserCookies() { await view.configuration.websiteDataStore.httpCookieStore.setCookie(cookie) }
        guard epoch == self.epoch, clientEpoch == client.sessionGeneration, !Task.isCancelled else { throw CancellationError() }
        _ = try await navigate(entry)
        // Only submit the school's signed card SSO form, never a password/SMS form.
        let submitted = try? await view.evaluateJavaScript(#"(() => { const input = document.querySelector('input[name="auid"]'); if (input && input.form && input.form.querySelector('input[name="timestamp"]')) { input.form.submit(); return true; } return false; })()"#)
        if submitted as? Bool == true {
            try await Task.sleep(nanoseconds: 800_000_000)
            try await waitUntilFinished(view)
        }
        try await navigateWalletPage(client: client)
        guard epoch == self.epoch, clientEpoch == client.sessionGeneration, !Task.isCancelled else { throw CancellationError() }
        await syncCookies(client, expected: clientEpoch)
        hasEstablishedSession = true
    }

    private func navigateWalletPage(client: PortalClient) async throws {
        var lastError: Error = NetworkError(message: "一卡通首页暂未响应")
        for path in [PortalClient.cardHomePath, "/selfsearch/User/baseinfo.aspx"] {
            let url = client.browserDestination(for: URL(string: path, relativeTo: baseURL)!.absoluteURL)
            do { _ = try await navigate(url); return }
            catch {
                if NetworkError.isCancellation(error) || Task.isCancelled { throw CancellationError() }
                lastError = error
            }
        }
        throw lastError
    }

    static func readBalance(in view: WKWebView, attempts: Int = 50) async throws -> CardBalance {
        var lastError: Error = NetworkError(message: "一卡通网页尚未提供可读取的主钱包余额")
        for attempt in 0..<attempts {
            try Task.checkCancellation()
            do {
                let html = try await view.evaluateJavaScript(CardBalanceDocument.browserScript) as? String ?? ""
                return try PortalClient.parseCardBalance(fromHTML: html)
            } catch {
                if NetworkError.isCancellation(error) { throw error }
                lastError = error
            }
            if attempt + 1 < attempts { try await Task.sleep(for: .milliseconds(100)) }
        }
        throw lastError
    }

    private func navigate(_ url: URL) async throws -> String {
        guard let view = webView else { throw CancellationError() }
        finished = false; failure = nil; status = 0
        var request = URLRequest(url: url)
        if let source = view.url ?? refererURL,
           source.scheme == url.scheme, source.host == url.host, source.port == url.port {
            request.setValue(source.absoluteString, forHTTPHeaderField: "Referer")
        }
        view.load(request)
        try await waitUntilFinished(view)
        if status >= 400 {
            let destination = view.url ?? url
            let path = (WebVPN.unwrap(destination) ?? destination).path
            throw NetworkError(message: "一卡通网页 HTTP \(status)（\(path)），可打开网页完成认证后同步")
        }
        refererURL = view.url
        let document = PortalLoginDocument.decode(try? await view.evaluateJavaScript(PortalLoginDocument.script))
        if document.hasLoginForm || view.url?.path.contains("/tpass/login") == true {
            throw NetworkError(message: "一卡通需要网页认证，请打开一卡通网页完成后同步")
        }
        return (try await view.evaluateJavaScript("document.documentElement.outerHTML")) as? String ?? ""
    }

    private func waitUntilFinished(_ view: WKWebView) async throws {
        let epoch = self.epoch
        for _ in 0..<200 {
            guard !Task.isCancelled, epoch == self.epoch else { throw CancellationError() }
            if let failure { throw failure }
            if finished && !view.isLoading { return }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        view.stopLoading()
        throw NetworkError(message: "一卡通网页暂未响应，可打开网页重试")
    }

    private func post(_ url: URL, fields: [String: String]) async throws -> String {
        guard let view = webView else { throw CancellationError() }
        let raw = try await view.callAsyncJavaScript(#"""
        const response = await fetch(url, {method: 'POST', credentials: 'include',
          headers: {'Content-Type': 'application/x-www-form-urlencoded; charset=UTF-8'},
          body: new URLSearchParams(fields).toString()});
        const bytes = await response.arrayBuffer();
        const preview = new TextDecoder().decode(bytes);
        const charset = response.headers.get('content-type')?.match(/charset=["']?([\w-]+)/i)?.[1]
          || preview.match(/charset=["']?([\w-]+)/i)?.[1] || 'utf-8';
        return JSON.stringify({status: response.status, url: response.url, html: new TextDecoder(charset).decode(bytes)});
        """#, arguments: ["url": url.absoluteString, "fields": fields], in: nil, contentWorld: .page)
        guard let text = raw as? String, let data = text.data(using: .utf8),
              let result = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              (200..<300).contains(result.int("status") ?? 0), !result.str("url").contains("/tpass/login") else {
            throw NetworkError(message: "一卡通流水网页未能完成查询，请打开网页认证后同步")
        }
        let html = result.str("html")
        guard !HTMLInputFields.parse(html).contains(where: { $0["type"]?.lowercased() == "password" }) else {
            throw NetworkError(message: "一卡通需要重新完成网页认证")
        }
        return html
    }

    private func syncCookies(_ client: PortalClient, expected: UUID) async {
        guard let view = webView else { return }
        let cookies = await view.configuration.websiteDataStore.httpCookieStore.allCookies()
        guard client.sessionGeneration == expected else { return }
        client.absorbBrowserCookies(cookies)
    }

    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard webView === self.webView else { decisionHandler(.cancel); return }
        if action.targetFrame?.isMainFrame != false,
           (action.request.httpMethod ?? "GET") == "GET",
           let source = action.request.url, let target = client?.browserDestination(for: source), source != target {
            decisionHandler(.cancel)
            var request = action.request
            request.url = target
            request.setValue(nil, forHTTPHeaderField: "Cookie")
            request.setValue(nil, forHTTPHeaderField: "Authorization")
            webView.load(request)
            return
        }
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        guard webView === self.webView else { return }
        finished = false
    }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard webView === self.webView else { return }
        finished = true
    }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        if webView === self.webView, (error as NSError).code != NSURLErrorCancelled { failure = error }
    }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        if webView === self.webView, (error as NSError).code != NSURLErrorCancelled { failure = error }
    }
    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse) async -> WKNavigationResponsePolicy {
        guard webView === self.webView else { return .cancel }
        if navigationResponse.isForMainFrame { status = (navigationResponse.response as? HTTPURLResponse)?.statusCode ?? 0 }
        return .allow
    }
}

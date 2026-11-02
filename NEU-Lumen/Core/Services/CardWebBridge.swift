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
    }

    func use(store: WKWebsiteDataStore) {
        reset()
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = store
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.navigationDelegate = self
        webView = view
    }

    func balance(client: PortalClient) async throws -> CardBalance {
        let epoch = self.epoch
        let clientEpoch = client.sessionGeneration
        await gate.acquire()
        do {
            guard epoch == self.epoch, clientEpoch == client.sessionGeneration else { throw CancellationError() }
            let value = try await establish(client: client)
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
            _ = try await establish(client: client)
            let url = await client.prepareBrowserURL(URL(string: "/selfsearch/User/ConsumeInfo.aspx", relativeTo: baseURL)!.absoluteURL)
            var html = try await navigate(url)
            var fields = PortalClient.cardBillSearchFields(html: html, year: year, month: month)
            html = try await post(url, fields: fields)
            var bills = PortalClient.parseBillTable(html)
            var truncated = false
            for page in 2...10 {
                guard html.contains("AspNetPager"), PortalClient.hasNextPage(html, page) else { break }
                fields = PortalClient.hiddenFields(html)
                fields["__EVENTTARGET"] = "ctl00$ContentPlaceHolder1$AspNetPager1"
                fields["__EVENTARGUMENT"] = "\(page)"
                html = try await post(url, fields: fields)
                let more = PortalClient.parseBillTable(html)
                if more.isEmpty { break }
                bills += more
                if page == 10 { truncated = PortalClient.hasNextPage(html, 11) }
            }
            await syncCookies(client, expected: clientEpoch)
            guard epoch == self.epoch, clientEpoch == client.sessionGeneration, !Task.isCancelled else { throw CancellationError() }
            await gate.release()
            return (bills, truncated)
        } catch { await gate.release(); throw error }
    }

    private func establish(client: PortalClient) async throws -> CardBalance {
        let epoch = self.epoch
        let clientEpoch = client.sessionGeneration
        if webView == nil {
            let configuration = WKWebViewConfiguration()
            configuration.websiteDataStore = .nonPersistent()
            let view = WKWebView(frame: .zero, configuration: configuration)
            view.navigationDelegate = self
            webView = view
        }
        guard let view = webView else { throw CancellationError() }
        view.customUserAgent = client.browserUserAgent ?? HTTPClient.userAgent
        for cookie in client.browserCookies() { await view.configuration.websiteDataStore.httpCookieStore.setCookie(cookie) }
        let entry = await client.prepareBrowserURL(entryURL)
        _ = try await navigate(entry)
        // Only submit the school's signed card SSO form, never a password/SMS form.
        let submitted = try? await view.evaluateJavaScript(#"(() => { const input = document.querySelector('input[name="auid"]'); if (input && input.form && input.form.querySelector('input[name="timestamp"]')) { input.form.submit(); return true; } return false; })()"#)
        if submitted as? Bool == true {
            try await Task.sleep(nanoseconds: 800_000_000)
            try await waitUntilFinished(view)
        }
        let base = await client.prepareBrowserURL(URL(string: "/selfsearch/User/baseinfo.aspx", relativeTo: baseURL)!.absoluteURL)
        let html = try await navigate(base)
        guard epoch == self.epoch, clientEpoch == client.sessionGeneration, !Task.isCancelled else { throw CancellationError() }
        await syncCookies(client, expected: clientEpoch)
        return try PortalClient.parseCardBalance(fromHTML: html)
    }

    private func navigate(_ url: URL) async throws -> String {
        guard let view = webView else { throw CancellationError() }
        finished = false; failure = nil; status = 0
        view.load(URLRequest(url: url))
        try await waitUntilFinished(view)
        if status >= 400 { throw NetworkError(message: "一卡通网页 HTTP \(status)，可打开网页完成认证后同步") }
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
        return JSON.stringify({status: response.status, url: response.url, html: await response.text()});
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

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) { finished = false }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { finished = true }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        if (error as NSError).code != NSURLErrorCancelled { failure = error }
    }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        if (error as NSError).code != NSURLErrorCancelled { failure = error }
    }
    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse) async -> WKNavigationResponsePolicy {
        if navigationResponse.isForMainFrame { status = (navigationResponse.response as? HTTPURLResponse)?.statusCode ?? 0 }
        return .allow
    }
}

import Foundation

@MainActor final class RefreshBrowser {
    final class WebView {
        var isLoading = false
        var url: URL?
    }
    let webView = WebView()
    var isLoading = false
    var allowsReload = true
    var reloadChecks = 0
    func reloadReadOnlyDocument() -> Bool { reloadChecks += 1; return allowsReload }
}

@main struct ECodeRefreshTests {
    @MainActor static func main() {
        let view = ECodeRefreshHarness()
        view.triggerRefresh()
        precondition(view.browser.reloadChecks == 0,
            "foreground before the first request must not lock code presentation")
        view.browser.webView.url = URL(string: "https://ecard.neu.edu.cn/code")!
        view.browser.isLoading = true
        view.browser.allowsReload = false
        view.triggerRefresh()
        precondition(view.browser.reloadChecks == 0,
            "an in-flight GET is allowed to finish without a reload check")
        view.browser.isLoading = false
        view.browser.webView.isLoading = true
        view.triggerRefresh()
        precondition(view.browser.reloadChecks == 0,
            "native WebKit loading state is checked before observation catches up")
        view.browser.webView.isLoading = false
        view.triggerRefresh()
        precondition(view.browser.reloadChecks == 1 && view.message == nil,
            "a POST-backed live document remains readable without replaying its request")
        view.browser.allowsReload = true
        view.triggerRefresh()
        precondition(view.browser.reloadChecks == 2,
            "a confirmed completed GET can refresh normally")
        precondition(view.clearCount == 5 && view.document == nil)
        print("ECode refresh: first load, observation lag, in-flight GET and read-only POST presentation passed")
    }
}

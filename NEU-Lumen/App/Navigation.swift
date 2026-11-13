import Foundation

/// 页面间导航目标（各标签页共用）。
enum AppDestination: Hashable {
    case web(URL)
    case card
    case academic

    /// 收藏、服务大厅使用同一路由；原生化入口仍保留各页的官网回退。
    static func service(_ app: PortalApp) -> AppDestination? {
        if app.nativeDestination == .academic { return .academic }
        guard let url = URL(string: app.entryUrl()),
              ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
              url.host != nil, url.user == nil, url.password == nil else { return nil }
        return .web(url)
    }
}

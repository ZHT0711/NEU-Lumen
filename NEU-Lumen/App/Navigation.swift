import Foundation

/// 页面间导航目标（各标签页共用）。
enum AppDestination: Hashable {
    case web(URL)
    case card
    case academic
    case ecode
    case nativeService(NativeCampusService)

    /// 门户应用和收藏始终使用学校提供的原始地址。
    static func service(_ app: PortalApp) -> AppDestination? {
        guard let url = URL(string: app.entryUrl()),
              ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
              url.host != nil, url.user == nil, url.password == nil else { return nil }
        return .web(url)
    }
}

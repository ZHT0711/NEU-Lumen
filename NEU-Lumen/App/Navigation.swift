import SwiftUI

/// 页面间导航目标（各标签页共用）。
enum AppDestination: Hashable {
    case web(URL)
    case card
}

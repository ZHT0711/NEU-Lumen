import Foundation
import ActivityKit

/// 主 App 与 Live Activity 扩展共享的数据协议。
struct NEULumenActivityAttributes: ActivityAttributes {
    typealias ContentState = LiveActivityContentState

    var campus: String
    // Optional so an upgrade can decode and retire activities from earlier builds.
    var accountID: String?
}

import ActivityKit

/// 主 App 与 Live Activity 扩展共享的数据协议。
struct NEULumenActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var title: String
        var subtitle: String
        var value: String
        var kind: String
        var updatedAt: Date
    }

    var campus: String
}

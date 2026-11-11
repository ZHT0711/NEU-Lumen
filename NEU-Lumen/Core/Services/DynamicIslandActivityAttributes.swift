import Foundation
import ActivityKit

/// 主 App 与 Live Activity 扩展共享的数据协议。
struct NEULumenActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var title: String
        var subtitle: String
        var value: String
        var kind: String
        var updatedAt: Date
        var startDate: Date?
        var endDate: Date?

        var symbol: String {
            switch kind {
            case "nextCourse": return "book.closed.fill"
            case "cardBalance": return "creditcard.fill"
            default: return "sparkles"
            }
        }

        var destination: URL {
            let path: String
            switch kind {
            case "nextCourse": path = "course"
            case "cardBalance": path = "card"
            default: path = "settings"
            }
            return URL(string: "neulumen://activity/\(path)")!
        }
    }

    var campus: String
    // Optional so an upgrade can decode and retire activities from earlier builds.
    var accountID: String?
}

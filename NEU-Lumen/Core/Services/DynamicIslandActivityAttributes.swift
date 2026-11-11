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
        // Optional fields keep already-running activities decodable after upgrades.
        var accent: String? = nil
        var symbolName: String? = nil
        var secondaryValue: String? = nil
        var progress: Double? = nil
        var countdownTitle: String? = nil
        var destinationPath: String? = nil

        static let allowedSymbols = ["book.closed.fill", "creditcard.fill", "wifi", "bolt.fill", "checklist", "calendar", "sparkles", "chart.bar.fill", "bell.fill", "heart.fill", "flag.fill"]

        var symbol: String {
            if let symbolName, Self.allowedSymbols.contains(symbolName) { return symbolName }
            switch kind {
            case "nextCourse": return "book.closed.fill"
            case "cardBalance": return "creditcard.fill"
            case "netBalance": return "wifi"
            case "electricBalance": return "bolt.fill"
            case "assignments": return "checklist"
            case "planner", "dayOverview": return "calendar"
            case "academicOverview": return "chart.bar.fill"
            default: return "sparkles"
            }
        }

        var destination: URL {
            let path: String
            let allowed = ["course", "card", "settings", "learning", "profile"]
            if let destinationPath, allowed.contains(destinationPath) {
                path = destinationPath
            } else {
                switch kind {
                case "nextCourse", "planner", "dayOverview": path = "course"
                case "cardBalance", "netBalance", "electricBalance": path = "card"
                case "assignments": path = "learning"
                case "academicOverview": path = "learning"
                default: path = "settings"
                }
            }
            let query = kind == "academicOverview" && path == "learning" ? "?section=grades" : ""
            return URL(string: "neulumen://activity/\(path)\(query)")!
        }
    }

    var campus: String
    // Optional so an upgrade can decode and retire activities from earlier builds.
    var accountID: String?
}

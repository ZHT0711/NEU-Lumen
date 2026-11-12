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
        /// Earliest source-data boundary, including variables in custom templates.
        var staleAfter: Date? = nil
        var countdownTarget: String? = nil

        var countdownDate: Date? {
            if countdownTarget == "start" { return startDate }
            if countdownTarget == "end" { return endDate }
            // Retain compatibility with activities created by older builds.
            if countdownTitle == "距上课" || countdownTitle == "距开始" { return startDate }
            return endDate
        }

        /// Character limits alone do not bound UTF-8/JSON (ZWJ emoji and combining
        /// marks can be one Character). Keep graphemes intact and budget encoded bytes.
        func boundedText() -> Self {
            func prefix(_ text: String, bytes: Int) -> String {
                var result = ""
                var used = 0
                for character in text {
                    let part = String(character)
                    guard used + part.utf8.count <= bytes else { break }
                    result.append(character)
                    used += part.utf8.count
                }
                return result
            }
            var copy = self
            copy.title = prefix(title, bytes: 640)
            copy.subtitle = prefix(subtitle, bytes: 1280)
            copy.value = prefix(value, bytes: 256)
            copy.secondaryValue = secondaryValue.map { prefix($0, bytes: 512) }
            copy.kind = prefix(kind, bytes: 64)
            copy.countdownTitle = countdownTitle.map { prefix($0, bytes: 64) }
            copy.countdownTarget = countdownTarget == "start" ? "start" : countdownTarget == "end" ? "end" : nil
            copy.accent = accent.map { prefix($0, bytes: 16) }
            copy.symbolName = symbolName.map { prefix($0, bytes: 96) }
            copy.destinationPath = destinationPath.map { prefix($0, bytes: 32) }
            if let progress = copy.progress, !progress.isFinite { copy.progress = nil }
            if !copy.updatedAt.timeIntervalSinceReferenceDate.isFinite { copy.updatedAt = .distantPast }
            if copy.startDate?.timeIntervalSinceReferenceDate.isFinite == false { copy.startDate = nil }
            if copy.endDate?.timeIntervalSinceReferenceDate.isFinite == false { copy.endDate = nil }
            if copy.staleAfter?.timeIntervalSinceReferenceDate.isFinite == false { copy.staleAfter = nil }
            // Leave room for static attributes and ActivityKit's envelope. Quotes and
            // backslashes may expand during encoding, so check the actual JSON too.
            let encoder = JSONEncoder()
            while (try? encoder.encode(copy).count).map({ $0 > 3200 }) == true {
                let fields = [copy.title, copy.subtitle, copy.value, copy.secondaryValue ?? ""]
                guard let index = fields.indices.max(by: { fields[$0].utf8.count < fields[$1].utf8.count }),
                      !fields[index].isEmpty else { break }
                let shorter = String(fields[index].prefix(max(0, fields[index].count - max(1, fields[index].count / 4))))
                switch index {
                case 0: copy.title = shorter
                case 1: copy.subtitle = shorter
                case 2: copy.value = shorter
                default: copy.secondaryValue = shorter
                }
            }
            return copy
        }

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

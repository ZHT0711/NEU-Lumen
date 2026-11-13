import Foundation

/// Small, source-neutral rows. Optional timing flag keeps older JSON decodable.
struct LiveActivityDetail: Codable, Hashable {
    var label: String
    var value: String
    var isTimeSensitive: Bool? = nil
}

enum LiveActivityText {
    static func prefix(_ text: String, bytes: Int) -> String {
        var result = ""
        var used = 0
        for character in text {
            let part = String(character)
            guard used + part.utf8.count <= bytes else { break }
            result.append(character)
            used += part.utf8.count
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func clean(_ text: String) -> String {
        text.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.joined(separator: " ")
            .unicodeScalars.filter { $0.value >= 32 && $0.value != 127 }
            .map(String.init).joined()
    }

    static func optional(_ text: String?, bytes: Int) -> String? {
        guard let text else { return nil }
        let result = prefix(clean(text), bytes: bytes)
        return result.isEmpty ? nil : result
    }

    /// Missing placeholders must not become purported teacher/room information.
    static func detail(_ label: String, _ value: String?, timeSensitive: Bool = false) -> LiveActivityDetail? {
        guard let value = optional(value, bytes: 240),
              !["待定", "未读取", "未知", "地点未读取", "暂无", "--", "—"].contains(value) else { return nil }
        return LiveActivityDetail(label: label, value: value, isTimeSensitive: timeSensitive ? true : nil)
    }
}

/// Foundation-only schema: the ActivityKit attributes expose this as ContentState.
/// Adding optional fields preserves decoding of already-running activities.
struct LiveActivityContentState: Codable, Hashable {
    var title: String
    var subtitle: String
    var value: String
    var kind: String
    var updatedAt: Date
    var startDate: Date?
    var endDate: Date?
    var accent: String? = nil
    var symbolName: String? = nil
    var secondaryValue: String? = nil
    var progress: Double? = nil
    var countdownTitle: String? = nil
    var destinationPath: String? = nil
    var staleAfter: Date? = nil
    var countdownTarget: String? = nil
    var detailItems: [LiveActivityDetail]? = nil
    /// upcoming / ongoing / finished / empty. Never inferred from wall-clock text.
    var phase: String? = nil

    var countdownDate: Date? {
        if countdownTarget == "start" { return startDate }
        if countdownTarget == "end" { return endDate }
        if countdownTitle == "距上课" || countdownTitle == "距开始" { return startDate }
        return endDate
    }

    static let payloadBudget = 3200
    static let maximumDetails = 6

    /// Grapheme-preserving limits AND the actual encoded JSON budget. JSON escaping
    /// and arbitrarily long combining/ZWJ sequences are included in the latter.
    func boundedText() -> Self {
        var copy = self
        copy.title = LiveActivityText.prefix(LiveActivityText.clean(title), bytes: 480)
        copy.subtitle = LiveActivityText.prefix(LiveActivityText.clean(subtitle), bytes: 640)
        copy.value = LiveActivityText.prefix(LiveActivityText.clean(value), bytes: 128)
        copy.kind = LiveActivityText.prefix(kind, bytes: 64)
        copy.secondaryValue = LiveActivityText.optional(secondaryValue, bytes: 256)
        copy.countdownTitle = LiveActivityText.optional(countdownTitle, bytes: 64)
        copy.countdownTarget = ["start", "end"].contains(countdownTarget ?? "") ? countdownTarget : nil
        copy.accent = LiveActivityText.optional(accent, bytes: 16)
        copy.symbolName = LiveActivityText.optional(symbolName, bytes: 96)
        copy.destinationPath = LiveActivityText.optional(destinationPath, bytes: 32)
        copy.phase = ["upcoming", "ongoing", "finished", "empty"].contains(phase ?? "") ? phase : nil
        var seen = Set<LiveActivityDetail>()
        let details = (detailItems ?? []).prefix(Self.maximumDetails).compactMap { row -> LiveActivityDetail? in
            guard let label = LiveActivityText.optional(row.label, bytes: 48),
                  let value = LiveActivityText.optional(row.value, bytes: 240) else { return nil }
            let item = LiveActivityDetail(label: label, value: value, isTimeSensitive: row.isTimeSensitive)
            return seen.insert(item).inserted ? item : nil
        }
        copy.detailItems = details.isEmpty ? nil : details
        if let progress = copy.progress { copy.progress = progress.isFinite ? min(1, max(0, progress)) : nil }
        if !copy.updatedAt.timeIntervalSinceReferenceDate.isFinite { copy.updatedAt = .distantPast }
        if copy.startDate?.timeIntervalSinceReferenceDate.isFinite == false { copy.startDate = nil }
        if copy.endDate?.timeIntervalSinceReferenceDate.isFinite == false { copy.endDate = nil }
        if copy.staleAfter?.timeIntervalSinceReferenceDate.isFinite == false { copy.staleAfter = nil }
        if let start = copy.startDate, let end = copy.endDate, start >= end {
            copy.startDate = nil
            copy.endDate = nil
            copy.progress = nil
        }
        let encoder = JSONEncoder()
        while (try? encoder.encode(copy).count).map({ $0 > Self.payloadBudget }) == true {
            var fields = [copy.title, copy.subtitle, copy.value, copy.secondaryValue ?? ""]
            for row in copy.detailItems ?? [] { fields.append(row.value); fields.append(row.label) }
            guard let index = fields.indices.max(by: { fields[$0].utf8.count < fields[$1].utf8.count }),
                  !fields[index].isEmpty else { break }
            let shorter = LiveActivityText.prefix(fields[index], bytes: fields[index].utf8.count * 3 / 4)
            switch index {
            case 0: copy.title = shorter
            case 1: copy.subtitle = shorter
            case 2: copy.value = shorter
            case 3: copy.secondaryValue = shorter.isEmpty ? nil : shorter
            default:
                let row = (index - 4) / 2
                if (index - 4).isMultiple(of: 2) { copy.detailItems?[row].value = shorter }
                else { copy.detailItems?[row].label = shorter }
                copy.detailItems = copy.detailItems?.filter { !$0.label.isEmpty && !$0.value.isEmpty }
                if copy.detailItems?.isEmpty == true { copy.detailItems = nil }
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
    var sourceTitle: String {
        switch kind {
        case "nextCourse": return "课程"
        case "cardBalance": return "校园卡"
        case "netBalance": return "校园网"
        case "electricBalance": return "宿舍电量"
        case "assignments": return "作业"
        case "planner": return "日程"
        case "dayOverview": return "今日"
        case "academicOverview": return "学业"
        default: return "自定义"
        }
    }
    var destination: URL {
        let allowed = ["course", "card", "settings", "learning", "profile"]
        let path: String
        if let destinationPath, allowed.contains(destinationPath) { path = destinationPath }
        else {
            switch kind {
            case "nextCourse", "planner", "dayOverview": path = "course"
            case "cardBalance", "netBalance", "electricBalance": path = "card"
            case "assignments", "academicOverview": path = "learning"
            default: path = "settings"
            }
        }
        let query = kind == "academicOverview" && path == "learning" ? "?section=grades" : ""
        return URL(string: "neulumen://activity/\(path)\(query)")!
    }

    /// The system, not an app-background poll, owns the boundary notification.
    var freshnessDeadline: Date? {
        let boundary: Date?
        if ["nextCourse", "planner"].contains(kind), let startDate, startDate > updatedAt { boundary = startDate }
        else if let endDate { boundary = endDate }
        else if kind == "custom" { boundary = nil }
        else { boundary = updatedAt.addingTimeInterval(1800) }
        return [boundary, staleAfter].compactMap { $0 }.min()
    }

    func displayTitle(isStale: Bool) -> String {
        guard isStale else { return title }
        if ["nextCourse", "planner", "dayOverview", "assignments"].contains(kind),
           phase == "finished" || phase == "empty" || title.contains("已结束") || title.contains("已完成") {
            return kind == "nextCourse" ? "课程与日程" : kind == "planner" ? "个人日程" : kind == "assignments" ? "学习作业" : "今日总览"
        }
        return title
    }
    func displaySecondary(isStale: Bool) -> String? {
        guard let text = LiveActivityText.optional(secondaryValue, bytes: 256) else { return nil }
        if isStale && (phase != nil || ["即将", "进行中", "已结束", "已完成", "已截止", "已到期"].contains(where: text.contains)) { return nil }
        return text
    }
    func displaySubtitle(isStale: Bool) -> String? {
        if isStale && (kind == "dayOverview" || ["即将", "已结束", "已完成"].contains(where: subtitle.contains)) { return nil }
        return LiveActivityText.optional(subtitle, bytes: 640)
    }
    func visibleDetails(isStale: Bool) -> [LiveActivityDetail] {
        (detailItems ?? []).filter { !isStale || $0.isTimeSensitive != true }
    }
    func displayValue(isStale: Bool) -> String {
        if isStale && (countdownDate != nil || phase != nil || kind == "dayOverview" || kind == "assignments") { return "待更新" }
        return value
    }
}

/// This exact geometry policy is used by the SwiftUI Layout, not a mock drawing.
/// Intrinsic sizes come from sizeThatFits; tests can supply measured font sizes.
enum LiveActivityLayoutMetrics {
    static let expandedContentHeight: CGFloat = 130
    static let gap: CGFloat = 8
    static let valueMinimumScale: CGFloat = 0.55
    struct MetricPlan: Equatable {
        let label: CGRect
        let value: CGRect
        let size: CGSize
        let stacked: Bool
    }
    static func metricPlan(width proposedWidth: CGFloat, label: CGSize, value: CGSize) -> MetricPlan {
        let width = max(0, proposedWidth.isFinite ? proposedWidth : 0)
        let labelWidth = min(width, max(0, label.width))
        let minimumValue = min(width, max(64, value.width * valueMinimumScale))
        if labelWidth + gap + minimumValue <= width {
            let valueWidth = max(0, width - labelWidth - gap)
            let height = max(label.height, value.height)
            return MetricPlan(label: CGRect(x: 0, y: (height - label.height) / 2, width: labelWidth, height: label.height),
                value: CGRect(x: labelWidth + gap, y: (height - value.height) / 2, width: valueWidth, height: value.height),
                size: CGSize(width: width, height: height), stacked: false)
        }
        return MetricPlan(label: CGRect(x: 0, y: 0, width: width, height: label.height),
            value: CGRect(x: 0, y: label.height + 3, width: width, height: value.height),
            size: CGSize(width: width, height: label.height + 3 + value.height), stacked: true)
    }
    static func detailColumns(width: CGFloat, accessibility: Bool) -> Int {
        !accessibility && width >= 300 ? 2 : 1
    }
}

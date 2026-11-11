import Foundation
import Observation

/// 系统实时活动的显示偏好，沿用已有配置键以兼容升级。
@MainActor
@Observable
final class DynamicIslandStore {
    enum ContentKind: String, CaseIterable, Identifiable {
        case nextCourse
        case cardBalance
        case custom
        case netBalance
        case electricBalance
        case assignments
        case planner
        case dayOverview
        case academicOverview

        var id: String { rawValue }

        var title: String {
            switch self {
            case .nextCourse: return "下一节课"
            case .cardBalance: return "校园卡余额"
            case .custom: return "自定义内容"
            case .netBalance: return "校园网余额"
            case .electricBalance: return "宿舍电量"
            case .assignments: return "学习作业"
            case .planner: return "个人日程"
            case .dayOverview: return "今日总览"
            case .academicOverview: return "学业总览"
            }
        }

        var icon: String {
            switch self {
            case .nextCourse: return "book.closed.fill"
            case .cardBalance: return "creditcard.fill"
            case .custom: return "sparkles"
            case .netBalance: return "wifi"
            case .electricBalance: return "bolt.fill"
            case .assignments: return "checklist"
            case .planner, .dayOverview: return "calendar"
            case .academicOverview: return "chart.bar.fill"
            }
        }
    }

    typealias TemplateVariable = LiveActivityTemplate.Variable
    static let templateVariables = LiveActivityTemplate.variables
    static let allowedAccents = LiveActivityDataPolicy.accents
    static let allowedCustomIcons = LiveActivityDataPolicy.symbols

    private struct Persisted: Codable {
        var enabled: Bool = true
        var kind: String = ContentKind.nextCourse.rawValue
        var customTitle: String = "东大提醒"
        var customSubtitle: String = "自定义你的实时活动内容"
        var customValue: String = ""
        var customIcon: String = "sparkles"
        var accent: String = "cyan"
        var showProgress: Bool = true
        var customDeadlineEnabled: Bool = false
        var customDeadline: Date = Date().addingTimeInterval(3600)

        init() {}
        private enum CodingKeys: String, CodingKey {
            case enabled, kind, customTitle, customSubtitle, customValue, customIcon, accent,
                 showProgress, customDeadlineEnabled, customDeadline
        }
        init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            enabled = try values.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
            kind = try values.decodeIfPresent(String.self, forKey: .kind) ?? ContentKind.nextCourse.rawValue
            customTitle = try values.decodeIfPresent(String.self, forKey: .customTitle) ?? "东大提醒"
            customSubtitle = try values.decodeIfPresent(String.self, forKey: .customSubtitle) ?? "自定义你的实时活动内容"
            customValue = try values.decodeIfPresent(String.self, forKey: .customValue) ?? ""
            customIcon = try values.decodeIfPresent(String.self, forKey: .customIcon) ?? "sparkles"
            accent = try values.decodeIfPresent(String.self, forKey: .accent) ?? "cyan"
            showProgress = try values.decodeIfPresent(Bool.self, forKey: .showProgress) ?? true
            customDeadlineEnabled = try values.decodeIfPresent(Bool.self, forKey: .customDeadlineEnabled) ?? false
            customDeadline = try values.decodeIfPresent(Date.self, forKey: .customDeadline) ?? Date().addingTimeInterval(3600)
        }
    }

    private static let storageKey = "lumen.dynamicIsland.configuration"
    private let defaults: UserDefaults

    var enabled = true { didSet { save() } }
    var kind: ContentKind = .nextCourse { didSet { save() } }
    var customTitle = "东大提醒" { didSet { save() } }
    var customSubtitle = "自定义你的实时活动内容" { didSet { save() } }
    var customValue = "" { didSet { save() } }
    var customIcon = "sparkles" { didSet { save() } }
    var accent = "cyan" { didSet { save() } }
    var showProgress = true { didSet { save() } }
    var customDeadlineEnabled = false { didSet { save() } }
    var customDeadline = Date().addingTimeInterval(3600) { didSet { save() } }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        guard let data = defaults.data(forKey: Self.storageKey),
              let value = try? JSONDecoder().decode(Persisted.self, from: data) else { return }
        enabled = value.enabled
        kind = ContentKind(rawValue: value.kind) ?? .nextCourse
        customTitle = String(value.customTitle.prefix(80))
        customSubtitle = String(value.customSubtitle.prefix(160))
        customValue = String(value.customValue.prefix(32))
        customIcon = LiveActivityDataPolicy.symbol(value.customIcon)
        accent = LiveActivityDataPolicy.accent(value.accent)
        showProgress = value.showProgress
        customDeadlineEnabled = value.customDeadlineEnabled
        customDeadline = value.customDeadline.timeIntervalSinceReferenceDate.isFinite
            ? value.customDeadline : Date().addingTimeInterval(3600)
    }

    func reset() {
        enabled = true
        kind = .nextCourse
        customTitle = "东大提醒"
        customSubtitle = "自定义你的实时活动内容"
        customValue = ""
        customIcon = "sparkles"
        accent = "cyan"
        showProgress = true
        customDeadlineEnabled = false
        customDeadline = Date().addingTimeInterval(3600)
    }

    private func save() {
        var value = Persisted()
        value.enabled = enabled
        value.kind = kind.rawValue
        value.customTitle = String(customTitle.prefix(80))
        value.customSubtitle = String(customSubtitle.prefix(160))
        value.customValue = String(customValue.prefix(32))
        value.customIcon = LiveActivityDataPolicy.symbol(customIcon)
        value.accent = LiveActivityDataPolicy.accent(accent)
        value.showProgress = showProgress
        value.customDeadlineEnabled = customDeadlineEnabled
        value.customDeadline = customDeadline.timeIntervalSinceReferenceDate.isFinite
            ? customDeadline : Date().addingTimeInterval(3600)
        guard let data = try? JSONEncoder().encode(value) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }
}

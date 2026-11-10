import Foundation
import Observation

/// 应用内灵动岛的展示配置。配置只保存显示偏好，不保存任何账号或校园数据。
@MainActor
@Observable
final class DynamicIslandStore {
    enum ContentKind: String, CaseIterable, Identifiable {
        case nextCourse
        case cardBalance
        case custom

        var id: String { rawValue }

        var title: String {
            switch self {
            case .nextCourse: return "下一节课"
            case .cardBalance: return "校园卡余额"
            case .custom: return "自定义内容"
            }
        }

        var icon: String {
            switch self {
            case .nextCourse: return "book.closed.fill"
            case .cardBalance: return "creditcard.fill"
            case .custom: return "sparkles"
            }
        }
    }

    private struct Persisted: Codable {
        var enabled: Bool
        var kind: String
        var customTitle: String
        var customSubtitle: String
    }

    private static let storageKey = "lumen.dynamicIsland.configuration"
    private let defaults: UserDefaults

    var enabled = true { didSet { save() } }
    var kind: ContentKind = .nextCourse { didSet { save() } }
    var customTitle = "东大提醒" { didSet { save() } }
    var customSubtitle = "自定义你的灵动岛内容" { didSet { save() } }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        guard let data = defaults.data(forKey: Self.storageKey),
              let value = try? JSONDecoder().decode(Persisted.self, from: data) else { return }
        enabled = value.enabled
        kind = ContentKind(rawValue: value.kind) ?? .nextCourse
        customTitle = value.customTitle
        customSubtitle = value.customSubtitle
    }

    func reset() {
        enabled = true
        kind = .nextCourse
        customTitle = "东大提醒"
        customSubtitle = "自定义你的灵动岛内容"
    }

    private func save() {
        let value = Persisted(enabled: enabled, kind: kind.rawValue,
                              customTitle: customTitle, customSubtitle: customSubtitle)
        guard let data = try? JSONEncoder().encode(value) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }
}

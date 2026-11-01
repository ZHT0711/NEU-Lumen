import Foundation

/// 分类来自门户数据，按应用数量降序排列；同数量时保持稳定顺序。
struct ServiceCategory: Identifiable, Equatable {
    let name: String
    let count: Int

    var id: String { name }
}

struct ServiceCatalog {
    let apps: [PortalApp]

    /// 沿用 Flutter 的入口选择：门户 e码通/校园码 → 一卡通 SSO。
    var ecodeURL: URL {
        let preferred = apps.filter {
            $0.name.localizedCaseInsensitiveContains("e码通") || $0.name.contains("校园码")
        }
        let card = apps.filter {
            URL(string: $0.entryUrl())?.host == "ecard.neu.edu.cn"
        }
        for app in preferred + card {
            if let url = URL(string: app.entryUrl()), ["http", "https"].contains(url.scheme ?? "") {
                return url
            }
        }
        return URL(string: "http://ecard.neu.edu.cn/selflogin/login.aspx")!
    }

    /// 短的公开目录不删除已有入口；新响应优先更新同一应用的非空字段。
    static func merging(_ catalogs: [[PortalApp]]) -> [PortalApp] {
        var order: [String] = []
        var merged: [String: PortalApp] = [:]
        func pick(_ next: String, _ old: String) -> String { next.isEmpty ? old : next }
        for app in catalogs.flatMap({ $0 }) where !app.name.isEmpty {
            let key = app.appId.isEmpty ? "name:" + app.name : "id:" + app.appId
            if let old = merged[key] {
                merged[key] = PortalApp(name: app.name, appId: app.appId,
                    url: pick(app.url, old.url), mobileUrl: pick(app.mobileUrl, old.mobileUrl),
                    iconUrl: pick(app.iconUrl, old.iconUrl), desc: pick(app.desc, old.desc),
                    category: pick(app.category, old.category), visits: app.visits)
            } else {
                order.append(key)
                merged[key] = app
            }
        }
        return order.compactMap { merged[$0] }
    }

    var categories: [ServiceCategory] {
        Dictionary(grouping: apps, by: \.serviceCategory)
            .map { ServiceCategory(name: $0.key, count: $0.value.count) }
            .sorted {
                $0.count == $1.count ? $0.name < $1.name : $0.count > $1.count
            }
    }

    func filtered(query: String, category: String?) -> [PortalApp] {
        let keyword = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return apps.filter { app in
            let matchesCategory = category == nil || app.serviceCategory == category
            let matchesQuery = keyword.isEmpty
                || app.name.localizedCaseInsensitiveContains(keyword)
                || app.desc.localizedCaseInsensitiveContains(keyword)
                || app.serviceCategory.localizedCaseInsensitiveContains(keyword)
            return matchesCategory && matchesQuery
        }
    }
}

extension PortalApp {
    var serviceCategory: String {
        let trimmed = category.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "其他服务" : trimmed
    }
}

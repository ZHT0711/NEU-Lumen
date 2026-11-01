import Foundation

/// 分类来自门户数据，按应用数量降序排列；同数量时保持稳定顺序。
struct ServiceCategory: Identifiable, Equatable {
    let name: String
    let count: Int

    var id: String { name }
}

struct ServiceCatalog {
    let apps: [PortalApp]

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

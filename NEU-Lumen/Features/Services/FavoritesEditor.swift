import SwiftUI

struct FavoritesEditor: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    private var repo: PortalRepository { environment.repository }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("收藏与首页常用应用实时联动，首页显示前 8 项。拖动右侧手柄排序，点击减号移除。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("我的收藏（\(repo.favorites.ids.count)）") {
                    ForEach(repo.favorites.ids, id: \.self) { id in
                        HStack {
                            if let app = repo.apps.first(where: { $0.id == id }) {
                                Text(app.name)
                            } else {
                                Text("暂不可用的服务").foregroundStyle(.secondary)
                            }
                        }
                    }
                    .onDelete { offsets in
                        for index in offsets.sorted().reversed() {
                            if let app = repo.apps.first(where: { $0.id == repo.favorites.ids[index] }) {
                                repo.favorites.toggle(app)
                            } else { repo.favorites.remove(id: repo.favorites.ids[index]) }
                        }
                    }
                    .onMove { repo.favorites.move(from: $0, to: $1) }
                }
                Section("添加服务") {
                    ForEach(ServiceCatalog(apps: repo.apps).filtered(query: query, category: nil).filter { !repo.favorites.contains($0) }) { app in
                        Button { repo.favorites.toggle(app) } label: {
                            Label(app.name, systemImage: "plus.circle.fill")
                        }
                        .deleteDisabled(true).moveDisabled(true)
                    }
                }
                Section {
                    Button("恢复默认常用应用") { repo.favorites.reset(apps: repo.apps) }
                }
            }
            .environment(\.editMode, .constant(.active))
            .searchable(text: $query, prompt: "搜索可添加的服务")
            .navigationTitle("编辑常用与收藏")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
            .task { await repo.loadAppsIfNeeded() }
        }
    }
}

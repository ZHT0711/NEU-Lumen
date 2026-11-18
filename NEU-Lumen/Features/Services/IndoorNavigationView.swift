import SwiftUI
import Observation

@MainActor @Observable
final class IndoorNavigationStore {
    private(set) var catalog: IndoorCatalog?
    private(set) var campus = "south"
    private(set) var buildingID = ""
    private(set) var startID = ""
    private(set) var endID = ""
    var preference = IndoorRoutePreference.shortest
    private(set) var route: IndoorRoute?
    private(set) var loading = false
    private(set) var error: String?
    private var destination = ""
    private var request = UUID()
    private var prepared = false
    private let client = PathlyClient.shared
    private let defaults = UserDefaults.standard
    var buildings: [IndoorBuilding] { catalog?.buildings.filter { $0.campus == campus } ?? [] }
    var building: IndoorBuilding? { buildings.first { $0.id == buildingID } }
    var start: IndoorRoom? { building?.room(startID) }
    var end: IndoorRoom? { building?.room(endID) }
    var selectionKey: String { [buildingID, startID, endID, preference.rawValue].joined(separator: "|") }
    var canSearch: Bool { building != nil && start != nil && end != nil && startID != endID }

    func prepare(destination: String, campus: String) {
        guard !prepared else { return }
        self.destination = destination
        do {
            catalog = try IndoorCatalog.bundled()
            self.campus = destination.contains("南湖") ? "main" : destination.contains("浑南") ? "south" : campus
            let saved = defaults.string(forKey: "lumen.pathly.building." + self.campus)
            let named = buildings.filter { destination.contains($0.name) || destination.contains($0.name.replacingOccurrences(of: "楼", with: "教学楼")) }.max { $0.name.count < $1.name.count }
            if let selected = named ?? buildings.first(where: { $0.id == saved }) ?? buildings.first { selectBuilding(selected.id) }
            prepared = true
        } catch { self.error = IndoorNavigationError.catalog.localizedDescription }
    }
    func selectCampus(_ value: String) {
        guard campus != value else { return }
        campus = value
        let saved = defaults.string(forKey: "lumen.pathly.building." + campus)
        selectBuilding(buildings.first(where: { $0.id == saved })?.id ?? buildings.first?.id ?? "")
    }
    func selectBuilding(_ value: String) {
        cancel(); route = nil; error = nil
        buildingID = value; startID = ""; endID = ""
        guard let building else { return }
        defaults.set(building.id, forKey: "lumen.pathly.building." + campus)
        let savedStart = defaults.string(forKey: "lumen.pathly.start." + building.id) ?? ""
        let savedEnd = defaults.string(forKey: "lumen.pathly.end." + building.id) ?? ""
        if building.room(savedStart) != nil { startID = savedStart }
        let matches = building.matchingRooms(destination)
        if !destination.isEmpty {
            if matches.count == 1 { endID = matches[0].id }
        } else if building.room(savedEnd) != nil { endID = savedEnd }
    }
    func select(_ room: IndoorRoom, forStart: Bool) {
        guard building?.room(room.id) != nil else { return }
        clearRoute()
        if forStart { startID = room.id } else { endID = room.id }
    }
    func swap() { let previous = startID; startID = endID; endID = previous; clearRoute() }
    func cancel() { request = UUID(); loading = false }
    func clearRoute() { cancel(); route = nil; error = nil }
    func search() async {
        guard let building, canSearch else { error = IndoorNavigationError.endpoints.localizedDescription; return }
        let token = UUID(); request = token
        let start = startID, end = endID, selected = preference
        loading = true; error = nil; route = nil
        defer { if request == token { loading = false } }
        do {
            let result = try await client.route(building: building, start: start, end: end, preference: selected)
            guard request == token, !Task.isCancelled else { return }
            route = result
            defaults.set(start, forKey: "lumen.pathly.start." + building.id)
            defaults.set(end, forKey: "lumen.pathly.end." + building.id)
        } catch {
            guard request == token, !Task.isCancelled else { return }
            self.error = (error as? IndoorNavigationError)?.localizedDescription ?? IndoorNavigationError.unavailable.localizedDescription
        }
    }
}

private struct IndoorPointSelection: Identifiable {
    let forStart: Bool
    var id: Bool { forStart }
}

struct IndoorNavigationView: View {
    var destination = ""
    @Environment(AppEnvironment.self) private var environment
    @State private var store = IndoorNavigationStore()
    @State private var picker: IndoorPointSelection?
    @State private var searchTask: Task<Void, Never>?

    var body: some View {
        @Bindable var store = store
        ScrollViewReader { proxy in
        Form {
            if !destination.isEmpty {
                Section("课程地点") { Text(destination).textSelection(.enabled) }
            }
            Section("校区与教学楼") {
                Picker("校区", selection: Binding(get: { store.campus }, set: { store.selectCampus($0) })) {
                    Text("南湖校区").tag("main")
                    Text("浑南校区").tag("south")
                }.pickerStyle(.segmented)
                Picker("教学楼", selection: Binding(get: { store.buildingID }, set: { store.selectBuilding($0) })) {
                    ForEach(store.buildings) { Text($0.name).tag($0.id) }
                }
            }
            Section("起点与终点") {
                pointButton(title: "起点", room: store.start, forStart: true)
                pointButton(title: "终点", room: store.end, forStart: false)
                Button("交换起终点", systemImage: "arrow.up.arrow.down") { store.swap() }
                    .disabled(store.start == nil && store.end == nil)
                if store.start != nil, store.startID == store.endID {
                    Text("起点与终点相同，请调整一个地点。").font(.caption).foregroundStyle(.secondary)
                }
            }
            Section {
                Picker("路线偏好", selection: $store.preference) {
                    ForEach(IndoorRoutePreference.allCases) { Text($0.title).tag($0) }
                }.pickerStyle(.segmented)
                Button {
                    searchTask?.cancel()
                    searchTask = Task { await store.search() }
                } label: { Label("规划楼内路线", systemImage: "figure.walk").frame(maxWidth: .infinity) }
                    .disabled(!store.canSearch || store.loading)
                if store.loading { ProgressView("正在规划路线…") }
                if let error = store.error { Text(error).font(.subheadline).foregroundStyle(.orange) }
            } header: { Text("路线偏好") } footer: {
                Text("请选择你所在的起点。楼层图和寻路服务由 Pathly 提供。")
            }
            if let route = store.route {
                Section("导航路线 · \(route.steps.count) 段") {
                    if route.usesElevator {
                        Label("路线包含电梯，高峰时可改选“避开电梯”重新规划。", systemImage: "arrow.up.arrow.down.square")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    ForEach(route.steps) { step in
                        if step.isVertical {
                            Label(step.title, systemImage: step.elevator ? "arrow.up.arrow.down.square" : "stairs")
                                .font(.headline).padding(.vertical, 10)
                        } else {
                            IndoorRouteMapCard(step: step, first: route.steps.first(where: { !$0.isVertical })?.id == step.id,
                                               last: route.steps.last(where: { !$0.isVertical })?.id == step.id)
                        }
                    }
                }.id("indoor-route")
            }
            Section("跨建筑出行") {
                NavigationLink("规划跨楼路线", destination: CampusJourneyView(destination: destination))
            }
            Section { Link("Pathly 原站", destination: URL(string: "https://pathly.top/user/user-path")!) }
        }
        .onChange(of: store.route != nil) { _, ready in
            if ready { withAnimation { proxy.scrollTo("indoor-route", anchor: .top) } }
        }
        }
        .navigationTitle("楼内导航")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .task { store.prepare(destination: destination, campus: environment.repository.campus == .hunnan ? "south" : "main") }
        .onChange(of: store.selectionKey) { _, _ in searchTask?.cancel(); store.clearRoute() }
        .onDisappear { searchTask?.cancel(); store.cancel() }
        .sheet(item: $picker) { selection in
            if let building = store.building {
                IndoorPointPicker(building: building, selected: selection.forStart ? store.startID : store.endID, forStart: selection.forStart) { room in
                    store.select(room, forStart: selection.forStart)
                }
            }
        }
    }
    private func pointButton(title: String, room: IndoorRoom?, forStart: Bool) -> some View {
        Button { picker = IndoorPointSelection(forStart: forStart) } label: {
            HStack {
                Label(title, systemImage: forStart ? "location.circle" : "mappin.circle")
                Spacer()
                VStack(alignment: .trailing, spacing: 3) {
                    Text(room?.title ?? "请选择").foregroundStyle(room == nil ? .secondary : .primary)
                    if let room, let building = store.building { Text(building.floorName(for: room)).font(.caption).foregroundStyle(.secondary) }
                }
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
            }.foregroundStyle(.primary)
        }.disabled(store.building == nil)
    }
}

struct IndoorPointPicker: View {
    let building: IndoorBuilding
    let selected: String
    let forStart: Bool
    let choose: (IndoorRoom) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var floor = -1
    @State private var reference: IndoorReferenceImage?
    var body: some View {
        NavigationStack {
            List {
                Picker("楼层", selection: $floor) {
                    Text("全部楼层").tag(-1)
                    ForEach(building.floors) { Text($0.name).tag($0.id) }
                }
                if let url = building.gateImageURL {
                    Button("查看楼门平面图", systemImage: "door.left.hand.open") {
                        reference = IndoorReferenceImage(title: building.name + " · 楼门平面图", url: url)
                    }
                }
                ForEach(building.floors.filter { floor == -1 || $0.id == floor }) { level in
                    let rooms = level.uniqueRooms.filter { query.isEmpty || $0.title.localizedCaseInsensitiveContains(query) }
                    if !rooms.isEmpty {
                        Section(level.name) {
                            let references = building.elevatorReferences(on: level)
                            if references.count == 1, let url = references.first?.url {
                                Button("查看本层电梯位置", systemImage: "arrow.up.arrow.down.square") {
                                    reference = IndoorReferenceImage(title: building.name + " · " + level.name + "电梯", url: url)
                                }
                            } else if !references.isEmpty {
                                Menu("查看本层电梯位置", systemImage: "arrow.up.arrow.down.square") {
                                    ForEach(references) { image in
                                        Button(image.id + " 区电梯位置") {
                                            reference = IndoorReferenceImage(title: building.name + " · " + image.id + "区电梯", url: image.url)
                                        }
                                    }
                                }
                            }
                            ForEach(rooms) { room in
                                Button { choose(room); dismiss() } label: {
                                    HStack {
                                        Label(room.title, systemImage: room.isGate ? "door.left.hand.open" : room.isElevator ? "arrow.up.arrow.down.square" : "mappin")
                                        Spacer()
                                        if room.id == selected { Image(systemName: "checkmark") }
                                    }.foregroundStyle(.primary)
                                }
                            }
                        }
                    }
                }
            }
            .searchable(text: $query, prompt: "搜索教室、楼门或电梯")
            .navigationTitle(building.name + (forStart ? " · 起点" : " · 终点"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } } }
            .fullScreenCover(item: $reference) { image in
                NavigationStack {
                    IndoorReferenceMapView(reference: image)
                        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { reference = nil } } }
                }
            }
        }
    }
}

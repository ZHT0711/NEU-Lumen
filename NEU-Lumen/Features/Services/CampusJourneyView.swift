import SwiftUI
import MapKit
import Observation

struct JourneyDoor {
    let name: String
    let coordinate: CLLocationCoordinate2D
    var key: String { "\(coordinate.latitude)|\(coordinate.longitude)" }
    var mapItem: MKMapItem {
        let item: MKMapItem
        if #available(iOS 26.0, *) {
            item = MKMapItem(location: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude), address: nil)
        } else { item = MKMapItem(placemark: MKPlacemark(coordinate: coordinate)) }
        item.name = name
        return item
    }
}

@MainActor @Observable
final class CampusJourneyStore {
    private(set) var catalog: IndoorCatalog?
    private(set) var origin = CampusJourneyEndpoint()
    private(set) var destination = CampusJourneyEndpoint()
    private(set) var originDoor: JourneyDoor?
    private(set) var destinationDoor: JourneyDoor?
    var preference = IndoorRoutePreference.shortest
    private(set) var departure: IndoorRoute?
    private(set) var arrival: IndoorRoute?
    private(set) var outdoor: MKRoute?
    private(set) var loading = false
    private(set) var progress = ""
    private(set) var error: String?
    private var request = UUID()
    private var directions: MKDirections?
    private let defaults = UserDefaults.standard
    private let client = PathlyClient()
    var buildings: [IndoorBuilding] { catalog?.buildings ?? [] }
    func building(_ start: Bool) -> IndoorBuilding? {
        buildings.first { $0.id == (start ? origin.buildingID : destination.buildingID) }
    }
    var selectionKey: String {
        "\(origin)|\(destination)|\(originDoor?.key ?? "")|\(destinationDoor?.key ?? "")|\(preference.rawValue)"
    }
    var canPlan: Bool {
        guard let first = building(true), let last = building(false) else { return false }
        return first.id != last.id && origin.valid(in: first) && destination.valid(in: last) && originDoor != nil && destinationDoor != nil
    }
    func prepare(campus: String, target: String) {
        guard catalog == nil else { return }
        do {
            catalog = try IndoorCatalog.bundled()
            let local = buildings.filter { $0.campus == campus }
            let named = buildings.filter { target.contains($0.name) }.max { $0.name.count < $1.name.count }
            let end = named ?? local.dropFirst().first ?? buildings.last
            let start = local.first(where: { $0.id != end?.id }) ?? buildings.first
            if let start { selectBuilding(start.id, start: true) }
            if let end {
                selectBuilding(end.id, start: false)
                let matches = end.matchingRooms(target)
                if matches.count == 1 { selectRoom(matches[0].id, start: false) }
            }
        } catch { self.error = IndoorNavigationError.catalog.localizedDescription }
    }
    func selectBuilding(_ id: String, start: Bool) {
        clear()
        guard let building = buildings.first(where: { $0.id == id }) else { return }
        let point = CampusJourneyEndpoint(buildingID: id, roomID: "", gateID: building.gates.first?.id ?? "")
        if start { origin = point; originDoor = savedDoor(for: point) } else { destination = point; destinationDoor = savedDoor(for: point) }
    }
    func selectRoom(_ id: String, start: Bool) {
        clear()
        if start { origin.roomID = id } else { destination.roomID = id }
    }
    func selectGate(_ id: String, start: Bool) {
        clear()
        if start { origin.gateID = id; originDoor = savedDoor(for: origin) }
        else { destination.gateID = id; destinationDoor = savedDoor(for: destination) }
    }
    func setDoor(_ door: JourneyDoor, start: Bool) {
        guard CLLocationCoordinate2DIsValid(door.coordinate) else { return }
        clear()
        if start { originDoor = door } else { destinationDoor = door }
        let point = start ? origin : destination
        defaults.set(["latitude": door.coordinate.latitude, "longitude": door.coordinate.longitude], forKey: doorKey(point))
    }
    private func doorKey(_ point: CampusJourneyEndpoint) -> String { "lumen.pathly.confirmedDoor." + point.buildingID + "." + point.gateID }
    private func savedDoor(for point: CampusJourneyEndpoint) -> JourneyDoor? {
        guard let saved = defaults.dictionary(forKey: doorKey(point)), let latitude = saved["latitude"] as? Double,
              let longitude = saved["longitude"] as? Double, let building = buildings.first(where: { $0.id == point.buildingID }),
              let gate = building.room(point.gateID) else { return nil }
        let coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        guard CLLocationCoordinate2DIsValid(coordinate) else { return nil }
        return JourneyDoor(name: building.name + " · " + gate.title, coordinate: coordinate)
    }
    func swap() {
        clear()
        let point = origin, door = originDoor
        origin = destination; originDoor = destinationDoor
        destination = point; destinationDoor = door
    }
    func cancel() { request = UUID(); directions?.cancel(); directions = nil; loading = false }
    func clear() { cancel(); departure = nil; arrival = nil; outdoor = nil; error = nil }
    func plan() async {
        guard canPlan, let first = building(true), let last = building(false),
              let from = originDoor, let to = destinationDoor else { return }
        clear()
        let token = request, a = origin, b = destination, selectedPreference = preference
        loading = true
        defer { if request == token { loading = false; directions = nil } }
        do {
            progress = "规划起点楼内路线…"
            var firstLeg: IndoorRoute?
            if let leg = try a.indoorLeg(in: first, departing: true) {
                firstLeg = try await client.route(building: first, start: leg.start, end: leg.end, preference: selectedPreference)
            }
            guard request == token, !Task.isCancelled else { return }
            progress = "读取 Apple 地图步行路线…"
            let query = MKDirections.Request()
            query.source = from.mapItem; query.destination = to.mapItem; query.transportType = .walking
            query.requestsAlternateRoutes = true
            let operation = MKDirections(request: query); directions = operation
            let response = try await operation.calculate()
            guard request == token, !Task.isCancelled else { return }
            guard let index = CampusWalkingRoutePolicy.shortestIndex(response.routes.map { ($0.distance, $0.expectedTravelTime) }) else {
                throw NetworkError(message: "Apple 地图暂未提供两处楼门之间的步行路线，可调整定位或在地图 App 中选择其他出行方式。")
            }
            let route = response.routes[index]
            progress = "规划终点楼内路线…"
            var finalLeg: IndoorRoute?
            if let leg = try b.indoorLeg(in: last, departing: false) {
                finalLeg = try await client.route(building: last, start: leg.start, end: leg.end, preference: selectedPreference)
            }
            guard request == token, !Task.isCancelled else { return }
            departure = firstLeg; outdoor = route; arrival = finalLeg
        } catch {
            guard request == token, !Task.isCancelled else { return }
            self.error = progress.replacingOccurrences(of: "…", with: "") + "未完成：" + NetworkError.from(error).message
        }
    }
    func openMaps() {
        guard let originDoor, let destinationDoor else { return }
        MKMapItem.openMaps(with: [originDoor.mapItem, destinationDoor.mapItem],
                          launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeWalking])
    }
}

private struct JourneySelection: Identifiable {
    let start: Bool
    let door: Bool
    var id: String { "\(start)|\(door)" }
}

struct CampusJourneyView: View {
    var destination = ""
    @Environment(AppEnvironment.self) private var environment
    @State private var store = CampusJourneyStore()
    @State private var selection: JourneySelection?
    @State private var refresh = 0
    private var intelligenceKey: String {
        "\(store.selectionKey)|\(store.outdoor?.distance ?? -1)|\(environment.repository.intelligence.preferences)|\(environment.repository.intelligence.available)"
    }
    var body: some View {
        @Bindable var store = store
        Form {
            Section {
                Label("教室 → 出口 → 室外步行 → 入口 → 教室", systemImage: "figure.walk")
                    .font(.subheadline)
                Text("选好两栋楼内的地点并确认楼门位置后，自动衔接楼内路线和室外最短步行方案。已确认的楼门位置会保存在本机，下次可直接使用。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            endpoint(start: true)
            Section { Button("交换起终点", systemImage: "arrow.up.arrow.down") { store.swap() } }
            endpoint(start: false)
            Section {
                Picker("楼内偏好", selection: $store.preference) {
                    ForEach(IndoorRoutePreference.allCases) { Text($0.title).tag($0) }
                }.pickerStyle(.segmented)
                Text("电梯偏好仅应用于楼内段，不能据此认定整条路线无障碍。")
                    .font(.caption).foregroundStyle(.secondary)
                if store.origin.buildingID == store.destination.buildingID {
                    Text("起终点在同一栋楼时，请使用楼内导航。").font(.caption).foregroundStyle(.secondary)
                }
                Button("重新规划完整路线", systemImage: "point.topleft.down.to.point.bottomright.curvepath") {
                    refresh += 1
                }.disabled(!store.canPlan || store.loading)
                if store.loading { ProgressView(store.progress) }
                if let error = store.error { Text(error).font(.subheadline).foregroundStyle(.orange) }
                Button("在 Apple 地图中规划室外段", systemImage: "map") { store.openMaps() }
                    .disabled(store.originDoor == nil || store.destinationDoor == nil)
            } header: { Text("规划出行") } footer: {
                Text("楼内图与路线由 Pathly 提供，室外路线由 Apple 地图提供。校园围栏、楼门开放和临时施工请以现场为准。")
            }
            if let outdoor = store.outdoor {
                if let digest = environment.repository.intelligenceDigest(for: .journey) {
                    Section { CampusIntelligenceDigestView(title: "路线速览", digest: digest) }
                }
                indoorLeg(store.departure, title: "1 · 从起点前往出口", start: true)
                Section("2 · 两栋楼之间步行") {
                    JourneyOutdoorMap(route: outdoor, origin: store.originDoor, destination: store.destinationDoor)
                    LabeledContent("室外距离", value: outdoor.distance.formatted(.number.precision(.fractionLength(0))) + " 米")
                    LabeledContent("室外预计耗时", value: "约 \(max(1, Int(ceil(outdoor.expectedTravelTime / 60)))) 分钟")
                    Text("已选择 Apple 地图本次返回方案中距离最短的一条。")
                        .font(.caption).foregroundStyle(.secondary)
                    Text("预计时间仅包含室外段，不含楼内步行、候梯和进出楼时间。")
                        .font(.caption).foregroundStyle(.secondary)
                    if store.building(true)?.campus != store.building(false)?.campus {
                        Text("这是跨校区行程，建议在 Apple 地图中比较公交或驾车方案。")
                            .font(.subheadline).foregroundStyle(.orange)
                    }
                    ForEach(Array(outdoor.steps.enumerated()), id: \.offset) { _, step in
                        if !step.instructions.isEmpty {
                            Label(step.instructions, systemImage: "figure.walk").font(.subheadline)
                        }
                    }
                    Button("打开 Apple 地图导航", systemImage: "arrow.triangle.turn.up.right.diamond") { store.openMaps() }
                }
                indoorLeg(store.arrival, title: "3 · 从入口前往终点", start: false)
            }
        }
        .navigationTitle("跨楼路线").navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .task { store.prepare(campus: environment.repository.campus == .hunnan ? "south" : "main", target: destination) }
        .task(id: store.selectionKey + "|\(refresh)") {
            store.clear()
            guard store.canPlan else { return }
            do { try await Task.sleep(for: .milliseconds(400)) } catch { return }
            await store.plan()
        }
        .task(id: intelligenceKey) {
            guard let route = store.outdoor else { environment.repository.intelligence.clear(.journey); return }
            let facts = ["起点": store.originDoor?.name ?? "", "终点": store.destinationDoor?.name ?? "",
                         "室外距离": "\(Int(route.distance.rounded())) 米", "室外用时": "约 \(max(1, Int(ceil(route.expectedTravelTime / 60)))) 分钟",
                         "说明": "室外返回方案中距离最短，时间不包含楼内步行和候梯",
                         "步行指引": route.steps.prefix(12).map { String($0.instructions.prefix(100)) }.joined(separator: "；")]
            let input = CampusIntelligenceInput(feature: .journey, payload: CampusIntelligenceInput.encode(facts), caption: "根据 Pathly 楼内段与 Apple 地图室外段规划")
            environment.repository.intelligence.request(input, for: .journey)
        }
        .onDisappear { store.cancel(); environment.repository.intelligence.clear(.journey) }
        .sheet(item: $selection) { selection in
            if let building = store.building(selection.start) {
                if selection.door {
                    let endpoint = selection.start ? store.origin : store.destination
                    JourneyDoorPicker(building: building, gate: building.room(endpoint.gateID)?.title ?? "楼门",
                                      existing: selection.start ? store.originDoor : store.destinationDoor) {
                        store.setDoor($0, start: selection.start)
                    }
                } else {
                    IndoorPointPicker(building: building, selected: selection.start ? store.origin.roomID : store.destination.roomID,
                                      forStart: selection.start) { store.selectRoom($0.id, start: selection.start) }
                }
            }
        }
    }
    private func endpoint(start: Bool) -> some View {
        let endpoint = start ? store.origin : store.destination
        let building = store.building(start)
        let door = start ? store.originDoor : store.destinationDoor
        return Section(start ? "起点建筑" : "终点建筑") {
            Picker("教学楼", selection: Binding(get: { endpoint.buildingID }, set: { store.selectBuilding($0, start: start) })) {
                ForEach(store.buildings) { Text($0.campusName + " · " + $0.name).tag($0.id) }
            }
            Button { selection = JourneySelection(start: start, door: false) } label: {
                LabeledContent(start ? "出发地点" : "目的地", value: building?.room(endpoint.roomID)?.title ?? "选择教室或楼门")
            }.disabled(building == nil)
            Picker(start ? "离开建筑的出口" : "进入建筑的入口",
                   selection: Binding(get: { endpoint.gateID }, set: { store.selectGate($0, start: start) })) {
                ForEach(building?.gates ?? []) { Text($0.title).tag($0.id) }
            }
            Button { selection = JourneySelection(start: start, door: true) } label: {
                Label(door == nil ? "在地图上确认楼门位置" : "楼门位置已确认 · 可调整",
                      systemImage: door == nil ? "mappin.and.ellipse" : "checkmark.circle")
            }.disabled(building?.room(endpoint.gateID) == nil)
            if building?.gates.isEmpty == true { Text("该建筑暂无楼门点位，暂不能衔接跨楼路线。").font(.caption) }
        }
    }
    @ViewBuilder private func indoorLeg(_ route: IndoorRoute?, title: String, start: Bool) -> some View {
        Section(title) {
            if let route {
                ForEach(route.steps) { step in
                    if step.isVertical { Label(step.title, systemImage: step.elevator ? "arrow.up.arrow.down.square" : "stairs") }
                    else { IndoorRouteMapCard(step: step, first: route.steps.first(where: { !$0.isVertical })?.id == step.id,
                                              last: route.steps.last(where: { !$0.isVertical })?.id == step.id) }
                }
            } else {
                Text(start ? "起点就是所选出口，可直接离楼。" : "终点就是所选入口，到达楼门后结束。")
            }
        }
    }
}

private struct JourneyOutdoorMap: View {
    let route: MKRoute
    let origin: JourneyDoor?
    let destination: JourneyDoor?
    var body: some View {
        Map {
            if let origin { Marker("出口 · " + origin.name, coordinate: origin.coordinate).tint(.blue) }
            if let destination { Marker("入口 · " + destination.name, coordinate: destination.coordinate).tint(.red) }
            MapPolyline(route.polyline).stroke(.blue, lineWidth: 5)
        }.mapControls { MapCompass(); MapScaleView() }
            .frame(height: 280).clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

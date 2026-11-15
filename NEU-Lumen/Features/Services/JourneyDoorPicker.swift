import SwiftUI
import MapKit

struct JourneyDoorPicker: View {
    let building: IndoorBuilding
    let gate: String
    let existing: JourneyDoor?
    let choose: (JourneyDoor) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var camera: MapCameraPosition = .automatic
    @State private var door: JourneyDoor?
    @State private var query = ""
    @State private var results: [CampusMapPlace] = []
    @State private var region: MKCoordinateRegion?
    @State private var operation: MKLocalSearch?
    @State private var task: Task<Void, Never>?
    @State private var request = UUID()
    @State private var loading = false
    @State private var error: String?
    @State private var prepared = false
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text(building.campusName + " · " + building.name + " · " + gate).font(.headline)
                    Text("搜索建筑后放大地图，点按实际楼门的位置。建筑检索结果不能直接代表楼门，确认后再用于室外步行段。")
                        .font(.subheadline).foregroundStyle(.secondary)
                    HStack {
                        TextField("搜索建筑或附近地标", text: $query).submitLabel(.search).onSubmit { startSearch() }
                        Button("搜索") { startSearch() }.disabled(loading)
                    }.padding(12).background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
                    MapReader { proxy in
                        Map(position: $camera) {
                            if let door { Marker("待确认楼门", coordinate: door.coordinate).tint(.blue) }
                        }
                        .mapControls { MapCompass(); MapScaleView() }
                        .onTapGesture { point in
                            guard let coordinate = proxy.convert(point, from: .local), CLLocationCoordinate2DIsValid(coordinate) else { return }
                            door = JourneyDoor(name: building.name + " · " + gate, coordinate: coordinate)
                        }
                    }.frame(height: 330).clipShape(RoundedRectangle(cornerRadius: 16))
                    if let door {
                        Text("选中坐标：\(door.coordinate.latitude.formatted(.number.precision(.fractionLength(5))))，\(door.coordinate.longitude.formatted(.number.precision(.fractionLength(5))))")
                            .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                    }
                    if loading { ProgressView("正在搜索 Apple 地图…") }
                    if let error { Text(error).font(.subheadline).foregroundStyle(.orange) }
                    ForEach(results) { result in
                        Button {
                            // Candidate locations only position the viewport. A separate
                            // map tap confirms the actual exit/entrance used for routing.
                            door = nil
                            camera = .region(MKCoordinateRegion(center: result.coordinate, latitudinalMeters: 450, longitudinalMeters: 450))
                        } label: {
                            Label(result.item.name ?? "地图地点", systemImage: "magnifyingglass")
                                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        }
                    }
                    if let url = building.gateImageURL {
                        NavigationLink("对照 Pathly 楼门平面图") {
                            IndoorReferenceMapView(reference: IndoorReferenceImage(title: building.name + " · 楼门", url: url))
                        }
                    }
                }.padding(16)
            }
            .navigationTitle("确认楼门位置").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("使用此位置") { if let door { choose(door); dismiss() } }.disabled(door == nil)
                }
            }
            .task {
                guard !prepared else { return }
                prepared = true
                door = existing
                query = "东北大学 " + building.campusName + " " + building.name
                if let existing { camera = .region(MKCoordinateRegion(center: existing.coordinate, latitudinalMeters: 450, longitudinalMeters: 450)) }
                await search()
            }
            .onDisappear { request = UUID(); task?.cancel(); operation?.cancel() }
        }
    }
    private func startSearch() { task?.cancel(); operation?.cancel(); task = Task { await search() } }
    @MainActor private func search() async {
        let token = UUID(); request = token
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { return }
        loading = true; error = nil; results = []
        defer { if request == token { loading = false; operation = nil } }
        do {
            if region == nil {
                let campus: Campus = building.campus == "south" ? .hunnan : .nanhu
                let anchorQuery = MKLocalSearch.Request()
                anchorQuery.naturalLanguageQuery = "东北大学 " + campus.title + " " + campus.address
                let anchorSearch = MKLocalSearch(request: anchorQuery); operation = anchorSearch
                let response = try await anchorSearch.start()
                guard request == token, !Task.isCancelled else { return }
                if let anchor = response.mapItems.first(where: { ($0.name ?? "").contains("东北大学") }) {
                    let center = CampusMapPlace(item: anchor).coordinate
                    region = MKCoordinateRegion(center: center, latitudinalMeters: 2500, longitudinalMeters: 2500)
                    if door == nil, let region { camera = .region(region) }
                }
            }
            let query = MKLocalSearch.Request(); query.naturalLanguageQuery = term
            if let region { query.region = region }
            let search = MKLocalSearch(request: query); operation = search
            let response = try await search.start()
            guard request == token, !Task.isCancelled else { return }
            results = response.mapItems.map(CampusMapPlace.init)
            if results.isEmpty { error = "未找到该建筑，可更换地标关键词，或直接在地图上放大选取楼门。" }
        } catch {
            guard request == token, !Task.isCancelled else { return }
            self.error = "地图检索暂不可用，可重试；已确认的位置仍会保留。"
        }
    }
}

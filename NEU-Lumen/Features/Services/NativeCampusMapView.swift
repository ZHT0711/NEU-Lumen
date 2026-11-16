import SwiftUI
import MapKit
import Observation

struct CampusMapPlace: Identifiable {
    let item: MKMapItem
    var coordinate: CLLocationCoordinate2D {
        if #available(iOS 26.0, *) { return item.location.coordinate }
        else { return item.placemark.coordinate }
    }
    var id: String { "\(item.name ?? "")|\(coordinate.latitude)|\(coordinate.longitude)" }
}

private struct CampusEntranceMapPlace: Identifiable {
    let building: IndoorBuilding
    let entrance: CampusEntrance
    var id: String { entrance.id }
    var title: String { building.name + " · " + (building.room(entrance.gateID)?.title ?? "楼门") }
    var door: JourneyDoor {
        JourneyDoor(name: title, coordinate: CLLocationCoordinate2D(latitude: entrance.latitude, longitude: entrance.longitude),
                    approximateAccuracyMeters: entrance.approximateAccuracyMeters)
    }
}

@MainActor @Observable
final class CampusMapStore {
    private(set) var places: [CampusMapPlace] = []
    private(set) var loading = false
    private(set) var error: String?
    private var operation: MKLocalSearch?
    private var request = UUID()
    private var anchors: [String: MKMapItem] = [:]

    func cancel() {
        request = UUID()
        operation?.cancel()
        operation = nil
        loading = false
    }

    func search(campus: Campus, keyword: String) async {
        cancel()
        let token = request
        loading = true
        error = nil
        places = []
        defer { if request == token { loading = false } }
        do {
            let anchor: MKMapItem
            if let cached = anchors[campus.rawValue] { anchor = cached }
            else {
                let query = MKLocalSearch.Request()
                query.naturalLanguageQuery = "东北大学 " + campus.title + " " + campus.address
                let search = MKLocalSearch(request: query)
                operation = search
                let response = try await search.start()
                guard request == token, !Task.isCancelled else { return }
                guard let match = response.mapItems.first(where: { ($0.name ?? "").contains("东北大学") }) else {
                    throw NetworkError(message: "地图暂未返回该校区，请稍后重试")
                }
                anchor = match
                anchors[campus.rawValue] = match
            }
            guard request == token, !Task.isCancelled else { return }
            let center = CampusMapPlace(item: anchor).coordinate
            let term = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
            if term.isEmpty { places = [CampusMapPlace(item: anchor)]; return }
            let query = MKLocalSearch.Request()
            query.naturalLanguageQuery = "东北大学 " + campus.title + " " + term
            query.region = MKCoordinateRegion(center: center, latitudinalMeters: 3500, longitudinalMeters: 3500)
            let search = MKLocalSearch(request: query)
            operation = search
            let response = try await search.start()
            guard request == token, !Task.isCancelled else { return }
            let origin = CLLocation(latitude: center.latitude, longitude: center.longitude)
            var seen = Set<String>()
            places = response.mapItems.map(CampusMapPlace.init).filter { place in
                let location = CLLocation(latitude: place.coordinate.latitude, longitude: place.coordinate.longitude)
                return location.distance(from: origin) <= 5000 && seen.insert(place.id).inserted
            }
        } catch {
            guard request == token, !Task.isCancelled else { return }
            self.error = NetworkError.from(error).message
        }
    }
}

struct NativeCampusMapView: View {
    var active = true
    var initialCampus: Campus?
    @Environment(AppEnvironment.self) private var environment
    @State private var store = CampusMapStore()
    @State private var campus = Campus.hunnan
    @State private var query = ""
    @State private var camera: MapCameraPosition = .automatic
    @State private var selected: String?
    @State private var owner: UUID?
    @State private var searchTask: Task<Void, Never>?
    @State private var entrances: [CampusEntranceMapPlace] = []
    @State private var entranceError: String?
    @FocusState private var searchFocused: Bool
    private var campusEntrances: [CampusEntranceMapPlace] {
        entrances.filter { $0.building.campus == (campus == .hunnan ? "south" : "main") }
    }
    private var visibleEntrances: [CampusEntranceMapPlace] {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return campusEntrances.filter { term.isEmpty || term == "教学楼" || $0.title.localizedStandardContains(term) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                NavigationLink {
                    IndoorNavigationView()
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "building.2.crop.circle").font(.title2)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("楼内导航").font(.headline)
                            Text("Pathly · 查教室、找楼梯与电梯").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                    }
                    .foregroundStyle(.primary).padding(16)
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
                }.buttonStyle(.plain)
                NavigationLink {
                    CampusJourneyView()
                } label: {
                    Label("跨楼路线 · 楼内 + Apple 地图步行", systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                        .font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity, minHeight: 48)
                        .background(AppTheme.accent.opacity(0.07), in: RoundedRectangle(cornerRadius: 14))
                }.buttonStyle(.plain)
                Picker("校区", selection: $campus) {
                    ForEach(Campus.allCases) { Text($0.title).tag($0) }
                }.pickerStyle(.segmented)
                Text(campus.address).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                HStack {
                    TextField("搜索教学楼、食堂或地点", text: $query)
                        .submitLabel(.search).focused($searchFocused).autocorrectionDisabled()
                        .onSubmit { search() }
                    Button("搜索") { search() }.disabled(store.loading)
                }.padding(14).background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        ForEach(["校区", "教学楼", "食堂", "图书馆", "体育馆"], id: \.self) { title in
                            Button(title) { query = title == "校区" ? "" : title; search() }.buttonStyle(.bordered)
                        }
                    }
                }
                Map(position: $camera, selection: $selected) {
                    ForEach(visibleEntrances) { place in
                        Marker(place.title, coordinate: place.door.coordinate).tint(.blue).tag(place.id)
                    }
                    ForEach(store.places) { place in
                        Marker(place.item.name ?? "校园地点", coordinate: place.coordinate).tint(.orange).tag(place.id)
                    }
                }
                .mapControls { MapCompass(); MapScaleView() }
                .frame(height: 280).clipShape(RoundedRectangle(cornerRadius: 18))
                if let place = visibleEntrances.first(where: { $0.id == selected }) {
                    VStack(alignment: .leading, spacing: 10) {
                        Label(place.title, systemImage: "door.left.hand.open").font(.headline)
                        Text("预置入口 · 可在跨楼路线中微调").font(.caption).foregroundStyle(.secondary)
                        Button("步行到这个楼门", systemImage: "figure.walk") {
                            place.door.mapItem.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeWalking])
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(16)
                        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
                }
                DisclosureGroup("已标注 \(visibleEntrances.count) 个楼门") {
                    ForEach(visibleEntrances) { place in
                        Button {
                            selected = place.id
                            camera = .region(MKCoordinateRegion(center: place.door.coordinate, latitudinalMeters: 400, longitudinalMeters: 400))
                        } label: { Label(place.title, systemImage: "mappin.and.ellipse").frame(maxWidth: .infinity, minHeight: 44, alignment: .leading) }
                    }
                }
                Text("蓝色为按 Pathly 楼门图与公开地图配准的预置入口，尚未现场实测。建筑轮廓 © OpenStreetMap 贡献者；材料馆参考 Esri World Imagery。")
                    .font(.caption).foregroundStyle(.secondary)
                Link("地图数据来源与许可", destination: URL(string: "https://www.openstreetmap.org/copyright")!).font(.caption)
                if let entranceError { Text(entranceError).font(.caption).foregroundStyle(.orange) }
                if store.loading { ProgressView("正在搜索校园地点…") }
                if let error = store.error {
                    ErrorStateView(message: error) { search() }
                } else if !store.loading && store.places.isEmpty && visibleEntrances.isEmpty {
                    ContentUnavailableView("暂无匹配地点", systemImage: "mappin.slash", description: Text("可更换关键词或校区重试。"))
                }
                ForEach(store.places) { place in
                    VStack(alignment: .leading, spacing: 12) {
                        Button {
                            selected = place.id
                            camera = .region(MKCoordinateRegion(center: place.coordinate, latitudinalMeters: 600, longitudinalMeters: 600))
                        } label: {
                            Label(place.item.name ?? "校园地点", systemImage: "mappin.and.ellipse")
                                .font(.headline).foregroundStyle(.primary)
                        }
                        HStack {
                            Button("步行导航", systemImage: "figure.walk") {
                                place.item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeWalking])
                            }
                            Spacer()
                            if let url = place.item.url { Link("地点网站", destination: url).font(.subheadline) }
                        }
                    }
                    .padding(16).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
                }
                Text("地点由系统地图实时检索，结果范围为所选校区附近。步行导航在系统地图中打开。")
                    .font(.caption).foregroundStyle(.secondary)
            }.padding(16)
        }
        .scrollDismissesKeyboard(.interactively)
        .task(id: String(active) + environment.session.requestEpoch.uuidString) {
            guard active else { store.cancel(); return }
            if owner != environment.session.requestEpoch {
                campus = initialCampus ?? environment.repository.campus
                query = ""
                owner = environment.session.requestEpoch
            }
            if entrances.isEmpty {
                do {
                    let catalog = try IndoorCatalog.bundled()
                    let locations = try CampusEntranceCatalog.bundled(catalog: catalog)
                    entrances = locations.entrances.compactMap { entrance in
                        catalog.buildings.first(where: { $0.id == entrance.buildingID }).map { CampusEntranceMapPlace(building: $0, entrance: entrance) }
                    }
                    entranceError = nil
                } catch { entranceError = "预置楼门暂未能读取，可重新打开页面或更新应用。" }
            }
            await store.search(campus: campus, keyword: query)
        }
        .onChange(of: campus) { _, _ in if active { search() } }
        .onChange(of: store.places.map(\.id)) { _, _ in camera = .automatic; selected = nil }
        .onDisappear { searchTask?.cancel(); store.cancel() }
    }

    private func search() {
        searchFocused = false
        let target = campus, term = query
        searchTask?.cancel()
        searchTask = Task { await store.search(campus: target, keyword: term) }
    }
}

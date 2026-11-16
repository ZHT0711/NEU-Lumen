import Foundation

enum IndoorNavigationError: LocalizedError, Equatable {
    case catalog, endpoints, samePoint, response, unavailable, incompatibleMap
    var errorDescription: String? {
        switch self {
        case .catalog: "楼宇资料暂时无法读取，请更新应用或使用 Pathly 原站"
        case .endpoints: "请选择同一教学楼内的起点与终点"
        case .samePoint: "起点与终点相同，请重新选择"
        case .response: "Pathly 暂未返回可用路线，请更换起终点或稍后重试"
        case .unavailable: "楼内导航连接失败，请检查网络后重试"
        case .incompatibleMap: "Pathly 楼层资料已变化，请更新应用或在原站查看路线"
        }
    }
}

enum IndoorRoutePreference: String, CaseIterable, Identifiable, Codable {
    case shortest = "NORMAL", elevator = "FORCE_ELEVATOR", stairs = "NO_ELEVATOR"
    var id: String { rawValue }
    var title: String {
        switch self { case .shortest: "最短路径"; case .elevator: "优先电梯"; case .stairs: "避开电梯" }
    }
}

struct IndoorCoordinate: Decodable, Hashable {
    let x: Double
    let y: Double
    var isValid: Bool { x.isFinite && y.isFinite && (0...100).contains(x) && (0...100).contains(y) }
}

struct IndoorRoom: Decodable, Identifiable, Hashable {
    let value: String
    let name: String
    var id: String { value }
    var isGate: Bool { value.hasPrefix("G") }
    var isElevator: Bool { value.hasPrefix("E") }
    var title: String { isGate ? name + "门" : isElevator ? "电梯 " + name : name }
    init(value: String, name: String? = nil) {
        self.value = value
        self.name = name ?? String(value.prefix(while: { $0 != "_" }))
    }
    init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer()
        if let raw = try? value.decode(String.self) { self.init(value: raw) }
        else {
            let object = try value.decode([String: String].self)
            guard let raw = object["value"], let name = object["name"] else { throw IndoorNavigationError.catalog }
            self.init(value: raw, name: name)
        }
    }
}

struct IndoorFloor: Decodable, Identifiable {
    let id: Int
    let name: String
    let rooms: [IndoorRoom]
    var uniqueRooms: [IndoorRoom] {
        var seen = Set<String>()
        return rooms.filter { seen.insert($0.id).inserted }
    }
}

struct IndoorBuilding: Decodable, Identifiable {
    struct ElevatorReference: Identifiable {
        let id: String
        let url: URL
    }
    let id: String
    let name: String
    let campus: String
    let floors: [IndoorFloor]
    let maps: [String: [String: IndoorCoordinate]]
    var campusName: String { campus == "south" ? "浑南校区" : "南湖校区" }
    var rooms: [IndoorRoom] { floors.flatMap(\.uniqueRooms) }
    var gates: [IndoorRoom] {
        var seen = Set<String>()
        return rooms.filter { $0.isGate && seen.insert($0.id).inserted }
    }
    var gateImageURL: URL? { URL(string: "https://pathly.top/images/" + id + "-gate-map.jpg") }
    func elevatorImageURL(on floor: IndoorFloor) -> URL? {
        elevatorReferences(on: floor).first?.url
    }
    func elevatorReferences(on floor: IndoorFloor) -> [ElevatorReference] {
        var seen = Set<String>()
        return floor.rooms.filter(\.isElevator).compactMap { elevator in
            let components = elevator.id.split(separator: "_")
            guard components.count >= 3 else { return nil }
            let level = String(components[components.count - 2])
            guard level.range(of: #"^[A-Za-z0-9]+$"#, options: .regularExpression) != nil,
                  seen.insert(level).inserted,
                  let url = URL(string: "https://pathly.top/images/" + id + "-" + level + "-elevator.jpg") else { return nil }
            return ElevatorReference(id: level, url: url)
        }
    }
    func room(_ id: String) -> IndoorRoom? { rooms.first { $0.id == id } }
    func floorName(for room: IndoorRoom) -> String { floors.first { $0.rooms.contains(room) }?.name ?? "" }
    func matchingRooms(_ destination: String) -> [IndoorRoom] {
        let text = (destination.applyingTransform(.fullwidthToHalfwidth, reverse: false) ?? destination).uppercased()
        return rooms.filter { room in
            guard !room.isGate, !room.isElevator else { return false }
            let pattern = "(?<![A-Z0-9])" + NSRegularExpression.escapedPattern(for: room.name.uppercased()) + "(?![A-Z0-9])"
            return text.range(of: pattern, options: .regularExpression) != nil
        }
    }
}

struct CampusJourneyEndpoint: Equatable {
    var buildingID = ""
    var roomID = ""
    var gateID = ""
    func valid(in building: IndoorBuilding) -> Bool {
        building.id == buildingID && building.room(roomID) != nil && building.gates.contains { $0.id == gateID }
    }
    func indoorLeg(in building: IndoorBuilding, departing: Bool) throws -> (start: String, end: String)? {
        guard valid(in: building) else { throw IndoorNavigationError.endpoints }
        guard roomID != gateID else { return nil }
        return departing ? (roomID, gateID) : (gateID, roomID)
    }
}

struct CampusEntrance: Decodable, Identifiable, Equatable {
    let buildingID: String
    let gateID: String
    let latitude: Double
    let longitude: Double
    let approximateAccuracyMeters: Double
    var id: String { buildingID + "|" + gateID }
}

struct CampusEntranceCatalog: Decodable {
    let version: Int
    let coordinateSystem: String
    let fieldVerified: Bool
    let entrances: [CampusEntrance]

    func entrance(buildingID: String, gateID: String) -> CampusEntrance? {
        entrances.first { $0.buildingID == buildingID && $0.gateID == gateID }
    }

    static func load(data: Data, catalog: IndoorCatalog) throws -> Self {
        let result = try JSONDecoder().decode(Self.self, from: data)
        let expected = Set(catalog.buildings.flatMap { building in building.gates.map { building.id + "|" + $0.id } })
        guard result.version == 1, result.coordinateSystem == "WGS84",
              Set(result.entrances.map(\.id)) == expected, result.entrances.count == expected.count,
              result.entrances.allSatisfy({ entrance in
                  guard let building = catalog.buildings.first(where: { $0.id == entrance.buildingID }) else { return false }
                  let latitudes = building.campus == "south" ? 41.64...41.66 : 41.75...41.78
                  return entrance.latitude.isFinite && entrance.longitude.isFinite &&
                      latitudes.contains(entrance.latitude) && (123.40...123.43).contains(entrance.longitude) &&
                      entrance.approximateAccuracyMeters.isFinite && (1...100).contains(entrance.approximateAccuracyMeters)
              }) else { throw IndoorNavigationError.catalog }
        return result
    }

    static func bundled(catalog: IndoorCatalog) throws -> Self {
        guard let url = Bundle.main.url(forResource: "CampusEntrances", withExtension: "json") ??
                Bundle.main.url(forResource: "CampusEntrances", withExtension: "json", subdirectory: "Resources") else {
            throw IndoorNavigationError.catalog
        }
        return try load(data: Data(contentsOf: url), catalog: catalog)
    }
}

struct IndoorCatalog: Decodable {
    let version: Int
    let importedAt: String
    let buildings: [IndoorBuilding]
    static func load(data: Data) throws -> Self {
        let result = try JSONDecoder().decode(Self.self, from: data)
        guard result.version == 1, !result.buildings.isEmpty,
              Set(result.buildings.map(\.id)).count == result.buildings.count,
              result.buildings.allSatisfy({ !$0.floors.isEmpty && !$0.maps.isEmpty && ["main", "south"].contains($0.campus) }) else { throw IndoorNavigationError.catalog }
        return result
    }
    static func bundled() throws -> Self {
        guard let url = Bundle.main.url(forResource: "PathlyCatalog", withExtension: "json") ??
                Bundle.main.url(forResource: "PathlyCatalog", withExtension: "json", subdirectory: "Resources") else { throw IndoorNavigationError.catalog }
        return try load(data: Data(contentsOf: url))
    }
}

struct IndoorRouteStep: Identifiable {
    let id: Int
    let imageKey: String?
    let points: [IndoorCoordinate]
    let fromFloor: String?
    let toFloor: String?
    let elevator: Bool
    var isVertical: Bool { imageKey == nil }
    var title: String {
        if isVertical { return (elevator ? "乘电梯" : "走楼梯") + " · " + (fromFloor ?? "") + " 楼 → " + (toFloor ?? "") + " 楼" }
        let floor = imageKey?.split(separator: "-").dropFirst().first.map(String.init) ?? ""
        return floor + " 楼路线"
    }
    var imageURL: URL? { imageKey.flatMap { URL(string: "https://pathly.top/images/" + $0 + ".jpg") } }
}

struct IndoorRoute {
    let steps: [IndoorRouteStep]
    var usesElevator: Bool { steps.contains { $0.isVertical && $0.elevator } }
    static func request(building: IndoorBuilding, start: String, end: String, preference: IndoorRoutePreference) throws -> [String: String] {
        guard building.room(start) != nil, building.room(end) != nil else { throw IndoorNavigationError.endpoints }
        guard start != end else { throw IndoorNavigationError.samePoint }
        return ["building": building.id, "start": "ref_" + start, "end": "ref_" + end, "strategy": preference.rawValue]
    }
    static func parse(_ payload: Any, building: IndoorBuilding) throws -> Self {
        guard let root = payload as? [String: Any], (root["code"] as? NSNumber)?.intValue == 200,
              let data = root["data"] as? [String: Any], let rows = data["steps"] as? [[String: Any]],
              !rows.isEmpty, rows.count <= 100 else { throw IndoorNavigationError.response }
        let steps = try rows.enumerated().map { index, row -> IndoorRouteStep in
            if row["type"] as? String == "VERTICAL" {
                guard let from = row["fromFloor"] as? NSNumber, let to = row["toFloor"] as? NSNumber,
                      from.doubleValue.isFinite, to.doubleValue.isFinite else { throw IndoorNavigationError.response }
                func floorName(_ value: NSNumber) -> String {
                    value.doubleValue.rounded() == value.doubleValue ? String(format: "%.0f", value.doubleValue) : value.stringValue
                }
                return IndoorRouteStep(id: index, imageKey: nil, points: [], fromFloor: floorName(from), toFloor: floorName(to), elevator: row["elevator"] as? Bool == true)
            }
            guard row["type"] as? String == "PLAN", let key = row["picName"] as? String,
                  key.hasPrefix(building.id + "-"), key.range(of: #"^[A-Za-z0-9_-]+$"#, options: .regularExpression) != nil,
                  let map = building.maps[key], let ids = row["points"] as? [NSNumber], !ids.isEmpty, ids.count <= 5000 else {
                throw IndoorNavigationError.incompatibleMap
            }
            let points = try ids.map { identifier -> IndoorCoordinate in
                guard identifier.doubleValue.isFinite, (0...1_000_000).contains(identifier.doubleValue),
                      identifier.doubleValue.rounded() == identifier.doubleValue,
                      let point = map[String(identifier.intValue)], point.isValid else { throw IndoorNavigationError.incompatibleMap }
                return point
            }
            return IndoorRouteStep(id: index, imageKey: key, points: points, fromFloor: nil, toFloor: nil, elevator: false)
        }
        guard steps.contains(where: { !$0.isVertical }) else { throw IndoorNavigationError.response }
        return Self(steps: steps)
    }
}

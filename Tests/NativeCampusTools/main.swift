import Foundation

enum PortalClient { static let portalBase = "https://personal.neu.edu.cn/portal" }

@main struct NativeCampusToolsTests {
    @MainActor static func main() throws {
        func grade(_ score: Double?, _ text: String = "", credit: Double = 2) -> GradeCourse {
            GradeCourse(name: "synthetic", credit: credit, category: "", score: score, scoreRaw: text)
        }
        let courses = [grade(90), grade(50), grade(nil, "优秀"), grade(nil, "缓考"), grade(nil, "85"), grade(.infinity), grade(80, credit: -1)]
        let stats = GradeAnalysis(courses: courses)
        precondition(stats.scored.count == 5 && stats.failed.count == 1 && stats.statusRecords.count == 2)
        precondition(stats.gradedCredits == 8 && stats.passedCredits == 6)
        precondition(stats.weightedAverage == 80)
        precondition(stats.bands.reduce(0) { $0 + $1.count } == 5)
        precondition(grade(nil, "0").hasScore && grade(nil, "0").normalizedScore == 0)
        precondition(grade(nil, " 优秀\n").normalizedScore == 95)
        precondition(!grade(nil, "缓考").hasScore && !grade(101).hasScore && !grade(.nan).hasScore)
        precondition(grade(.infinity).scoreText == "暂无")
        let semester = GradeSemester(name: "synthetic", termCode: "1", current: true, courses: courses)
        precondition(semester.weightedAvg == 80 && semester.credits == 8)
        precondition(GradeAnalysis(courses: []).weightedAverage == nil)

        let phone = CampusPhoneEntry(cells: ["合成部门", "合成办公室", "00000000/00000001（传真）", "合成地址"])!
        precondition(phone.dialNumbers == ["02400000000"])
        precondition(CampusPhoneEntry(cells: ["部门名称", "办公室名称", "办公电话", "办公地址"]) == nil)
        precondition(CampusPhoneEntry(cells: ["incomplete"]) == nil)
        precondition(NativeCampusService.telephone.allowsNativeDocument(URL(string: "https://plat.neu.edu.cn/telephone-directory/home")!))
        precondition(!NativeCampusService.telephone.allowsNativeDocument(URL(string: "https://plat.neu.edu.cn.evil.example/")!))
        precondition(NativeCampusService.library.allowsNativeDocument(URL(string: "http://210.30.202.58:8991/F/-?func=find-b-0")!))
        precondition(!NativeCampusService.payment.allowsNativeDocument(URL(string: "http://pay.neu.edu.cn/")!))
        precondition(!NativeCampusService.library.allowsNativeDocument(URL(string: "http://210.30.202.58:8992/F/")!))
        precondition(!NativeCampusService.library.allowsNativeDocument(URL(string: "http://210.30.202.58:8991/other")!))

        let rooms = ElectricRoomKey.recentRooms(selecting: "１２３-４５６７", in: ["1234567", "2345678", "3456789", "invalid", "4567890", "5678901", "6789012"])
        precondition(rooms == ["1234567", "2345678", "3456789", "4567890", "5678901"])

        let suite = "NEULumen.NativeNews.Tests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let saved = SavedCampusNews(defaults: defaults)
        let item = NewsItem(id: "synthetic", title: "合成资讯", date: "2026-01-01", category: "合成频道", url: "https://neunews.neu.edu.cn/synthetic", picUrl: "")
        saved.bind(account: "A")
        saved.toggle(item)
        precondition(saved.items == [item])
        saved.bind(account: "B")
        precondition(saved.items.isEmpty)
        saved.bind(account: "A")
        precondition(saved.items == [item])
        let restored = SavedCampusNews(defaults: defaults)
        restored.bind(account: "A")
        precondition(restored.items == [item])
        restored.toggle(item)
        precondition(restored.items.isEmpty)
        saved.bind(account: nil)
        saved.toggle(item)
        precondition(saved.items.isEmpty)
        let root = URL(fileURLWithPath: CommandLine.arguments[1])
        let catalog = try IndoorCatalog.load(data: Data(contentsOf: root.appendingPathComponent("NEU-Lumen/Resources/PathlyCatalog.json")))
        precondition(catalog.buildings.count == 19)
        let entranceData = try Data(contentsOf: root.appendingPathComponent("NEU-Lumen/Resources/CampusEntrances.json"))
        let entrances = try CampusEntranceCatalog.load(data: entranceData, catalog: catalog)
        precondition(entrances.entrances.count == 57 && !entrances.fieldVerified)
        for item in catalog.buildings {
            for gate in item.gates {
                precondition(entrances.entrance(buildingID: item.id, gateID: gate.id) != nil)
            }
        }
        let originalEntrances = try JSONSerialization.jsonObject(with: entranceData) as! [String: Any]
        for mutation in ["missing", "duplicate", "wrong-gate", "wrong-campus", "wrong-crs"] {
            var changed = originalEntrances
            var points = changed["entrances"] as! [[String: Any]]
            switch mutation {
            case "missing": points.removeLast()
            case "duplicate": points.append(points[0])
            case "wrong-gate": points[0]["gateID"] = "G999_unknown"
            case "wrong-campus": points[0]["latitude"] = 41.65
            default: changed["coordinateSystem"] = "BD09"
            }
            changed["entrances"] = points
            do {
                _ = try CampusEntranceCatalog.load(data: JSONSerialization.data(withJSONObject: changed), catalog: catalog)
                preconditionFailure("Invalid entrance data accepted: " + mutation)
            } catch { precondition(error as? IndoorNavigationError == .catalog) }
        }
        precondition(catalog.buildings.filter { $0.campus == "main" }.count == 13)
        precondition(catalog.buildings.filter { $0.campus == "south" }.count == 6)
        for building in catalog.buildings {
            precondition(!building.rooms.isEmpty)
            precondition(building.maps.values.allSatisfy { $0.values.allSatisfy(\.isValid) })
            precondition(building.rooms.allSatisfy { !$0.id.isEmpty && !$0.name.isEmpty })
        }
        let building = catalog.buildings.first { $0.id == "BuildingOne" }!
        precondition(building.gateImageURL?.lastPathComponent == "BuildingOne-gate-map.jpg")
        precondition(building.elevatorImageURL(on: building.floors[0]) == nil)
        precondition(building.elevatorImageURL(on: building.floors[1])?.lastPathComponent == "BuildingOne-1-elevator.jpg")
        let wingBuilding = catalog.buildings.first { $0.id == "WenGuan" }!
        let wingFloor = wingBuilding.floors.first { $0.id == 3 }!
        precondition(Set(wingBuilding.elevatorReferences(on: wingFloor).map(\.id)) == ["3A", "3B"])
        let gate = building.rooms.first { $0.isGate }!
        let endpoint = building.matchingRooms("浑南一号楼 Ａ１０２ 教室").first!
        precondition(endpoint.name == "A102")
        let journey = CampusJourneyEndpoint(buildingID: building.id, roomID: endpoint.id, gateID: gate.id)
        precondition(journey.valid(in: building))
        precondition(Set(building.gates.map(\.id)).count == building.gates.count)
        let leaving = try journey.indoorLeg(in: building, departing: true)!
        let entering = try journey.indoorLeg(in: building, departing: false)!
        precondition(leaving.start == endpoint.id && leaving.end == gate.id)
        precondition(entering.start == gate.id && entering.end == endpoint.id)
        let atDoor = CampusJourneyEndpoint(buildingID: building.id, roomID: gate.id, gateID: gate.id)
        let skipped = try atDoor.indoorLeg(in: building, departing: true)
        precondition(skipped == nil, "Already at the gate needs no duplicate indoor path request")
        precondition(!journey.valid(in: wingBuilding), "Cross-building legs must use each building's own catalog")
        let invalidGate = CampusJourneyEndpoint(buildingID: building.id, roomID: endpoint.id, gateID: endpoint.id)
        do { _ = try invalidGate.indoorLeg(in: building, departing: true); preconditionFailure() }
        catch { precondition(error as? IndoorNavigationError == .endpoints) }
        precondition(building.matchingRooms("A1020").isEmpty, "Do not confuse room number substrings")
        for preference in IndoorRoutePreference.allCases {
            let fields = try IndoorRoute.request(building: building, start: gate.id, end: endpoint.id, preference: preference)
            precondition(fields["strategy"] == preference.rawValue && fields["start"] == "ref_" + gate.id)
        }
        do { _ = try IndoorRoute.request(building: building, start: gate.id, end: gate.id, preference: .shortest); preconditionFailure() }
        catch { precondition(error as? IndoorNavigationError == .samePoint) }
        do { _ = try IndoorRoute.request(building: building, start: "foreign-room", end: endpoint.id, preference: .shortest); preconditionFailure() }
        catch { precondition(error as? IndoorNavigationError == .endpoints) }
        let routes = try JSONSerialization.jsonObject(with: Data(contentsOf: root.appendingPathComponent("Tests/IndoorNavigation/route-samples.json"))) as! [String: Any]
        let normal = try IndoorRoute.parse(routes["NORMAL"]!, building: building)
        precondition(normal.steps.count == 1 && normal.steps[0].points.count == 4 && !normal.usesElevator)
        let elevator = try IndoorRoute.parse(routes["FORCE_ELEVATOR"]!, building: building)
        precondition(elevator.usesElevator, "Actual vertical steps override the backend's inconsistent hasElevator flag")
        precondition(elevator.steps.contains { $0.isVertical && $0.title.contains("走楼梯") })
        for key in ["OtherBuilding-1-N", "../BuildingOne-1-N"] {
            let invalid: [String: Any] = ["code":200, "data":["steps":[["type":"PLAN","picName":key,"points":[4,55]]]]]
            do { _ = try IndoorRoute.parse(invalid, building: building); preconditionFailure() }
            catch { precondition(error as? IndoorNavigationError == .incompatibleMap) }
        }
        let missing: [String: Any] = ["code":200,"data":["steps":[["type":"PLAN","picName":"BuildingOne-1-N","points":[999999]]]]]
        do { _ = try IndoorRoute.parse(missing, building: building); preconditionFailure() }
        catch { precondition(error as? IndoorNavigationError == .incompatibleMap) }

        try WebVPNDirectory.validateIdentity(["username":" SYNTH-A "], expected:"SYNTH-A")
        do { try WebVPNDirectory.validateIdentity(["username":"SYNTH-B"], expected:"SYNTH-A"); preconditionFailure() }
        catch { precondition(error as? WebVPNDirectoryError == .accountMismatch) }
        do { try WebVPNDirectory.validateIdentity(["login":true], expected:"SYNTH-A"); preconditionFailure() }
        catch { precondition(error as? WebVPNDirectoryError == .authentication) }
        let entry: [String: Any] = ["id":1,"name":"合成数据库","url":"https://example.org/database?q=1","redirect":"/https/abcdef/database?q=1"]
        let directory = try WebVPNDirectory.parse(groups: ["data":[["group":["id":4,"group_name":"合成图书馆资源"],"type":"common","resource":[entry]]]], recent:["data":[entry]])
        precondition(directory.groups[0].name == "合成图书馆资源" && directory.resources.count == 1 && directory.recent.count == 1)
        precondition(directory.resources[0].gatewayURL.host == "webvpn.neu.edu.cn", "Use gateway-provided routes even for external databases")
        for redirect in ["https://webvpn.neu.edu.cn.evil.example/https/abcdef/x", "https://evil.example/x", "javascript:alert(1)", "/logout", "http://webvpn.neu.edu.cn/http/abcdef/x"] {
            var changed = entry; changed["redirect"] = redirect
            precondition(WebVPNResource(json: changed) == nil)
        }
        print("PASS: native campus models, 19 Pathly buildings, full map coordinates, three route preferences, room matching, elevator steps, mismatched map rejection and WebVPN identity/gateway bounds")
    }
}

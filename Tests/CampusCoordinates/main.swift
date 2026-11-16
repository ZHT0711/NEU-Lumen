import Foundation

// Reference values independently obtained from coordtransform 2.1.2 (MIT).
let controls: [(CampusGeoPoint, CampusGeoPoint)] = [
    (.init(latitude: 39.915, longitude: 116.404), .init(latitude: 39.91640428150164, longitude: 116.41024449916938)),
    (.init(latitude: 41.651784, longitude: 123.420627), .init(latitude: 41.654206722100014, longitude: 123.42675184608318)),
    (.init(latitude: 41.76462, longitude: 123.41316), .init(latitude: 41.767062334005146, longitude: 123.41930407149538))
]
for (wgs, gcj) in controls {
    let result = wgs.converted(from: .wgs84, to: .gcj02)
    precondition(abs(result.latitude - gcj.latitude) < 1e-10 && abs(result.longitude - gcj.longitude) < 1e-10)
    let restored = result.converted(from: .gcj02, to: .wgs84)
    precondition(restored.distance(to: wgs) < 0.01)
    precondition(gcj.converted(from: .gcj02, to: .gcj02) == gcj, "Never convert native map pins twice")
    precondition(CampusMapDatumPolicy.infer(reference: wgs, observed: gcj) == .gcj02)
    precondition(CampusMapDatumPolicy.infer(reference: wgs, observed: wgs) == .wgs84)
}
let library = CampusGeoPoint(latitude: 41.65285, longitude: 123.41846)
precondition(CampusMapDatumPolicy.infer(reference: library, observed: .init(latitude: 41.66, longitude: 123.44)) == nil)
let midway = CampusGeoPoint(latitude: 41.6540623, longitude: 123.4215232)
precondition(CampusMapDatumPolicy.infer(reference: library, observed: midway) == nil, "Ambiguous matches must not override provider")
let overseas = CampusGeoPoint(latitude: 40.7, longitude: -74)
precondition(overseas.converted(from: .wgs84, to: .gcj02) == overseas)
let root = URL(fileURLWithPath: CommandLine.arguments[1])
let raw = try JSONSerialization.jsonObject(with: Data(contentsOf: root.appendingPathComponent("NEU-Lumen/Resources/CampusEntrances.json"))) as! [String: Any]
precondition(raw["coordinateSystem"] as? String == "WGS84", "Keep source data in its original datum")
let entries = raw["entrances"] as! [[String: Any]]
for entry in entries {
    let source = CampusGeoPoint(latitude: entry["latitude"] as! Double, longitude: entry["longitude"] as! Double)
    let displayed = source.converted(from: .wgs84, to: .gcj02)
    precondition((450...750).contains(displayed.distance(to: source)), "The Shenyang provider offset must be corrected")
    precondition(displayed.converted(from: .gcj02, to: .wgs84).distance(to: source) < 0.01)
}
precondition(entries.count == 57)
print("PASS: independent WGS84/GCJ02 controls, all 57 entrances, inverse persistence, no double conversion and provider classification")

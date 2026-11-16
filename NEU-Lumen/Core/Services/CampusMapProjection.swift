import MapKit
import Observation

/// The mainland MapKit/Gaode provider needs GCJ-02; overseas MapKit can return
/// WGS84 for the same campus. Never infer this from language, SIM, or permissions.
@MainActor @Observable
final class CampusMapProjection {
    static let shared = CampusMapProjection()
    private(set) var datum: CampusMapDatum = .gcj02
    private var checkedAt: Date?
    private var resolving: Task<Void, Never>?
    init(datum: CampusMapDatum = .gcj02) { self.datum = datum }

    func coordinate(latitude: Double, longitude: Double, from source: CampusMapDatum = .wgs84) -> CLLocationCoordinate2D {
        let point = CampusGeoPoint(latitude: latitude, longitude: longitude).converted(from: source, to: datum)
        return CLLocationCoordinate2D(latitude: point.latitude, longitude: point.longitude)
    }

    func resolve() async {
        if let resolving { await resolving.value; return }
        if let checkedAt, Date().timeIntervalSince(checkedAt) < 60 { return }
        let task = Task { await detect() }
        resolving = task
        await task.value
        resolving = nil
    }

    private func detect() async {
        checkedAt = Date()
        let references: [(String, CampusGeoPoint)] = [
            ("东北大学浑南校区图书馆", CampusGeoPoint(latitude: 41.65285, longitude: 123.41846)),
            ("东北大学南湖校区宁恩承图书馆", CampusGeoPoint(latitude: 41.76462, longitude: 123.41316))
        ]
        for (name, reference) in references {
            let query = MKLocalSearch.Request()
            query.naturalLanguageQuery = name
            query.region = MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: reference.latitude, longitude: reference.longitude),
                                             latitudinalMeters: 3500, longitudinalMeters: 3500)
            let search = MKLocalSearch(request: query)
            let deadline = Task {
                do { try await Task.sleep(for: .seconds(4)); search.cancel() } catch { }
            }
            defer { deadline.cancel() }
            guard let result = try? await search.start() else { continue }
            let candidates = result.mapItems.filter {
                let title = $0.name ?? ""
                return title.contains("图书馆") || title.localizedCaseInsensitiveContains("library")
            }.compactMap { item -> CampusMapDatum? in
                let coordinate: CLLocationCoordinate2D
                if #available(iOS 26.0, *) { coordinate = item.location.coordinate }
                else { coordinate = item.placemark.coordinate }
                return CampusMapDatumPolicy.infer(reference: reference,
                    observed: CampusGeoPoint(latitude: coordinate.latitude, longitude: coordinate.longitude))
            }
            if let match = candidates.first, candidates.allSatisfy({ $0 == match }) {
                datum = match
                return
            }
        }
    }
}

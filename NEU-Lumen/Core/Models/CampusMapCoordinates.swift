import Foundation

enum CampusMapDatum: String, Codable {
    case wgs84 = "WGS84", gcj02 = "GCJ02"
}

struct CampusGeoPoint: Equatable {
    let latitude: Double
    let longitude: Double

    func converted(from source: CampusMapDatum, to target: CampusMapDatum) -> Self {
        guard source != target else { return self }
        if target == .gcj02 { return gcj02 }
        var guess = self
        for _ in 0..<8 {
            let projected = guess.gcj02
            let dy = projected.latitude - latitude, dx = projected.longitude - longitude
            guess = Self(latitude: guess.latitude - dy, longitude: guess.longitude - dx)
            if max(abs(dx), abs(dy)) < 1e-10 { break }
        }
        return guess
    }

    // Standard GCJ-02 forward transform; see coordtransform (MIT) attribution.
    private var gcj02: Self {
        guard latitude.isFinite, longitude.isFinite, (0.8293...55.8271).contains(latitude),
              (72.004...137.8347).contains(longitude) else { return self }
        let x = longitude - 105, y = latitude - 35, pi = Double.pi
        var dy = -100 + 2 * x + 3 * y + 0.2 * y * y + 0.1 * x * y + 0.2 * sqrt(abs(x))
        dy += (20 * sin(6 * x * pi) + 20 * sin(2 * x * pi)) * 2 / 3
        dy += (20 * sin(y * pi) + 40 * sin(y / 3 * pi)) * 2 / 3
        dy += (160 * sin(y / 12 * pi) + 320 * sin(y * pi / 30)) * 2 / 3
        var dx = 300 + x + 2 * y + 0.1 * x * x + 0.1 * x * y + 0.1 * sqrt(abs(x))
        dx += (20 * sin(6 * x * pi) + 20 * sin(2 * x * pi)) * 2 / 3
        dx += (20 * sin(x * pi) + 40 * sin(x / 3 * pi)) * 2 / 3
        dx += (150 * sin(x / 12 * pi) + 300 * sin(x / 30 * pi)) * 2 / 3
        let radians = latitude / 180 * pi, eccentricity = 0.00669342162296594323
        let magic = 1 - eccentricity * sin(radians) * sin(radians), axis = 6378245.0
        dy = dy * 180 / ((axis * (1 - eccentricity)) / (magic * sqrt(magic)) * pi)
        dx = dx * 180 / (axis / sqrt(magic) * cos(radians) * pi)
        return Self(latitude: latitude + dy, longitude: longitude + dx)
    }

    func distance(to other: Self) -> Double {
        let lat = (latitude + other.latitude) / 2 * .pi / 180
        let dx = (longitude - other.longitude) * cos(lat), dy = latitude - other.latitude
        return hypot(dx, dy) * .pi / 180 * 6_371_000
    }
}

enum CampusMapDatumPolicy {
    /// Compare the same named building returned by MapKit with a public
    /// footprint centre. Ambiguous/far-away search results must not change datum.
    static func infer(reference: CampusGeoPoint, observed: CampusGeoPoint) -> CampusMapDatum? {
        let wgsDistance = reference.distance(to: observed)
        let gcjDistance = reference.converted(from: .wgs84, to: .gcj02).distance(to: observed)
        guard min(wgsDistance, gcjDistance) < 180, abs(wgsDistance - gcjDistance) > 250 else { return nil }
        return wgsDistance < gcjDistance ? .wgs84 : .gcj02
    }
}

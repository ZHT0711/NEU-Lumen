import SwiftUI

/// Original line drawings: campus landmarks, dining and everyday university life.
/// Normalized paths stay sharp at every text size and require no network assets.
struct NativeServiceCardArt: Shape {
    let service: NativeCampusService

    func path(in rect: CGRect) -> Path {
        var p = Path()
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x * rect.width / 100, y: rect.minY + y * rect.height / 100)
        }
        func line(_ points: [(CGFloat, CGFloat)]) {
            guard let first = points.first else { return }
            p.move(to: point(first.0, first.1))
            for pair in points.dropFirst() { p.addLine(to: point(pair.0, pair.1)) }
        }
        func box(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) {
            p.addRect(CGRect(origin: point(x, y), size: CGSize(width: w * rect.width / 100, height: h * rect.height / 100)))
        }
        func oval(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) {
            p.addEllipse(in: CGRect(origin: point(x, y), size: CGSize(width: w * rect.width / 100, height: h * rect.height / 100)))
        }
        func curve(_ start: (CGFloat, CGFloat), _ end: (CGFloat, CGFloat), _ a: (CGFloat, CGFloat), _ b: (CGFloat, CGFloat)) {
            p.move(to: point(start.0, start.1))
            p.addCurve(to: point(end.0, end.1), control1: point(a.0, a.1), control2: point(b.0, b.1))
        }
        switch service {
        case .academic:
            // Heshili teaching building: long wings and its distinctive central roof.
            box(8, 53, 84, 34); box(39, 36, 22, 51)
            line([(35, 36), (50, 18), (65, 36), (35, 36)])
            line([(50, 18), (50, 36)]); box(35, 62, 30, 7)
            for x in [39, 46, 54, 61] as [CGFloat] { line([(x, 69), (x, 87)]) }
            for x in [14, 23, 76, 85] as [CGFloat] {
                for y in [60, 72] as [CGFloat] { box(x, y, 4, 7) }
            }
            line([(3, 91), (97, 91)])
        case .payment:
            // Dining-hall warmth: a bowl of noodles, steam and chopsticks.
            oval(12, 49, 68, 14)
            curve((13, 56), (79, 56), (18, 99), (70, 99))
            line([(30, 88), (63, 88)]); line([(61, 57), (88, 16)]); line([(66, 59), (95, 21)])
            for x in [26, 40, 54] as [CGFloat] {
                curve((x, 45), (x + 2, 20), (x - 9, 36), (x + 11, 32))
            }
            curve((24, 55), (52, 55), (30, 46), (43, 64))
            line([(7, 94), (88, 94)])
        case .vpn:
            // Campus gate: entrance piers, lintel, iron gates and trees.
            box(16, 35, 9, 53); box(75, 35, 9, 53); box(12, 29, 76, 8)
            line([(9, 29), (50, 17), (91, 29)])
            box(28, 52, 44, 36); line([(50, 52), (50, 88)])
            for x in [32, 38, 44, 56, 62, 68] as [CGFloat] { line([(x, 55), (x, 88)]) }
            line([(4, 91), (96, 91)]); line([(3, 77), (3, 48)])
            curve((1, 50), (12, 53), (-9, 27), (20, 25))
        case .affairs:
            // A campus bench under a ginkgo tree, with an open book.
            line([(13, 64), (66, 64), (66, 70), (13, 70), (13, 64)])
            line([(20, 70), (17, 88)]); line([(59, 70), (62, 88)])
            line([(16, 59), (16, 49), (63, 49), (63, 59)])
            line([(22, 58), (57, 58)]); line([(77, 88), (77, 35)])
            curve((77, 37), (77, 37), (25, 25), (95, -6))
            line([(77, 35), (62, 22)]); line([(77, 35), (88, 17)])
            line([(29, 51), (29, 36), (41, 39), (52, 36), (52, 51), (41, 54), (29, 51)])
            line([(41, 39), (41, 54)]); line([(6, 92), (94, 92)])
        case .mail:
            // Letter carried through campus: envelope, plane and a gingko leaf.
            box(10, 48, 65, 38)
            line([(10, 48), (43, 72), (75, 48)])
            line([(10, 86), (32, 64)]); line([(75, 86), (54, 64)])
            line([(46, 26), (94, 10), (78, 43), (70, 28), (46, 26)])
            line([(70, 28), (94, 10)]); line([(70, 28), (64, 38), (65, 27)])
            curve((13, 29), (35, 28), (10, 10), (38, 9))
            line([(13, 29), (24, 38), (35, 28)]); line([(24, 38), (26, 20)])
        case .news:
            // The rocket monument at Nanhu campus, with plaza steps.
            line([(43, 71), (43, 28), (50, 8), (57, 28), (57, 71), (43, 71)])
            line([(43, 30), (57, 30)]); line([(43, 56), (34, 76), (43, 70)])
            line([(57, 56), (66, 76), (57, 70)]); box(39, 76, 22, 7)
            box(31, 83, 38, 6); line([(20, 94), (80, 94)])
            for x in [14, 24, 76, 86] as [CGFloat] { line([(x, 85), (x, 61)]) }
            curve((9, 60), (29, 60), (9, 39), (29, 39))
            curve((71, 60), (91, 60), (71, 39), (91, 39))
        case .agenda:
            // Liuchangchun stadium roof silhouette and a running track.
            curve((8, 42), (92, 42), (31, 13), (69, 13))
            curve((8, 42), (92, 42), (36, 51), (65, 51))
            line([(15, 44), (15, 65), (85, 65), (85, 44)])
            for x in [25, 35, 45, 55, 65, 75] as [CGFloat] { line([(x, 47), (x, 64)]) }
            oval(6, 70, 88, 23); oval(15, 75, 70, 13)
            line([(45, 71), (45, 75)]); line([(56, 88), (56, 93)])
        case .analysis:
            // A notebook and the steps of the teaching building.
            box(16, 22, 62, 60); line([(24, 17), (24, 85)])
            for y in [34, 46, 58] as [CGFloat] { line([(34, y), (65, y)]) }
            line([(8, 91), (36, 91), (36, 86), (65, 86), (65, 91), (92, 91)])
            line([(65, 71), (75, 55), (85, 61), (94, 37)])
        case .map:
            // Folded campus map and a compass above a tree-lined path.
            line([(6, 30), (32, 23), (60, 31), (87, 23), (87, 83), (60, 91), (32, 83), (6, 91), (6, 30)])
            line([(32, 23), (32, 83)]); line([(60, 31), (60, 91)])
            curve((13, 72), (75, 46), (25, 30), (53, 96))
            oval(64, 7, 29, 29); line([(78, 10), (73, 28), (87, 20), (78, 10)])
        case .library:
            // Library facade with a central reading window and an open book.
            box(13, 32, 74, 42); line([(8, 29), (50, 12), (92, 29), (8, 29)])
            for x in [21, 34, 59, 72] as [CGFloat] { box(x, 41, 7, 20) }
            box(46, 44, 8, 30)
            line([(18, 84), (18, 73), (50, 78), (82, 73), (82, 84), (50, 91), (18, 84)])
            line([(50, 78), (50, 91)])
        case .telephone:
            // Campus information board beside the main building's entrance.
            box(11, 23, 48, 57); box(17, 30, 36, 36)
            for y in [39, 49, 59] as [CGFloat] { line([(23, y), (47, y)]) }
            line([(20, 80), (20, 94)]); line([(49, 80), (49, 94)])
            box(66, 39, 24, 51); line([(62, 37), (78, 22), (94, 37)])
            for y in [48, 61] as [CGFloat] { box(72, y, 5, 6); box(81, y, 5, 6) }
            line([(63, 93), (96, 93)])
        case .downloads:
            // Library study table, stacked books and a reading lamp.
            line([(7, 78), (93, 78)]); line([(15, 78), (15, 94)]); line([(84, 78), (84, 94)])
            box(12, 68, 35, 9); box(16, 58, 33, 10); box(10, 49, 36, 9)
            line([(16, 53), (39, 53)]); line([(22, 63), (43, 63)]); line([(18, 73), (40, 73)])
            line([(59, 76), (84, 76)]); line([(72, 76), (85, 43), (69, 24)])
            line([(56, 34), (69, 24), (79, 35), (56, 34)])
            line([(64, 39), (60, 52)]); line([(71, 40), (75, 53)])
        }
        return p
    }
}

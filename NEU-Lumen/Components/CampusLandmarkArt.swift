import SwiftUI

/// Original vector silhouettes, using each campus landmark's facade and roof profile.
struct CampusLandmarkArt: Shape {
    let campus: Campus

    func path(in rect: CGRect) -> Path {
        var path = Path()
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x * rect.width, y: rect.minY + y * rect.height)
        }
        func line(_ values: [(CGFloat, CGFloat)]) {
            guard let first = values.first else { return }
            path.move(to: point(first.0, first.1))
            for value in values.dropFirst() { path.addLine(to: point(value.0, value.1)) }
        }
        func box(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat) {
            path.addRect(CGRect(origin: point(x, y), size: CGSize(width: width * rect.width, height: height * rect.height)))
        }
        func windows(_ x: CGFloat, _ y: CGFloat, columns: Int, rows: Int, dx: CGFloat, dy: CGFloat) {
            for column in 0..<columns {
                for row in 0..<rows { box(x + CGFloat(column) * dx, y + CGFloat(row) * dy, 0.012, 0.045) }
            }
        }
        line([(0.01, 0.89), (0.99, 0.89)])
        switch campus {
        case .nanhu:
            // 何世礼教学馆的对称长翼、中央门廊与玻璃天窗。
            box(0.025, 0.44, 0.27, 0.40)
            box(0.115, 0.30, 0.09, 0.54)
            line([(0.10, 0.30), (0.16, 0.16), (0.22, 0.30), (0.10, 0.30)])
            line([(0.16, 0.16), (0.16, 0.30)])
            box(0.105, 0.60, 0.11, 0.07)
            for x in [0.113, 0.145, 0.177, 0.207] as [CGFloat] { line([(x, 0.67), (x, 0.84)]) }
            windows(0.043, 0.49, columns: 3, rows: 3, dx: 0.022, dy: 0.10)
            windows(0.224, 0.49, columns: 3, rows: 3, dx: 0.022, dy: 0.10)
            line([(0.09, 0.85), (0.23, 0.85)])
            // 火箭广场，尖锥、箭体、尾翼和纪念基座。
            line([(0.472, 0.70), (0.472, 0.22), (0.50, 0.04), (0.528, 0.22), (0.528, 0.70), (0.472, 0.70)])
            line([(0.472, 0.51), (0.44, 0.73), (0.472, 0.67)])
            line([(0.528, 0.51), (0.56, 0.73), (0.528, 0.67)])
            line([(0.472, 0.24), (0.528, 0.24)])
            box(0.453, 0.74, 0.094, 0.10)
            line([(0.42, 0.86), (0.58, 0.86)])
            // 刘长春体育馆的双曲飞檐、玻璃幕墙和入口台阶。
            path.move(to: point(0.68, 0.28))
            path.addCurve(to: point(0.98, 0.35), control1: point(0.77, 0.67), control2: point(0.92, 0.18))
            path.addCurve(to: point(0.68, 0.28), control1: point(0.88, 0.56), control2: point(0.77, 0.61))
            line([(0.70, 0.45), (0.70, 0.78), (0.955, 0.78), (0.955, 0.43)])
            for x in [0.73, 0.76, 0.79, 0.82, 0.85, 0.88, 0.91, 0.94] as [CGFloat] { line([(x, 0.53), (x, 0.78)]) }
            line([(0.70, 0.62), (0.955, 0.62)])
            line([(0.68, 0.81), (0.975, 0.81)])
            line([(0.66, 0.85), (0.99, 0.85)])
        case .hunnan:
            // 1 号教学楼，通高门厅、成排立柱与双翼。
            box(0.025, 0.38, 0.27, 0.46)
            box(0.10, 0.26, 0.12, 0.58)
            box(0.115, 0.40, 0.09, 0.44)
            line([(0.11, 0.56), (0.21, 0.56)])
            for x in [0.13, 0.16, 0.19] as [CGFloat] { line([(x, 0.40), (x, 0.84)]) }
            windows(0.04, 0.44, columns: 3, rows: 3, dx: 0.021, dy: 0.11)
            windows(0.23, 0.44, columns: 3, rows: 3, dx: 0.021, dy: 0.11)
            // 信息学馆，错动的高低体块、竖向窗格和连廊。
            line([(0.36, 0.84), (0.36, 0.32), (0.48, 0.22), (0.48, 0.84)])
            line([(0.48, 0.22), (0.62, 0.30), (0.62, 0.84), (0.36, 0.84)])
            box(0.41, 0.61, 0.16, 0.23)
            windows(0.38, 0.38, columns: 4, rows: 2, dx: 0.024, dy: 0.11)
            windows(0.50, 0.38, columns: 4, rows: 2, dx: 0.025, dy: 0.11)
            line([(0.43, 0.65), (0.55, 0.65), (0.55, 0.84)])
            // 建筑学馆，层叠挑檐、水平长窗与开放柱廊。
            line([(0.69, 0.43), (0.74, 0.29), (0.97, 0.29), (0.94, 0.43), (0.69, 0.43)])
            line([(0.70, 0.46), (0.70, 0.72), (0.96, 0.72), (0.96, 0.43)])
            box(0.72, 0.50, 0.21, 0.055)
            box(0.72, 0.61, 0.21, 0.055)
            for x in [0.72, 0.78, 0.84, 0.90, 0.95] as [CGFloat] { line([(x, 0.72), (x, 0.84)]) }
            line([(0.68, 0.84), (0.98, 0.84)])
        }
        return path
    }
}

/// 南湖校门居左，浑南校门居右，共用一条地平线。
struct CampusGatesArt: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: rect.minX + x * rect.width, y: rect.minY + y * rect.height) }
        func line(_ values: [(CGFloat, CGFloat)]) {
            guard let first = values.first else { return }
            path.move(to: point(first.0, first.1))
            for value in values.dropFirst() { path.addLine(to: point(value.0, value.1)) }
        }
        // 南湖校门的舒展弧墙与校名立面。
        path.move(to: point(0.02, 0.78))
        path.addCurve(to: point(0.46, 0.42), control1: point(0.12, 0.70), control2: point(0.30, 0.26))
        line([(0.46, 0.42), (0.46, 0.84), (0.02, 0.84), (0.02, 0.78)])
        path.move(to: point(0.045, 0.73))
        path.addCurve(to: point(0.44, 0.46), control1: point(0.19, 0.57), control2: point(0.29, 0.35))
        // 浑南校门的四根砖柱、白色柱帽与中间校名墙。
        for (x, top) in [(0.54, 0.38), (0.66, 0.26), (0.84, 0.26), (0.96, 0.38)] as [(CGFloat, CGFloat)] {
            let w: CGFloat = 0.025
            line([(x, 0.84), (x, top), (x + w, top), (x + w, 0.84)])
            line([(x - 0.008, top), (x + w + 0.008, top), (x + w + 0.008, top - 0.045), (x - 0.008, top - 0.045), (x - 0.008, top)])
        }
        line([(0.69, 0.58), (0.84, 0.58), (0.84, 0.84), (0.69, 0.84), (0.69, 0.58)])
        line([(0.015, 0.87), (0.99, 0.87)])
        return path
    }
}

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
            // 以学校校区风采照片为参考，信息学馆的水平玻璃长带置于远景。
            line([(0.30, 0.37), (0.30, 0.19), (0.56, 0.20), (0.56, 0.12), (0.95, 0.15), (0.95, 0.49)])
            for y in [0.23, 0.30, 0.37, 0.44] as [CGFloat] {
                line([(0.34, y), (0.55, y + 0.025), (0.66, y - 0.025), (0.95, y)])
                line([(0.34, y + 0.02), (0.55, y + 0.045), (0.66, y - 0.005), (0.95, y + 0.02)])
            }
            line([(0.55, 0.20), (0.55, 0.48)])
            line([(0.66, 0.15), (0.66, 0.49)])
            // 1 号教学楼的红砖实墙、密集花格、折面高体块和低入口。
            line([(0.02, 0.84), (0.02, 0.36), (0.14, 0.36), (0.14, 0.27), (0.19, 0.26),
                  (0.21, 0.35), (0.21, 0.83)])
            line([(0.02, 0.36), (0.045, 0.39), (0.045, 0.84)])
            box(0.21, 0.43, 0.13, 0.25)
            for column in 0..<11 {
                let x = 0.217 + CGFloat(column) * 0.0105
                line([(x, 0.44), (x, 0.66)])
            }
            for row in 0..<12 {
                let y = 0.44 + CGFloat(row) * 0.019
                line([(0.214, y), (0.335, y)])
            }
            line([(0.34, 0.80), (0.34, 0.42), (0.40, 0.36), (0.47, 0.38), (0.47, 0.82)])
            line([(0.40, 0.36), (0.40, 0.80)])
            windows(0.158, 0.38, columns: 2, rows: 5, dx: 0.023, dy: 0.075)
            windows(0.422, 0.46, columns: 2, rows: 4, dx: 0.023, dy: 0.08)
            line([(0.21, 0.73), (0.29, 0.65), (0.36, 0.72), (0.21, 0.73)])
            box(0.225, 0.74, 0.105, 0.09)
            // 建筑学馆的白色架空体量、红砖支柱、深凹窗和连接玻璃廊。
            line([(0.55, 0.77), (0.55, 0.44), (0.73, 0.43), (0.77, 0.47), (0.77, 0.76)])
            line([(0.73, 0.43), (0.73, 0.72)])
            line([(0.77, 0.50), (1.02, 0.52), (1.02, 0.84), (0.77, 0.81), (0.77, 0.50)])
            line([(0.55, 0.70), (0.73, 0.70), (0.77, 0.74)])
            for x in [0.57, 0.63, 0.70] as [CGFloat] { box(x, 0.71, 0.015, 0.15) }
            windows(0.565, 0.48, columns: 6, rows: 3, dx: 0.026, dy: 0.065)
            windows(0.80, 0.57, columns: 7, rows: 3, dx: 0.03, dy: 0.075)
            line([(0.74, 0.49), (0.77, 0.51), (0.77, 0.67), (0.74, 0.66)])
        }
        // 前后错落的树冠、步道和草地把楼群连成同一片校园景观。
        for (x, y, scale) in [(0.005, 0.81, 0.8), (0.32, 0.86, 0.55), (0.64, 0.88, 0.65), (0.98, 0.87, 0.75)] as [(CGFloat, CGFloat, CGFloat)] {
            let crown = CGRect(x: point(x - 0.035 * scale, y - 0.23 * scale).x,
                               y: point(x, y - 0.23 * scale).y, width: 0.07 * scale * rect.width, height: 0.16 * scale * rect.height)
            path.addEllipse(in: crown)
            line([(x, y - 0.13 * scale), (x, y + 0.04)])
        }
        path.move(to: point(0.01, 0.89))
        path.addCurve(to: point(1.02, 0.92), control1: point(0.35, 0.96), control2: point(0.64, 0.80))
        path.move(to: point(0.27, 0.85))
        path.addCurve(to: point(0.44, 1.04), control1: point(0.23, 0.95), control2: point(0.35, 0.96))
        path.move(to: point(0.71, 0.87))
        path.addCurve(to: point(0.49, 1.04), control1: point(0.67, 0.96), control2: point(0.54, 0.96))
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

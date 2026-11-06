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
            // 同一地面上的横向组景，以一号楼为中心，避免远近建筑的线条互相穿透。
            // 信息学馆位于左侧，保留台阶式体量和连续玻璃横带。
            line([(0.02, 0.83), (0.02, 0.43), (0.19, 0.43), (0.19, 0.36),
                  (0.31, 0.36), (0.31, 0.83)])
            line([(0.02, 0.43), (0.045, 0.47), (0.045, 0.83)])
            for y in [0.49, 0.59, 0.69] as [CGFloat] {
                line([(0.045, y), (0.19, y), (0.21, y - 0.04), (0.31, y - 0.04)])
                line([(0.045, y + 0.025), (0.19, y + 0.025), (0.21, y - 0.015), (0.31, y - 0.015)])
            }
            line([(0.19, 0.43), (0.19, 0.81)])
            // 一号楼居中，实墙、折面高塔、花格墙和低门廊形成主轮廓。
            line([(0.34, 0.83), (0.34, 0.35), (0.43, 0.35), (0.43, 0.23),
                  (0.48, 0.22), (0.50, 0.29), (0.50, 0.68)])
            line([(0.34, 0.35), (0.355, 0.38), (0.355, 0.83)])
            line([(0.43, 0.35), (0.43, 0.83)])
            box(0.50, 0.40, 0.09, 0.28)
            for column in 1..<7 {
                let x = 0.50 + CGFloat(column) * 0.0128
                line([(x, 0.40), (x, 0.68)])
            }
            for row in 1..<9 {
                let y = 0.40 + CGFloat(row) * 0.031
                line([(0.50, y), (0.59, y)])
            }
            line([(0.59, 0.83), (0.59, 0.38), (0.63, 0.30), (0.68, 0.31), (0.68, 0.83)])
            line([(0.63, 0.30), (0.63, 0.83)])
            windows(0.448, 0.34, columns: 2, rows: 4, dx: 0.022, dy: 0.078)
            windows(0.645, 0.42, columns: 1, rows: 4, dx: 0.025, dy: 0.08)
            line([(0.49, 0.74), (0.55, 0.68), (0.61, 0.74), (0.49, 0.74)])
            box(0.50, 0.75, 0.09, 0.08)
            line([(0.525, 0.75), (0.525, 0.83), (0.565, 0.83), (0.565, 0.75)])
            // 建筑学馆在右侧，以架空白盒、砖柱和不规则深窗收尾。
            line([(0.72, 0.70), (0.72, 0.44), (0.87, 0.44), (0.89, 0.48), (0.89, 0.70), (0.72, 0.70)])
            line([(0.87, 0.44), (0.87, 0.68)])
            line([(0.89, 0.53), (0.99, 0.54), (0.99, 0.83), (0.89, 0.83), (0.89, 0.53)])
            for x in [0.74, 0.80, 0.855] as [CGFloat] { box(x, 0.70, 0.012, 0.13) }
            for (x, y, w) in [(0.74, 0.49, 0.014), (0.77, 0.49, 0.019), (0.82, 0.49, 0.011),
                               (0.845, 0.49, 0.015), (0.75, 0.58, 0.017), (0.79, 0.58, 0.012),
                               (0.83, 0.58, 0.022), (0.91, 0.59, 0.018), (0.945, 0.59, 0.024),
                               (0.91, 0.70, 0.024), (0.95, 0.70, 0.013)] as [(CGFloat, CGFloat, CGFloat)] {
                box(x, y, w, 0.035)
            }
            line([(0.31, 0.83), (0.34, 0.83)])
            line([(0.68, 0.83), (0.72, 0.83)])
        }
        if campus == .hunnan {
            path.move(to: point(0.01, 0.86))
            path.addCurve(to: point(0.99, 0.86), control1: point(0.32, 0.88), control2: point(0.70, 0.84))
            line([(0.51, 0.86), (0.47, 0.98)])
            line([(0.57, 0.86), (0.64, 0.98)])
        } else {
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

import SwiftUI

/// 以东大校园中央塔楼、两侧教学楼和松树为意象的原生矢量线稿。
/// 使用相对坐标绘制，随设备尺寸缩放；颜色和透明度由页面控制。
struct CampusLineArt: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x * rect.width, y: rect.minY + y * rect.height)
        }
        func line(_ coordinates: [(CGFloat, CGFloat)]) {
            guard let first = coordinates.first else { return }
            path.move(to: point(first.0, first.1))
            for coordinate in coordinates.dropFirst() { path.addLine(to: point(coordinate.0, coordinate.1)) }
        }
        func box(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) {
            path.addRect(CGRect(x: rect.minX + x * rect.width, y: rect.minY + y * rect.height,
                                width: w * rect.width, height: h * rect.height))
        }
        // 中央塔楼、层叠檐口、钟楼与旗杆。
        line([(0.39, 0.83), (0.39, 0.34), (0.61, 0.34), (0.61, 0.83)])
        line([(0.37, 0.34), (0.63, 0.34), (0.61, 0.31), (0.39, 0.31), (0.37, 0.34)])
        box(0.435, 0.22, 0.13, 0.09)
        line([(0.42, 0.22), (0.58, 0.22), (0.56, 0.20), (0.44, 0.20), (0.42, 0.22)])
        box(0.47, 0.12, 0.06, 0.08)
        line([(0.46, 0.12), (0.54, 0.12), (0.50, 0.09), (0.46, 0.12)])
        line([(0.50, 0.09), (0.50, 0.025)])
        path.addEllipse(in: CGRect(x: rect.minX + 0.485 * rect.width, y: rect.minY + 0.14 * rect.height,
                                   width: 0.03 * rect.width, height: 0.035 * rect.height))
        // 立面、长窗和入口。
        let windowColumns: [CGFloat] = [0.415, 0.46, 0.505, 0.55]
        for x in windowColumns {
            box(x, 0.38, 0.025, 0.06)
            box(x, 0.48, 0.025, 0.06)
            box(x, 0.58, 0.025, 0.06)
        }
        box(0.455, 0.71, 0.09, 0.12)
        line([(0.50, 0.71), (0.50, 0.83)])
        line([(0.37, 0.85), (0.63, 0.85)])
        line([(0.35, 0.88), (0.65, 0.88)])
        let wings: [CGFloat] = [0.12, 0.64]
        for x in wings {
            box(x, 0.46, 0.24, 0.37)
            line([(x - 0.015, 0.46), (x + 0.255, 0.46)])
            for column in 0..<5 {
                for row in 0..<3 {
                    box(x + 0.025 + CGFloat(column) * 0.043, 0.50 + CGFloat(row) * 0.10, 0.02, 0.045)
                }
            }
        }
        // 两侧松树，地平线和向校园延伸的道路。
        let trees: [(CGFloat, CGFloat)] = [(0.075, 1), (0.17, 0.65), (0.925, 1), (0.83, 0.65)]
        for (x, scale) in trees {
            let top = 0.83 - 0.50 * scale
            line([(x, top), (x - 0.035 * scale, top + 0.14 * scale),
                  (x - 0.017 * scale, top + 0.14 * scale),
                  (x - 0.055 * scale, top + 0.28 * scale),
                  (x - 0.03 * scale, top + 0.28 * scale),
                  (x - 0.075 * scale, 0.78), (x + 0.075 * scale, 0.78),
                  (x + 0.03 * scale, top + 0.28 * scale),
                  (x + 0.055 * scale, top + 0.28 * scale),
                  (x + 0.017 * scale, top + 0.14 * scale),
                  (x + 0.035 * scale, top + 0.14 * scale), (x, top)])
            line([(x, 0.78), (x, 0.87)])
        }
        line([(0.02, 0.88), (0.33, 0.88)])
        line([(0.67, 0.88), (0.98, 0.88)])
        line([(0.42, 0.88), (0.30, 1)])
        line([(0.58, 0.88), (0.70, 1)])
        return path
    }
}

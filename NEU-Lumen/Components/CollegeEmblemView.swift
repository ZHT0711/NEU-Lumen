import SwiftUI

/// 学院识别徽章。门户只提供学院名称，使用统一的东大校徽底图和学院缩写生成清晰的本地徽章。
struct CollegeEmblemView: View {
    let department: String

    private var profile: (short: String, color: Color, asset: String?) {
        let rules: [(String, String, Color, String?)] = [
            ("计算机", "计", .indigo, nil), ("软件", "软", .purple, nil), ("信息科学", "信", .blue, nil),
            ("机器人", "机", .teal, nil), ("未来技术", "未", .cyan, nil), ("自动化", "自", .orange, nil),
            ("电气工程", "电", .red, nil), ("机械", "机", .brown, nil), ("材料", "材", .pink, nil),
            ("冶金", "冶", .gray, nil), ("资源与土木", "资", .green, nil), ("理学院", "理", .mint, nil),
            ("工商管理", "商", .blue, nil), ("江河建筑", "建", .orange, nil), ("文法", "文", .purple, nil),
            ("马克思主义", "马", .red, nil), ("外国语", "外", .teal, nil), ("艺术", "艺", .pink, nil),
            ("体育", "体", .green, nil), ("医学", "医", .red, nil), ("生命科学", "生", .mint, nil),
            ("中荷", "中", .indigo, nil), ("国防", "国", .gray, nil)
        ]
        if department.contains("未来技术") {
            return ("未", .blue, "FutureTechnologyEmblem")
        }
        if let rule = rules.first(where: { department.contains($0.0) }) {
            return (rule.1, rule.2, nil)
        }
        let first = department.first.map { String($0) } ?? "院"
        return (first, .blue, nil)
    }

    var body: some View {
        ZStack {
            if let asset = profile.asset {
                Image(asset)
                    .resizable()
                    .scaledToFill()
                    .clipShape(Circle())
                    .overlay(Circle().strokeBorder(.white.opacity(0.75), lineWidth: 1.5))
            } else {
                Circle()
                    .fill(profile.color.gradient)
                Circle()
                    .strokeBorder(.white.opacity(0.72), lineWidth: 1.5)
                    .padding(4)
                Image("NEUEmblem")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .padding(8)
                    .foregroundStyle(.white.opacity(0.22))
                Text(profile.short)
                    .font(.system(size: 20, weight: .bold, design: .serif))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: 54, height: 54)
        .shadow(color: profile.color.opacity(0.28), radius: 5, y: 2)
        .accessibilityLabel("\(department.isEmpty ? "学院" : department)院徽")
    }
}

import SwiftUI

/// 学院识别徽章。门户只提供学院名称，使用统一的东大校徽底图和学院缩写生成清晰的本地徽章。
struct CollegeEmblemView: View {
    let department: String

    private var profile: (short: String, color: Color) {
        let rules: [(String, String, Color)] = [
            ("计算机", "计", .indigo), ("软件", "软", .purple), ("信息科学", "信", .blue),
            ("机器人", "机", .teal), ("未来技术", "未", .cyan), ("自动化", "自", .orange),
            ("电气工程", "电", .red), ("机械", "机", .brown), ("材料", "材", .pink),
            ("冶金", "冶", .gray), ("资源与土木", "资", .green), ("理学院", "理", .mint),
            ("工商管理", "商", .blue), ("江河建筑", "建", .orange), ("文法", "文", .purple),
            ("马克思主义", "马", .red), ("外国语", "外", .teal), ("艺术", "艺", .pink),
            ("体育", "体", .green), ("医学", "医", .red), ("生命科学", "生", .mint),
            ("中荷", "中", .indigo), ("国防", "国", .gray)
        ]
        if let rule = rules.first(where: { department.contains($0.0) }) {
            return (rule.1, rule.2)
        }
        let first = department.first.map { String($0) } ?? "院"
        return (first, .blue)
    }

    var body: some View {
        ZStack {
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
        .frame(width: 54, height: 54)
        .shadow(color: profile.color.opacity(0.28), radius: 5, y: 2)
        .accessibilityLabel("\(department.isEmpty ? "学院" : department)院徽")
    }
}

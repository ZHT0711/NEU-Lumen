import Foundation

enum Campus: String, CaseIterable, Identifiable {
    case nanhu, hunnan
    var id: String { rawValue }
    var title: String { self == .nanhu ? "南湖校区" : "浑南校区" }
    var landmarks: [String] {
        self == .nanhu ? ["何世礼教学馆", "火箭广场", "刘长春体育馆"] : ["1 号教学楼", "信息学馆", "建筑学馆"]
    }

    /// Explicit campus wording takes priority over a college's usual teaching site.
    static func inferred(from department: String) -> Campus? {
        if department.contains("浑南") { return .hunnan }
        if department.contains("南湖") { return .nanhu }
        let hunnan = ["文法", "马克思主义", "工商管理", "计算机", "软件", "医学与生物信息", "中荷", "生命科学", "江河建筑", "机器人", "未来技术",
                      "软件工程", "信息安全", "数字媒体技术", "生物医学工程", "人工智能", "建筑学", "城乡规划"]
        if hunnan.contains(where: department.contains) { return .hunnan }
        let nanhu = ["冶金", "材料", "机械", "资源与土木", "信息科学与工程", "理学院", "外国语", "艺术学院", "体育", "自动化", "电气工程", "应用物理", "数学与应用数学"]
        if nanhu.contains(where: department.contains) { return .nanhu }
        return nil
    }
}

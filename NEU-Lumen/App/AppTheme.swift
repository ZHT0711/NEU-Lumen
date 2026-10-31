import SwiftUI

/// 设计常量：东大蓝主题、课程色板、通用格式化。
enum AppTheme {
    /// 门户 site/info 返回的主题色 #3553A2。
    static let accent = Color(red: 0x35 / 255.0, green: 0x53 / 255.0, blue: 0xA2 / 255.0)
    /// 深色模式品牌底 #1F2C60。
    static let accentDeep = Color(red: 0x1F / 255.0, green: 0x2C / 255.0, blue: 0x60 / 255.0)

    /// 课程块色板（浅色底，深浅色模式均可读）。
    static let coursePalette: [Color] = [
        Color(red: 0x35 / 255, green: 0x53 / 255, blue: 0xA2 / 255),
        Color(red: 0x0E / 255, green: 0x7C / 255, blue: 0x7A / 255),
        Color(red: 0xB4 / 255, green: 0x59 / 255, blue: 0x16 / 255),
        Color(red: 0x7A / 255, green: 0x3E / 255, blue: 0x9D / 255),
        Color(red: 0x1D / 255, green: 0x6F / 255, blue: 0xB2 / 255),
        Color(red: 0xB0 / 255, green: 0x2E / 255, blue: 0x5C / 255),
        Color(red: 0x4E / 255, green: 0x6E / 255, blue: 0x28 / 255),
    ]

    /// 课程名稳定哈希 → 色板索引（FNV-1a）。
    static func courseColor(for name: String) -> Color {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in name.utf8 {
            hash = (hash ^ UInt64(byte)) &* 0x100000001b3
        }
        return coursePalette[Int(hash % UInt64(coursePalette.count))]
    }

    static func greeting(_ date: Date = Date()) -> String {
        let hour = Calendar.current.component(.hour, from: date)
        switch hour {
        case 5..<9: return "早上好"
        case 9..<12: return "上午好"
        case 12..<14: return "中午好"
        case 14..<18: return "下午好"
        default: return "晚上好"
        }
    }
}

import Foundation

/// 一门课程的成绩（数字分或五级制文本）。
struct GradeCourse: Identifiable, Hashable {
    let name: String
    let credit: Double
    let category: String
    let score: Double?
    let scoreRaw: String

    var id: String { name + "|" + scoreText }

    var scoreText: String {
        if let score {
            return score == score.rounded() ? String(Int(score)) : String(format: "%.1f", score)
        }
        return scoreRaw.isEmpty ? "暂无" : scoreRaw
    }

    /// 绩点计算用数值：数字成绩直接用；五级制按校标换算
    /// （优≈95 / 良≈85 / 中≈75 / 及格≈65 / 不及格≈50）。
    var scoreValue: Double {
        if let score { return score }
        switch scoreRaw.trimmingCharacters(in: .whitespaces) {
        case "优", "优秀": return 95
        case "良", "良好": return 85
        case "中", "中等": return 75
        case "及格", "合格": return 65
        case "不及格", "不合格": return 50
        default: return 0
        }
    }

    var hasScore: Bool { score != nil || !scoreRaw.isEmpty }
}

/// 一个学期的成绩单。
struct GradeSemester: Identifiable, Hashable {
    let name: String
    let termCode: String
    let current: Bool
    let courses: [GradeCourse]

    var id: String { termCode.isEmpty ? name : termCode }

    var credits: Double {
        courses.filter(\.hasScore).reduce(0) { $0 + $1.credit }
    }

    var weightedAvg: Double {
        var ws = 0.0, wc = 0.0
        for c in courses where c.hasScore {
            ws += c.scoreValue * c.credit
            wc += c.credit
        }
        return wc == 0 ? 0 : ws / wc
    }

    var gpa: Double {
        var ws = 0.0, wc = 0.0
        for c in courses where c.hasScore {
            ws += Self.gpaOf(c.scoreValue) * c.credit
            wc += c.credit
        }
        return wc == 0 ? 0 : ws / wc
    }

    /// 东北大学常见绩点档位。
    static func gpaOf(_ s: Double) -> Double {
        switch s {
        case 90...: return 4.0
        case 85..<90: return 3.7
        case 82..<85: return 3.3
        case 78..<82: return 3.0
        case 75..<78: return 2.7
        case 72..<75: return 2.3
        case 68..<72: return 2.0
        case 64..<68: return 1.5
        case 60..<64: return 1.0
        default: return 0
        }
    }
}

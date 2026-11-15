import Foundation

struct GradeAnalysis {
    struct Band: Identifiable {
        let title: String
        let count: Int
        var id: String { title }
    }
    let courses: [GradeCourse]
    var scored: [GradeCourse] { courses.filter { $0.normalizedScore != nil } }
    var statusRecords: [GradeCourse] { courses.filter { $0.normalizedScore == nil } }
    var failed: [GradeCourse] { courses.filter { ($0.normalizedScore ?? 100) < 60 } }
    var gradedCredits: Double { courses.filter { $0.hasScore && $0.credit.isFinite && $0.credit > 0 }.reduce(0) { $0 + $1.credit } }
    var passedCredits: Double { courses.filter { ($0.normalizedScore ?? 0) >= 60 && $0.credit.isFinite && $0.credit > 0 }.reduce(0) { $0 + $1.credit } }
    var weightedAverage: Double? {
        guard gradedCredits > 0 else { return nil }
        return courses.reduce(0) { total, course in
            guard let score = course.normalizedScore, course.credit.isFinite, course.credit > 0 else { return total }
            return total + score * course.credit
        } / gradedCredits
    }
    var bands: [Band] {
        let ranges: [(String, Range<Double>)] = [("90–100", 90..<101), ("80–89", 80..<90), ("70–79", 70..<80), ("60–69", 60..<70), ("未及格", 0..<60)]
        return ranges.map { title, range in Band(title: title, count: scored.filter { range.contains($0.normalizedScore!) }.count) }
    }
}

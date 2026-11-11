import SwiftUI

/// Uses a college asset when available and the university emblem as a fallback.
struct CollegeEmblemView: View {
    let department: String

    private var hasCollegeEmblem: Bool { department.contains("未来技术") }

    var body: some View {
        Image(hasCollegeEmblem ? "FutureTechnologyEmblem" : "NEUEmblemDark")
            .resizable()
            .scaledToFit()
            .frame(width: 54, height: 54)
            .accessibilityLabel(hasCollegeEmblem ? "未来技术学院院徽" : "东北大学校徽")
    }
}

import SwiftUI

/// “走进东大”连续点击三次后的彩蛋，向海洋之心团队致意。
struct AquaCoreEasterEggView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                ZStack {
                    Circle()
                        .fill(.white.opacity(0.14))
                        .frame(width: 108, height: 108)
                    Image(systemName: "water.waves.and.arrow.up")
                        .font(.system(size: 46, weight: .medium))
                        .foregroundStyle(.white)
                }
                Text("欢迎加入海洋之心团队")
                    .font(.title2.bold())
                    .foregroundStyle(.white)
                Text("让热爱汇成浪潮，一起做有趣、有用的校园项目。")
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white.opacity(0.82))
                Link(destination: URL(string: "https://github.com/NEU-AquaCore")!) {
                    Label("探索 AquaCore", systemImage: "arrow.up.right")
                        .font(.headline)
                        .foregroundStyle(.blue)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(.white, in: Capsule())
                }
                .padding(.horizontal, 28)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(24)
            .background {
                LinearGradient(
                    colors: [Color(red: 0.03, green: 0.27, blue: 0.45), Color(red: 0.04, green: 0.58, blue: 0.70)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                        .foregroundStyle(.white)
                }
            }
        }
    }
}

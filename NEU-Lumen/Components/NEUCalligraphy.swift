import SwiftUI

/// The exact calligraphy pixels from the official logo already used in README.
/// Clip only the emblem on the left; keep the complete height and original aspect ratio.
struct NEUCalligraphy: View {
    var width: CGFloat = 142
    private var scale: CGFloat { width / 215 }
    var body: some View {
        Image("NEULogo")
            .renderingMode(.template)
            .resizable()
            .frame(width: 309 * scale, height: 83 * scale)
            .offset(x: -94 * scale)
            .frame(width: width, height: 83 * scale, alignment: .topLeading)
            .clipped()
            .accessibilityLabel("东北大学")
    }
}

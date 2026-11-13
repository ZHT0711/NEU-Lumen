import SwiftUI

/// 门户应用使用学校提供的图标；原生工具不替换门户应用。
struct ServiceAppIcon: View {
    let app: PortalApp

    var body: some View {
        RemoteImageView(path: app.iconUrl).accessibilityHidden(true)
    }
}

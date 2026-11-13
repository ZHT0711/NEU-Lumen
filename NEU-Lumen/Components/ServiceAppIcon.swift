import SwiftUI

/// 本地原生服务用系统符号，不为新增学习入口额外请求外部图标。
struct ServiceAppIcon: View {
    let app: PortalApp

    var body: some View {
        Group {
            if let symbol = app.nativeSymbol {
                Image(systemName: symbol)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(AppTheme.accent)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(AppTheme.accent.opacity(0.1), in: RoundedRectangle(cornerRadius: 11))
            } else {
                RemoteImageView(path: app.iconUrl)
            }
        }
        .accessibilityHidden(true)
    }
}

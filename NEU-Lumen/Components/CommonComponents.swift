import SwiftUI

/// 液态玻璃卡片：iOS 26+ 使用系统 glassEffect，低版本回退 ultraThinMaterial。
struct GlassCard<Content: View>: View {
    var cornerRadius: CGFloat = 20
    @ViewBuilder var content: () -> Content

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        if #available(iOS 26.0, *) {
            content()
                .glassEffect(.regular, in: shape)
        } else {
            content()
                .background(.ultraThinMaterial, in: shape)
                .overlay(shape.strokeBorder(Color.primary.opacity(0.06)))
        }
    }
}

/// 远程图片：AsyncImage + URLCache，占位与失败同形，避免布局跳动。
struct RemoteImageView: View {
    let path: String

    var body: some View {
        if let url = Self.resolve(path) {
            AsyncImage(url: url, transaction: Transaction(animation: .easeOut(duration: 0.2))) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFit()
                default:
                    placeholder
                }
            }
        } else {
            placeholder
        }
    }

    private var placeholder: some View {
        Image(systemName: "square.grid.2x2")
            .resizable()
            .scaledToFit()
            .foregroundStyle(.tertiary)
    }

    /// 相对路径拼门户域名；其余走 withScheme 补协议。
    static func resolve(_ raw: String) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return nil }
        if trimmed.hasPrefix("/") {
            return URL(string: PortalClient.portalBase + trimmed)
        }
        return URL(string: withScheme(trimmed))
    }
}

/// 错误态 + 重试。
struct ErrorStateView: View {
    let message: String
    var retryTitle: String = "重试"
    var onRetry: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 36))
                .foregroundStyle(.secondary)
            Text(message)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button(retryTitle, action: onRetry)
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
        .padding(.horizontal, 24)
    }
}

/// 加载态。
struct LoadingView: View {
    var text: String = "加载中…"

    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text(text)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.vertical, 40)
    }
}

import SwiftUI

struct NativeServiceSwitcherPanel: View {
    let selected: NativeCampusService
    let choose: (NativeCampusService) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: typeSize.isAccessibilitySize ? 260 : 100), spacing: 12)]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("切换服务").font(.title2.bold())
                Spacer()
                Button("关闭", systemImage: "xmark") { dismiss() }
                    .labelStyle(.iconOnly).font(.title3).foregroundStyle(.secondary)
                    .frame(width: 44, height: 44).accessibilityIdentifier("services.panel.close")
            }
            Text("当前：\(selected.title) · \((NativeCampusService.allCases.firstIndex(of: selected) ?? 0) + 1) / \(NativeCampusService.allCases.count)")
                .font(.subheadline).foregroundStyle(.secondary)
            ScrollView {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(NativeCampusService.allCases) { service in
                        serviceCard(service)
                    }
                }.padding(2)
            }
        }
        .padding(.horizontal, 20).padding(.top, 20)
        .background(Color(.systemGroupedBackground))
        .accessibilityIdentifier("services.switcher-panel")
        .presentationDetents([.fraction(0.72), .large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(28)
        .presentationBackground(Color(.systemGroupedBackground))
    }

    private func serviceCard(_ service: NativeCampusService) -> some View {
        let active = service == selected
        let ink = colorScheme == .dark ? Color(red: 0.59, green: 0.69, blue: 0.95) : AppTheme.accent
        return Button { choose(service) } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: service.symbol).font(.title3)
                    Spacer(minLength: 0)
                    if active { Image(systemName: "checkmark.circle.fill").accessibilityHidden(true) }
                }.foregroundStyle(AppTheme.accent)
                Text(service.title).font(.callout.weight(.semibold))
                    .foregroundStyle(.primary).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(12).frame(maxWidth: .infinity, minHeight: 108, alignment: .topLeading)
            .background(alignment: .bottomTrailing) {
                NativeServiceCardArt(service: service)
                    .stroke(ink.opacity(contrast == .increased ? 0.07 : colorScheme == .dark ? 0.24 : 0.15),
                            style: StrokeStyle(lineWidth: 1.2, lineCap: .round, lineJoin: .round))
                    .frame(width: 92, height: 78).padding(4)
                    .accessibilityHidden(true).allowsHitTesting(false)
            }
            .background(active ? AppTheme.accent.opacity(0.09) : Color(.secondarySystemGroupedBackground),
                        in: RoundedRectangle(cornerRadius: 18))
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .overlay { RoundedRectangle(cornerRadius: 18).strokeBorder(active ? AppTheme.accent : .clear, lineWidth: 2) }
            .contentShape(RoundedRectangle(cornerRadius: 18))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(service.title)
        .accessibilityValue(active ? "当前服务" : service.subtitle)
        .accessibilityAddTraits(active ? .isSelected : [])
        .accessibilityIdentifier("services.panel." + service.rawValue)
    }
}

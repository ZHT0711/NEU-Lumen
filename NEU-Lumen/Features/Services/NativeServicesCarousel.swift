import SwiftUI

struct NativeServicesCarousel: View {
    let services: [NativeCampusService]
    var searching = false
    let open: (NativeCampusService) -> Void
    @State private var expanded = false
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        DisclosureGroup(isExpanded: Binding(get: { expanded || searching }, set: { expanded = $0 })) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: typeSize.isAccessibilitySize ? 260 : 148), spacing: 10)], spacing: 10) {
                ForEach(services) { service in
                    Button { open(service) } label: {
                        VStack(alignment: .leading, spacing: 8) {
                            Label(service.title, systemImage: service.symbol)
                                .font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                            Text(service.subtitle).font(.caption).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, minHeight: 82, alignment: .leading)
                        .padding(12)
                        .background(alignment: .trailing) {
                            NativeServiceCardArt(service: service)
                                .stroke(AppTheme.accent.opacity(contrast == .increased ? 0.07 : 0.16),
                                        style: StrokeStyle(lineWidth: 1.3, lineCap: .round, lineJoin: .round))
                                .frame(width: 116, height: 100).padding(.trailing, 2)
                                .accessibilityHidden(true).allowsHitTesting(false)
                        }
                        .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .contentShape(Rectangle())
                    }.buttonStyle(.plain)
                        .accessibilityIdentifier("services.native." + service.rawValue)
                }
            }.padding(.top, 12)
        } label: {
            Label("原生服务", systemImage: "square.stack.3d.up")
                .font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                .frame(minHeight: 44)
        }
        .padding(.horizontal, 14).padding(.vertical, 4)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
        .accessibilityIdentifier("services.native.disclosure")
    }
}

struct NativeServiceSwitcher: View {
    let services: [NativeCampusService]
    let selected: NativeCampusService
    let select: (NativeCampusService) -> Void
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                if #available(iOS 26.0, *), !reduceTransparency, contrast != .increased {
                    GlassEffectContainer(spacing: 10) { buttons }
                } else { buttons }
            }
            .scrollClipDisabled()
            .onAppear { proxy.scrollTo(selected, anchor: .center) }
            .onChange(of: selected) { _, value in
                withAnimation(reduceMotion ? nil : .snappy(duration: 0.25)) { proxy.scrollTo(value, anchor: .center) }
            }
        }
    }
    private var buttons: some View {
        HStack(spacing: 8) {
            ForEach(services) { service in
                Button { select(service) } label: {
                    Label(service.title, systemImage: service.symbol)
                        .font(.subheadline.weight(selected == service ? .semibold : .regular))
                        .lineLimit(1).fixedSize(horizontal: true, vertical: false)
                        .padding(.horizontal, 14).frame(minHeight: 44)
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .id(service)
                .modifier(NativeServiceGlass(selected: selected == service))
                .accessibilityAddTraits(selected == service ? .isSelected : [])
                .accessibilityLabel(service.title)
            }
        }.padding(.vertical, 4)
    }
}

private struct NativeServiceGlass: ViewModifier {
    let selected: Bool
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    func body(content: Content) -> some View {
        if reduceTransparency || contrast == .increased {
            content.background(Color(.secondarySystemGroupedBackground), in: Capsule())
                .overlay(Capsule().strokeBorder(selected ? AppTheme.accent : Color.secondary, lineWidth: selected ? 2 : 1))
        } else if #available(iOS 26.0, *) {
            content.glassEffect(.regular.tint(selected ? AppTheme.accent.opacity(0.18) : .clear).interactive(), in: Capsule())
        } else {
            content.background(selected ? AppTheme.accent.opacity(0.16) : Color(.secondarySystemGroupedBackground), in: Capsule())
        }
    }
}

struct NativeServiceHost: View {
    let initial: NativeCampusService
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selected: NativeCampusService
    @State private var originalWeb: NativeServiceWebLink?
    init(initial: NativeCampusService) {
        self.initial = initial
        _selected = State(initialValue: initial)
    }
    var body: some View {
        VStack(spacing: 0) {
            NativeServiceSwitcher(services: NativeCampusService.allCases, selected: selected) { value in
                withAnimation(reduceMotion ? nil : .snappy(duration: 0.25)) { selected = value }
            }.padding(.horizontal, 16).padding(.bottom, 8)
            TabView(selection: $selected) {
                AcademicCenterView().tag(NativeCampusService.academic)
                NativePaymentView(active: selected == .payment).tag(NativeCampusService.payment)
                NativeVPNView(active: selected == .vpn).tag(NativeCampusService.vpn)
                NativeAffairsView(active: selected == .affairs).tag(NativeCampusService.affairs)
                NativeMailView(active: selected == .mail).tag(NativeCampusService.mail)
                NativeNewsView(active: selected == .news).tag(NativeCampusService.news)
                NativeAgendaView(active: selected == .agenda).tag(NativeCampusService.agenda)
                BrowserDownloadsView(store: .shared, embedded: true).tag(NativeCampusService.downloads)
            }.tabViewStyle(.page(indexDisplayMode: .never))
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(selected.title).navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if selected.hasSchoolPage { ToolbarItem(placement: .topBarTrailing) {
                Button("学校原站", systemImage: "globe") {
                    originalWeb = NativeServiceWebLink(url: selected.entryURL(apps: environment.repository.apps))
                }
            } }
        }
        .sheet(item: $originalWeb) { link in NavigationStack { PortalWebViewScreen(url: link.url) } }
    }
}

struct NativeServiceWebLink: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}

import SwiftUI

struct NativeServicesCarousel: View {
    let services: [NativeCampusService]
    let open: (NativeCampusService) -> Void
    @State private var selected: NativeCampusService? = .academic
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("原生服务").font(.headline)
                Spacer()
                Text("左右滑动切换").font(.caption).foregroundStyle(.secondary)
            }
            NativeServiceSwitcher(services: services, selected: selected ?? services.first ?? .academic) { value in
                withAnimation(reduceMotion ? nil : .snappy(duration: 0.25)) { selected = value }
            }
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 12) {
                    ForEach(services) { service in
                        VStack(alignment: .leading, spacing: 12) {
                            Image(systemName: service.symbol).font(.title2).foregroundStyle(AppTheme.accent)
                                .accessibilityHidden(true)
                            Text(service.title).font(.title3.bold())
                            Text(service.subtitle).font(.subheadline).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                            Button { open(service) } label: {
                                HStack { Text("进入" + service.title); Spacer(); Image(systemName: "arrow.right") }
                                    .font(.subheadline.weight(.semibold)).padding(.vertical, 8).frame(minHeight: 44)
                            }.buttonStyle(.plain).foregroundStyle(AppTheme.accent)
                                .accessibilityIdentifier("services.native." + service.rawValue)
                        }
                        .padding(20).frame(maxWidth: .infinity, minHeight: 200, alignment: .leading)
                        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 24))
                        .containerRelativeFrame(.horizontal).id(service)
                    }
                }.scrollTargetLayout()
            }
            .scrollTargetBehavior(.viewAligned)
            .scrollPosition(id: $selected)
            .contentMargins(.horizontal, 0)
        }
    }
}

struct NativeServiceSwitcher: View {
    let services: [NativeCampusService]
    let selected: NativeCampusService
    let select: (NativeCampusService) -> Void
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityContrast) private var contrast
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                if #available(iOS 26.0, *), !reduceTransparency, contrast != .increased {
                    GlassEffectContainer(spacing: 10) { buttons }
                } else { buttons }
            }
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
    @Environment(\.accessibilityContrast) private var contrast
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
            }.tabViewStyle(.page(indexDisplayMode: .never))
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(selected.title).navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("学校原站", systemImage: "globe") {
                    originalWeb = NativeServiceWebLink(url: selected.entryURL(apps: environment.repository.apps))
                }
            }
        }
        .sheet(item: $originalWeb) { link in NavigationStack { PortalWebViewScreen(url: link.url) } }
    }
}

struct NativeServiceWebLink: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}

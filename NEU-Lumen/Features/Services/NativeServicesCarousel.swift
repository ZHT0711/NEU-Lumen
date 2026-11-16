import SwiftUI

struct NativeServicesCarousel: View {
    let services: [NativeCampusService]
    var searching = false
    let open: (NativeCampusService) -> Void
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast

    private var illustrationInk: Color {
        colorScheme == .dark ? Color(red: 0.59, green: 0.69, blue: 0.95) : AppTheme.accent
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            ForEach(searching ? ["服务"] : NativeCampusService.groups, id: \.self) { group in
                let items = services.filter { searching || $0.group == group }
                if !items.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(group).font(.headline)
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: typeSize.isAccessibilitySize ? 260 : 148), spacing: 12)], spacing: 12) {
                            ForEach(items) { service in
                                Button { open(service) } label: {
                                    VStack(alignment: .leading, spacing: 10) {
                                        Label(service.title, systemImage: service.symbol)
                                            .font(.subheadline.weight(.semibold))
                                            .foregroundStyle(.primary)
                                        Text(service.subtitle)
                                            .font(.caption).foregroundStyle(.secondary)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                    .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
                                    .padding(14)
                                    .background(alignment: .bottomTrailing) {
                                        NativeServiceCardArt(service: service)
                                            .stroke(illustrationInk.opacity(contrast == .increased ? 0.07 : 0.16),
                                                    style: StrokeStyle(lineWidth: 1.2, lineCap: .round, lineJoin: .round))
                                            .frame(width: 120, height: 96).padding(.trailing, 4)
                                            .accessibilityHidden(true).allowsHitTesting(false)
                                    }
                                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
                                    .clipShape(RoundedRectangle(cornerRadius: 18))
                                    .contentShape(RoundedRectangle(cornerRadius: 18))
                                }
                                .buttonStyle(.plain)
                                .accessibilityElement(children: .combine)
                                .accessibilityIdentifier("services.native." + service.rawValue)
                            }
                        }
                    }
                }
            }
        }
    }
}

struct NativeServiceHost: View {
    let initial: NativeCampusService
    @Environment(AppEnvironment.self) private var environment
    @State private var selected: NativeCampusService
    @State private var originalWeb: NativeServiceWebLink?
    @State private var preview: NativeCampusService?
    init(initial: NativeCampusService) {
        self.initial = initial
        _selected = State(initialValue: initial)
    }
    var body: some View {
        VStack(spacing: 0) {
            // Reserve real layout height below navigation. A page-style TabView
            // may ignore propagated safe-area insets, so the switcher is a sibling.
            NativeServiceScrubber(selected: $selected, preview: $preview)
                .padding(.horizontal, 16)
                .padding(.vertical, 4)
                .background(Color(.systemGroupedBackground))
            TabView(selection: $selected) {
                AcademicCenterView(active: selected == .academic).tag(NativeCampusService.academic)
                NativePaymentView(active: selected == .payment).tag(NativeCampusService.payment)
                NativeVPNView(active: selected == .vpn).tag(NativeCampusService.vpn)
                NativeAffairsView(active: selected == .affairs).tag(NativeCampusService.affairs)
                NativeMailView(active: selected == .mail).tag(NativeCampusService.mail)
                NativeNewsView(active: selected == .news).tag(NativeCampusService.news)
                NativeAgendaView(active: selected == .agenda).tag(NativeCampusService.agenda)
                BrowserDownloadsView(store: .shared, embedded: true).tag(NativeCampusService.downloads)
                NativeGradeAnalysisView(active: selected == .analysis).tag(NativeCampusService.analysis)
                NativeCampusMapView(active: selected == .map).tag(NativeCampusService.map)
                NativeLibraryView().tag(NativeCampusService.library)
                NativeTelephoneView(active: selected == .telephone).tag(NativeCampusService.telephone)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            // A page-style TabView can draw beyond its content safe area. Keep each
            // service below the separately reserved switcher, not under navigation.
            .clipped()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(selected.title).navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu("切换服务", systemImage: "square.grid.2x2") {
                    ForEach(NativeCampusService.groups, id: \.self) { group in
                        Section(group) {
                            ForEach(NativeCampusService.allCases.filter { $0.group == group }) { service in
                                Button { selected = service } label: {
                                    Label(service.title, systemImage: selected == service ? "checkmark" : service.symbol)
                                }
                            }
                        }
                    }
                }
                .labelStyle(.iconOnly)
                .frame(minWidth: 44, minHeight: 44)
                .accessibilityLabel("切换原生服务")
                .accessibilityIdentifier("services.switcher")
            }
            if selected.hasSchoolPage { ToolbarItem(placement: .topBarTrailing) {
                Button("学校原站", systemImage: "globe") {
                    originalWeb = NativeServiceWebLink(url: selected.entryURL(apps: environment.repository.apps))
                }
                .labelStyle(.iconOnly)
                .frame(minWidth: 44, minHeight: 44)
                .accessibilityLabel("打开\(selected.title)学校原站")
                .accessibilityIdentifier("services.school-web")
            } }
        }
        .sheet(item: $originalWeb) { link in NavigationStack { PortalWebViewScreen(url: link.url) } }
    }
}

private struct NativeServiceScrubber: View {
    @Binding var selected: NativeCampusService
    @Binding var preview: NativeCampusService?
    @GestureState private var dragging = false
    private let services = NativeCampusService.allCases
    private var visible: NativeCampusService { preview ?? selected }
    var body: some View {
        VStack(spacing: 0) {
            Text(preview == nil ? "左右滑动或长按切换服务" : visible.title)
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity)
            GeometryReader { geometry in
                HStack(spacing: 3) {
                    ForEach(services) { service in
                        Capsule().fill(Color.blue.opacity(service == visible ? 1 : 0.16))
                            .frame(maxWidth: .infinity)
                            .frame(height: service == visible ? 4 : 3)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .gesture(LongPressGesture(minimumDuration: 0.3).sequenced(before: DragGesture(minimumDistance: 0))
                    .updating($dragging) { value, state, _ in
                        if case .second(true, _) = value { state = true }
                    }
                    .onChanged { value in
                        if case .second(true, let drag) = value {
                            preview = drag.map { service(at: $0.location.x, width: geometry.size.width) } ?? selected
                        }
                    }
                    .onEnded { value in
                        if case .second(true, let drag?) = value {
                            selected = service(at: drag.location.x, width: geometry.size.width)
                        }
                        preview = nil
                    })
            }
            .frame(height: 44)
        }
        .onChange(of: dragging) { _, active in if !active { preview = nil } }
        .sensoryFeedback(.selection, trigger: visible)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("原生服务切换")
        .accessibilityValue(visible.title + "，\((services.firstIndex(of: visible) ?? 0) + 1)/\(services.count)")
        .accessibilityHint("左右滑动页面，或长按指示条并左右拖动，松手切换；也可使用导航栏服务目录")
        .accessibilityIdentifier("services.scrubber")
        .accessibilityAdjustableAction { direction in
            let index = services.firstIndex(of: selected) ?? 0
            switch direction {
            case .increment: selected = services[min(index + 1, services.count - 1)]
            case .decrement: selected = services[max(index - 1, 0)]
            @unknown default: break
            }
        }
    }
    private func service(at x: CGFloat, width: CGFloat) -> NativeCampusService {
        services[NativeServicePosition.index(at: Double(x), width: Double(width), count: services.count)]
    }
}

struct NativeServiceWebLink: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}

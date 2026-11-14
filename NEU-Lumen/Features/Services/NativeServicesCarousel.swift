import SwiftUI

struct NativeServicesCarousel: View {
    let services: [NativeCampusService]
    var searching = false
    let open: (NativeCampusService) -> Void
    @Environment(\.dynamicTypeSize) private var typeSize

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
                                            .foregroundStyle(AppTheme.accent)
                                        Text(service.subtitle)
                                            .font(.caption).foregroundStyle(.secondary)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                    .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
                                    .padding(14)
                                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
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
    init(initial: NativeCampusService) {
        self.initial = initial
        _selected = State(initialValue: initial)
    }
    var body: some View {
        VStack(spacing: 0) {
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
                .accessibilityIdentifier("services.switcher")
            }
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

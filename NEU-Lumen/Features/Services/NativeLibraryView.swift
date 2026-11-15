import SwiftUI

struct CampusPhoneRow: View {
    let entry: CampusPhoneEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(entry.office).font(.headline)
            Text(entry.department).font(.subheadline).foregroundStyle(.secondary)
            Text(entry.phone).font(.subheadline.monospacedDigit()).textSelection(.enabled)
            if !entry.address.isEmpty {
                Label(entry.address, systemImage: "mappin.and.ellipse")
                    .font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
            }
            HStack {
                ForEach(entry.dialNumbers, id: \.self) { number in
                    if let url = URL(string: "tel:" + number) {
                        Link(destination: url) { Label(number, systemImage: "phone") }.font(.caption)
                    }
                }
                Spacer(minLength: 0)
                ShareLink(item: entry.shareText) { Image(systemName: "square.and.arrow.up") }
                    .accessibilityLabel("分享办公联系方式")
            }.buttonStyle(.borderless)
        }.padding(.vertical, 8)
    }
}

struct NativeLibraryView: View {
    @Environment(AppEnvironment.self) private var environment

    var body: some View {
        List {
            Section("查询与借阅") {
                NavigationLink {
                    PortalWebViewScreen(url: URL(string: "http://210.30.202.58:8991/F/-?func=find-b-0")!, nativeService: .library)
                } label: {
                    AcademicEntryCard(title: "馆藏书刊检索", subtitle: "书名、作者、索书号与馆藏复本", icon: "magnifyingglass")
                }
                NavigationLink {
                    PortalWebViewScreen(url: NativeCampusService.library.entryURL(apps: environment.repository.apps), nativeService: .library)
                } label: {
                    AcademicEntryCard(title: "我的借阅与续借", subtitle: "借阅记录、归还日期与续借操作", icon: "book.closed")
                }
            }
            Section {
                NavigationLink {
                    PortalWebViewScreen(url: URL(string: "http://www.lib.neu.edu.cn/page/jygz/")!)
                } label: { Label("新生入馆与借阅指南", systemImage: "person.crop.rectangle") }
                NavigationLink {
                    PortalWebViewScreen(url: URL(string: "http://www.lib.neu.edu.cn/page/zy/gd/")!)
                } label: { Label("电子资源导航", systemImage: "books.vertical") }
                NavigationLink {
                    PortalWebViewScreen(url: URL(string: "http://www.lib.neu.edu.cn/")!)
                } label: { Label("图书馆公告与开放安排", systemImage: "building.columns") }
            } header: { Text("读者服务") } footer: {
                Text("馆藏和借阅来自学校图书馆。查询表单、复本表格与可识别操作在原生视图中呈现，续借结果以学校返回为准。")
            }
        }
    }
}

struct NativeTelephoneView: View {
    var active = true
    @State private var browser = PortalBrowser()
    var body: some View {
        Group {
            if active {
                PortalWebViewScreen(url: NativeCampusService.telephone.fallbackURL, nativeService: .telephone, retainedBrowser: browser)
            } else { Color.clear }
        }
    }
}

import SwiftUI

struct CampusExploreContent: View {
    private let history = [
        ("1923", "东北大学创办", "学校始建于 1923 年 4 月，爱国主义传统贯穿办学历程。"),
        ("1931", "流亡办学", "九一八事变后，学校辗转北平、西安、开封、四川三台等地，坚持办学。"),
        ("1950", "东北工学院", "1950 年 8 月，学校定名为东北工学院。"),
        ("1993", "复名东北大学", "1993 年 3 月，学校恢复东北大学校名。"),
        ("2023", "百年东大", "跨越百年的办学历程，延续育人兴邦的追求。")
    ]
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 16) {
                Label("百年校史", systemImage: "clock.arrow.circlepath").font(.title3.bold())
                ForEach(history, id: \.0) { year, title, detail in
                    HStack(alignment: .top, spacing: 14) {
                        Text(year).font(.headline.monospacedDigit()).foregroundStyle(AppTheme.accent).frame(width: 48)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(title).font(.headline)
                            Text(detail).font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                schoolLink("读完整校史", symbol: "book", path: "/xygk/bnlc.htm")
            }.padding(18).background(.background, in: RoundedRectangle(cornerRadius: 20))
            VStack(alignment: .leading, spacing: 12) {
                Label("校训与文化", systemImage: "text.book.closed").font(.title3.bold())
                Image("NEUMotto").resizable().scaledToFit().frame(height: 40).accessibilityLabel("知行合一")
                Text("自强不息、知行合一").font(.title3.weight(.semibold)).foregroundStyle(AppTheme.accent)
                Text("走近校徽、校歌与校训，了解东大人的精神传承。")
                    .font(.subheadline).foregroundStyle(.secondary)
                schoolLink("校徽 · 校歌 · 校训", symbol: "music.note", path: "/xygk/dxwh.htm")
            }.padding(18).background(.background, in: RoundedRectangle(cornerRadius: 20))
            Text("两处校园，日常漫游").font(.title3.bold()).id("campus-explore-campuses")
            ForEach(Campus.allCases) { campus in
                VStack(alignment: .leading, spacing: 12) {
                    Text(campus.title).font(.headline)
                    campusIllustration(campus)
                    Text(campus.address).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                    Text(campus == .nanhu ? "主楼 · 中心花园" : "浑南图书馆 · 阅读庭院").font(.subheadline)
                    NavigationLink {
                        NativeCampusMapView(initialCampus: campus).navigationTitle(campus.title)
                    } label: { Label("在地图里探索", systemImage: "map") }
                }.padding(18).background(AppTheme.accent.opacity(0.05), in: RoundedRectangle(cornerRadius: 20))
            }
            VStack(alignment: .leading, spacing: 14) {
                Label("看见校园", systemImage: "photo.on.rectangle.angled").font(.title3.bold())
                schoolLink("校园风景", symbol: "leaf", path: "/zjdd/xyfj.htm")
                schoolLink("校园看点", symbol: "sparkles", path: "/xykd.htm")
                schoolLink("校园生活", symbol: "figure.walk", path: "/zjdd/xysh.htm")
                schoolLink("认识今天的东大", symbol: "building.columns", path: "/xygk/xxjj.htm")
                NavigationLink {
                    PortalWebViewScreen(url: URL(string: "https://xwb.neu.edu.cn/10010/list.htm")!)
                } label: { Label("新生服务指南", systemImage: "person.crop.rectangle.badge.plus") }
            }.padding(18).background(.background, in: RoundedRectangle(cornerRadius: 20))
            Text("校史与校训依据学校官网整理，校区地址取自学校综合信息。校园插画为装饰性创作；完整介绍与动态内容以学校页面为准。")
                .font(.caption).foregroundStyle(.secondary)
            schoolLink("内容来源与校区信息", symbol: "link", path: "/zhxx1.htm")
        }.padding(.top, 16)
    }
    @ViewBuilder private func campusIllustration(_ campus: Campus) -> some View {
        // Each placement has its own NEU subject; the home-page landmark groups
        // and the two campus gates above are deliberately not reused here.
        if campus == .nanhu {
            CampusLineArt()
                .stroke(AppTheme.accent.opacity(0.7), style: StrokeStyle(lineWidth: 1.2, lineCap: .round, lineJoin: .round))
                .frame(height: 130).accessibilityLabel("南湖校区主楼与中心花园线稿")
        } else {
            CampusLibraryArt()
                .stroke(AppTheme.accent.opacity(0.7), style: StrokeStyle(lineWidth: 1.2, lineCap: .round, lineJoin: .round))
                .frame(height: 130).accessibilityLabel("浑南校区图书馆线稿")
        }
    }
    private func schoolLink(_ title: String, symbol: String, path: String) -> some View {
        NavigationLink {
            PortalWebViewScreen(url: URL(string: "https://www.neu.edu.cn" + path)!)
        } label: { Label(title, systemImage: symbol).frame(minHeight: 32) }
    }
}

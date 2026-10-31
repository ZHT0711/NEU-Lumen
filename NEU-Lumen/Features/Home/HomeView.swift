import SwiftUI

/// 首页仪表盘：问候、数据条、下一节课、今日时间轴、常用应用、办事动态、校园资讯。
struct HomeView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var path: [URL] = []

    private var repo: PortalRepository {
        environment.repository
    }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    if repo.usedOfflineFallback {
                        offlineBanner
                    }
                    nextClassBanner
                    dataCardsSection
                    todaySection
                    quickAppsSection
                    if !repo.todos.isEmpty {
                        todosSection
                    }
                    newsSection
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 32)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("首页")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await repo.refreshHome() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
            .refreshable {
                await repo.refreshHome()
            }
            .task {
                await repo.ensureLoadedForCurrentUser()
                if repo.homeState == .idle {
                    await repo.refreshHome()
                }
                await repo.loadWeek(containing: Date())
            }
            .navigationDestination(for: URL.self) { url in
                PortalWebViewScreen(url: url)
            }
        }
    }

    // MARK: - 区块

    private var offlineBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "wifi.slash")
            Text("门户接口不可用，以下为离线演示数据")
                .font(.footnote)
        }
        .foregroundStyle(.orange)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    @ViewBuilder
    private var nextClassBanner: some View {
        if let next = repo.nextCourse() {
            let ongoing = next.isOngoing
            HStack(spacing: 12) {
                Image(systemName: ongoing ? "figure.run" : "book.fill")
                    .font(.title3)
                VStack(alignment: .leading, spacing: 3) {
                    Text(ongoing ? "正在上课" : "下一节课")
                        .font(.caption)
                        .opacity(0.85)
                    Text("\(next.slot.name) · \(Semester.hm(next.slot.startMinutes))")
                        .font(.headline)
                        .lineLimit(1)
                    if !next.slot.room.isEmpty {
                        Text(next.slot.room)
                            .font(.caption)
                            .opacity(0.85)
                    }
                }
                Spacer()
            }
            .foregroundStyle(.white)
            .padding(16)
            .background(
                LinearGradient(colors: [AppTheme.accent, AppTheme.accentDeep], startPoint: .topLeading, endPoint: .bottomTrailing),
                in: RoundedRectangle(cornerRadius: 20, style: .continuous)
            )
        }
    }

    private var dataCardsSection: some View {
        Group {
            if !repo.dataCards.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    sectionHeader("数据条", icon: "chart.bar.doc.horizontal")
                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(spacing: 10) {
                            ForEach(repo.dataCards) { card in
                                GlassCard(cornerRadius: 16) {
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text(card.name)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                        Text(card.value)
                                            .font(.title3.bold())
                                            .lineLimit(1)
                                            .minimumScaleFactor(0.6)
                                    }
                                    .padding(12)
                                    .frame(width: 116, height: 76, alignment: .topLeading)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private var todaySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            let timeline = repo.todayTimeline()
            sectionHeader("今日课程", icon: "clock")
            GlassCard {
                VStack(spacing: 0) {
                    if timeline.isEmpty {
                        HStack {
                            Image(systemName: "cup.and.saucer.fill")
                                .foregroundStyle(.secondary)
                            Text("今天没有课，好好休息")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 22)
                    } else {
                        ForEach(Array(timeline.enumerated()), id: \.element.id) { index, occ in
                            TimelineRow(occurrence: occ)
                            if index < timeline.count - 1 {
                                Divider().padding(.leading, 86)
                            }
                        }
                    }
                }
                .padding(.vertical, 6)
            }
        }
    }

    private var quickAppsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("常用应用", icon: "square.grid.2x2")
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4), spacing: 12) {
                ForEach(Array(repo.apps.prefix(8))) { app in
                    Button {
                        open(app)
                    } label: {
                        VStack(spacing: 6) {
                            RemoteImageView(path: app.iconUrl)
                                .frame(width: 40, height: 40)
                            Text(app.name)
                                .font(.caption2)
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .padding(.horizontal, 4)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var todosSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("办事动态", icon: "checklist")
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 10) {
                    ForEach(repo.todos) { todo in
                        Button {
                            if let url = URL(string: withScheme(todo.url)) {
                                path.append(url)
                            }
                        } label: {
                            GlassCard(cornerRadius: 16) {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(todo.title)
                                        .font(.footnote.bold())
                                        .foregroundStyle(.primary)
                                        .lineLimit(1)
                                    Text(todo.instance)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                    ProgressView(value: Double(todo.percent) / 100)
                                        .tint(AppTheme.accent)
                                    Text("\(todo.node) · \(todo.percent)%")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                .padding(12)
                                .frame(width: 180, alignment: .topLeading)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var newsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("校园资讯", icon: "newspaper")
            GlassCard {
                VStack(spacing: 0) {
                    if repo.news.isEmpty {
                        HStack {
                            ProgressView()
                            Text("资讯加载中…")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 20)
                    } else {
                        ForEach(Array(repo.news.enumerated()), id: \.element.id) { index, item in
                            Button {
                                if let url = URL(string: withScheme(item.url)) {
                                    path.append(url)
                                }
                            } label: {
                                NewsRow(item: item)
                            }
                            .buttonStyle(.plain)
                            if index < repo.news.count - 1 {
                                Divider().padding(.leading, 14)
                            }
                        }
                    }
                }
            }
        }
    }

    private func sectionHeader(_ title: String, icon: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.footnote)
                .foregroundStyle(AppTheme.accent)
            Text(title)
                .font(.subheadline.bold())
        }
    }

    private func open(_ app: PortalApp) {
        let entry = app.entryUrl()
        guard !entry.isEmpty, let url = URL(string: entry) else { return }
        path.append(url)
    }
}

/// 今日时间轴一行。
struct TimelineRow: View {
    let occurrence: CourseOccurrence

    var body: some View {
        HStack(spacing: 12) {
            VStack(spacing: 2) {
                Text(Semester.hm(occurrence.slot.startMinutes))
                    .font(.caption.monospacedDigit())
                Text(Semester.hm(occurrence.slot.endMinutes))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .frame(width: 46)

            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(AppTheme.courseColor(for: occurrence.slot.name))
                .frame(width: 4, height: 36)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(occurrence.slot.name)
                        .font(.subheadline.bold())
                        .lineLimit(1)
                    if occurrence.isOngoing {
                        Text("进行中")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Color.green, in: Capsule())
                    }
                }
                Text(occurrence.slot.room)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
    }
}

/// 资讯一行。
struct NewsRow: View {
    let item: NewsItem

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(.footnote)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
                Text("\(item.category) · \(item.date)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if !item.picUrl.isEmpty {
                RemoteImageView(path: item.picUrl)
                    .frame(width: 52, height: 40)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }
}

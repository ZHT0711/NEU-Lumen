import SwiftUI

/// 首页仪表盘：问候、数据条、下一节课、今日时间轴、常用应用、办事动态、校园资讯。
struct HomeView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.colorScheme) private var colorScheme
    @Binding var selection: AppTab
    @ScaledMetric(relativeTo: .caption) private var appColumnWidth: CGFloat = 72
    @State private var showFavorites = false
    @State private var path: [AppDestination] = []
    @State private var refreshTask: Task<Void, Never>?

    private var campusInk: Color {
        colorScheme == .dark ? Color(red: 0.59, green: 0.69, blue: 0.95) : AppTheme.accent
    }

    private var accountID: String {
        guard let user = environment.session.user else { return "" }
        return user.sid.isEmpty ? user.uid : user.sid
    }

    private var repo: PortalRepository {
        environment.repository
    }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 22) {
                    campusHeader
                    if repo.usedOfflineFallback {
                        offlineBanner
                    }
                    todaySection
                    quickAppsSection
                    cardEntrySection
                    if !repo.dataCards.isEmpty {
                        DisclosureGroup("校园数据") { dataCardsSection }
                    }
                    if !repo.todos.isEmpty {
                        todosSection
                    }
                    newsSection
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 32)
            }
            .tracksTabBarScrolling()
            .background(Color(.systemGroupedBackground))
            .navigationTitle("东大 · Lumen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        environment.pendingActivityURL = URL(string: "neulumen://activity/reminders")
                    } label: { Image(systemName: environment.reminders.unreadCount > 0 ? "bell.badge" : "bell") }
                    .accessibilityLabel("提醒与通知")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        refreshTask?.cancel()
                        refreshTask = Task { await refreshHomeData(force: true) }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .accessibilityLabel("刷新首页")
                    .disabled(repo.homeState == .loading)
                }
            }
            .refreshable { await refreshHomeData(force: true) }
            .onDisappear { refreshTask?.cancel(); refreshTask = nil }
            .task(id: accountID) {
                refreshTask?.cancel()
                await repo.ensureLoadedForCurrentUser()
                await refreshHomeData(force: false)
            }
            .navigationDestination(for: AppDestination.self) { dest in
                switch dest {
                case .web(let url):
                    PortalWebViewScreen(url: url)
                case .card:
                    CardView()
                case .academic:
                    AcademicCenterView()
                case .ecode:
                    NativeECodeView()
                case .nativeService(let service):
                    NativeServiceHost(initial: service)
                }
            }
        }
        .sheet(isPresented: $showFavorites) { FavoritesEditor() }
        .tint(campusInk)
    }

    private func refreshHomeData(force: Bool) async {
        async let home: Void = refreshPortalHome(force: force)
        async let wallet: Void = repo.loadCardOverview(force: force)
        async let week: Void = repo.loadDisplayWeek(starting: Semester.weekStart(forDay: Date()), force: force)
        _ = await (home, wallet, week)
    }

    private func refreshPortalHome(force: Bool) async {
        if force || repo.homeState == .idle { await repo.refreshHome(force: force) }
    }

    // MARK: - 区块

    private var campusHeader: some View {
        Group {
            TimelineView(.periodic(from: .now, by: 60)) { context in
                VStack(alignment: .leading, spacing: 18) {
                    HStack(spacing: 10) {
                        Image("NEUEmblem")
                            .renderingMode(.template)
                            .resizable().scaledToFit()
                            .frame(width: 42, height: 42)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 3) {
                            NEUCalligraphy(width: 88)
                            Text("NORTHEASTERN UNIVERSITY")
                                .font(.system(size: 6, weight: .semibold)).tracking(0.5)
                                .lineLimit(1).minimumScaleFactor(0.7)
                        }
                        Spacer(minLength: 0)
                    }
                    .foregroundStyle(campusInk)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(greeting(at: context.date))
                            .font(.title3.bold())
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .bottom) {
                            campusDate(context.date)
                            Spacer(minLength: 12)
                            motto
                        }
                        VStack(alignment: .leading, spacing: 14) {
                            campusDate(context.date)
                            motto
                        }
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background {
                    ZStack {
                    Color(.secondarySystemGroupedBackground)
                    LinearGradient(colors: [AppTheme.accent.opacity(0.035), AppTheme.accent.opacity(0.08)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                    GeometryReader { geometry in
                        CampusLandmarkArt(campus: repo.campus)
                            .stroke(campusInk.opacity(0.14), style: StrokeStyle(lineWidth: 1.1, lineCap: .round, lineJoin: .round))
                            .frame(width: geometry.size.width * (repo.campus == .hunnan ? 0.84 : 0.78), height: geometry.size.height * 0.85)
                            .offset(x: geometry.size.width * (repo.campus == .hunnan ? 0.15 : 0.31), y: geometry.size.height * 0.25)
                    }.accessibilityHidden(true)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .strokeBorder(AppTheme.accent.opacity(0.1), lineWidth: 1)
                }
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .gesture(LongPressGesture(minimumDuration: 0.5).exclusively(before: TapGesture()).onEnded { action in
            switch action {
            case .first: path.append(.ecode)
            case .second: path.append(.web(repo.ecodeEntryURL))
            }
        })
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel("东北大学，\(repo.campus.title)，e码通")
        .accessibilityHint("单击打开学校页面，长按打开原生校园码")
        .accessibilityAction { path.append(.web(repo.ecodeEntryURL)) }
        .accessibilityAction(named: "原生e码通") { path.append(.ecode) }
        .accessibilityIdentifier("home.ecode")
    }

    private func greeting(at date: Date) -> String {
        let name = environment.session.user?.name.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return name.isEmpty ? "\(AppTheme.greeting(date))，东大人" : "\(AppTheme.greeting(date))，\(name)"
    }

    private func campusDate(_ date: Date) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(date, format: .dateTime.locale(Locale(identifier: "zh_CN")).month().day().weekday(.wide))
                .font(.caption.weight(.medium))
            Text(semesterLabel(at: date))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private var motto: some View {
        Image("NEUMotto")
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .foregroundStyle(campusInk.opacity(0.75))
            .frame(width: 112, height: 27)
            .accessibilityLabel("知行合一")
    }

    private func semesterLabel(at date: Date) -> String {
        let week = Semester.weekNumberOf(date)
        if week < 1 || week > Semester.totalWeeks { return "校园时光 · 假期中" }
        return Semester.isExamWeek(week) ? "第 \(week) 周 · 考试周" : "第 \(week) 教学周"
    }

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

    private var dataCardsSection: some View {
        Group {
            if !repo.dataCards.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    sectionHeader("我的校园数据", icon: "chart.bar.doc.horizontal")
                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(spacing: 10) {
                            ForEach(repo.dataCards) { card in
                                Button { path.append(.web(repo.dataCardURL(card))) } label: {
                                GlassCard(cornerRadius: 16) {
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text(card.name)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                        Text(card.value)
                                            .font(.title3.bold())
                                            .lineLimit(1)
                                            .minimumScaleFactor(0.6)
                                    }
                                    .padding(12)
                                    .frame(width: 128, alignment: .topLeading)
                                }
                                }.buttonStyle(.plain)
                                .accessibilityHint("打开对应校园数据网页")
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
            let status = repo.todayScheduleStatus()
            HStack {
                sectionHeader("今日课程", icon: "clock")
                Spacer()
                Button("查看课表") { selection = .schedule }
                    .font(.caption.weight(.medium))
            }
            GlassCard {
                VStack(spacing: 0) {
                    if status != .loaded {
                        todayStatusLabel(status)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(14)
                    }
                    if timeline.isEmpty && status == .loaded {
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

    @ViewBuilder
    private func todayStatusLabel(_ status: ScheduleReadStatus) -> some View {
        switch status {
        case .unread: Label("今日课表尚未读取，请刷新后查看", systemImage: "calendar.badge.questionmark")
        case .loading: HStack { ProgressView(); Text("正在读取今日课表…") }
        case .failed(let message): Label("今日课表读取失败：" + message, systemImage: "exclamationmark.triangle")
        case .partial(let message): Label("课表未完整同步，以下可能为部分或上次结果：" + message, systemImage: "exclamationmark.triangle")
        case .loaded: EmptyView()
        }
    }

    private var quickAppsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            let favorites = repo.favorites.apps(in: repo.apps)
            HStack {
                sectionHeader("常用应用", icon: "square.grid.2x2")
                Spacer()
                Menu {
                    Button("编辑常用应用", systemImage: "star") { showFavorites = true }
                    Button("全部服务", systemImage: "square.grid.2x2") { selection = .services }
                } label: {
                    Image(systemName: "ellipsis").frame(width: 44, height: 44)
                }.accessibilityLabel("管理常用应用")
            }
            if favorites.isEmpty {
                Button("添加常用应用", systemImage: "plus") { showFavorites = true }
                    .font(.subheadline).frame(maxWidth: .infinity, minHeight: 60)
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
            } else {
                GlassCard {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: appColumnWidth), spacing: 8)], spacing: 12) {
                        ForEach(Array(favorites.prefix(4))) { app in
                            Button { open(app) } label: {
                                VStack(spacing: 8) {
                                    ServiceAppIcon(app: app).frame(width: 40, height: 40)
                                    Text(app.name).font(.caption).foregroundStyle(.primary)
                                        .lineLimit(2).multilineTextAlignment(.center)
                                        .frame(minHeight: 28, alignment: .top)
                                }
                                .frame(maxWidth: .infinity).padding(.vertical, 10)
                            }.buttonStyle(.plain)
                        }
                    }.padding(12)
                }
            }
        }
    }

    private var todosSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                sectionHeader("办事动态", icon: "checklist")
                Spacer()
                Button("全部") { path.append(.nativeService(.affairs)) }.font(.subheadline)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 10) {
                    ForEach(repo.todos.prefix(2)) { todo in
                        Button {
                            if let url = PortalLink.resolve(todo.url) {
                                path.append(.web(url))
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
            HStack {
                sectionHeader("校园资讯", icon: "newspaper")
                Spacer()
                Button("更多") { path.append(.nativeService(.news)) }.font(.subheadline)
            }
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
                        ForEach(Array(repo.news.prefix(3).enumerated()), id: \.element.id) { index, item in
                            Button {
                                if let url = PortalLink.resolve(item.url) {
                                    path.append(.web(url))
                                }
                            } label: {
                                NewsRow(item: item)
                            }
                            .buttonStyle(.plain)
                            if index < min(repo.news.count, 3) - 1 {
                                Divider().padding(.leading, 14)
                            }
                        }
                    }
                }
            }
        }
    }

    private var cardEntrySection: some View {
        GlassCard {
            Button {
                path.append(.card)
            } label: {
                HStack(spacing: 14) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(LinearGradient(colors: [AppTheme.accent, AppTheme.accentDeep], startPoint: .topLeading, endPoint: .bottomTrailing))
                        Image(systemName: "creditcard.fill")
                            .font(.title3)
                            .foregroundStyle(.white)
                    }
                    .frame(width: 44, height: 44)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("校园卡")
                            .font(.subheadline.bold())
                            .foregroundStyle(.primary)
                        Text(cardEntrySubtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .padding(14)
            }
            .buttonStyle(.plain)
        }
    }

    private var cardEntrySubtitle: String {
        switch repo.cardState {
        case .loaded:
            var parts: [String] = []
            if let balance = repo.cardBalance {
                parts.append("余额 \(String(format: "%.2f", balance.balance)) 元")
            }
            if let net = repo.netInfo, net.flowFromPortal {
                parts.append("网费 \(String(format: "%.2f", net.balance)) 元")
            }
            return parts.isEmpty ? "查看余额与流水" : parts.joined(separator: " · ")
        case .loading:
            return "正在同步…"
        default:
            return "查看余额、流水、网费与电费"
        }
    }

    private func sectionHeader(_ title: String, icon: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.footnote)
                .foregroundStyle(campusInk)
            Text(title)
                .font(.headline)
        }
    }

    private func open(_ app: PortalApp) {
        guard let destination = AppDestination.service(app) else { return }
        path.append(destination)
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
    @Environment(AppEnvironment.self) private var environment
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
            Group {
                if let data = environment.repository.newsThumbnails[item.id], let image = UIImage(data: data) {
                    Image(uiImage: image).resizable().scaledToFill()
                } else {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(AppTheme.accent.opacity(0.06))
                        .overlay {
                            if environment.repository.newsThumbnails[item.id] == nil { ProgressView().controlSize(.small) }
                            else { Text("暂无配图").font(.caption2).foregroundStyle(.secondary) }
                        }
                }
            }
            .frame(width: 88, height: 64)
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .accessibilityHidden(true)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .task(id: "\(item.id)|\(environment.repository.newsRevision)") {
            await environment.repository.loadNewsThumbnail(item)
        }
    }
}

import Foundation
import SwiftUI
import WidgetKit

struct NEULumenNextCourseWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "NEULumenNextCourseWidget", provider: CampusWidgetProvider(content: .nextCourse)) { entry in
            NextCourseWidgetView(entry: entry)
        }
        .configurationDisplayName("下一节课")
        .description("查看下一节课的时间和教室，轻点打开课表。")
        .supportedFamilies([.systemSmall, .accessoryRectangular, .accessoryInline])
        .disfavoredLocations(campusWidgetDisfavoredLocations, for: [.systemSmall])
    }
}

struct NEULumenTodayScheduleWidget: Widget {
    private var families: [WidgetFamily] {
        #if compiler(>=6.4)
        if #available(iOS 27.0, *) {
            return [.systemMedium, .systemLarge, .systemExtraLargePortrait]
        }
        #endif
        return [.systemMedium, .systemLarge]
    }

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "NEULumenTodayScheduleWidget", provider: CampusWidgetProvider(content: .today)) { entry in
            TodayScheduleWidgetView(entry: entry)
        }
        .configurationDisplayName("今日课表")
        .description("查看今天的课程安排和上课位置。")
        .supportedFamilies(families)
    }
}

struct NEULumenAssignmentsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "NEULumenAssignmentsWidget", provider: CampusWidgetProvider(content: .assignments)) { entry in
            AssignmentsWidgetView(entry: entry)
        }
        .configurationDisplayName("待交作业")
        .description("查看待交作业与截止时间，轻点打开作业页。")
        .supportedFamilies([.systemSmall, .systemMedium])
        .disfavoredLocations(campusWidgetDisfavoredLocations, for: [.systemSmall])
    }
}

struct NEULumenCampusLauncherWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "NEULumenCampusLauncherWidget", provider: CampusWidgetProvider(content: .launcher)) { _ in
            CampusLauncherWidgetView()
        }
        .configurationDisplayName("校园入口")
        .description("从主屏幕访问服务大厅，或直达地图、图书馆、校园卡与缴费。")
        .supportedFamilies([.systemSmall, .systemMedium])
        .disfavoredLocations(campusWidgetDisfavoredLocations, for: [.systemSmall])
    }
}

private var campusWidgetDisfavoredLocations: [WidgetLocation] {
    if #available(iOS 26.0, *) { return [.carPlay] }
    return []
}

private struct CampusWidgetEntry: TimelineEntry {
    let date: Date
    var snapshot: CampusWidgetSnapshot? = nil

    var schedule: CampusWidgetSnapshot.Schedule? {
        guard let schedule = snapshot?.schedule, schedule.expiresAt > date else { return nil }
        return schedule
    }

    var assignments: CampusWidgetSnapshot.Assignments? {
        guard let assignments = snapshot?.assignments, assignments.expiresAt > date else { return nil }
        return assignments
    }

    var nextCourse: CampusWidgetSnapshot.Course? {
        guard hasTodaySchedule else { return nil }
        return schedule?.courses.first { $0.start > date }
    }

    var hasTodaySchedule: Bool {
        schedule?.loadedDays.contains(CampusWidgetSnapshot.schoolCalendar.startOfDay(for: date)) == true
    }

    var todayCourses: [CampusWidgetSnapshot.Course]? {
        let calendar = CampusWidgetSnapshot.schoolCalendar
        let startOfDay = calendar.startOfDay(for: date)
        guard let schedule, schedule.loadedDays.contains(startOfDay),
              let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) else { return nil }
        return schedule.courses.filter { $0.start < endOfDay && $0.end > startOfDay }
    }

    var assignmentItems: [CampusWidgetSnapshot.Assignment] {
        guard let items = assignments?.items else { return [] }
        let upcoming = items.filter { $0.deadline.map { $0 > date } == true }
        let overdue = items.filter { $0.deadline.map { $0 <= date } == true }
        return upcoming + overdue + items.filter { $0.deadline == nil }
    }

    static var preview: Self {
        let calendar = CampusWidgetSnapshot.schoolCalendar
        let day = calendar.startOfDay(for: Date())
        let time = day.addingTimeInterval(8 * 3600)
        let expiry = day.addingTimeInterval(24 * 3600)
        let courses = [
            CampusWidgetSnapshot.Course(id: "one", title: "离散数学", room: "教学楼 A204",
                                        start: time.addingTimeInterval(1800), end: time.addingTimeInterval(7200)),
            CampusWidgetSnapshot.Course(id: "two", title: "程序设计", room: "教学楼 B310",
                                        start: time.addingTimeInterval(9000), end: time.addingTimeInterval(14400)),
            CampusWidgetSnapshot.Course(id: "three", title: "大学物理", room: "教学楼 A106",
                                        start: time.addingTimeInterval(25200), end: time.addingTimeInterval(30600))
        ]
        let assignments = [
            CampusWidgetSnapshot.Assignment(id: "one", title: "第三章课后练习", platform: "中国大学 MOOC",
                                            deadline: time.addingTimeInterval(10800)),
            CampusWidgetSnapshot.Assignment(id: "two", title: "实验报告", platform: "超星学习通",
                                            deadline: time.addingTimeInterval(144000))
        ]
        return Self(date: time, snapshot: CampusWidgetSnapshot(
            capturedAt: time,
            schedule: .init(courses: courses, loadedDays: [day], expiresAt: expiry),
            assignments: .init(pendingCount: assignments.count, isPartial: false, items: assignments, expiresAt: expiry)
        ))
    }
}

private struct CampusWidgetProvider: TimelineProvider {
    enum Content {
        case nextCourse, today, assignments, launcher
    }

    let content: Content

    func placeholder(in context: Context) -> CampusWidgetEntry {
        .preview
    }

    func getSnapshot(in context: Context, completion: @escaping (CampusWidgetEntry) -> Void) {
        if context.isPreview {
            completion(.preview)
        } else {
            completion(CampusWidgetEntry(date: Date(),
                                         snapshot: content == .launcher ? nil : CampusWidgetSnapshot.load()))
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<CampusWidgetEntry>) -> Void) {
        let now = Date()
        guard content != .launcher else {
            completion(Timeline(entries: [CampusWidgetEntry(date: now)], policy: .never))
            return
        }

        let snapshot = CampusWidgetSnapshot.load()
        let current = CampusWidgetEntry(date: now, snapshot: snapshot)
        let dates = transitionDates(for: current)
        let entries = [current] + dates.map { CampusWidgetEntry(date: $0, snapshot: snapshot) }
        // The app requests reloads on changes. One retry covers temporary storage access failures.
        let retry = (dates.last ?? now).addingTimeInterval(3 * 3600)
        completion(Timeline(entries: entries, policy: .after(retry)))
    }

    private func transitionDates(for entry: CampusWidgetEntry) -> [Date] {
        let expiry: Date
        var changes: [Date]
        switch content {
        case .nextCourse, .today:
            guard let schedule = entry.schedule else { return [] }
            expiry = schedule.expiresAt
            changes = schedule.courses.map(\.start)
            if content == .today { changes += schedule.courses.map(\.end) }
        case .assignments:
            guard let assignments = entry.assignments else { return [] }
            expiry = assignments.expiresAt
            changes = assignments.items.compactMap(\.deadline)
        case .launcher:
            return []
        }
        let calendar = CampusWidgetSnapshot.schoolCalendar
        var day = calendar.startOfDay(for: entry.date)
        while let nextDay = calendar.date(byAdding: .day, value: 1, to: day), nextDay < expiry {
            changes.append(nextDay)
            day = nextDay
        }
        return Array(Set(changes.filter { $0 > entry.date && $0 < expiry })).sorted() + [expiry]
    }
}

private enum CampusWidgetLink {
    static let course = URL(string: "neulumen://activity/course")!
    static let todaySchedule = CampusShortcutPage.todaySchedule.url
    static let assignments = URL(string: "neulumen://activity/learning?section=assignments")!
    static let services = URL(string: "neulumen://activity/services")!
    static let settings = URL(string: "neulumen://activity/widget-settings")!
}

private struct NextCourseWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: CampusWidgetEntry

    private var title: String {
        entry.nextCourse?.title ?? (entry.hasTodaySchedule ? "暂无后续课程" : "打开应用同步")
    }

    var body: some View {
        Group {
            switch family {
            case .accessoryInline:
                if let course = entry.nextCourse {
                    Label("\(WidgetDateText.start(course.start, at: entry.date)) \(course.title)", systemImage: "calendar")
                        .privacySensitive()
                } else {
                    Label(title, systemImage: "calendar").privacySensitive(entry.hasTodaySchedule)
                }
            case .accessoryRectangular:
                VStack(alignment: .leading, spacing: 2) {
                    Label("下一节课", systemImage: "calendar")
                        .font(.caption2.weight(.semibold))
                        .widgetAccentable()
                    if let course = entry.nextCourse {
                        Text(course.title).font(.headline).lineLimit(1).privacySensitive()
                        Text([WidgetDateText.start(course.start, at: entry.date), course.room]
                            .filter { !$0.isEmpty }.joined(separator: " · "))
                            .font(.caption2)
                            .lineLimit(1)
                            .privacySensitive()
                    } else {
                        Text(title).font(.caption).lineLimit(1).privacySensitive(entry.hasTodaySchedule)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            default:
                VStack(alignment: .leading, spacing: 7) {
                    CampusWidgetHeader(title: "下一节课", symbol: "calendar")
                    Spacer(minLength: 0)
                    if let course = entry.nextCourse {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(WidgetDateText.start(course.start, at: entry.date))
                                .font(.subheadline.weight(.semibold).monospacedDigit())
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                            Text(course.title).font(.headline).lineLimit(2)
                            if !course.room.isEmpty {
                                Label(course.room, systemImage: "mappin")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                        .privacySensitive()
                    } else {
                        CampusWidgetMessage(title: title, detail: entry.hasTodaySchedule ? nil : "在小组件设置中更新")
                            .privacySensitive(entry.hasTodaySchedule)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            }
        }
        .containerBackground(for: .widget) {
            if family == .systemSmall { CampusWidgetBackground() }
        }
        .widgetURL(entry.hasTodaySchedule ? CampusWidgetLink.course : CampusWidgetLink.settings)
    }
}

private struct TodayScheduleWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: CampusWidgetEntry

    private var isExtraLarge: Bool {
        #if compiler(>=6.4)
        if #available(iOS 27.0, *) { return family == .systemExtraLargePortrait }
        #endif
        return false
    }

    private var visibleCount: Int {
        if isExtraLarge { return 10 }
        return family == .systemLarge ? 7 : 3
    }

    private var rowSpacing: CGFloat { family == .systemMedium ? 5 : 8 }

    var body: some View {
        VStack(alignment: .leading, spacing: rowSpacing) {
            HStack {
                CampusWidgetHeader(title: "今日课表", symbol: "calendar")
                Spacer(minLength: 4)
                Text(WidgetDateText.day(entry.date))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            if let courses = entry.todayCourses, !courses.isEmpty {
                ViewThatFits(in: .vertical) {
                    courseList(courses, limit: visibleCount)
                    courseList(courses, limit: max(1, visibleCount - 2))
                    courseList(courses, limit: 1)
                }
                Spacer(minLength: 0)
            } else {
                Spacer(minLength: 0)
                if entry.todayCourses == nil {
                    CampusWidgetMessage(title: "今日课表等待同步", detail: "打开应用更新课表")
                } else {
                    CampusWidgetMessage(title: "今天没有课", detail: nil).privacySensitive()
                }
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .containerBackground(for: .widget) { CampusWidgetBackground() }
        .widgetURL(entry.todayCourses == nil ? CampusWidgetLink.settings : CampusWidgetLink.todaySchedule)
    }

    private func courseList(_ courses: [CampusWidgetSnapshot.Course], limit: Int) -> some View {
        VStack(alignment: .leading, spacing: rowSpacing) {
            ForEach(courses.prefix(limit)) { course in
                courseRow(course)
            }
            if courses.count > limit {
                Text("另有 \(courses.count - limit) 节 · 打开完整课表")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .privacySensitive()
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private func courseRow(_ course: CampusWidgetSnapshot.Course) -> some View {
        let ongoing = course.start <= entry.date && entry.date < course.end
        return HStack(spacing: 8) {
            Text(isExtraLarge
                 ? "\(WidgetDateText.clock(course.start))–\(WidgetDateText.clock(course.end))"
                 : WidgetDateText.clock(course.start))
                .font(.caption.monospacedDigit().weight(ongoing ? .semibold : .regular))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Text(course.title)
                .font(.subheadline.weight(ongoing ? .semibold : .regular))
                .lineLimit(1)
                .layoutPriority(1)
            Spacer(minLength: 0)
            if !course.room.isEmpty {
                Text(course.room)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue(Text(ongoing ? "上课中" : ""))
        .privacySensitive()
    }
}

private struct AssignmentsWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: CampusWidgetEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 4) {
                CampusWidgetHeader(title: "待交作业", symbol: "checklist")
                Spacer(minLength: 0)
                if let data = entry.assignments, family == .systemMedium, data.pendingCount > 0 {
                    Text(data.isPartial ? "已同步 \(data.pendingCount) 项" : "共 \(data.pendingCount) 项")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .privacySensitive()
                }
            }
            Spacer(minLength: 0)
            if let data = entry.assignments, !data.items.isEmpty {
                ForEach(entry.assignmentItems.prefix(family == .systemSmall ? 1 : 2)) { assignment in
                    assignmentRow(assignment)
                }
                if family == .systemSmall, data.pendingCount > 1 {
                    Text("另有 \(data.pendingCount - 1) 项")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .privacySensitive()
                }
                if data.isPartial {
                    Text("部分平台待同步").font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
            } else if let data = entry.assignments, !data.isPartial {
                CampusWidgetMessage(title: "没有待交作业", detail: nil).privacySensitive()
            } else {
                CampusWidgetMessage(title: "作业等待同步", detail: "打开应用更新作业")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .containerBackground(for: .widget) { CampusWidgetBackground() }
        .widgetURL(entry.assignments == nil ? CampusWidgetLink.settings : CampusWidgetLink.assignments)
    }

    private func assignmentRow(_ assignment: CampusWidgetSnapshot.Assignment) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(assignment.title).font(.subheadline.weight(.semibold))
                .lineLimit(family == .systemSmall ? 2 : 1)
            if let deadline = assignment.deadline {
                Text(deadline <= entry.date ? "已截止" : "\(WidgetDateText.start(deadline, at: entry.date)) 截止")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            } else {
                Text(assignment.platform).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .accessibilityElement(children: .combine)
        .privacySensitive()
    }
}

private struct CampusLauncherWidgetView: View {
    @Environment(\.widgetFamily) private var family
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            CampusWidgetHeader(title: "校园入口", symbol: "square.grid.2x2.fill")
            Spacer(minLength: 0)
            if family == .systemSmall {
                Image(systemName: "building.columns")
                    .font(.title2.weight(.medium))
                    .foregroundStyle(CampusWidgetBackground.accent(for: colorScheme))
                    .widgetAccentable()
                    .accessibilityHidden(true)
                Text("服务大厅").font(.headline).lineLimit(1)
            } else {
                HStack(alignment: .top, spacing: 5) {
                    shortcut("校园地图", symbol: "map", destination: "neulumen://activity/services?native=map")
                    shortcut("图书馆", symbol: "books.vertical", destination: "neulumen://activity/services?native=library")
                    shortcut("校园卡", symbol: "creditcard", destination: "neulumen://activity/card")
                    shortcut("生活缴费", symbol: "bolt", destination: "neulumen://activity/services?native=payment")
                }
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .containerBackground(for: .widget) { CampusWidgetBackground() }
        .widgetURL(CampusWidgetLink.services)
    }

    private func shortcut(_ title: String, symbol: String, destination: String) -> some View {
        Link(destination: URL(string: destination)!) {
            VStack(spacing: 5) {
                Image(systemName: symbol)
                    .font(.title3.weight(.medium))
                    .frame(width: 38, height: 38)
                    .foregroundStyle(CampusWidgetBackground.accent(for: colorScheme))
                    .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 11))
                    .widgetAccentable()
                    .accessibilityHidden(true)
                Text(title)
                    .font(.caption2.weight(.medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .frame(maxWidth: .infinity)
        }
    }
}

private struct CampusWidgetHeader: View {
    @Environment(\.colorScheme) private var colorScheme
    let title: String
    let symbol: String

    var body: some View {
        Label(title, systemImage: symbol)
            .font(.caption.weight(.semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .foregroundStyle(CampusWidgetBackground.accent(for: colorScheme))
            .widgetAccentable()
    }
}

private struct CampusWidgetMessage: View {
    let title: String
    let detail: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.headline).lineLimit(2)
            if let detail {
                Text(detail).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
            }
        }
    }
}

private struct CampusWidgetBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    static func accent(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark
            ? Color(red: 0.66, green: 0.77, blue: 0.99)
            : Color(red: 0.21, green: 0.33, blue: 0.64)
    }

    var body: some View {
        Color(uiColor: .systemBackground)
            .overlay {
                LinearGradient(colors: [Self.accent(for: colorScheme).opacity(0.12), .clear],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
            }
    }
}

private enum WidgetDateText {
    private static let clockFormatter = formatter("HH:mm")
    private static let dayFormatter = formatter("EEE M/d")
    private static let shortDayFormatter = formatter("M/d")

    static func clock(_ date: Date) -> String { clockFormatter.string(from: date) }
    static func day(_ date: Date) -> String { dayFormatter.string(from: date) }

    static func start(_ date: Date, at reference: Date) -> String {
        let calendar = CampusWidgetSnapshot.schoolCalendar
        if calendar.isDate(date, inSameDayAs: reference) { return clock(date) }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: reference),
           calendar.isDate(date, inSameDayAs: tomorrow) { return "明天 \(clock(date))" }
        return "\(shortDayFormatter.string(from: date)) \(clock(date))"
    }

    private static func formatter(_ format: String) -> DateFormatter {
        let value = DateFormatter()
        value.locale = Locale(identifier: "zh_CN")
        value.calendar = CampusWidgetSnapshot.schoolCalendar
        value.timeZone = CampusWidgetSnapshot.schoolCalendar.timeZone
        value.dateFormat = format
        return value
    }
}

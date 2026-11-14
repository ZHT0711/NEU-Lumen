// Synthetic UI fixture only: copied into the disposable Debug project, never Release.
import SwiftUI
import UIKit

@MainActor
enum LiveActivityUIFixture {
    static let kinds = ["nextCourse", "cardBalance", "netBalance", "electricBalance", "assignments",
                        "planner", "dayOverview", "academicOverview", "custom"]
    static let widths: [CGFloat] = [330, 350, 370]
    static let now = Date()
    static let budget = LiveActivityLayoutMetrics.expandedContentHeight
    static let fonts: [(String, DynamicTypeSize)] = [("large", .large), ("accessibility3", .accessibility3)]

    static func state(_ kind: String) -> LiveActivityContentState {
        var state = LiveActivityContentState(title: "合成数据 · 共享组件验证", subtitle: "非真实账号数据",
            value: "", kind: kind, updatedAt: now, accent: "cyan")
        func detail(_ label: String, _ value: String, timed: Bool = false) -> LiveActivityDetail {
            .init(label: label, value: value, isTimeSensitive: timed ? true : nil)
        }
        switch kind {
        case "nextCourse", "planner":
            state.title = kind == "nextCourse" ? "合成课程：程序设计基础与人工智能综合实践（长中文标题）" : "合成日程：跨学科小组讨论与项目实践"
            state.subtitle = "合成地点 · 不代表学校课表"
            state.startDate = now.addingTimeInterval(21 * 86400 + 21 * 3600 + 16 * 60)
            state.endDate = state.startDate!.addingTimeInterval(5400)
            state.countdownTarget = "start"
            state.countdownTitle = kind == "nextCourse" ? "距上课" : "距开始"
            state.phase = "upcoming"
            state.detailItems = [detail("地点", "合成教学楼 A101"), detail("时间", "合成起止日期时间", timed: true),
                detail(kind == "nextCourse" ? "教师" : "备注", kind == "nextCourse" ? "合成教师" : "合成会议准备事项"),
                detail("周节", "合成第 9 周 · 第 3–4 节"), detail("今日", "已读 4 项 · 待完成 2 项", timed: true),
                detail("后续", "合成后续事项 · 信息仅用于 UI", timed: true)]
        case "cardBalance":
            state.title = "合成校园卡余额 · 真实组件展示"
            state.value = "¥66.50"
            state.detailItems = [detail("卡状态", "合成正常卡"), detail("补助", "¥7.50"), detail("来源", "合成缓存 · 非校园账号"),
                                detail("同步", "合成同步时间")]
        case "netBalance":
            state.title = "合成校园网余额与已读取用量"
            state.value = "¥25.00"
            state.detailItems = [detail("流量", "合成 3.0 GB"), detail("时长", "合成 2 小时"), detail("连接", "合成 12 次"),
                                detail("同步", "合成同步时间")]
        case "electricBalance":
            state.title = "合成宿舍电量 · 长中文房间名称验证"
            state.value = "19.75 kWh"
            state.accent = "orange"
            state.detailItems = [detail("房间", "合成学生宿舍 A 栋 101 室"), detail("房间码", "SYNTH-101"),
                                detail("抄表", "合成抄表时间"), detail("同步", "合成同步时间"), detail("提醒", "合成低余量提示")]
        case "assignments":
            state.title = "合成学习作业 · 部分读取覆盖提示"
            state.value = "5+ 项待办"
            state.progress = 0.4
            state.detailItems = [detail("平台", "合成 MOOC / 学习通 / CG"), detail("截止", "合成最近截止日期", timed: true),
                detail("逾期", "合成 1 项", timed: true), detail("已同步", "合成 2 / 3 平台"),
                detail("完成", "合成 4 项", timed: true), detail("覆盖", "部分数据 · 非全量任务")]
        case "dayOverview":
            state.title = "合成今日课程与个人日程总览"
            state.value = "4 项已读取"
            state.progress = 0.5
            state.phase = "ongoing"
            state.detailItems = [detail("课程", "合成 3 门"), detail("日程", "合成 1 项"), detail("待完成", "合成 2 项", timed: true),
                detail("下一项", "合成讨论课", timed: true), detail("时间地点", "合成 14:00 · A101", timed: true),
                detail("覆盖", "部分课表已读取")]
        case "academicOverview":
            state.title = "合成学业统计 · 未知成绩不作为零分"
            state.value = "GPA 3.85"
            state.detailItems = [detail("学期", "合成学期 · UI 验证"), detail("有效学分", "合成 8.0"),
                detail("均分", "合成 90.5"), detail("成绩", "合成 2 / 3 门有效"), detail("同步", "合成同步时间")]
        default:
            state.title = "合成自定义：跨学科项目截止与用户辅助信息（长中文）"
            state.subtitle = "{sf:mappin.and.ellipse} 合成校园项目 · {sf:clock.fill} 合成截止时间"
            state.value = "123:21:16:00"
            state.secondaryValue = "合成用户辅助值"
            state.symbolName = "bell.fill"
            state.accent = "purple"
            state.endDate = now.addingTimeInterval(123 * 86400 + 21 * 3600 + 16 * 60)
            state.countdownTarget = "end"
            state.countdownTitle = "距截止"
            state.progress = 0.35
            state.detailItems = [detail("辅助值", "合成用户辅助内容"), detail("截止", "合成多日目标", timed: true),
                                detail("备注", "合成项目安排")]
        }
        return state.boundedText()
    }

    static func missing(_ kind: String) -> LiveActivityContentState {
        var value = state(kind)
        value.startDate = nil; value.endDate = nil; value.countdownTarget = nil; value.countdownTitle = nil
        value.detailItems = nil; value.secondaryValue = nil; value.progress = nil; value.phase = nil
        value.accent = nil; value.symbolName = nil; value.staleAfter = nil; value.destinationPath = nil
        value.updatedAt = .distantPast; value.subtitle = ""; value.value = "合成未提供"
        return value
    }
}

struct LiveActivityExpandedPreview: View {
    let token: String
    private var ax: Bool { token == "ax-stale" }
    var body: some View {
        ScrollView([.vertical, .horizontal]) {
            VStack(alignment: .leading, spacing: 12) {
                Text("模拟器共享组件布局验证").font(.headline)
                Text("非系统灵动岛截屏/非真机").font(.subheadline).foregroundStyle(.orange)
                Text("合成数据 · 非真实校园账号 · 实际 LiveActivityExpandedContent")
                    .font(.caption).foregroundStyle(.secondary)
                ForEach(Array(LiveActivityUIFixture.widths.enumerated()), id: \.offset) { index, width in
                    let kind = ax ? (index == 0 ? "custom" : index == 1 ? "nextCourse" : "academicOverview") : token
                    let stale = ax && index == 1
                    let state = ax && index == 2 ? LiveActivityUIFixture.missing(kind) : LiveActivityUIFixture.state(kind)
                    Text("\(Int(width)) × 100pt 下区 · \(ax ? "AX3" : "标准字号") · \(stale ? "过期待更新" : index == 2 && ax ? "nil 元数据" : state.sourceTitle)")
                        .font(.caption).foregroundStyle(.secondary)
                    LiveActivityExpandedContent(state: state, isStale: stale)
                        .environment(\.dynamicTypeSize, ax ? .accessibility3 : .large)
                        .environment(\.colorScheme, .dark)
                        .frame(width: width, height: LiveActivityUIFixture.budget, alignment: .topLeading)
                        .background(Color.black, in: RoundedRectangle(cornerRadius: 12))
                }
            }.padding(8)
        }
        .background(Color(.systemGroupedBackground))
    }
}

@MainActor
private final class LiveActivityUIObservation {
    var bounds: [String: CGRect] = [:]
}

private struct LiveActivityMeasuredView<Content: View>: View {
    let content: Content
    let observation: LiveActivityUIObservation
    let font: DynamicTypeSize
    var body: some View {
        content.environment(\.dynamicTypeSize, font).environment(\.colorScheme, .dark)
            .environment(\.locale, Locale(identifier: "zh_CN"))
            .coordinateSpace(name: "activity-layout-validation")
            .onPreferenceChange(LiveActivityUIBounds.self) { observation.bounds = $0 }
    }
}

// Both children are actual Text and use the production Layout, not metricPlan rectangles.
private struct LiveActivityMetricStress: View {
    let systemTimer: Bool
    var body: some View {
        LiveActivityMetricLayout {
            Text("距离下一项合成跨学科实践活动开始")
                .font(.caption2).lineLimit(1).minimumScaleFactor(0.8)
                .background(LiveActivityUIProbe(id: "metric.label"))
            Group {
                if systemTimer {
                    Text(timerInterval: LiveActivityUIFixture.now...LiveActivityUIFixture.now.addingTimeInterval(123 * 86400 + 21 * 3600 + 16 * 60), countsDown: true)
                } else {
                    Text("123:21:16:00")
                }
            }
            .font(.title3.monospacedDigit().weight(.semibold)).lineLimit(1)
            .minimumScaleFactor(LiveActivityLayoutMetrics.valueMinimumScale)
            .multilineTextAlignment(.trailing)
            .background(LiveActivityUIProbe(id: "metric.value"))
        }
    }
}

@MainActor
private func measuredActivity<Content: View>(_ content: Content, width: CGFloat, font: DynamicTypeSize,
    container: UIViewController, name: String, shared: Bool) async throws -> String {
    let observation = LiveActivityUIObservation()
    let host = UIHostingController(rootView: LiveActivityMeasuredView(content: content, observation: observation, font: font))
    host.safeAreaRegions = []
    container.addChild(host)
    container.view.addSubview(host.view)
    host.didMove(toParent: container)
    defer {
        host.willMove(toParent: nil); host.view.removeFromSuperview(); host.removeFromParent()
    }
    // No fixed-size fixture wrapper or clipping: ask the actual production view twice.
    let intrinsic = host.sizeThatFits(in: CGSize(width: width, height: 10_000))
    let fitted = host.sizeThatFits(in: CGSize(width: width, height: LiveActivityUIFixture.budget))
    func require(_ condition: Bool, _ message: String) throws {
        if !condition { throw NetworkError(message: name + ": " + message) }
    }
    for (label, size) in [("intrinsic", intrinsic), ("fitted", fitted)] {
        try require(size.width.isFinite && size.height.isFinite && size.width > 0 && size.height > 0,
                    label + " invalid hosting size")
        try require(size.width <= width + 0.5 && size.height <= LiveActivityUIFixture.budget + 0.5,
                    label + " exceeds 100pt lower-region budget: \(size)")
    }
    host.view.frame = CGRect(x: 0, y: 0, width: width, height: LiveActivityUIFixture.budget)
    host.view.setNeedsLayout(); host.view.layoutIfNeeded()
    // Preferences are delivered after real SwiftUI placement, not during synthetic calculations.
    for _ in 0..<30 {
        await Task.yield()
        host.view.layoutIfNeeded()
        if observation.bounds.count >= (shared ? 4 : 2) { break }
        try await Task.sleep(for: .milliseconds(20))
    }
    let bounds = observation.bounds
    let bodies = bounds.filter { $0.key.hasSuffix(".body") }
    try require(!shared || bodies.count == 1, "missing/ambiguous selected ViewThatFits content probes: \(bounds.keys.sorted())")
    let prefix = shared ? String(bodies.keys.first!.dropLast(5)) : "metric"
    try require(bounds[prefix + ".label"] != nil && bounds[prefix + ".value"] != nil,
                "actual metric label/value Text placement probes missing")
    let region = CGRect(x: -0.5, y: -0.5, width: width + 1, height: LiveActivityUIFixture.budget + 1)
    for (key, rect) in bounds {
        try require(rect.origin.x.isFinite && rect.origin.y.isFinite && rect.width.isFinite && rect.height.isFinite,
                    "nonfinite rendered bounds: " + key)
        try require(rect.width > 0 && rect.height > 0 && region.contains(rect),
                    "rendered bounds exceed 100pt (fixed parent must not hide overflow): \(key)=\(rect)")
    }
    // Body is an ancestor. All other probes mark sibling rendered title, metric Text,
    // optional subtitle, individual detail cells, or footer (never overlapping ancestors).
    let leaves = bounds.filter { !$0.key.hasSuffix(".body") }.sorted { $0.key < $1.key }
    for first in leaves.indices {
        for second in leaves.indices where second > first {
            let overlap = leaves[first].value.intersection(leaves[second].value)
            try require(overlap.isNull || overlap.width <= 0.5 || overlap.height <= 0.5,
                        "overlap between actual rendered siblings: \(leaves[first].key), \(leaves[second].key)")
        }
    }
    let bodyHeight = bodies.values.first?.height ?? fitted.height
    return "CASE: \(name) width=\(Int(width)) intrinsic=\(intrinsic.height) fitted=\(fitted.height) content=\(bodyHeight) actual-bounds=\(bounds.count)"
}

@MainActor
func runLiveActivityLayoutChecks() async {
    let output = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("live-activity-layout-checks.txt")
    var lines: [String] = []
    do {
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first else {
            throw NetworkError(message: "No simulator UIWindowScene for actual hosting layout")
        }
        let window = UIWindow(windowScene: scene)
        let container = UIViewController()
        window.rootViewController = container
        window.windowLevel = UIWindow.Level(rawValue: UIWindow.Level.normal.rawValue + 1)
        window.isHidden = false
        defer { window.isHidden = true }
        var sharedCount = 0
        var metricCount = 0
        for kind in LiveActivityUIFixture.kinds {
            for variant in ["fresh", "stale", "nil-metadata"] {
                let state = variant == "nil-metadata" ? LiveActivityUIFixture.missing(kind) : LiveActivityUIFixture.state(kind)
                for width in LiveActivityUIFixture.widths {
                    for (fontName, font) in LiveActivityUIFixture.fonts {
                        let line = try await measuredActivity(LiveActivityExpandedContent(state: state, isStale: variant == "stale"),
                            width: width, font: font, container: container, name: kind + "." + variant + "." + fontName, shared: true)
                        lines.append(line); sharedCount += 1
                    }
                }
            }
        }
        for systemTimer in [true, false] {
            var state = LiveActivityUIFixture.state("custom")
            state.countdownTitle = "距离下一项合成跨学科实践开始"
            if !systemTimer { state.endDate = nil; state.countdownTitle = nil; state.countdownTarget = nil }
            for width in LiveActivityUIFixture.widths {
                for (fontName, font) in LiveActivityUIFixture.fonts {
                    let name = (systemTimer ? "multi-day-system-Text" : "multi-day-string") + "." + fontName
                    lines.append(try await measuredActivity(LiveActivityExpandedContent(state: state, isStale: false),
                        width: width, font: font, container: container, name: name, shared: true))
                    sharedCount += 1
                    lines.append(try await measuredActivity(LiveActivityMetricStress(systemTimer: systemTimer),
                        width: width, font: font, container: container, name: "actual-metric-Layout." + name, shared: false))
                    metricCount += 1
                }
            }
        }
        // Negative controls exercise the SAME hosting/bounds oracle on real bad views.
        var negativeCount = 0
        do {
            _ = try await measuredActivity(ZStack {
                Text("故意重叠标签").background(LiveActivityUIProbe(id: "metric.label"))
                Text("故意重叠数值").background(LiveActivityUIProbe(id: "metric.value"))
            }, width: 330, font: .large, container: container, name: "negative-overlap", shared: false)
            throw NetworkError(message: "Overlap oracle accepted a real overlapping ZStack")
        } catch {
            guard error.localizedDescription.contains("overlap between actual") else { throw error }
            negativeCount += 1
            lines.append("NEGATIVE-CONTROL: negative-overlap-rejected")
        }
        do {
            _ = try await measuredActivity(Text("故意超过高度").frame(height: LiveActivityUIFixture.budget + 1), width: 330,
                font: .large, container: container, name: "negative-oversize", shared: false)
            throw NetworkError(message: "Height oracle accepted a real oversized intrinsic view")
        } catch {
            guard error.localizedDescription.contains("exceeds 100pt lower-region budget") else { throw error }
            negativeCount += 1
            lines.append("NEGATIVE-CONTROL: negative-oversize-rejected")
        }
        guard sharedCount == 174, metricCount == 12, negativeCount == 2 else {
            throw NetworkError(message: "Incomplete real layout matrix")
        }
        let coverage: [String: Any] = ["shared_view_cases": sharedCount, "metric_layout_cases": metricCount,
            "negative_controls": negativeCount, "widths_pt": [330, 350, 370], "max_height_pt": 100, "expanded_max_height_pt": 160, "reserved_height_pt": 60,
            "kinds": LiveActivityUIFixture.kinds, "dynamic_types": ["large", "accessibility3"],
            "variants": ["fresh", "stale", "nil-metadata"], "timer_modes": ["system-Text", "multi-day-string"]]
        let json = String(data: try JSONSerialization.data(withJSONObject: coverage, options: [.sortedKeys]), encoding: .utf8)!
        try (["PASS: actual UIHostingController + shared expanded view + production metric Layout; 174 shared cases, 12 metric cases, 2 rejecting negative controls; simulator only, not system Dynamic Island or real device", "COVERAGE: " + json] + lines)
            .joined(separator: "\n").write(to: output, atomically: true, encoding: .utf8)
    } catch {
        try? (["FAIL: " + error.localizedDescription] + lines).joined(separator: "\n")
            .write(to: output, atomically: true, encoding: .utf8)
    }
}

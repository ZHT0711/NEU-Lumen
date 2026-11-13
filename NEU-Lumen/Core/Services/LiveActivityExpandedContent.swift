import SwiftUI

/// The widget AND simulator validation render this view. The 130pt lower region
/// leaves approximately 30pt for the system camera/leading/trailing regions.
/// ViewThatFits drops lower-priority rows at larger text sizes; nothing is placed
/// over the camera, offset outside a region, or hidden behind a clipping mask.
struct LiveActivityExpandedContent: View {
    let state: LiveActivityContentState
    let isStale: Bool

    var body: some View {
        ViewThatFits(in: .vertical) {
            content(detailLimit: 6, titleLines: 2, compact: false, footer: true)
                .fixedSize(horizontal: false, vertical: true)
            content(detailLimit: 4, titleLines: 2, compact: false, footer: true)
                .fixedSize(horizontal: false, vertical: true)
            content(detailLimit: 2, titleLines: 1, compact: true, footer: true)
                .fixedSize(horizontal: false, vertical: true)
            content(detailLimit: 0, titleLines: 1, compact: true, footer: false)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(maxHeight: LiveActivityLayoutMetrics.expandedContentHeight, alignment: .topLeading)
        .accessibilityElement(children: .contain)
    }

    private func content(detailLimit: Int, titleLines: Int, compact: Bool, footer: Bool) -> some View {
        let details = Array(state.visibleDetails(isStale: isStale).prefix(detailLimit))
        let hasFooterContent = isStale || state.updatedAt != .distantPast || state.progress?.isFinite == true
        return VStack(alignment: .leading, spacing: compact ? 4 : 5) {
            Text(state.displayTitle(isStale: isStale))
                .font(compact ? .subheadline.weight(.semibold) : .headline)
                .lineLimit(titleLines)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let subtitle = state.displaySubtitle(isStale: isStale),
               !compact && (state.kind == "custom" || details.isEmpty) {
                Text(subtitle).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
            if state.countdownDate != nil || !state.value.isEmpty || isStale {
                LiveActivityMetricRow(state: state, isStale: isStale, compact: compact)
            }
            if !details.isEmpty {
                LiveActivityDetailRows(details: details)
            }
            if footer && hasFooterContent {
                HStack(spacing: 6) {
                    if isStale {
                        Label("打开应用更新", systemImage: "arrow.clockwise")
                            .foregroundStyle(.secondary)
                    } else if state.updatedAt != .distantPast {
                        Text("更新")
                            .foregroundStyle(.secondary)
                        Text(state.updatedAt, format: .dateTime.month(.twoDigits).day(.twoDigits).hour().minute())
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    if !isStale, let progress = state.progress, progress.isFinite {
                        if let start = state.startDate, let end = state.endDate, start < end {
                            ProgressView(timerInterval: start...end, countsDown: false)
                                .frame(width: 64)
                                .tint(liveActivityAccent(state.accent))
                        } else {
                            ProgressView(value: min(max(progress, 0), 1))
                                .frame(width: 64)
                                .tint(liveActivityAccent(state.accent))
                                .accessibilityLabel("进度")
                                .accessibilityValue("\(Int(min(max(progress, 0), 1) * 100))%")
                        }
                    }
                }
                .font(.caption2)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct LiveActivityMetricRow: View {
    let state: LiveActivityContentState
    let isStale: Bool
    var compact = false

    private var label: String {
        if isStale { return "内容待更新" }
        if state.countdownDate != nil { return state.countdownTitle ?? "倒计时" }
        switch state.kind {
        case "cardBalance", "netBalance": return "可用余额"
        case "electricBalance": return "剩余电量"
        case "assignments": return "待办汇总"
        case "dayOverview": return "今日事项"
        case "academicOverview": return "学业统计"
        default: return state.sourceTitle
        }
    }

    var body: some View {
        LiveActivityMetricLayout {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Group {
                if let target = state.countdownDate, !isStale, target > Date() {
                    // System-managed Text continues to tick while the app is suspended.
                    Text(timerInterval: Date()...target, countsDown: true)
                } else if state.countdownDate != nil {
                    Text(isStale ? "待更新" : "已到时间 · 待更新")
                } else {
                    Text(state.displayValue(isStale: isStale))
                }
            }
            .font(compact ? .caption.monospacedDigit().weight(.semibold) : .title3.monospacedDigit().weight(.semibold))
            .foregroundStyle(liveActivityAccent(state.accent))
            .lineLimit(1)
            .minimumScaleFactor(LiveActivityLayoutMetrics.valueMinimumScale)
            .multilineTextAlignment(.trailing)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Measures real SwiftUI label/timer subviews. Reserve the label first and shrink
/// only the single-line timer; stack when even its minimum readable width won't fit.
struct LiveActivityMetricLayout: Layout {
    private func plan(_ proposal: ProposedViewSize, _ subviews: Subviews) -> LiveActivityLayoutMetrics.MetricPlan {
        let label = subviews[0].sizeThatFits(.unspecified)
        let value = subviews[1].sizeThatFits(.unspecified)
        let width = proposal.width ?? label.width + LiveActivityLayoutMetrics.gap + value.width
        return LiveActivityLayoutMetrics.metricPlan(width: width, label: label, value: value)
    }
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard subviews.count == 2 else { return .zero }
        return plan(proposal, subviews).size
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard subviews.count == 2 else { return }
        let result = plan(ProposedViewSize(width: bounds.width, height: bounds.height), subviews)
        for (index, rect) in [result.label, result.value].enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + rect.minX, y: bounds.minY + rect.minY),
                anchor: .topLeading, proposal: ProposedViewSize(width: rect.width, height: rect.height))
        }
    }
}

private struct LiveActivityDetailRows: View {
    let details: [LiveActivityDetail]
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        LiveActivityDetailLayout(accessibility: dynamicTypeSize.isAccessibilitySize) {
            ForEach(Array(details.enumerated()), id: \.offset) { _, row in
                (Text(row.label + " ").foregroundColor(.secondary) + Text(row.value))
                    .font(.caption2)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityLabel(row.label + "，" + row.value)
            }
        }
    }
}

private struct LiveActivityDetailLayout: Layout {
    let accessibility: Bool
    private func measurements(width: CGFloat, subviews: Subviews) -> (Int, CGFloat, [CGFloat]) {
        let columns = LiveActivityLayoutMetrics.detailColumns(width: width, accessibility: accessibility)
        let cellWidth = max(0, (width - CGFloat(columns - 1) * 10) / CGFloat(columns))
        var heights: [CGFloat] = []
        for index in subviews.indices {
            let height = subviews[index].sizeThatFits(ProposedViewSize(width: cellWidth, height: nil)).height
            if index.isMultiple(of: columns) { heights.append(height) }
            else { heights[heights.count - 1] = max(heights.last ?? 0, height) }
        }
        return (columns, cellWidth, heights)
    }
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 330
        let (_, _, heights) = measurements(width: width, subviews: subviews)
        return CGSize(width: width, height: heights.reduce(0, +) + CGFloat(max(0, heights.count - 1)) * 3)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let (columns, cellWidth, heights) = measurements(width: bounds.width, subviews: subviews)
        var y = bounds.minY
        for index in subviews.indices {
            let row = index / columns
            subviews[index].place(at: CGPoint(x: bounds.minX + CGFloat(index % columns) * (cellWidth + 10), y: y),
                anchor: .topLeading, proposal: ProposedViewSize(width: cellWidth, height: heights[row]))
            if index % columns == columns - 1 { y += heights[row] + 3 }
        }
    }
}

func liveActivityAccent(_ token: String?) -> Color {
    switch token {
    case "blue": return .blue
    case "green": return .green
    case "orange": return .orange
    case "pink": return .pink
    case "purple": return .purple
    default: return .cyan
    }
}

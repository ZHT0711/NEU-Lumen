import ActivityKit
import SwiftUI
import WidgetKit

struct NEULumenLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: NEULumenActivityAttributes.self) { context in
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label("NEU-Lumen", systemImage: context.state.symbol)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    if context.isStale {
                        Text("打开应用更新").font(.caption).foregroundStyle(.secondary)
                    }
                }
                HStack(alignment: .center, spacing: 14) {
                    ActivityDetails(state: context.state)
                    Spacer(minLength: 0)
                    ActivityValue(state: context.state, isStale: context.isStale)
                }
            }
            .padding(16)
            .activityBackgroundTint(activityAccent(context.state.accent).opacity(0.12))
            .activitySystemActionForegroundColor(activityAccent(context.state.accent))
            .widgetURL(context.state.destination)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: context.state.symbol)
                        .font(.title3)
                        .foregroundStyle(activityAccent(context.state.accent))
                        .accessibilityHidden(true)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    ActivityValue(state: context.state, isStale: context.isStale)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 8) {
                        ActivityDetails(state: context.state)
                        if context.isStale {
                            Text("打开应用更新").font(.caption2).foregroundStyle(.secondary)
                        }
                        if !context.isStale, let progress = context.state.progress, progress.isFinite {
                            if let start = context.state.startDate, let end = context.state.endDate, start < end {
                                ProgressView(timerInterval: start...end, countsDown: false)
                                    .tint(activityAccent(context.state.accent))
                            } else {
                                ProgressView(value: min(max(progress, 0), 1))
                                    .tint(activityAccent(context.state.accent))
                            }
                        }
                    }
                }
            } compactLeading: {
                Image(systemName: context.state.symbol).foregroundStyle(activityAccent(context.state.accent))
            } compactTrailing: {
                if context.isStale {
                    Image(systemName: "arrow.clockwise").accessibilityLabel("内容待更新")
                } else if let target = context.state.countdownDate {
                    if target > Date() {
                        Text(timerInterval: Date()...target, countsDown: true)
                            .font(.caption2.monospacedDigit())
                            .multilineTextAlignment(.trailing)
                            .minimumScaleFactor(0.65)
                            .frame(width: 64)
                    } else {
                        Text("待更新").font(.caption2)
                    }
                } else {
                    Text(context.state.value.isEmpty ? String(context.state.title.prefix(2)) : context.state.value)
                        .font(.caption2.monospacedDigit())
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .frame(maxWidth: 64)
                }
            } minimal: {
                Image(systemName: context.state.symbol).foregroundStyle(activityAccent(context.state.accent))
            }
            .widgetURL(context.state.destination)
            .keylineTint(activityAccent(context.state.accent))
        }
    }
}

private struct ActivityDetails: View {
    let state: NEULumenActivityAttributes.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(state.title).font(.headline).lineLimit(2)
            Text(state.subtitle).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
            if let secondary = state.secondaryValue, !secondary.isEmpty {
                Text(secondary).font(.caption.weight(.medium)).foregroundStyle(activityAccent(state.accent)).lineLimit(2)
            }
            if let start = state.startDate, let end = state.endDate {
                HStack(spacing: 3) {
                    Text(start, style: .time)
                    Text("–")
                    Text(end, style: .time)
                }
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            }
        }
    }
}

private struct ActivityValue: View {
    let state: NEULumenActivityAttributes.ContentState
    let isStale: Bool

    private var target: Date? { state.countdownDate }

    var body: some View {
        if let target, !isStale, target > Date() {
            VStack(alignment: .trailing, spacing: 3) {
                Text(state.countdownTitle ?? "倒计时").font(.caption2).foregroundStyle(.secondary)
                Text(timerInterval: Date()...target, countsDown: true)
                    .font(.headline.monospacedDigit())
                    .multilineTextAlignment(.trailing)
                    .minimumScaleFactor(0.7)
                    .frame(width: 96)
            }
        } else if target != nil {
            Text(isStale ? "待更新" : "已到时间")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
        } else if !state.value.isEmpty {
            Text(state.value)
                .font(.headline.monospacedDigit())
                .foregroundStyle(activityAccent(state.accent))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }
}

private func activityAccent(_ token: String?) -> Color {
    switch token {
    case "blue": return .blue
    case "green": return .green
    case "orange": return .orange
    case "pink": return .pink
    case "purple": return .purple
    default: return .cyan
    }
}

@main
struct NEULumenLiveActivityBundle: WidgetBundle {
    var body: some Widget { NEULumenLiveActivity() }
}

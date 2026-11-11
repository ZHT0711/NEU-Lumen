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
            .activityBackgroundTint(.clear)
            .activitySystemActionForegroundColor(.primary)
            .widgetURL(context.state.destination)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: context.state.symbol)
                        .font(.title3)
                        .foregroundStyle(.cyan)
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
                        } else if let start = context.state.startDate, let end = context.state.endDate, start < end {
                            ProgressView(timerInterval: start...end, countsDown: false)
                                .tint(.cyan)
                        }
                    }
                }
            } compactLeading: {
                Image(systemName: context.state.symbol).foregroundStyle(.cyan)
            } compactTrailing: {
                if context.isStale {
                    Image(systemName: "arrow.clockwise").accessibilityLabel("内容待更新")
                } else {
                    Text(context.state.value.isEmpty ? String(context.state.title.prefix(2)) : context.state.value)
                        .font(.caption2.monospacedDigit())
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .frame(maxWidth: 64)
                }
            } minimal: {
                Image(systemName: context.state.symbol).foregroundStyle(.cyan)
            }
            .widgetURL(context.state.destination)
            .keylineTint(.cyan)
        }
    }
}

private struct ActivityDetails: View {
    let state: NEULumenActivityAttributes.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(state.title).font(.headline).lineLimit(2)
            Text(state.subtitle).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
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

    var body: some View {
        if let end = state.endDate, !isStale {
            VStack(alignment: .trailing, spacing: 3) {
                Text("距下课").font(.caption2).foregroundStyle(.secondary)
                Text(timerInterval: end.addingTimeInterval(-24 * 3600)...end, countsDown: true)
                    .font(.headline.monospacedDigit())
                    .multilineTextAlignment(.trailing)
                    .frame(width: 84)
            }
        } else if !state.value.isEmpty {
            Text(state.value)
                .font(.headline.monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }
}

@main
struct NEULumenLiveActivityBundle: WidgetBundle {
    var body: some Widget { NEULumenLiveActivity() }
}

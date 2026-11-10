import ActivityKit
import SwiftUI
import WidgetKit

struct NEULumenLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: NEULumenActivityAttributes.self) { context in
            HStack(spacing: 12) {
                Image(systemName: context.state.kind == "cardBalance" ? "creditcard.fill" : "book.closed.fill")
                    .font(.title3)
                    .foregroundStyle(.blue)
                VStack(alignment: .leading, spacing: 3) {
                    Text(context.state.title).font(.headline).lineLimit(1)
                    Text(context.state.subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 0)
                if !context.state.value.isEmpty {
                    Text(context.state.value).font(.subheadline.monospacedDigit()).fontWeight(.semibold)
                }
            }
            .padding(16)
            .foregroundStyle(.white)
            .activityBackgroundTint(.black)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: context.state.kind == "cardBalance" ? "creditcard.fill" : "book.closed.fill")
                        .foregroundStyle(.blue)
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(alignment: .leading) {
                        Text(context.state.title).font(.headline).lineLimit(1)
                        Text(context.state.subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if !context.state.value.isEmpty { Text(context.state.value).font(.caption.monospacedDigit()) }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        Text("NEU-Lumen").font(.caption2).foregroundStyle(.secondary)
                        Spacer()
                        Text(context.state.updatedAt, style: .time)
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            } compactLeading: {
                Image(systemName: context.state.kind == "cardBalance" ? "creditcard.fill" : "book.closed.fill")
            } compactTrailing: {
                Text(context.state.value.isEmpty ? String(context.state.title.prefix(2)) : context.state.value)
                    .font(.caption2.monospacedDigit())
            } minimal: {
                Image(systemName: context.state.kind == "cardBalance" ? "creditcard.fill" : "book.closed.fill")
            }
            .widgetURL(URL(string: "neulumen://dynamic-island"))
            .keylineTint(.blue)
        }
    }
}

@main
struct NEULumenLiveActivityBundle: WidgetBundle {
    var body: some Widget { NEULumenLiveActivity() }
}

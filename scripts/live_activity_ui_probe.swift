// Only appended to the actual shared source in a disposable Debug simulator copy.
// Passive post-layout probes do not replace Layout, Text, fonts or the fitting policy.
import SwiftUI

struct LiveActivityUIBounds: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

private struct LiveActivityUIProbePrefix: EnvironmentKey {
    static let defaultValue = "metric"
}

extension EnvironmentValues {
    var liveActivityUIProbePrefix: String {
        get { self[LiveActivityUIProbePrefix.self] }
        set { self[LiveActivityUIProbePrefix.self] = newValue }
    }
}

struct LiveActivityUIProbe: View {
    let id: String
    var body: some View {
        GeometryReader { geometry in
            Color.clear.preference(key: LiveActivityUIBounds.self,
                value: [id: geometry.frame(in: .named("activity-layout-validation"))])
        }
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }
}

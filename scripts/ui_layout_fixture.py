"""Instrument only the disposable production SwiftUI view with passive bounds probes."""
from pathlib import Path
import shutil

# Exact replace hooks fail closed if the real component changes; no substitute view.
HOOKS = (
    ('            }\n            if let subtitle',
     '            }\n            .background(LiveActivityUIProbe(id: "candidate-\\(detailLimit)-\\(footer).title"))\n            if let subtitle'),
    ('LiveActivitySymbolText(text: subtitle, accent: state.accent).font(.caption2).foregroundStyle(.secondary).lineLimit(1)',
     'LiveActivitySymbolText(text: subtitle, accent: state.accent).font(.caption2).foregroundStyle(.secondary).lineLimit(1)\n                    .background(LiveActivityUIProbe(id: "candidate-\\(detailLimit)-\\(footer).subtitle"))'),
    ('                .font(.caption2)\n                .lineLimit(1)\n                .minimumScaleFactor(0.8)',
     '                .font(.caption2)\n                .lineLimit(1)\n                .minimumScaleFactor(0.8)\n                .background(LiveActivityUIProbe(id: "candidate-\\(detailLimit)-\\(footer).footer"))'),
    ('        .frame(maxWidth: .infinity, alignment: .leading)\n    }\n}\n\nstruct LiveActivityMetricRow',
     '        .frame(maxWidth: .infinity, alignment: .leading)\n        .environment(\\.liveActivityUIProbePrefix, "candidate-\\(detailLimit)-\\(footer)")\n        .background(LiveActivityUIProbe(id: "candidate-\\(detailLimit)-\\(footer).body"))\n    }\n}\n\nstruct LiveActivityMetricRow'),
    ('    var compact = false\n',
     '    var compact = false\n    @Environment(\\.liveActivityUIProbePrefix) private var probePrefix\n'),
    ('                .minimumScaleFactor(0.8)\n            Group {',
     '                .minimumScaleFactor(0.8)\n                .background(LiveActivityUIProbe(id: probePrefix + ".label"))\n            Group {'),
    ('            .multilineTextAlignment(.trailing)\n',
     '            .multilineTextAlignment(.trailing)\n            .background(LiveActivityUIProbe(id: probePrefix + ".value"))\n'),
    ('    @Environment(\\.dynamicTypeSize) private var dynamicTypeSize\n',
     '    @Environment(\\.dynamicTypeSize) private var dynamicTypeSize\n    @Environment(\\.liveActivityUIProbePrefix) private var probePrefix\n'),
    ('ForEach(Array(details.enumerated()), id: \\.offset) { _, row in',
     'ForEach(Array(details.enumerated()), id: \\.offset) { index, row in'),
    ('                    .accessibilityLabel(row.label + "，" + row.value)',
     '                    .accessibilityLabel(row.label + "，" + row.value)\n                    .background(LiveActivityUIProbe(id: probePrefix + ".detail-\\(index)"))'),
)


def instrument(source):
    for old, new in HOOKS:
        if source.count(old) != 1:
            raise RuntimeError(f'Actual shared UI probe hook changed: {old}')
        source = source.replace(old, new)
    return source


def inject(root: Path, destination: Path):
    shared = destination / 'NEU-Lumen/Core/Services/LiveActivityExpandedContent.swift'
    original = shared.read_text(encoding='utf-8')
    measured = instrument(original)
    # The neutral probe compiles with this file in both Debug App and Widget.
    # No AppEnvironment/test-only reference is introduced into the Widget target.
    probe = (root / 'scripts/live_activity_ui_probe.swift').read_text(encoding='utf-8')
    shared.write_text(measured + '\n' + probe, encoding='utf-8')
    for source, target in [('live_activity_ui_fixture.swift', 'LiveActivityUIFixture.swift'),
                           ('native_ui_fixture.swift', 'NativeUIFixture.swift'),
                           ('academic_web_sync_fixture.swift', 'AcademicWebSyncFixture.swift')]:
        shutil.copyfile(root / 'scripts' / source, destination / 'NEU-Lumen/App' / target)

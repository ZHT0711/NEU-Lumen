from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]

import check_live_activity_bundle


class LiveActivityBundleTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.app = Path(self.directory.name) / 'Test.app'
        self.extension = self.app / 'PlugIns/NEU-LumenLiveActivity.appex'
        self.extension.mkdir(parents=True)
        self.info = {'CFBundleIdentifier': 'edu.neu.lumen', 'CFBundleVersion': '6',
                     'CFBundleShortVersionString': '1.1.2', 'NSSupportsLiveActivities': True,
                     'CFBundleURLTypes': [{'CFBundleURLSchemes': ['neulumen']}]}
        self.widget = {'CFBundleIdentifier': 'edu.neu.lumen.liveactivity', 'CFBundleVersion': '6',
                       'CFBundleShortVersionString': '1.1.2', 'CFBundleExecutable': 'Widget',
                       'NSExtension': {'NSExtensionPointIdentifier': 'com.apple.widgetkit-extension'}}
        (self.extension / 'Widget').write_bytes(b'fixture')

    def write_plists(self):
        (self.app / 'Info.plist').write_bytes(plistlib.dumps(self.info))
        (self.extension / 'Info.plist').write_bytes(plistlib.dumps(self.widget))

    def test_complete_bundle(self):
        self.write_plists()
        check_live_activity_bundle.check_bundle(self.app)

    def test_missing_executable_and_wrong_entrypoint(self):
        del self.widget['CFBundleExecutable']
        self.write_plists()
        with self.assertRaisesRegex(AssertionError, 'executable'):
            check_live_activity_bundle.check_bundle(self.app)
        self.widget['CFBundleExecutable'] = 'Widget'
        self.widget['NSExtension']['NSExtensionPrincipalClass'] = 'OldWidgetBundle'
        self.write_plists()
        with self.assertRaisesRegex(AssertionError, 'entry point'):
            check_live_activity_bundle.check_bundle(self.app)

    def test_version_mismatch(self):
        self.widget['CFBundleVersion'] = '5'
        self.write_plists()
        with self.assertRaisesRegex(AssertionError, 'mismatch'):
            check_live_activity_bundle.check_bundle(self.app)


class ExpandedActivityContracts(unittest.TestCase):
    def test_camera_regions_never_host_multiline_metrics(self):
        widget = (ROOT / 'NEU-LumenLiveActivity/NEULumenLiveActivity.swift').read_text()
        expanded = widget.split('DynamicIsland {', 1)[1].split('} compactLeading:', 1)[0]
        top, bottom = expanded.split('DynamicIslandExpandedRegion(.bottom)', 1)
        self.assertIn('DynamicIslandExpandedRegion(.leading)', top)
        self.assertIn('DynamicIslandExpandedRegion(.trailing)', top)
        self.assertNotIn('ActivityValue(', top)
        self.assertNotIn('Text(timerInterval:', top)
        self.assertNotIn('VStack', top)
        self.assertIn('.lineLimit(1)', top)
        self.assertIn('LiveActivityExpandedContent(state: context.state, isStale: context.isStale)', bottom)
        self.assertIn('.frame(maxWidth: .infinity, alignment: .leading)', bottom)
        self.assertIn('.widgetURL(context.state.destination)', widget)

    def test_real_layout_is_shared_and_height_bounded(self):
        shared = (ROOT / 'NEU-Lumen/Core/Services/LiveActivityExpandedContent.swift').read_text()
        model = (ROOT / 'NEU-Lumen/Core/Models/LiveActivityPresentation.swift').read_text()
        self.assertIn('struct LiveActivityExpandedContent: View', shared)
        self.assertIn('struct LiveActivityMetricLayout: Layout', shared)
        self.assertIn('sizeThatFits(.unspecified)', shared)
        self.assertIn('LiveActivityLayoutMetrics.metricPlan', shared)
        self.assertIn('ViewThatFits(in: .vertical)', shared)
        for limit in [6, 4, 2, 0]:
            self.assertIn(f'content(detailLimit: {limit}', shared)
        self.assertIn('expandedContentHeight: CGFloat = 130', model)
        self.assertIn('.frame(maxHeight: LiveActivityLayoutMetrics.expandedContentHeight', shared)
        self.assertIn('Text(timerInterval:', shared)
        self.assertIn('.lineLimit(1)', shared)
        self.assertNotIn('.offset(', shared)
        self.assertNotIn('.clipped(', shared)
        self.assertNotIn('GeometryReader', shared)
        self.assertIn('dynamicTypeSize.isAccessibilitySize', shared)

    @unittest.skipUnless(shutil.which('swiftc'), 'swiftc unavailable: native policy/geometry tests require Swift, not a Python mock')
    def test_native_payload_and_real_geometry_policy(self):
        # Compile the SAME checks used by the existing full native test, against
        # the production Foundation schema/geometry helper. No ActivityKit mock.
        tests = (ROOT / 'Tests/LiveActivity/main.swift').read_text()
        source = tests.split('// BEGIN standalone presentation checks', 1)[1].split('// END standalone presentation checks', 1)[0]
        source = source.split('\n', 1)[1]
        with tempfile.TemporaryDirectory() as directory:
            main = Path(directory) / 'main.swift'
            main.write_text('import Foundation\n' + source)
            binary = Path(directory) / 'presentation-tests'
            subprocess.run([shutil.which('swiftc'), '-swift-version', '5', '-warnings-as-errors',
                            str(ROOT / 'NEU-Lumen/Core/Models/LiveActivityPresentation.swift'),
                            str(main), '-o', str(binary)], check=True, capture_output=True, text=True)
            result = subprocess.run([str(binary)], check=True, capture_output=True, text=True)
            self.assertIn('Live activity payload: nine sources', result.stdout)
            self.assertIn('100 real-policy', result.stdout)
            print(result.stdout, end='')


if __name__ == '__main__':
    unittest.main()

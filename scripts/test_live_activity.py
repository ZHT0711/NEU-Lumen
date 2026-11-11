from pathlib import Path
import plistlib
import tempfile
import unittest

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


if __name__ == '__main__':
    unittest.main()

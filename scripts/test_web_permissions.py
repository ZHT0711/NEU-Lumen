"""WebKit requires purpose strings before web content can request device access."""
from pathlib import Path
import plistlib
import unittest


class WebPermissionTests(unittest.TestCase):
    def test_web_device_access_has_purpose_strings(self):
        path = Path(__file__).resolve().parents[1] / "NEU-Lumen/Info.plist"
        info = plistlib.loads(path.read_bytes())
        for key in [
            "NSLocationWhenInUseUsageDescription",
            "NSCameraUsageDescription",
            "NSMicrophoneUsageDescription",
            "NSMotionUsageDescription",
        ]:
            with self.subTest(key=key):
                self.assertIsInstance(info[key], str)
                self.assertTrue(info[key].strip())


if __name__ == "__main__":
    unittest.main()

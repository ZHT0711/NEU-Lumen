"""Execute the production coordinate math against independent control values."""
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class CampusCoordinateTests(unittest.TestCase):
    @unittest.skipUnless(shutil.which('swiftc'), 'Swift compiler unavailable')
    def test_coordinate_controls_and_all_published_entrances(self):
        with tempfile.TemporaryDirectory() as temporary:
            binary = Path(temporary) / 'campus-coordinates'
            subprocess.run(['swiftc', '-swift-version', '5', '-warnings-as-errors',
                            str(ROOT / 'NEU-Lumen/Core/Models/CampusMapCoordinates.swift'),
                            str(ROOT / 'Tests/CampusCoordinates/main.swift'), '-o', str(binary)], check=True)
            subprocess.run([str(binary), str(ROOT)], check=True)


if __name__ == '__main__':
    unittest.main()

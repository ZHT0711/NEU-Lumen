"""Execute the production isolated CAS scripts with synthetic form events."""
from pathlib import Path
import shutil
import subprocess
import unittest


class WebLoginCredentialTests(unittest.TestCase):
    @unittest.skipUnless(shutil.which('node'), 'Node is unavailable')
    def test_production_capture_and_fill_scripts(self):
        root = Path(__file__).resolve().parents[1]
        result = subprocess.run(['node', str(root / 'Tests/OffCampusLogin/credentials.mjs')],
                                capture_output=True, text=True, encoding='utf-8')
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)


if __name__ == '__main__':
    unittest.main()

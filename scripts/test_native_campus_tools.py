"""Run the native models used by new campus services and account-scoped UX."""
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class NativeCampusToolsTests(unittest.TestCase):
    @unittest.skipUnless(shutil.which('swiftc'), 'Swift compiler is unavailable')
    def test_actual_models_and_saved_news(self):
        sources = ['Core/Support/JSONHelpers.swift', 'Core/Support/LoadState.swift',
                   'Core/Models/PortalModels.swift', 'Core/Models/GradeModels.swift',
                   'Core/Models/GradeAnalysis.swift', 'Core/Models/CampusPhoneEntry.swift',
                   'Core/Models/DataReliability.swift', 'Core/Models/NativeCampusService.swift',
                   'Core/Persistence/SavedCampusNews.swift']
        with tempfile.TemporaryDirectory() as directory:
            binary = Path(directory) / 'native-campus-tools'
            command = ['swiftc', '-swift-version', '5', '-parse-as-library',
                       *(str(ROOT / 'NEU-Lumen' / path) for path in sources),
                       str(ROOT / 'Tests/NativeCampusTools/main.swift'), '-o', str(binary)]
            result = subprocess.run(command, capture_output=True, text=True, encoding='utf-8')
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertNotRegex(result.stdout + result.stderr, r'(?im)\bwarning:')
            result = subprocess.run([str(binary)], capture_output=True, text=True, encoding='utf-8')
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)


if __name__ == '__main__':
    unittest.main()

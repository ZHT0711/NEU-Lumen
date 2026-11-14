"""Execute the production refresh method against lifecycle and safe-reload states."""
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class ECodeRefreshTests(unittest.TestCase):
    @unittest.skipUnless(shutil.which('swiftc'), 'Swift compiler is unavailable')
    def test_actual_refresh_does_not_block_the_initial_request(self):
        source = (ROOT / 'NEU-Lumen/Features/Card/NativeECodeView.swift').read_text(encoding='utf-8')
        method = source.split('    private func refresh() {', 1)[1].split('    private func open(', 1)[0]
        harness = '''import Foundation
@MainActor final class ECodeRefreshHarness {
    let browser = RefreshBrowser()
    var needsSchoolRefresh = false
    var document: String? = "previous code"
    var loadedAt: Date? = Date()
    var message: String?
    var clearCount = 0
    func clearCode() { clearCount += 1 }
    func triggerRefresh() { refresh() }
    private func refresh() {''' + method + '\n}\n'
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory)
            (path / 'Refresh.swift').write_text(harness, encoding='utf-8')
            binary = path / 'ecode-refresh-tests'
            result = subprocess.run(['swiftc', '-swift-version', '5', '-parse-as-library', str(path / 'Refresh.swift'),
                                     str(ROOT / 'Tests/ECode/Refresh.swift'), '-o', str(binary)],
                                    capture_output=True, text=True, encoding='utf-8')
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertNotRegex(result.stdout + result.stderr, r'(?im)\bwarning:')
            result = subprocess.run([str(binary)], capture_output=True, text=True, encoding='utf-8')
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)


if __name__ == '__main__':
    unittest.main()

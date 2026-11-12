"""Offline download contracts; on macOS also compiles/runs the real Foundation tests.

CI: python3 scripts/test_browser_downloads.py --require-swift -v
Linux: python3 scripts/test_browser_downloads.py -v (explicit native-test skip)
"""
from pathlib import Path
import argparse
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
MODEL = ROOT / 'NEU-Lumen/Core/Models/BrowserDownloadRecord.swift'
FILES = ROOT / 'NEU-Lumen/Core/Models/BrowserDownloadFiles.swift'
STORE = ROOT / 'NEU-Lumen/Core/Services/BrowserDownloadStore.swift'
PORTAL = ROOT / 'NEU-Lumen/Features/Web/PortalWebView.swift'
VIEW = ROOT / 'NEU-Lumen/Features/Web/BrowserDownloadsView.swift'
SWIFTC = shutil.which('swiftc') if sys.platform == 'darwin' else None


class DownloadContracts(unittest.TestCase):
    def test_metadata_contains_no_request_or_credentials(self):
        source = MODEL.read_text()
        for token in ['URLRequest', 'HTTPCookie', 'var url:', 'let url:', 'var token:', 'var resumeData:']:
            self.assertNotIn(token, source)
        self.assertIn('case downloading, completed, failed, cancelled, interrupted', source)
        self.assertIn('interruptUnfinished()', source)
        self.assertIn('Set(records.map(\\.id))', source)

    def test_private_atomic_disk_layout(self):
        source = FILES.read_text()
        for token in ['SHA256.hash', 'id.uuidString', 'isExcludedFromBackup = true',
                      'completeUntilFirstUserAuthentication', '.atomic', 'rejectSymlink',
                      'record.filename == BrowserDownloadNames.sanitize(record.filename)',
                      'guard !manager.fileExists(atPath: directory.path)']:
            self.assertIn(token, source)
        self.assertIn('Data("%PDF-".utf8)', source)

    def test_webkit_owns_original_download(self):
        store = STORE.read_text()
        portal = PORTAL.read_text()
        self.assertIn('webView.startDownload(using: request)', store)
        self.assertIn('download.delegate = self', store)
        self.assertIn('let webView: WKWebView', store)
        self.assertIn('job.download.progress', store)
        for forbidden in ['URLSession.shared', 'downloadTask(', 'resumeDownload(', 'sharedFile', 'temporaryDirectory']:
            self.assertNotIn(forbidden, store + portal)
        original = portal.split('    func downloadCurrentFile()', 1)[1].split('    private func validDownloadScope()', 1)[0]
        self.assertNotIn('.pdf(configuration:', original)
        self.assertIn('documentUnsafeMethod', original)
        self.assertIn('POST', original)
        self.assertIn('forHTTPHeaderField: "Referer"', original)
        self.assertIn('documentMIMEType = BrowserDownloadNames.mime(response.response.mimeType)', portal)

    def test_account_epoch_and_late_callbacks(self):
        source = STORE.read_text()
        activation = source.split('func activate(account:', 1)[1].split('func accepts(', 1)[0]
        self.assertLess(activation.index('scope = UUID()'), activation.index('for job in oldJobs'))
        self.assertIn('jobs.removeAll()', activation)
        self.assertIn('pending.removeAll()', activation)
        self.assertIn('self.accepts(token)', source)
        self.assertIn('job.scope == scope', source)
        self.assertIn('download.cancel(nil)', source)
        self.assertIn('records = []', activation)
        self.assertIn('manifest.interruptUnfinished()', activation)
        self.assertIn('epoch ?? sessionEpoch', activation)
        self.assertIn('nextEpoch != sessionEpoch', activation)
        self.assertIn('session.requestEpoch == downloadSessionEpoch', PORTAL.read_text())
        self.assertIn('Identity(account: account, epoch: session.requestEpoch)', VIEW.read_text())

    def test_user_controlled_presentation(self):
        portal = PORTAL.read_text()
        view = VIEW.read_text()
        for label in ['下载管理', '下载原始PDF', '导出网页为 PDF']:
            self.assertIn(label, portal)
        for token in ['.quickLookPreview($preview)', 'UIActivityViewController', '.confirmationDialog(',
                      'store.cancel(record.id)', 'store.delete(deleting.id)', '.onChange(of: store.scope)',
                      'BrowserDownloadCoordinator', 'activate(account: value.account, epoch: value.epoch)']:
            self.assertIn(token, view)
        self.assertNotIn('UIApplication.shared.open', STORE.read_text())
        self.assertNotIn('self.error = "下载失败', portal)

    def test_new_files_are_in_synchronized_main_group(self):
        project = (ROOT / 'NEU-Lumen.xcodeproj/project.pbxproj').read_text()
        self.assertIn('isa = PBXFileSystemSynchronizedRootGroup;', project)
        self.assertIn('fileSystemSynchronizedGroups = (', project)
        for path in [MODEL, FILES, STORE, VIEW]:
            self.assertTrue(path.is_file())
            self.assertNotIn(path.name, project.split('membershipExceptions = (', 1)[1].split(');', 1)[0])

    @unittest.skipUnless(SWIFTC, 'requires macOS swiftc/Foundation/CryptoKit; not a Linux native-pass claim')
    def test_native_foundation_behaviour(self):
        with tempfile.TemporaryDirectory(prefix='browser-download-tests-') as directory:
            binary = Path(directory) / 'tests'
            command = [SWIFTC, '-warnings-as-errors', str(MODEL), str(FILES),
                       str(ROOT / 'Tests/BrowserDownloads/main.swift'), '-o', str(binary)]
            built = subprocess.run(command, text=True, capture_output=True)
            self.assertEqual(built.returncode, 0, built.stdout + built.stderr)
            run = subprocess.run([str(binary)], text=True, capture_output=True)
            self.assertEqual(run.returncode, 0, run.stdout + run.stderr)
            self.assertIn('PASS:', run.stdout)
            print(run.stdout.strip())


if __name__ == '__main__':
    parser = argparse.ArgumentParser(add_help=False)
    parser.add_argument('--require-swift', action='store_true')
    options, remaining = parser.parse_known_args()
    if options.require_swift and not SWIFTC:
        raise SystemExit('ERROR: --require-swift needs macOS swiftc; native tests were NOT run')
    unittest.main(argv=[sys.argv[0], *remaining])

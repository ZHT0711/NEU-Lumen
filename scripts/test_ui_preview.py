import json
import os
from pathlib import Path
import struct
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch
import zipfile
import zlib

import package_ui_preview as preview


def png():
    def chunk(kind, data):
        return struct.pack('>I', len(data)) + kind + data + struct.pack('>I', zlib.crc32(kind + data))
    return (b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', 1, 1, 8, 2, 0, 0, 0))
            + chunk(b'IDAT', zlib.compress(b'\x00\x00\x00\x00')) + chunk(b'IEND', b''))


class UIPreviewTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.path = Path(self.temp.name)
        self.env = {'GITHUB_REPOSITORY': 'owner/repo', 'GITHUB_SHA': 'a' * 40,
                    'GITHUB_RUN_ID': '123', 'GITHUB_RUN_NUMBER': '45'}
        for name in preview.SCREENSHOTS:
            (self.path / name).write_bytes(png())
        for name in preview.CHECKS:
            (self.path / name).write_text('PASS: fixture checks\n')
        (self.path / 'simulator-device.json').write_text(json.dumps({'name': 'iPhone', 'runtime': 'iOS-test'}))

    def test_package_provenance_and_allowlist(self):
        (self.path / 'server.log').write_text('not a release asset')
        (self.path / 'old-user-screenshot.jpg').write_bytes(b'old')
        manifest = preview.package(self.path, self.env)
        self.assertEqual(manifest['commit'], self.env['GITHUB_SHA'])
        self.assertEqual(manifest['run_url'], 'https://github.com/owner/repo/actions/runs/123')
        self.assertEqual(manifest['device_type'], 'iPhone simulator')
        self.assertIn('not a real campus account', manifest['data_source'])
        self.assertEqual(len(manifest['screenshots']), len(preview.SCREENSHOTS))
        with zipfile.ZipFile(self.path / preview.ARCHIVE) as archive:
            self.assertEqual(set(archive.namelist()), set((*preview.SCREENSHOTS, preview.MANIFEST)))
        with patch.dict(os.environ, self.env):
            assets = preview.release_assets(self.path)
        self.assertEqual(len(assets), len(preview.SCREENSHOTS) + 2)
        self.assertNotIn(self.path / 'server.log', assets)

    def test_missing_and_invalid_screenshot_block_package(self):
        image = self.path / preview.SCREENSHOTS[0]
        image.unlink()
        with self.assertRaises(FileNotFoundError):
            preview.package(self.path, self.env)
        for invalid in [b'not a PNG', png()[:24], png()[:-1], png()[:-12]]:
            image.write_bytes(invalid)
            with self.assertRaises(ValueError):
                preview.package(self.path, self.env)

    def test_failed_checks_block_package(self):
        for text in ['pending\n', 'FAIL: broken\n', 'PASS: first\nFAIL: second\n']:
            (self.path / preview.CHECKS[0]).write_text(text)
            with self.assertRaises(ValueError):
                preview.package(self.path, self.env)

    def test_cross_run_and_cross_commit_block_release(self):
        preview.package(self.path, self.env)
        for key in ['GITHUB_SHA', 'GITHUB_RUN_ID']:
            wrong = dict(self.env, **{key: 'different'})
            with patch.dict(os.environ, wrong), self.assertRaises(ValueError):
                preview.release_assets(self.path)

    def test_changed_pixels_and_unexpected_files_block_release(self):
        preview.package(self.path, self.env)
        image = self.path / preview.SCREENSHOTS[0]
        image.write_bytes(png() + b'changed')
        with patch.dict(os.environ, self.env), self.assertRaises(ValueError):
            preview.release_assets(self.path)
        image.write_bytes(png())
        manifest = json.loads((self.path / preview.MANIFEST).read_text())
        manifest['screenshots'][0]['file'] = '../outside.png'
        (self.path / preview.MANIFEST).write_text(json.dumps(manifest))
        with patch.dict(os.environ, self.env), self.assertRaises(ValueError):
            preview.release_assets(self.path)

    def test_screenshot_fixtures_are_disposable_and_loaded(self):
        root = Path(__file__).resolve().parents[1]
        destination = self.path / 'generated-project'
        subprocess.run([sys.executable, str(root / 'scripts/prepare_ui_validation.py'), str(destination)], check=True, capture_output=True)
        session = 'NEU-Lumen/Core/Services/SessionStore.swift'
        repository = 'NEU-Lumen/Core/Services/PortalRepository.swift'
        self.assertNotIn('seedScreenshotSession', (root / session).read_text())
        self.assertNotIn('hasPrefix("--screen=")', (root / repository).read_text())
        generated = (destination / repository).read_text()
        self.assertEqual(generated.count('hasPrefix("--screen=")'), 6)
        self.assertIn('loadedForEpoch = session.requestEpoch', generated)
        self.assertIn('for key in weekCache.keys { weekStates[key] = .loaded }', generated)
        self.assertIn('cardBalance = CardBalance(balance: 66.50', generated)
        self.assertIn('billsCache["\\(billsYear)-\\(billsMonth)"] = cardBills', generated)
        self.assertIn('func seedScreenshotSession()', (destination / session).read_text())
        app = (destination / 'NEU-Lumen/App/NEULumenApp.swift').read_text()
        self.assertLess(app.index('environment.session.seedScreenshotSession()'), app.index('environment.repository.seedUIValidation()'))
        self.assertNotIn('browser.sharedFile', app)
        self.assertIn('BrowserDownloadCoordinator()', app)
        self.assertIn('case "downloads":', app)
        self.assertIn('--download-restore-check', app)
        injected = destination / 'NEU-Lumen/App/BrowserDownloadValidation.swift'
        self.assertTrue(injected.is_file())
        self.assertFalse((root / 'NEU-Lumen/App/BrowserDownloadValidation.swift').exists())
        checks = injected.read_text()
        self.assertIn('try bytes(original) == pdf', checks)
        self.assertIn('seedBrowserDownloadScreenshot', checks)
        self.assertIn('verifyBrowserDownloadProcessRestart', checks)

    def test_download_fixture_real_http_routes(self):
        # Real localhost server exercises the integrated GET/POST dispatch, not string matching.
        import http.cookiejar
        from http.server import ThreadingHTTPServer
        import threading
        import urllib.error
        import urllib.request
        import ui_fixture_server
        from browser_download_fixture import PDF

        class QuietHandler(ui_fixture_server.Handler):
            def log_message(self, *args):
                pass

        (self.path / 'plain.txt').write_text('ordinary fixture still works')
        with patch.object(sys, 'argv', ['fixture-server', str(self.path)]):
            server = ThreadingHTTPServer(('127.0.0.1', 0), QuietHandler)
            thread = threading.Thread(target=server.serve_forever, daemon=True)
            thread.start()
            try:
                base = 'http://127.0.0.1:' + str(server.server_port)
                opener = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(http.cookiejar.CookieJar()))
                def fetch(path, referer=False, body=None):
                    headers = {'Referer': base + '/dl/index'} if referer else {}
                    request = urllib.request.Request(base + path, data=body, headers=headers)
                    with opener.open(request, timeout=5) as response:
                        return response.read(), response.headers.get_content_type()
                self.assertEqual(fetch('/plain.txt')[0], b'ordinary fixture still works')
                self.assertIn(b'Login required', fetch('/dl/document')[0])
                fetch('/dl/index')
                self.assertIn(b'Login required', fetch('/dl/document')[0])  # cookie alone is insufficient
                self.assertEqual(fetch('/dl/document', True), (PDF, 'application/pdf'))
                self.assertEqual(fetch('/dl/reference')[0], PDF)
                self.assertEqual(fetch('/dl/post', True, b'document=fixture')[0], PDF)
                self.assertEqual(fetch('/dl/post-attachment', True, b'document=fixture')[0], PDF)
                with self.assertRaises(urllib.error.HTTPError) as denied:
                    fetch('/dl/post', True)
                with denied.exception as response:
                    self.assertEqual(response.code, 405)
                    self.assertEqual(response.read(), b'GET replay forbidden')
                self.assertEqual(fetch('/dl/same?v=1')[0], b'same-1')
                self.assertEqual(fetch('/dl/same?v=2')[0], b'same-2')
                self.assertEqual(fetch('/dl/attachment')[0], b'NEU-Lumen original attachment')
            finally:
                server.shutdown()
                server.server_close()
                thread.join(timeout=5)

    def test_download_checks_and_twentieth_screenshot_are_required(self):
        self.assertEqual(len(preview.SCREENSHOTS), 20)
        self.assertIn('downloads-light.png', preview.SCREENSHOTS)
        for name in ['download-checks.txt', 'download-restore.txt', 'download-screenshot.txt',
                     'learning-save.txt', 'learning-restore.txt']:
            self.assertIn(name, preview.CHECKS)
            path = self.path / name
            path.write_text('FAIL: download regression\n')
            with self.assertRaises(ValueError):
                preview.package(self.path, self.env)
            path.write_text('PASS: synthetic download fixture\n')
        (self.path / 'downloads-light.png').unlink()
        with self.assertRaises(FileNotFoundError):
            preview.package(self.path, self.env)

    def test_readme_and_workflow_contract(self):
        root = Path(__file__).resolve().parents[1]
        readme = (root / 'README.md').read_text()
        self.assertNotIn('docs/screenshots/', readme)
        self.assertNotIn('AquaCore', readme)
        self.assertNotIn('三次', readme)
        self.assertIn('模拟器', readme)
        self.assertIn('/releases/download/nightly/home-light.png', readme)
        workflow = (root / '.github/workflows/build-unsigned.yml').read_text()
        self.assertEqual(workflow.count('cron: "17 19 * * *"'), 1)
        self.assertEqual(workflow.count('--dir release-assets/ui-preview'), 2)
        self.assertIn('run: python3 scripts/publish_nightly.py', workflow)
        self.assertIn('cancel-in-progress: false', workflow)
        prepare = (root / 'scripts/prepare_ui_validation.py').read_text()
        self.assertIn('contains("--screen=grades") ? "成绩" : "作业"', prepare)
        self.assertNotIn('bash scripts/validate_ui.sh\n          fi', workflow)


if __name__ == '__main__':
    unittest.main()

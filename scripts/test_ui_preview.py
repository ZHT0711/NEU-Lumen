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


def layout_marker():
    # Python test-only synthetic measurements; this is NOT evidence of a simulator run.
    cases = [f'CASE: {key} intrinsic=100.0 fitted=100.0 content=94.0 actual-bounds=4'
             for key in sorted(preview.layout_case_keys())]
    return '\n'.join(['PASS: unit-test synthetic layout marker',
                      'COVERAGE: ' + json.dumps(preview.LAYOUT_COVERAGE), *cases,
                      *(f'NEGATIVE-CONTROL: {name}' for name in preview.LAYOUT_NEGATIVE_CONTROLS)])


def academic_marker():
    # Synthetic packaging input only; native WebKit writes its own observed evidence.
    return '\n'.join(['PASS: unit-test synthetic identity marker',
                      *(f'CASE: {name}' for name in preview.ACADEMIC_WEB_CASES),
                      *('IDENTITY: ' + json.dumps(item) for item in preview.ACADEMIC_IDENTITY_EVIDENCE),
                      'NEGATIVE-CONTROL: unsafe-page-world-spoof-accepted'])


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
        (self.path / preview.LAYOUT_CHECK).write_text(layout_marker())
        (self.path / preview.ACADEMIC_WEB_CHECK).write_text(academic_marker())
        (self.path / 'system-island-checks.txt').write_text('\n'.join(
            f'PASS: actual system expanded {kind}; title and metric visible above Settings; simulator synthetic data'
            for kind in ('nextCourse', 'custom', 'electricBalance')))
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
        # Chinese identity labels must survive real HTTP loading without a charset header.
        self.assertIn('<meta charset="utf-8">', (destination / 'fixtures/ecode.html').read_text(encoding='utf-8'))
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
        self.assertEqual(len(preview.SCREENSHOTS), 49)
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
    def test_exact_new_snapshots_and_required_checks(self):
        self.assertEqual(len(preview.SCREENSHOTS), 49)
        self.assertEqual(len(preview.CHECKS), 19)
        self.assertEqual(len(set(preview.SCREENSHOTS)), 49)
        self.assertEqual(len(set(preview.CHECKS)), 19)
        self.assertIn('native-ecode-light.png', preview.SCREENSHOTS)
        self.assertIn('ecode-screenshot.txt', preview.CHECKS)
        for kind in preview.LIVE_KINDS:
            self.assertIn(f'live-expanded-{kind}-light.png', preview.SCREENSHOTS)
        self.assertIn('live-expanded-ax-stale-light.png', preview.SCREENSHOTS)
        for name in (preview.LAYOUT_CHECK, *(f'{s}-screenshot.txt' for s in preview.NATIVE_SCREENS)):
            path = self.path / name
            original = path.read_bytes()
            path.unlink()
            with self.assertRaises(FileNotFoundError):
                preview.package(self.path, self.env)
            path.write_text('FAIL: native/layout regression\n')
            with self.assertRaises(ValueError):
                preview.package(self.path, self.env)
            path.write_bytes(original)
        for name in (*preview.LIVE_SCREENSHOTS, *(f'{s}-light.png' for s in preview.NATIVE_SCREENS)):
            path = self.path / name
            path.unlink()
            with self.assertRaises(FileNotFoundError):
                preview.package(self.path, self.env)
            path.write_bytes(png())

    def test_real_measurement_matrix_not_only_a_pass_flag(self):
        path = self.path / preview.LAYOUT_CHECK
        valid = layout_marker()
        coverage = preview.LAYOUT_COVERAGE
        self.assertEqual((len(coverage['kinds']) * len(coverage['variants']) + 2)
                         * len(coverage['widths_pt']) * len(coverage['dynamic_types']), 174)
        self.assertEqual(2 * len(coverage['widths_pt']) * len(coverage['dynamic_types']), 12)
        self.assertEqual(len(preview.layout_case_keys()), 186)
        bad_coverage = dict(coverage, shared_view_cases=54)
        for invalid in ['PASS: geometry only\n',
                        valid.replace(json.dumps(coverage), json.dumps(bad_coverage)),
                        '\n'.join(valid.splitlines()[:-1]),
                        valid + '\n' + valid.splitlines()[-1],
                        valid.replace('content=94.0', 'content=131.0', 1),
                        valid.replace('actual-bounds=4', 'actual-bounds=0', 1)]:
            path.write_text(invalid)
            with self.assertRaises(ValueError):
                preview.package(self.path, self.env)
        path.write_text(valid)
        manifest = preview.package(self.path, self.env)
        self.assertEqual(manifest['live_activity_layout'], coverage)
        self.assertIn('非系统灵动岛截屏/非真机', manifest['live_activity_preview']['notice'])

    def test_system_island_requires_all_three_actual_expanded_cases(self):
        path = self.path / 'system-island-checks.txt'
        valid = path.read_text()
        for invalid in ['PASS: generic flag only', valid.splitlines()[0], valid + '\n' + valid.splitlines()[0]]:
            path.write_text(invalid)
            with self.assertRaises(ValueError):
                preview.package(self.path, self.env)
        path.write_text(valid)
        preview.package(self.path, self.env)
        path.write_text('IOServiceMatchingfailed for: AppleM2ScalerParavirtDriver\n' + valid)
        preview.package(self.path, self.env)

    def test_check_evidence_hash_cannot_change_after_packaging(self):
        manifest = preview.package(self.path, self.env)
        self.assertEqual(tuple(item['file'] for item in manifest['required_checks']), preview.CHECKS)
        path = self.path / 'academic-center-screenshot.txt'
        path.write_text('PASS: different synthetic run\n')
        with patch.dict(os.environ, self.env), self.assertRaises(ValueError):
            preview.release_assets(self.path)

    def test_probe_hooks_keep_actual_layout_and_fail_closed(self):
        import ui_layout_fixture
        root = Path(__file__).resolve().parents[1]
        source = (root / 'NEU-Lumen/Core/Services/LiveActivityExpandedContent.swift').read_text()
        instrumented = ui_layout_fixture.instrument(source)
        restored = instrumented
        for old, new in reversed(ui_layout_fixture.HOOKS):
            self.assertEqual(restored.count(new), 1)
            restored = restored.replace(new, old)
        self.assertEqual(restored, source)
        self.assertIn('Text(timerInterval: Date()...target, countsDown: true)', instrumented)
        self.assertIn('subviews[0].sizeThatFits(.unspecified)', instrumented)
        self.assertIn('subviews[index].place(', instrumented)
        with self.assertRaises(RuntimeError):
            ui_layout_fixture.instrument(source.replace('var compact = false', 'var compact = true'))
        fixture = (root / 'scripts/live_activity_ui_fixture.swift').read_text()
        for term in ['UIHostingController', 'host.sizeThatFits(in:', 'observation.bounds',
                     'LiveActivityMetricLayout {', 'Text(timerInterval:', 'intersection(',
                     'bodies.count == 1', 'sharedCount == 174', 'metricCount == 12',
                     'negativeCount == 2', 'negative-overlap', 'negative-oversize', 'accessibility3']:
            self.assertIn(term, fixture)
        self.assertNotIn('metricPlan(width:', fixture)
        self.assertNotIn('.clipped()', fixture)

    def test_fixture_copies_native_sources_and_only_explicit_debug_seeds(self):
        root = Path(__file__).resolve().parents[1]
        paths = ['NEU-Lumen/App/NEULumenApp.swift',
                 'NEU-Lumen/Core/Services/LiveActivityExpandedContent.swift',
                 'NEU-Lumen/Core/Services/PortalRepository.swift',
                 'NEU-Lumen/Features/Academic/AcademicWebSyncSheet.swift',
                 'NEU-Lumen/Core/Models/AcademicPageReader.swift',
                 'Tests/Learning/PersistenceValidation.swift']
        original = {path: (root / path).read_bytes() for path in paths}
        destination = self.path / 'native-generated-project'
        subprocess.run([sys.executable, str(root / 'scripts/prepare_ui_validation.py'), str(destination)],
                       check=True, capture_output=True)
        for path in paths:
            self.assertEqual((root / path).read_bytes(), original[path])
        app = (destination / 'NEU-Lumen/App/NEULumenApp.swift').read_text()
        for view in ('AcademicCenterView()', 'AcademicCalendarView()', 'PersonalAcademicProgramDetail(program:',
                     'LiveActivityExpandedPreview(', 'runLiveActivityLayoutChecks()',
                     'runAcademicWebSyncChecks(environment)', 'verifyLearningProcessRestart(save: save'):
            self.assertIn(view, app)
        helper = (destination / 'NEU-Lumen/App/NativeUIFixture.swift').read_text()
        self.assertLess(helper.index('await repo.ensureLoadedForCurrentUser()'), helper.index('repo.seedAcademicPreview('))
        for term in ('#if DEBUG', 'repo.seedAcademicPreview(', 'verifyAcademicUIValidation(environment)',
                     'SYNTH-TERM', 'SYNTH-PLAN', 'SYNTH-C-1'):
            self.assertIn(term, helper)
        self.assertNotIn('evaluateJavaScript("fetch(', helper)
        self.assertEqual((destination / 'NEU-Lumen/App/LearningPersistenceValidation.swift').read_bytes(),
                         original['Tests/Learning/PersistenceValidation.swift'])
        for path in paths[3:5]:
            self.assertEqual((destination / path).read_bytes(), original[path])
        for name in ('NativeUIFixture.swift', 'LiveActivityUIFixture.swift', 'AcademicWebSyncFixture.swift',
                     'LearningPersistenceValidation.swift'):
            self.assertFalse((root / 'NEU-Lumen/App' / name).exists())

    def test_prepare_refuses_production_or_nested_destination(self):
        root = Path(__file__).resolve().parents[1]
        for target in (root, root / 'build/never-fixture'):
            result = subprocess.run([sys.executable, str(root / 'scripts/prepare_ui_validation.py'), str(target)],
                                    capture_output=True, text=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn('outside the production repository', result.stderr)

    def test_simulator_launches_matrix_and_all_native_routes(self):
        root = Path(__file__).resolve().parents[1]
        shell = (root / 'scripts/validate_ui.sh').read_text()
        self.assertIn('--live-activity-layout-checks', shell)
        self.assertIn('wait_ui_marker live-activity-layout-checks.txt', shell)
        self.assertIn('from package_ui_preview import CHECKS', shell)
        for token in (*preview.LIVE_KINDS, 'ax-stale', *preview.NATIVE_SCREENS):
            self.assertIn(token, shell)
        for token in ('--download-checks', '--download-save-check', '--download-restore-check',
                      '--live-activity-data-checks', '--live-activity-checks', '--browser-checks',
                      '--session-${STAGE}-check'):
            self.assertIn(token, shell)
    def test_identity_evidence_and_negative_controls_fail_closed(self):
        path = self.path / preview.ACADEMIC_WEB_CHECK
        valid = academic_marker()
        invalid = [
            'PASS: without real identity evidence\n',
            valid.replace('CASE: wrong-account\n', ''),
            valid + '\nCASE: same-account',
            valid.replace('"requests": 2', '"requests": 0', 1),
            valid.replace('"accepted": true', '"accepted": 1', 1),
            valid.replace('NEGATIVE-CONTROL: unsafe-page-world-spoof-accepted', ''),
        ]
        for text in invalid:
            path.write_text(text)
            with self.assertRaisesRegex(ValueError, 'WebKit identity/account evidence'):
                preview.package(self.path, self.env)
        path.write_text(valid)
        layout = self.path / preview.LAYOUT_CHECK
        for name in preview.LAYOUT_NEGATIVE_CONTROLS:
            layout.write_text(layout_marker().replace('NEGATIVE-CONTROL: ' + name, ''))
            with self.assertRaisesRegex(ValueError, 'negative-control rejection'):
                preview.package(self.path, self.env)
        layout.write_text(layout_marker())
        preview.package(self.path, self.env)

    def test_academic_fixture_actual_local_http_identity_counts(self):
        import http.cookiejar
        from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
        import threading
        import urllib.request
        from academic_fixture_server import handle_academic_fixture

        class Handler(BaseHTTPRequestHandler):
            def do_GET(self):
                if not handle_academic_fixture(self):
                    self.send_error(404)
            def log_message(self, *_):
                pass

        server = ThreadingHTTPServer(('127.0.0.1', 0), Handler)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        base = 'http://127.0.0.1:' + str(server.server_port)
        try:
            for index, mode in enumerate(('same', 'wrong', 'spoof', 'change')):
                opener = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(http.cookiejar.CookieJar()))
                identifier = 'unit-identity-' + str(index)
                with opener.open(base + '/jwapp/sys/synthetic/identity.html?id=' + identifier + '&mode=' + mode + '&account=SYNTH-A', timeout=5) as response:
                    body = response.read()
                    self.assertIn('HttpOnly', response.headers['Set-Cookie'])
                    self.assertIn('合成账号隔离课程'.encode(), body)
                    if mode == 'spoof':
                        self.assertIn(b'window.__academicSpoofFetchCalls', body)
                for count in (1, 2):
                    with opener.open(base + '/jwapp/sys/homeapp/api/home/currentUser.do', timeout=5) as response:
                        value = json.load(response)
                    expected = 'SYNTH-B' if mode in ('wrong', 'spoof') or (mode == 'change' and count == 2) else 'SYNTH-A'
                    self.assertEqual(value, {'code': '0', 'datas': {'userId': expected}})
                    with opener.open(base + '/academic-fixture/evidence?id=' + identifier, timeout=5) as response:
                        self.assertEqual(json.load(response), {'requests': count})
            with urllib.request.urlopen(base + '/jwapp/sys/homeapp/api/home/currentUser.do', timeout=5) as response:
                self.assertEqual(json.load(response), {'code': '401'})
        finally:
            server.shutdown()
            server.server_close()
            thread.join(timeout=5)


if __name__ == '__main__':
    unittest.main()

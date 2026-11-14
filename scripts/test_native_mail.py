"""Execute the shipped mail reader and the actual list-refresh transaction with synthetic transport."""
from pathlib import Path
from io import BytesIO
import shutil
import subprocess
import tempfile
import unittest
from browser_download_fixture import handle_download_fixture

ROOT = Path(__file__).resolve().parents[1]


class NativeMailTransactions(unittest.TestCase):
    def test_synthetic_attachment_requires_webkit_session_and_exact_mail_part(self):
        class Handler:
            def __init__(self, path, headers=None):
                self.path = path
                self.headers = headers or {}
                self.wfile = BytesIO()
                self.status = None
                self.response_headers = {}

            def send_response(self, status):
                self.status = status

            def send_header(self, key, value):
                self.response_headers[key] = value

            def end_headers(self):
                pass

        index = Handler('/dl/mail/coremail/XT/index.jsp')
        self.assertTrue(handle_download_fixture(index, 'GET'))
        self.assertEqual(index.status, 200)
        self.assertIn('mail-fixture=ready', index.response_headers['Set-Cookie'])
        path = '/dl/mail/coremail/s/json?sid=SYNTH-MAIL-TOKEN-ONLY&func=mbox%3AgetMessageData&mid=SYNTH-MAIL-1&part=2&mode=download'
        headers = {'Host': '127.0.0.1:8787', 'Cookie': 'mail-fixture=ready',
                   'Referer': 'http://127.0.0.1:8787/dl/mail/coremail/XT/index.jsp'}
        response = Handler(path, headers)
        self.assertTrue(handle_download_fixture(response, 'GET'))
        self.assertEqual(response.status, 200)
        self.assertEqual(response.wfile.getvalue(), b'NEU-Lumen native mail attachment')
        for missing in ['Cookie', 'Referer']:
            response = Handler(path, {key: value for key, value in headers.items() if key != missing})
            handle_download_fixture(response, 'GET')
            self.assertEqual(response.status, 403)
        response = Handler(path.replace('part=2', 'part=3'), headers)
        handle_download_fixture(response, 'GET')
        self.assertEqual(response.status, 403)
        response = Handler(path, headers)
        handle_download_fixture(response, 'POST')
        self.assertEqual(response.status, 405)

    @unittest.skipUnless(shutil.which('swiftc'), 'Swift compiler is unavailable')
    def test_actual_refresh_retains_loaded_pages_and_search_ownership(self):
        source = (ROOT / 'NEU-Lumen/Core/Services/NativeMailStore.swift').read_text(encoding='utf-8')
        method = '    func refresh(' + source.split('    func refresh(', 1)[1].split('    func selectFolder(', 1)[0]
        fixture = (ROOT / 'Tests/NativeMail/main.swift').read_text(encoding='utf-8')
        with tempfile.TemporaryDirectory(prefix='lumen-mail-') as directory:
            path = Path(directory)
            (path / 'main.swift').write_text(fixture.replace('// ACTUAL_REFRESH_METHOD', method), encoding='utf-8')
            binary = path / 'mail-tests'
            result = subprocess.run(['swiftc', '-swift-version', '5', '-warnings-as-errors', '-parse-as-library',
                                     str(ROOT / 'NEU-Lumen/Core/Models/NativeMail.swift'), str(path / 'main.swift'), '-o', str(binary)],
                                    capture_output=True, text=True, encoding='utf-8')
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            result = subprocess.run([str(binary)], capture_output=True, text=True, encoding='utf-8')
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)


if __name__ == '__main__':
    unittest.main()

import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

import check_build_diagnostics
import publish_manual_nightly


class NightlyPublishTests(unittest.TestCase):
    def test_beijing_date_and_retry_stability(self):
        identity = publish_manual_nightly.release_identity('2026-11-04T19:17:00Z', '61')
        self.assertEqual(identity, ('nightly-20261105-031700-61', '2026-11-05 03:17:00', '20261105-031700'))
        self.assertEqual(identity, publish_manual_nightly.release_identity('2026-11-04T19:17:00Z', '61'))
        self.assertNotEqual(identity, publish_manual_nightly.release_identity('2026-11-04T19:17:00Z', '62'))

    def test_automatic_events_do_not_publish_dated_releases(self):
        for event in ['push', 'schedule', 'pull_request']:
            with patch.dict(os.environ, {'GITHUB_EVENT_NAME': event}), patch('publish_manual_nightly.gh') as gh:
                publish_manual_nightly.main()
                gh.assert_not_called()

    def test_warning_detection(self):
        self.assertEqual(check_build_diagnostics.warnings('Build succeeded\n0 warnings'), [])
        for text in ['file.swift:1: warning: example', 'DeprecationWarning: example', '::warning::example',
                     'clang: WARNING : example', 'ResourceWarning: example', '::warning file=a.swift,line=1::example']:
            self.assertEqual(check_build_diagnostics.warnings(text), [text])

    def test_diagnostics_cli_exit_codes_and_varied_valid_formats(self):
        script = str(Path(check_build_diagnostics.__file__).resolve())
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            first, second = root / 'native.log', root / 'device.log'
            first.write_text('PASS: 14 native assertions\n')
            second.write_text('** BUILD SUCCEEDED **\n0 warnings\n')
            def invoke(*args):
                return subprocess.run([sys.executable, script, *map(str, args)], capture_output=True, text=True)
            self.assertEqual(invoke('--required-count', 2, first, second).returncode, 0)
            for args in [(), (first,), ('--required-count', 0, first), ('--required-count', 2, first),
                         ('--required-count', 1, first, second), ('--required-count', 2, first, first)]:
                self.assertEqual(invoke(*args).returncode, 2)
            for text in ['', '\n \t\n', 'file.swift:1: warning: incorrect', 'DeprecationWarning: bad']:
                first.write_text(text)
                self.assertEqual(invoke('--required-count', 2, first, second).returncode, 1)
            first.unlink()
            self.assertEqual(invoke('--required-count', 2, first, second).returncode, 1)
            first.mkdir()
            self.assertEqual(invoke('--required-count', 2, first, second).returncode, 1)


if __name__ == '__main__':
    unittest.main()

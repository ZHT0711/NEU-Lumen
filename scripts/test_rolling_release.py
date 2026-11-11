import hashlib
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

import publish_nightly as nightly


class RollingReleaseTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.path = Path(self.temp.name)
        self.cwd = Path.cwd()
        os.chdir(self.path)
        self.addCleanup(os.chdir, self.cwd)
        Path('release-assets').mkdir()
        Path('release-assets/NEU-Lumen-iOS-unsigned.ipa').write_bytes(b'new ipa')
        self.preview = Path('new.png')
        self.preview.write_bytes(b'new pixels')
        self.calls = []
        self.env = {'GITHUB_REPOSITORY': 'o/r', 'GITHUB_SHA': 'new', 'GITHUB_RUN_ID': '123'}
        self.old = {'draft': False, 'name': 'old title', 'body': 'old notes', 'prerelease': True,
                    'assets': [{'name': 'NEU-Lumen-iOS-unsigned.ipa'}, {'name': 'unmanaged.ipa'}]}
        self.remote_assets = {p.name: p.read_bytes() for p in [Path('release-assets/NEU-Lumen-iOS-unsigned.ipa'), self.preview]}

    def run_publish(self, fail=False, stale=False):
        def fake(*args):
            self.calls.append(args)
            if args[:2] == ('api', 'repos/o/r/git/ref/heads/main'):
                return 'stale' if stale else 'new'
            if args[:2] == ('api', 'repos/o/r/git/ref/tags/nightly'):
                return 'old'
            if args[:3] == ('release', 'download', 'nightly'):
                directory = Path(args[args.index('--dir') + 1])
                (directory / 'NEU-Lumen-iOS-unsigned.ipa').write_bytes(b'old ipa')
            if args[:3] == ('release', 'upload', 'nightly'):
                if fail and 'release-assets/NEU-Lumen-iOS-unsigned.ipa' in args:
                    raise subprocess.CalledProcessError(1, args, stderr='simulated interruption')
            return ''
        with patch.dict(os.environ, self.env), patch.object(nightly, 'release_assets', return_value=[self.preview]), \
             patch.object(nightly, 'gh', side_effect=fake), patch.object(nightly, 'release', side_effect=[self.old, dict(self.old, assets=self.old['assets'] + [{'name': 'new.png'}])]), \
             patch.object(nightly, 'verify_uploads'):
            nightly.publish()

    def test_verify_then_tag_then_publish(self):
        self.run_publish()
        draft = next(i for i, c in enumerate(self.calls) if '--draft=true' in c)
        upload = next(i for i, c in enumerate(self.calls) if c[:2] == ('release', 'upload'))
        tag = next(i for i, c in enumerate(self.calls) if 'PATCH' in c)
        public = next(i for i, c in enumerate(self.calls) if '--draft=false' in c)
        self.assertLess(draft, upload)
        self.assertLess(upload, tag)
        self.assertLess(tag, public)

    def test_failure_restores_old_assets_tag_and_notes(self):
        with self.assertRaises(subprocess.CalledProcessError):
            self.run_publish(fail=True)
        self.assertTrue(any('sha=old' in c for c in self.calls))
        restored = [c for c in self.calls if '--draft=false' in c]
        self.assertEqual(len(restored), 1)
        self.assertIn('old title', restored[0])
        self.assertTrue(any(c[:2] == ('release', 'delete-asset') and 'new.png' in c for c in self.calls))
        uploads = [c for c in self.calls if c[:2] == ('release', 'upload')]
        self.assertEqual(len(uploads), 2)
        self.assertNotIn('unmanaged.ipa', ' '.join(uploads[-1]))

    def test_stale_build_never_changes_release(self):
        self.run_publish(stale=True)
        self.assertEqual(len(self.calls), 1)

    def test_digest_and_missing_asset_rejected(self):
        p = self.preview
        remote = {'assets': [{'name': p.name, 'size': p.stat().st_size,
                             'digest': 'sha256:' + hashlib.sha256(p.read_bytes()).hexdigest()}]}
        with patch.object(nightly, 'gh', return_value=json.dumps(remote)):
            nightly.verify_uploads('o/r', 'nightly', [p])
        for data in [{'assets': []}, {'assets': [{'name': p.name, 'size': p.stat().st_size, 'digest': 'sha256:bad'}]}]:
            with patch.object(nightly, 'gh', return_value=json.dumps(data)), self.assertRaises(RuntimeError):
                nightly.verify_uploads('o/r', 'nightly', [p])


if __name__ == '__main__':
    unittest.main()

import hashlib
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

import release_transaction as transaction
from release_test_support import FakeGitHub, NEW, OLD
import publish_nightly as nightly


class RollingReleaseTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.path = Path(self.temp.name)
        self.ipa = self.path / 'app.ipa'
        self.ipa.write_bytes(b'new ipa')
        self.preview = self.path / 'new.png'
        self.preview.write_bytes(b'new pixels')
        self.body = self.path / 'notes.md'
        self.body.write_text('new notes')
        self.fake = FakeGitHub()

    def publish(self):
        with patch.object(transaction, 'gh', self.fake):
            transaction.publish_release('o/r', 'nightly', NEW, 'new title', self.body, [self.ipa, self.preview])

    def test_verify_then_tag_then_publish(self):
        self.publish()
        self.assertNotIn('ci-transaction-nightly', self.fake.releases)
        self.assertEqual(self.fake.tags['nightly'], NEW)
        self.assertFalse(self.fake.releases['nightly']['draft'])
        self.assertEqual(self.fake.releases['nightly']['_bytes']['unmanaged.txt'], b'keep me')
        calls = self.fake.calls
        ready = next(i for i, c in enumerate(calls) if c[:3] == ('release', 'edit', 'ci-transaction-nightly'))
        hide = next(i for i, c in enumerate(calls) if c[:3] == ('release', 'edit', 'nightly') and '--draft=true' in c)
        upload = next(i for i, c in enumerate(calls) if c[:3] == ('release', 'upload', 'nightly'))
        tag = next(i for i, c in enumerate(calls) if 'PATCH' in c)
        public = next(i for i, c in enumerate(calls) if c[:3] == ('release', 'edit', 'nightly') and '--draft=false' in c)
        self.assertLess(ready, hide)
        self.assertLess(hide, upload)
        self.assertLess(upload, tag)
        self.assertLess(tag, public)
        self.assertTrue(any(c[0] == 'api' and '/releases/' in ' '.join(c) for c in calls[upload + 1:tag]))

    def test_failure_restores_old_assets_tag_and_notes(self):
        self.fake.partial = True
        self.fake.exception = RuntimeError
        with self.assertRaises(RuntimeError):
            self.publish()
        self.assertEqual(self.fake.tags['nightly'], OLD)
        restored = self.fake.releases['nightly']
        self.assertFalse(restored['draft'])
        self.assertEqual(restored['body'], 'old notes')
        self.assertEqual(restored['_bytes'], {'app.ipa': b'old ipa', 'unmanaged.txt': b'keep me'})
        self.assertNotIn('ci-transaction-nightly', self.fake.releases)

    def test_stale_build_recovers_before_skipping_without_local_assets(self):
        events = []
        with patch.dict(os.environ, {'GITHUB_REPOSITORY': 'o/r', 'GITHUB_SHA': OLD, 'GITHUB_RUN_ID': '123'}), \
             patch.object(nightly, 'recover', side_effect=lambda *a: events.append('recover')), \
             patch.object(nightly, 'gh', side_effect=lambda *a: events.append('main') or NEW), \
             patch.object(nightly, 'validate') as validate:
            nightly.publish()
        self.assertEqual(events, ['recover', 'main'])
        validate.assert_not_called()

    def test_digest_and_missing_asset_rejected(self):
        for omit in (False, True):
            self.fake.omit_digest = omit
            self.ipa.write_bytes(b'old ipa')
            with patch.object(transaction, 'gh', self.fake):
                transaction.verify_uploads('o/r', 'nightly', [self.ipa])
                self.ipa.write_bytes(b'bad ipa')
                with self.assertRaises(RuntimeError):
                    transaction.verify_uploads('o/r', 'nightly', [self.ipa])
                with self.assertRaises(RuntimeError):
                    transaction.verify_uploads('o/r', 'nightly', [self.preview])

    def test_release_commands_require_ci_and_never_invoke_gh_locally(self):
        with patch.dict(os.environ, {'GITHUB_ACTIONS': 'false'}), patch.object(transaction.subprocess, 'run') as run:
            with self.assertRaises(RuntimeError):
                transaction.gh('release', 'delete', 'nightly', '--yes')
            run.assert_not_called()


if __name__ == '__main__':
    unittest.main()

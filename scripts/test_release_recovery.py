"""Fault matrix including a real SIGKILL with a file-backed mocked GitHub server."""
import copy
import json
import os
from pathlib import Path
import shutil
import signal
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

import release_transaction as tx
from release_test_support import FakeGitHub, RunnerLost, NEW, OLD


class ReleaseRecoveryTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.assets = [self.root / 'app.ipa', self.root / 'new.png']
        for p, raw in zip(self.assets, (b'new ipa', b'new pixels')):
            p.write_bytes(raw)
        self.body = self.root / 'notes.md'
        self.body.write_text('new notes')

    def publish(self, fake, tag='nightly'):
        with patch.object(tx, 'gh', fake):
            tx.publish_release('o/r', tag, NEW, 'new title', self.body, self.assets)

    def recover(self, fake, tag='nightly'):
        with patch.object(tx, 'gh', fake):
            tx.recover('o/r', tag)

    def coherent(self, fake, existing=True, tag='nightly'):
        self.assertNotIn(tx.transaction_tag(tag), fake.releases)
        item = fake.releases.get(tag)
        if item is None:
            self.assertFalse(existing)
            self.assertNotIn(tag, fake.tags)
            return
        self.assertFalse(item['draft'])
        self.assertEqual(item['_bytes'].get('unmanaged.txt'), b'keep me' if existing else None)
        if fake.tags[tag] == OLD:
            self.assertEqual(item['body'], 'old notes')
            self.assertEqual(item['_bytes'], {'app.ipa': b'old ipa', 'unmanaged.txt': b'keep me'})
        else:
            self.assertEqual(fake.tags[tag], NEW)
            self.assertEqual(item['body'], 'new notes')
            for p in self.assets:
                self.assertEqual(item['_bytes'][p.name], p.read_bytes())

    def test_every_publish_api_boundary_before_and_after_runner_loss(self):
        cases = 0
        for existing in (True, False):
            baseline = FakeGitHub(existing)
            self.publish(baseline)
            count = len(baseline.calls)
            for after in (False, True):
                for cut in range(1, count + 1):
                    with self.subTest(existing=existing, after=after, cut=cut):
                        fake = FakeGitHub(existing)
                        fake.cut, fake.after = cut, after
                        try:
                            self.publish(fake)
                        except RunnerLost:
                            pass
                        fake.cut = None
                        self.recover(fake)
                        self.recover(fake)
                        self.coherent(fake, existing)
                        cases += 1
        print(f'Fault matrix: {cases} publish API cut points')

    def test_every_publish_api_boundary_ordinary_exception_rolls_back(self):
        for existing in (True, False):
            baseline = FakeGitHub(existing)
            self.publish(baseline)
            for after in (False, True):
                for cut in range(1, len(baseline.calls) + 1):
                    with self.subTest(existing=existing, after=after, cut=cut):
                        fake = FakeGitHub(existing)
                        fake.cut, fake.after, fake.exception = cut, after, RuntimeError
                        try:
                            self.publish(fake)
                        except RuntimeError:
                            pass
                        fake.cut = None
                        self.recover(fake)
                        self.coherent(fake, existing)

    def test_failed_ordinary_rollback_retains_backup_for_next_runner(self):
        fake = FakeGitHub()
        fake.partial, fake.exception = True, RuntimeError
        def fail_restore(server, args):
            if args[:3] == ('release', 'upload', 'nightly'):
                raise RuntimeError('restore transport failed')
        fake.on_call = fail_restore
        with self.assertRaisesRegex(RuntimeError, 'durable backup retained'):
            self.publish(fake)
        self.assertIn('ci-transaction-nightly', fake.releases)
        self.assertTrue(fake.releases['nightly']['draft'])
        fake.on_call = None
        self.recover(fake)
        self.coherent(fake)

    def interrupted(self, existing=True, tag='nightly'):
        fake = FakeGitHub(existing, tag)
        fake.partial = True
        with self.assertRaises(RunnerLost):
            self.publish(fake, tag)
        return fake

    def test_every_rollback_boundary_can_itself_be_interrupted(self):
        for existing in (True, False):
            initial = self.interrupted(existing)
            baseline = copy.deepcopy(initial)
            baseline.calls.clear()
            self.recover(baseline)
            for after in (False, True):
                for cut in range(1, len(baseline.calls) + 1):
                    with self.subTest(existing=existing, after=after, cut=cut):
                        fake = copy.deepcopy(initial)
                        fake.calls.clear()
                        fake.cut, fake.after = cut, after
                        try:
                            self.recover(fake)
                        except RunnerLost:
                            pass
                        fake.cut = None
                        self.recover(fake)
                        self.coherent(fake, existing)

    def test_partial_upload_and_corrupt_persistent_backup_fail_closed(self):
        fake = self.interrupted()
        self.assertTrue(fake.releases['nightly']['draft'])
        self.assertEqual(fake.releases['nightly']['_bytes']['app.ipa'], b'new ipa')
        journal = fake.releases['ci-transaction-nightly']
        journal['_bytes']['app.ipa'] = b'corrupt'
        with self.assertRaises(RuntimeError):
            self.recover(fake)
        self.assertIn('ci-transaction-nightly', fake.releases)
        self.assertTrue(fake.releases['nightly']['draft'])
        journal['_bytes']['app.ipa'] = b'old ipa'
        self.recover(fake)
        self.coherent(fake)

    def test_dated_release_idempotent_and_recoverable(self):
        tag = 'nightly-20261112-031700-61'
        fake = FakeGitHub(False)
        self.publish(fake, tag)
        identity = fake.releases[tag]['id']
        self.publish(fake, tag)
        self.assertEqual(fake.releases[tag]['id'], identity)
        self.assertEqual(list(fake.releases), [tag])
        fake.partial = True
        with self.assertRaises(RunnerLost):
            self.publish(fake, tag)
        self.recover(fake, tag)
        self.coherent(fake, False, tag)

    def test_malformed_journal_and_unjournaled_draft_are_not_deleted(self):
        fake = self.interrupted()
        fake.releases['ci-transaction-nightly']['body'] = '{}'
        before = copy.deepcopy(fake.releases)
        with self.assertRaises(RuntimeError):
            self.recover(fake)
        self.assertEqual(fake.releases, before)
        fake = FakeGitHub()
        fake.releases['nightly']['draft'] = True
        with self.assertRaisesRegex(RuntimeError, 'Unjournaled'):
            self.publish(fake)
        self.assertTrue(fake.releases['nightly']['draft'])

    @unittest.skipUnless(hasattr(signal, 'SIGKILL'), 'requires POSIX')
    def test_real_sigkill_then_fresh_process_recovers_without_runner_temp(self):
        state = self.root / 'fake-remote.json'
        FakeGitHub().save(state)
        script = str(Path(__file__).resolve())
        runner_temp = self.root / 'lost-runner-temp'
        runner_temp.mkdir()
        result = subprocess.run([sys.executable, script, '--worker', 'kill', str(state), str(self.root)],
                                capture_output=True, text=True, env=dict(os.environ, TMPDIR=str(runner_temp)))
        self.assertEqual(result.returncode, -signal.SIGKILL, result.stderr)
        self.assertTrue(FakeGitHub.load(state).releases['nightly']['draft'])
        # Drop ALL original job artifacts and local backups, including leaked SIGKILL temp files.
        shutil.rmtree(runner_temp)
        for p in [*self.assets, self.body]:
            p.unlink()
        result = subprocess.run([sys.executable, script, '--worker', 'recover', str(state), str(self.root)], capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        fake = FakeGitHub.load(state)
        self.assertEqual(fake.tags['nightly'], OLD)
        self.assertFalse(fake.releases['nightly']['draft'])
        self.assertEqual(fake.releases['nightly']['_bytes']['app.ipa'], b'old ipa')
        self.assertNotIn('ci-transaction-nightly', fake.releases)


def worker(mode, state, directory):
    root = Path(directory)
    fake = FakeGitHub.load(state)
    def persist_then_kill(server, args):
        server.save(state)
        if mode == 'kill' and args[:3] == ('release', 'upload', 'nightly'):
            os.kill(os.getpid(), signal.SIGKILL)
    fake.on_call = persist_then_kill
    with patch.object(tx, 'gh', fake):
        if mode == 'kill':
            tx.publish_release('o/r', 'nightly', NEW, 'new title', root / 'notes.md', [root / 'app.ipa', root / 'new.png'])
        else:
            tx.recover('o/r', 'nightly')
    fake.save(state)


if __name__ == '__main__':
    if len(sys.argv) > 1 and sys.argv[1] == '--worker':
        worker(*sys.argv[2:])
    else:
        unittest.main()

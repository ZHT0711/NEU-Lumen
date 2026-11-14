import json
import os
from pathlib import Path
import re
import shlex
import subprocess
import tempfile
import unittest
from unittest.mock import patch

import build_provenance as provenance


class BuildProvenanceTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        (self.root / 'ui-preview').mkdir()
        for path, content in [(self.root / provenance.IPA, b'ipa'),
                              (self.root / 'ui-preview' / provenance.ARCHIVE, b'zip'),
                              (self.root / 'ui-preview' / provenance.MANIFEST, b'{}'),
                              (self.root / 'toolchain-provenance.txt', b'Xcode tested runner')]:
            path.write_bytes(content)
        self.env = {'GITHUB_REPOSITORY': 'o/r', 'GITHUB_SHA': 'b' * 40, 'GITHUB_RUN_ID': '123',
                    'GITHUB_RUN_NUMBER': '61', 'GITHUB_RUN_ATTEMPT': '1', 'BUILD_ATTEMPT': '1',
                    'IPA_ARTIFACT_ID': '789', 'IPA_ARTIFACT_NAME': 'NEU-Lumen-iOS-unsigned-61-attempt-1'}

    def test_build_rerun_names_are_distinct_and_release_only_retry_uses_original(self):
        self.assertNotEqual(provenance.artifact_name('ipa', '61', '1'), provenance.artifact_name('ipa', '61', '2'))
        with patch.dict(os.environ, self.env):
            provenance.record(self.root)
        with patch.dict(os.environ, dict(self.env, GITHUB_RUN_ATTEMPT='7')):
            self.assertEqual(provenance.validate(self.root), self.root / provenance.NAME)
        with patch.dict(os.environ, dict(self.env, BUILD_ATTEMPT='2')):
            with self.assertRaises(ValueError):
                provenance.validate(self.root)

    def test_cross_attempt_pairing_and_tampered_bytes_fail(self):
        for field in ('commit', 'run_id', 'build_attempt'):
            with self.subTest(field=field), patch.dict(os.environ, self.env):
                data = provenance.record(self.root)
                data[field] = 'different'
                (self.root / provenance.NAME).write_text(json.dumps(data))
                with self.assertRaises(ValueError):
                    provenance.validate(self.root)
        with patch.dict(os.environ, self.env):
            provenance.record(self.root)
            (self.root / 'ui-preview' / provenance.NAME).write_text('{}')
            with self.assertRaises(ValueError):
                provenance.validate(self.root)
            provenance.record(self.root)
            (self.root / provenance.IPA).write_bytes(b'tampered')
            with self.assertRaises(ValueError):
                provenance.validate(self.root)

    def test_download_checks_successful_artifact_id_run_and_name(self):
        meta = {'id': 789, 'name': self.env['IPA_ARTIFACT_NAME'], 'expired': False,
                'workflow_run': {'id': 123, 'head_sha': self.env['GITHUB_SHA']}}
        with patch.dict(os.environ, dict(self.env, GITHUB_RUN_ATTEMPT='8')), \
             patch.object(provenance.subprocess, 'run', return_value=subprocess.CompletedProcess([], 0, json.dumps(meta))) as run:
            provenance.download('ipa', self.root)
            self.assertIn('/actions/artifacts/789', run.call_args_list[0].args[0][-1])
            self.assertIn(self.env['IPA_ARTIFACT_NAME'], run.call_args_list[1].args[0])
            self.assertNotIn('attempt-8', ' '.join(run.call_args_list[1].args[0]))
        for bad in [dict(meta, id=1), dict(meta, expired=True), dict(meta, name='wrong'),
                    dict(meta, workflow_run={'id': 124, 'head_sha': self.env['GITHUB_SHA']}),
                    dict(meta, workflow_run={'id': 123, 'head_sha': 'a' * 40})]:
            with patch.dict(os.environ, self.env), \
                 patch.object(provenance.subprocess, 'run', return_value=subprocess.CompletedProcess([], 0, json.dumps(bad))) as run:
                with self.assertRaises(ValueError):
                    provenance.download('ipa')
                self.assertEqual(run.call_count, 1)

    def test_native_entries_and_explicit_log_count_gate_publication(self):
        text = (Path(__file__).resolve().parents[1] / '.github/workflows/build-unsigned.yml').read_text()
        blocks = re.split(r'(?m)^      - name: ', text)[1:]
        gate = next(block for block in blocks if block.startswith('Require warning-free compiler logs'))
        command = ' '.join(line.strip() for line in gate.splitlines() if line.startswith('          '))
        args = shlex.split(command)
        self.assertEqual(args[:3], ['python3', 'scripts/check_build_diagnostics.py', '--required-count'])
        required, logs = int(args[3]), args[4:]
        self.assertEqual(required, len(logs))
        self.assertEqual(required, len(set(logs)))
        self.assertTrue({'${RUNNER_TEMP}/browser-download-tests.log', '${RUNNER_TEMP}/data-reliability-tests.log'} <= set(logs))
        commands = {'browser-download-tests.log': 'python3 scripts/test_browser_downloads.py --require-swift -v',
                    'data-reliability-tests.log': 'Tests/DataReliability/main.swift'}
        for log, entry in commands.items():
            step = next(block for block in blocks if entry in block)
            self.assertIn(log, step)
            self.assertIn('set -euo pipefail', step)
            self.assertLess(text.index(entry), text.index('Require warning-free compiler logs'))
        wildcard_steps = [block for block in blocks if 'NEU-Lumen/Core/Models/*.swift' in block]
        self.assertTrue(wildcard_steps)
        for block in wildcard_steps:
            self.assertIn('swiftc', block)
            self.assertIn('NEU-Lumen/Core/Support/LoadState.swift', block)
        policy_step = next(block for block in blocks if 'Tests/DataReliability/main.swift' in block)
        for source in ('NEU-Lumen/Core/Support/LoadState.swift', 'NEU-Lumen/Core/Models/DataReliability.swift'):
            self.assertIn(source, policy_step)
        self.assertIn('"${RUNNER_TEMP}/data-reliability-tests"', policy_step)

    def test_workflow_contract_pins_gates_and_recovery_order(self):
        text = (Path(__file__).resolve().parents[1] / '.github/workflows/build-unsigned.yml').read_text()
        actions = re.findall(r'uses:\s+([^\s#]+)', text)
        self.assertTrue(actions)
        self.assertTrue(all(re.fullmatch(r'[^@]+@[0-9a-f]{40}', action) for action in actions))
        self.assertEqual(text.count('cron: "17 19 * * *"'), 1)
        self.assertEqual(text.count('BUILD_ATTEMPT: ${{ needs.build.outputs.attempt }}'), 3)
        self.assertNotIn('--name "NEU-Lumen-iOS-unsigned-${GITHUB_RUN_NUMBER}"', text)
        self.assertNotIn('overwrite: true', text)
        self.assertLess(text.index('Require warning-free'), text.index('Upload unsigned IPA'))
        self.assertLess(text.index('publish_nightly.py --recover-only'), text.index('Check current main commit'))
        self.assertIn('--required-count', text)
        self.assertIn('runs-on: macos-26', text)
        self.assertNotIn('id-token: write', text)
        nightly = text.split('  nightly:', 1)[1]
        self.assertIn("startsWith(github.ref, 'refs/tags/v')", nightly)
        self.assertIn('CURRENT_SHA', nightly)



if __name__ == '__main__':
    unittest.main()

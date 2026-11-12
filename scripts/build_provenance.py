"""Bind downloads and published bytes to the successful BUILD attempt, not release retries."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess

NAME = 'build-provenance.json'
IPA = 'NEU-Lumen-iOS-unsigned.ipa'
ARCHIVE = 'NEU-Lumen-ui-preview.zip'
MANIFEST = 'ui-preview.json'


def digest(path):
    if not path.is_file() or not path.stat().st_size:
        raise ValueError(f'Missing or empty build output: {path}')
    return hashlib.sha256(path.read_bytes()).hexdigest()


def artifact_name(kind, run_number, attempt):
    if kind not in ('ipa', 'ui') or not str(run_number).isdigit() or not str(attempt).isdigit():
        raise ValueError('Invalid artifact identity')
    prefix = 'NEU-Lumen-iOS-unsigned' if kind == 'ipa' else 'NEU-Lumen-ui-preview'
    return f'{prefix}-{run_number}-attempt-{attempt}'


def record(root=Path('build')):
    root = Path(root)
    env = os.environ
    attempt = env['GITHUB_RUN_ATTEMPT']  # ONLY record() reads the current attempt.
    data = {'schema_version': 1, 'repository': env['GITHUB_REPOSITORY'],
            'commit': env['GITHUB_SHA'], 'run_id': env['GITHUB_RUN_ID'],
            'run_number': env['GITHUB_RUN_NUMBER'], 'build_attempt': attempt,
            'artifact_names': {k: artifact_name(k, env['GITHUB_RUN_NUMBER'], attempt) for k in ('ipa', 'ui')},
            'ipa_sha256': digest(root / IPA),
            'ui_archive_sha256': digest(root / 'ui-preview' / ARCHIVE),
            'ui_manifest_sha256': digest(root / 'ui-preview' / MANIFEST),
            'toolchain': (root / 'toolchain-provenance.txt').read_text(encoding='utf-8')}
    if not data['toolchain'].strip():
        raise ValueError('Missing toolchain provenance')
    text = json.dumps(data, ensure_ascii=False, indent=2) + '\n'
    (root / NAME).write_text(text, encoding='utf-8')
    (root / 'ui-preview' / NAME).write_text(text, encoding='utf-8')
    return data


def validate(root=Path('release-assets'), require_ui=True):
    root = Path(root)
    data = json.loads((root / NAME).read_text(encoding='utf-8'))
    expected = {'schema_version': 1, 'repository': os.environ['GITHUB_REPOSITORY'],
                'commit': os.environ['GITHUB_SHA'], 'run_id': os.environ['GITHUB_RUN_ID'],
                'run_number': os.environ['GITHUB_RUN_NUMBER'], 'build_attempt': os.environ['BUILD_ATTEMPT']}
    if any(data.get(key) != value for key, value in expected.items()):
        raise ValueError('Artifact provenance does not match the successful build')
    for kind in ('ipa', 'ui'):
        name = artifact_name(kind, expected['run_number'], expected['build_attempt'])
        if data['artifact_names'].get(kind) != name:
            raise ValueError('Artifact name does not match the build attempt')
    if digest(root / IPA) != data['ipa_sha256']:
        raise ValueError('IPA checksum mismatch')
    if require_ui:
        if (root / 'ui-preview' / NAME).read_bytes() != (root / NAME).read_bytes():
            raise ValueError('IPA and UI artifacts come from different build attempts')
        for filename, key in ((ARCHIVE, 'ui_archive_sha256'), (MANIFEST, 'ui_manifest_sha256')):
            if digest(root / 'ui-preview' / filename) != data[key]:
                raise ValueError(f'UI provenance checksum mismatch: {filename}')
    return root / NAME


def download(kind, destination=None):
    """Check immutable upload ID, then download its unique name; no newest/name fallback."""
    env = os.environ
    identity = env[kind.upper() + '_ARTIFACT_ID']
    name = env[kind.upper() + '_ARTIFACT_NAME']
    if not identity.isdigit() or name != artifact_name(kind, env['GITHUB_RUN_NUMBER'], env['BUILD_ATTEMPT']):
        raise ValueError('Missing or mismatched successful-build artifact outputs')
    result = subprocess.run(['gh', 'api', f'repos/{env["GITHUB_REPOSITORY"]}/actions/artifacts/{identity}'],
                            check=True, capture_output=True, text=True)
    remote = json.loads(result.stdout)
    run = remote.get('workflow_run', {})
    if (str(remote.get('id')) != identity or remote.get('name') != name or remote.get('expired') is not False
            or str(run.get('id')) != env['GITHUB_RUN_ID'] or run.get('head_sha') != env['GITHUB_SHA']):
        raise ValueError('GitHub artifact identity/run/commit mismatch or expired artifact')
    destination = Path(destination or ('release-assets/ui-preview' if kind == 'ui' else 'release-assets'))
    subprocess.run(['gh', 'run', 'download', env['GITHUB_RUN_ID'], '--name', name, '--dir', str(destination)], check=True)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('operation', choices=('record', 'validate', 'download'))
    parser.add_argument('kind', nargs='?', choices=('ipa', 'ui'))
    parser.add_argument('--ipa-only', action='store_true')
    parser.add_argument('--dir', dest='destination')
    args = parser.parse_args(argv)
    if args.operation == 'record':
        record()
    elif args.operation == 'validate':
        validate(require_ui=not args.ipa_only)
    elif args.kind:
        download(args.kind, args.destination)
    else:
        parser.error('download requires ipa or ui')


if __name__ == '__main__':
    main()

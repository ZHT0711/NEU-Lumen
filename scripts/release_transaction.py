"""Durable, hidden Release transactions. Call only under the workflow publish lock.

A private draft stores a write-ahead record and verified copies of EVERY old asset.
'preparing' never permits target mutations; 'ready' is always rolled back on recovery;
'committed' only needs verified cleanup. No signal handler is needed for recovery.
"""
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile


def gh(*args):
    if os.environ.get('GITHUB_ACTIONS') != 'true':
        raise RuntimeError('Release commands require GitHub Actions and the publish concurrency lock; mock gh locally')
    return subprocess.run(['gh', *args], check=True, capture_output=True, text=True).stdout.strip()


def missing(error):
    text = (error.stderr or '').lower()
    return 'http 404' in text or 'release not found' in text


def release_data(repo, tag):
    identity = gh('release', 'view', tag, '--json', 'databaseId', '--jq', '.databaseId')
    return json.loads(gh('api', f'repos/{repo}/releases/{identity}'))


def optional_release(repo, tag):
    try:
        return release_data(repo, tag)
    except subprocess.CalledProcessError as error:
        if missing(error):
            return None
        raise


def tag_sha(repo, tag):
    try:
        return gh('api', f'repos/{repo}/git/ref/tags/{tag}', '--jq', '.object.sha')
    except subprocess.CalledProcessError as error:
        if missing(error):
            return None
        raise


def set_tag(repo, tag, sha):
    current = tag_sha(repo, tag)
    if current == sha:
        return
    if sha is None:
        gh('api', '--method', 'DELETE', f'repos/{repo}/git/refs/tags/{tag}')
    elif current is None:
        gh('api', '--method', 'POST', f'repos/{repo}/git/refs', '-f', f'ref=refs/tags/{tag}', '-f', f'sha={sha}')
    else:
        gh('api', '--method', 'PATCH', f'repos/{repo}/git/refs/tags/{tag}', '-f', f'sha={sha}', '-F', 'force=true')


def asset_name(name):
    if not isinstance(name, str) or not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9._-]*', name):
        raise RuntimeError(f'Unsafe release asset name: {name!r}')
    return name


def specification(path):
    return {'name': asset_name(path.name), 'size': path.stat().st_size,
            'sha256': hashlib.sha256(path.read_bytes()).hexdigest()}


def verify_specs(repo, tag, specs, exact=False):
    remote = release_data(repo, tag)
    by_name = {asset['name']: asset for asset in remote['assets']}
    if len(by_name) != len(remote['assets']) or (exact and set(by_name) != {s['name'] for s in specs}):
        raise RuntimeError('Unexpected release asset set')
    for spec in specs:
        name = asset_name(spec['name'])
        asset = by_name.get(name)
        if asset is None or asset['size'] != spec['size']:
            raise RuntimeError(f'Release asset missing or truncated: {name}')
        if asset.get('digest'):
            if asset['digest'] != 'sha256:' + spec['sha256']:
                raise RuntimeError(f'Release checksum mismatch: {name}')
        else:
            with tempfile.TemporaryDirectory() as directory:
                gh('release', 'download', tag, '--pattern', name, '--dir', directory)
                if specification(Path(directory) / name) != spec:
                    raise RuntimeError(f'Release download mismatch: {name}')
    return remote


def verify_uploads(repo, tag, assets):
    return verify_specs(repo, tag, [specification(path) for path in assets])


def transaction_tag(tag):
    if not re.fullmatch(r'nightly(?:-[0-9]+-[0-9]+-[0-9]+)?', tag):
        raise RuntimeError('Only rolling or dated nightly transactions are supported')
    return 'ci-transaction-' + tag


def write_record(path, record):
    path.write_text(json.dumps(record, ensure_ascii=False, sort_keys=True) + '\n', encoding='utf-8')
    return str(path)


def update_record(tag, path, record, phase):
    record['phase'] = phase
    gh('release', 'edit', transaction_tag(tag), '--notes-file', write_record(path, record))


def download_specs(tag, specs, directory):
    paths = []
    for spec in specs:
        name = asset_name(spec['name'])
        gh('release', 'download', tag, '--pattern', name, '--dir', str(directory))
        path = directory / name
        if specification(path) != spec:
            raise RuntimeError(f'Transaction backup checksum mismatch: {name}')
        paths.append(path)
    return paths


def read_record(repo, tag, journal):
    if not journal['draft']:
        raise RuntimeError('Transaction backup must remain a draft')
    record = json.loads(journal['body'])
    if (record.get('schema') != 1 or record.get('repo') != repo or record.get('tag') != tag
            or record.get('phase') not in ('preparing', 'ready', 'committed')
            or not re.fullmatch(r'[0-9a-f]{40}', record.get('sha', ''))):
        raise RuntimeError('Invalid transaction identity; refusing destructive recovery')
    for field in ('old_assets', 'new_assets'):
        specs = record[field]
        if len({s['name'] for s in specs}) != len(specs):
            raise RuntimeError('Duplicate transaction asset')
        for spec in specs:
            asset_name(spec['name'])
            if (not isinstance(spec['size'], int) or spec['size'] < 0
                    or not re.fullmatch(r'[0-9a-f]{64}', spec['sha256'])):
                raise RuntimeError('Invalid transaction asset specification')
    if record['old'] is not None and (record['old']['draft'] or not record['old'].get('id')):
        raise RuntimeError('Invalid previous release identity')
    if record['old_tag'] is not None and not re.fullmatch(r'[0-9a-f]{40}', record['old_tag']):
        raise RuntimeError('Invalid previous tag')
    return record


def recover(repo, tag='nightly'):
    """Idempotently roll back uncommitted work, or clean a verified commit.

    Keep the record on *any* recovery failure. A later runner retries the same work.
    The caller MUST hold the same lock used by publish_release.
    """
    journal_tag = transaction_tag(tag)
    journal = optional_release(repo, journal_tag)
    if journal is None:
        return False
    record = read_record(repo, tag, journal)
    phase = record['phase']
    if phase == 'committed':
        current = verify_specs(repo, tag, record['new_assets'])
        if current['draft'] or tag_sha(repo, tag) != record['sha']:
            raise RuntimeError('Committed release has changed; retaining recovery backup')
    elif phase == 'ready':
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            paths = download_specs(journal_tag, record['old_assets'], root)
            # Validate ALL backups before hiding/changing the target again.
            verify_specs(repo, journal_tag, record['old_assets'], exact=True)
            current = optional_release(repo, tag)
            current_tag = tag_sha(repo, tag)
            if current_tag not in (None, record['old_tag'], record['sha']):
                raise RuntimeError('Release tag changed outside transaction; retaining recovery backup')
            old = record['old']
            if old:
                if current is None or current['id'] != old['id']:
                    raise RuntimeError('Release identity changed; retaining recovery backup')
                gh('release', 'edit', tag, '--draft=true')
                previous = {s['name'] for s in record['old_assets']}
                for asset in current['assets']:
                    if asset['name'] not in previous:
                        gh('release', 'delete-asset', tag, asset_name(asset['name']), '--yes')
                if paths:
                    gh('release', 'upload', tag, *(str(p) for p in paths), '--clobber')
                verify_specs(repo, tag, record['old_assets'], exact=True)
                set_tag(repo, tag, record['old_tag'])
                notes = root / 'restore-notes.md'
                notes.write_text(old.get('body') or '', encoding='utf-8')
                gh('release', 'edit', tag, '--title', old.get('name') or tag,
                   '--notes-file', str(notes), f'--prerelease={str(old["prerelease"]).lower()}',
                   '--latest=false', '--draft=false')
            else:
                if current:
                    if current['target_commitish'] != record['sha']:
                        raise RuntimeError('First-release identity changed; retaining recovery backup')
                    gh('release', 'edit', tag, '--draft=true')
                    gh('release', 'delete', tag, '--yes')
                current_tag = tag_sha(repo, tag)
                if current_tag not in (None, record['old_tag'], record['sha']):
                    raise RuntimeError('First-release tag changed; retaining recovery backup')
                set_tag(repo, tag, record['old_tag'])
    # 'preparing' explicitly promises that the target was never touched.
    gh('release', 'delete', journal_tag, '--yes')  # Never --cleanup-tag: drafts have no new tag.
    print(f'Recovered {tag}: {phase}')
    return True


def publish_release(repo, tag, sha, title, body, assets):
    """Publish while locked. Durable recovery is installed BEFORE any overwrite."""
    journal_tag = transaction_tag(tag)
    if not re.fullmatch(r'[0-9a-f]{40}', sha):
        raise RuntimeError('Publishing requires a full commit SHA')
    recover(repo, tag)
    old = optional_release(repo, tag)
    if old and old['draft']:
        raise RuntimeError('Unjournaled draft: cannot reconstruct old assets; explicit operator repair required')
    old_tag = tag_sha(repo, tag)
    if old and old_tag is None:
        raise RuntimeError('Published release has no tag; explicit operator repair required')
    if tag != 'nightly' and old_tag not in (None, sha):
        raise RuntimeError('Dated nightly already points to another commit')
    new_specs = [specification(p) for p in assets]
    if not new_specs or any(s['size'] == 0 for s in new_specs) or len({s['name'] for s in new_specs}) != len(new_specs):
        raise RuntimeError('Missing, empty or duplicate publishing assets')
    with tempfile.TemporaryDirectory() as directory:
        root = Path(directory)
        backup = root / 'assets'
        backup.mkdir()
        old_paths = []
        for asset in old['assets'] if old else []:
            name = asset_name(asset['name'])
            gh('release', 'download', tag, '--pattern', name, '--dir', str(backup))
            old_paths.append(backup / name)
        # Check original server sizes and digests (or re-download on older APIs).
        verify_uploads(repo, tag, old_paths) if old else None
        record = {'schema': 1, 'repo': repo, 'tag': tag, 'sha': sha,
                  'run_id': os.environ.get('GITHUB_RUN_ID'),
                  'build_attempt': os.environ.get('BUILD_ATTEMPT'),
                  'phase': 'preparing', 'old': old, 'old_tag': old_tag,
                  'old_assets': [specification(p) for p in old_paths], 'new_assets': new_specs}
        record_path = root / 'transaction.json'
        try:
            gh('release', 'create', journal_tag, '--target', sha, '--title', f'CI recovery backup: {tag}',
               '--notes-file', write_record(record_path, record), '--draft', '--prerelease', '--latest=false')
            if old_paths:
                gh('release', 'upload', journal_tag, *(str(p) for p in old_paths))
            verify_specs(repo, journal_tag, record['old_assets'], exact=True)
            update_record(tag, record_path, record, 'ready')
            # From here SIGKILL/runner loss is safe: the next holder rolls back.
            if old:
                gh('release', 'edit', tag, '--draft=true')
            else:
                gh('release', 'create', tag, '--target', sha, '--title', title,
                   '--notes-file', str(body), '--draft', '--prerelease', '--latest=false')
            gh('release', 'upload', tag, *(str(p) for p in assets), '--clobber')
            verify_uploads(repo, tag, assets)
            set_tag(repo, tag, sha)
            gh('release', 'edit', tag, '--title', title, '--notes-file', str(body),
               '--prerelease', '--latest=false', '--draft=false')
            # A crash before this durable commit conservatively restores the old release.
            update_record(tag, record_path, record, 'committed')
            recover(repo, tag)
        except Exception:
            try:
                recover(repo, tag)
            except Exception as recovery_error:
                raise RuntimeError(f'{tag} recovery incomplete; durable backup retained at {journal_tag}; '
                                   'retry recovery under the publish lock') from recovery_error
            raise


if __name__ == '__main__':
    import argparse
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('operation', choices=['recover'])
    parser.add_argument('--tag', default='nightly', help='Run under the ORIGINAL target publish concurrency lock')
    args = parser.parse_args()
    recover(os.environ['GITHUB_REPOSITORY'], args.tag)

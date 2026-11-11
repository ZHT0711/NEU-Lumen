"""Publish a coherent rolling preview; hide partial updates and restore on failure."""
import hashlib
import json
import os
from pathlib import Path
import subprocess
import tempfile

from package_ui_preview import release_assets
from publish_manual_nightly import gh


def release_data(repo, tag):
    # gh also locates drafts, whose tag may not exist yet. Query by release ID.
    identity = gh('release', 'view', tag, '--json', 'databaseId', '--jq', '.databaseId')
    return json.loads(gh('api', f'repos/{repo}/releases/{identity}'))


def release(repo):
    try:
        return release_data(repo, 'nightly')
    except subprocess.CalledProcessError as error:
        if 'HTTP 404' in (error.stderr or '') or 'release not found' in (error.stderr or '').lower():
            return None
        raise


def verify_uploads(repo, tag, assets):
    remote = release_data(repo, tag)
    by_name = {asset['name']: asset for asset in remote['assets']}
    for path in assets:
        asset = by_name.get(path.name)
        expected = 'sha256:' + hashlib.sha256(path.read_bytes()).hexdigest()
        if asset is None or asset['size'] != path.stat().st_size:
            raise RuntimeError(f'Release asset missing or truncated: {path.name}')
        if asset.get('digest'):
            if asset['digest'] != expected:
                raise RuntimeError(f'Release checksum mismatch: {path.name}')
        else:
            # Older GitHub API responses may omit digest; verify actual download.
            with tempfile.TemporaryDirectory() as directory:
                gh('release', 'download', tag, '--pattern', path.name, '--dir', directory)
                if (Path(directory) / path.name).read_bytes() != path.read_bytes():
                    raise RuntimeError(f'Release download mismatch: {path.name}')


def notes(repo, sha, run):
    url = f'https://github.com/{repo}/releases/download/nightly'
    return (f'NEU-Lumen Nightly · 未签名 IPA，需自行签名安装。\n\n'
            f'计划北京时间每天 03:17 一次，Actions 可能延迟；main 更新也会构建。\n\n'
            f'[构建与检查](https://github.com/{repo}/actions/runs/{run}) · 提交 `{sha}`\n\n'
            '本次 App 运行截图：iPhone 模拟器、演示数据，非实体真机。\n\n'
            f'![首页]({url}/home-light.png)\n\n![课表]({url}/schedule-light.png)\n\n'
            f'[全部截图]({url}/NEU-Lumen-ui-preview.zip) · [截图来源]({url}/ui-preview.json)\n')


def publish():
    repo, sha, run = os.environ['GITHUB_REPOSITORY'], os.environ['GITHUB_SHA'], os.environ['GITHUB_RUN_ID']
    previews = release_assets('release-assets/ui-preview')
    ipa = Path('release-assets/NEU-Lumen-iOS-unsigned.ipa')
    if not ipa.is_file():
        raise RuntimeError('Missing verified IPA')
    assets = [ipa, *previews]
    current = gh('api', f'repos/{repo}/git/ref/heads/main', '--jq', '.object.sha')
    if current != sha:
        print('main changed; skip stale rolling release')
        return
    old = release(repo)
    if old and old['draft']:
        raise RuntimeError('Nightly is already a draft; inspect the previous publish before retrying')
    old_tag = gh('api', f'repos/{repo}/git/ref/tags/nightly', '--jq', '.object.sha') if old else None
    body = Path('release-assets/nightly-notes.md')
    body.write_text(notes(repo, sha, run), encoding='utf-8')
    with tempfile.TemporaryDirectory() as directory:
        backup = Path(directory)
        managed = {path.name for path in assets}
        previous = {asset['name'] for asset in old['assets']} & managed if old else set()
        if previous:
            args = ['release', 'download', 'nightly', '--dir', str(backup)]
            for name in sorted(previous):
                args.extend(['--pattern', name])
            gh(*args)
            if not all((backup / name).is_file() for name in previous):
                raise RuntimeError('Could not back up previous Nightly assets')
        old_notes = backup / 'old-notes.md'
        old_notes.write_text(old.get('body') or '' if old else '', encoding='utf-8')
        try:
            if old:
                gh('release', 'edit', 'nightly', '--draft=true')
            else:
                gh('release', 'create', 'nightly', '--target', sha, '--title', 'NEU-Lumen Nightly',
                   '--notes-file', str(body), '--draft', '--prerelease', '--latest=false')
            gh('release', 'upload', 'nightly', *(str(path) for path in assets), '--clobber')
            verify_uploads(repo, 'nightly', assets)
            if old:
                gh('api', '--method', 'PATCH', f'repos/{repo}/git/refs/tags/nightly', '-f', f'sha={sha}', '-F', 'force=true')
            else:
                # Draft release tags may only be created when the draft is published.
                try:
                    gh('api', '--method', 'POST', f'repos/{repo}/git/refs', '-f', 'ref=refs/tags/nightly', '-f', f'sha={sha}')
                except subprocess.CalledProcessError as error:
                    if 'Reference already exists' not in error.stderr:
                        raise
                    gh('api', '--method', 'PATCH', f'repos/{repo}/git/refs/tags/nightly', '-f', f'sha={sha}', '-F', 'force=true')
            gh('release', 'edit', 'nightly', '--title', 'NEU-Lumen Nightly', '--notes-file', str(body),
               '--prerelease', '--latest=false', '--draft=false')
        except Exception:
            # Never publicly expose a mixture of assets from different runs.
            if old:
                try:
                    gh('release', 'edit', 'nightly', '--draft=true')
                    now = release(repo)
                    present = {asset['name'] for asset in now['assets']}
                    for name in sorted((managed - previous) & present):
                        gh('release', 'delete-asset', 'nightly', name, '--yes')
                    if previous:
                        gh('release', 'upload', 'nightly', *(str(backup / name) for name in sorted(previous)), '--clobber')
                        verify_uploads(repo, 'nightly', [backup / name for name in sorted(previous)])
                    gh('api', '--method', 'PATCH', f'repos/{repo}/git/refs/tags/nightly', '-f', f'sha={old_tag}', '-F', 'force=true')
                    gh('release', 'edit', 'nightly', '--title', old['name'] or 'NEU-Lumen Nightly',
                       '--notes-file', str(old_notes), f'--prerelease={str(old["prerelease"]).lower()}', '--latest=false', '--draft=false')
                except Exception:
                    raise RuntimeError('Nightly restore failed; kept hidden when possible. Inspect Actions before retrying') from None
            raise
    print(f'https://github.com/{repo}/releases/tag/nightly')


if __name__ == '__main__':
    publish()

"""Publish one dated prerelease per manual workflow run, with retry-stable tags."""
from datetime import datetime, timedelta, timezone
from pathlib import Path
import os
import shutil
import subprocess


def release_identity(created_at, run_number):
    triggered = datetime.fromisoformat(created_at.replace('Z', '+00:00'))
    beijing = triggered.astimezone(timezone(timedelta(hours=8)))
    stamp = beijing.strftime('%Y%m%d-%H%M%S')
    return f'nightly-{stamp}-{run_number}', beijing.strftime('%Y-%m-%d %H:%M:%S'), stamp


def gh(*args):
    return subprocess.run(['gh', *args], check=True, capture_output=True, text=True).stdout.strip()


def main():
    if os.environ.get('GITHUB_EVENT_NAME') != 'workflow_dispatch':
        return
    repo = os.environ['GITHUB_REPOSITORY']
    run = os.environ['GITHUB_RUN_ID']
    sha = os.environ['GITHUB_SHA']
    created = gh('api', f'repos/{repo}/actions/runs/{run}', '--jq', '.created_at')
    tag, date, stamp = release_identity(created, os.environ['GITHUB_RUN_NUMBER'])
    title = f'NEU-Lumen Nightly {date}（北京时间）'
    notes = Path('release-assets/manual-notes.md')
    notes.write_text(f'手动触发的每夜预发布，时间为北京时间 {date}。\n\n'
                     f'- 提交 `{sha}`\n'
                     f'- [构建与检查](https://github.com/{repo}/actions/runs/{run})\n'
                     '- IPA 已完成全部回归与编译警告检查，需自行签名安装。\n', encoding='utf-8')
    asset = Path(f'release-assets/NEU-Lumen-iOS-unsigned-{stamp}-{os.environ["GITHUB_RUN_NUMBER"]}.ipa')
    shutil.copyfile('release-assets/NEU-Lumen-iOS-unsigned.ipa', asset)
    exists = subprocess.run(['gh', 'release', 'view', tag], capture_output=True, text=True).returncode == 0
    if exists:
        target = gh('api', f'repos/{repo}/git/ref/tags/{tag}', '--jq', '.object.sha')
        if target != sha:
            raise RuntimeError('手动每夜版标签已指向其它提交，请检查发布记录')
        gh('release', 'edit', tag, '--title', title, '--notes-file', str(notes), '--prerelease', '--latest=false')
    else:
        gh('release', 'create', tag, '--target', sha, '--title', title, '--notes-file', str(notes), '--prerelease', '--latest=false')
    gh('release', 'upload', tag, str(asset), '--clobber')
    print(f'https://github.com/{repo}/releases/tag/{tag}')


if __name__ == '__main__':
    main()

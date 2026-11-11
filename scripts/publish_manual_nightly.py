"""Publish one dated prerelease per manual workflow run, with retry-stable tags."""
from datetime import datetime, timedelta, timezone
from pathlib import Path
import os
import shutil
import subprocess

from package_ui_preview import release_assets


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
    preview_assets = release_assets('release-assets/ui-preview')
    url = f'https://github.com/{repo}/releases/download/{tag}'
    notes = Path('release-assets/manual-notes.md')
    notes.write_text(f'北京时间 {date} 手动构建。IPA 未签名，需自行签名安装。\n\n'
                     f'[构建与检查](https://github.com/{repo}/actions/runs/{run}) · 提交 `{sha}`\n\n'
                     '本次 App 运行截图：iPhone 模拟器、演示数据，非实体真机。\n\n'
                     f'![首页]({url}/home-light.png)\n\n'
                     f'![课表]({url}/schedule-light.png)\n\n'
                     f'[全部截图]({url}/NEU-Lumen-ui-preview.zip) · [截图来源]({url}/ui-preview.json)\n', encoding='utf-8')
    asset = Path(f'release-assets/NEU-Lumen-iOS-unsigned-{stamp}-{os.environ["GITHUB_RUN_NUMBER"]}.ipa')
    shutil.copyfile('release-assets/NEU-Lumen-iOS-unsigned.ipa', asset)
    from publish_nightly import release_data, verify_uploads
    exists = subprocess.run(['gh', 'release', 'view', tag], capture_output=True, text=True).returncode == 0
    if exists:
        existing = release_data(repo, tag)
        target = existing['target_commitish'] if existing['draft'] else gh('api', f'repos/{repo}/git/ref/tags/{tag}', '--jq', '.object.sha')
        if target != sha:
            raise RuntimeError('手动每夜版已指向其它提交，请检查发布记录')
        gh('release', 'edit', tag, '--draft=true')
    else:
        gh('release', 'create', tag, '--target', sha, '--title', title, '--notes-file', str(notes), '--prerelease', '--latest=false', '--draft')
    gh('release', 'upload', tag, str(asset), *(str(path) for path in preview_assets), '--clobber')
    verify_uploads(repo, tag, [asset, *preview_assets])
    gh('release', 'edit', tag, '--title', title, '--notes-file', str(notes), '--prerelease', '--latest=false', '--draft=false')
    print(f'https://github.com/{repo}/releases/tag/{tag}')


if __name__ == '__main__':
    main()

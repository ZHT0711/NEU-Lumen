"""Publish one dated prerelease per manual workflow run, with retry-stable tags."""
import argparse
from datetime import datetime, timedelta, timezone
from pathlib import Path
import os
import shutil

from package_ui_preview import release_assets
from build_provenance import validate
from release_transaction import gh, publish_release, recover


def release_identity(created_at, run_number):
    triggered = datetime.fromisoformat(created_at.replace('Z', '+00:00'))
    beijing = triggered.astimezone(timezone(timedelta(hours=8)))
    stamp = beijing.strftime('%Y%m%d-%H%M%S')
    return f'nightly-{stamp}-{run_number}', beijing.strftime('%Y-%m-%d %H:%M:%S'), stamp


def main(recover_only=False):
    if os.environ.get('GITHUB_EVENT_NAME') != 'workflow_dispatch':
        return
    repo = os.environ['GITHUB_REPOSITORY']
    run = os.environ['GITHUB_RUN_ID']
    sha = os.environ['GITHUB_SHA']
    created = gh('api', f'repos/{repo}/actions/runs/{run}', '--jq', '.created_at')
    tag, date, stamp = release_identity(created, os.environ['GITHUB_RUN_NUMBER'])
    recover(repo, tag)
    if recover_only:
        return
    provenance = validate()
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
    publish_release(repo, tag, sha, title, notes, [asset, *preview_assets, provenance])
    print(f'https://github.com/{repo}/releases/tag/{tag}')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--recover-only', action='store_true')
    main(parser.parse_args().recover_only)

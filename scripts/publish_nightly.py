"""Publish a coherent rolling preview with cross-run durable rollback."""
import argparse
import os
from pathlib import Path

from package_ui_preview import release_assets
from build_provenance import validate
from release_transaction import gh, optional_release, publish_release, recover, release_data, verify_uploads


def release(repo):
    return optional_release(repo, 'nightly')


def notes(repo, sha, run):
    url = f'https://github.com/{repo}/releases/download/nightly'
    return (f'NEU-Lumen Nightly · 未签名 IPA，需自行签名安装。\n\n'
            f'计划北京时间每天 03:17 一次，Actions 可能延迟；main 更新也会构建。\n\n'
            f'[构建与检查](https://github.com/{repo}/actions/runs/{run}) · 提交 `{sha}`\n\n'
            '本次 App 运行截图：iPhone 模拟器、演示数据，非实体真机。\n\n'
            f'![首页]({url}/home-light.png)\n\n![课表]({url}/schedule-light.png)\n\n'
            f'[全部截图]({url}/NEU-Lumen-ui-preview.zip) · [截图来源]({url}/ui-preview.json)\n')


def publish(recover_only=False):
    repo = os.environ['GITHUB_REPOSITORY']
    # Recovery precedes staleness checks AND local artifact validation/downloads.
    recover(repo, 'nightly')
    if recover_only:
        return
    sha, run = os.environ['GITHUB_SHA'], os.environ['GITHUB_RUN_ID']
    current = gh('api', f'repos/{repo}/git/ref/heads/main', '--jq', '.object.sha')
    if current != sha:
        print('main changed; skip stale rolling release')
        return
    provenance = validate()
    previews = release_assets('release-assets/ui-preview')
    ipa = Path('release-assets/NEU-Lumen-iOS-unsigned.ipa')
    body = Path('release-assets/nightly-notes.md')
    body.write_text(notes(repo, sha, run), encoding='utf-8')
    publish_release(repo, 'nightly', sha, 'NEU-Lumen Nightly', body, [ipa, *previews, provenance])
    print(f'https://github.com/{repo}/releases/tag/nightly')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--recover-only', action='store_true', help='Recover/clean journal under the publish-nightly lock; no local artifacts required')
    publish(parser.parse_args().recover_only)

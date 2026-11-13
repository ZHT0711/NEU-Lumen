"""Package only screenshots captured by this run's simulator validation."""
import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import struct
import zipfile
import zlib

SCREENSHOTS = (
    'home-light.png', 'home-nanhu-light.png', 'home-dark.png',
    'schedule-light.png', 'services-light.png', 'grades-light.png',
    'mooc-light.png', 'chaoxing-light.png', 'card-light.png',
    'profile-light.png', 'favorites-light.png', 'holidays-light.png',
    'calendar-light.png', 'browser-light.png', 'browser-dark.png',
    'live-activity-light.png', 'live-activity-custom-light.png',
    'live-activity-dark.png', 'profile-dark.png', 'downloads-light.png',
)
LIVE_KINDS = ('nextCourse', 'cardBalance', 'netBalance', 'electricBalance', 'assignments',
              'planner', 'dayOverview', 'academicOverview', 'custom')
LIVE_SCREENSHOTS = tuple(f'live-expanded-{kind}-light.png' for kind in LIVE_KINDS) + ('live-expanded-ax-stale-light.png',)
SYSTEM_ISLAND_SCREENSHOTS = tuple(f'system-island-{kind}.png' for kind in ('nextCourse', 'custom', 'electricBalance'))
NATIVE_SCREENS = ('academic-center', 'academic-calendar', 'academic-plan')
SERVICE_SCREENS = ('native-payment', 'native-vpn', 'native-affairs', 'native-mail')
ACADEMIC_WEB_CHECK = 'academic-web-sync-checks.txt'
ACADEMIC_WEB_CASES = ('same-account', 'wrong-account', 'spoofed-page-world',
                      'identity-changes-between-checks', 'account-epoch-rejects-old-snapshot')
ACADEMIC_IDENTITY_EVIDENCE = [
    {'case': name, 'requests': requests, 'accepted': accepted}
    for name, requests, accepted in zip(ACADEMIC_WEB_CASES, (2, 1, 1, 2), (True, False, False, False))
]
LAYOUT_NEGATIVE_CONTROLS = ('negative-overlap-rejected', 'negative-oversize-rejected')
SCREENSHOTS = SCREENSHOTS + SYSTEM_ISLAND_SCREENSHOTS + LIVE_SCREENSHOTS + tuple(f'{screen}-light.png' for screen in (*NATIVE_SCREENS, *SERVICE_SCREENS))
LAYOUT_CHECK = 'live-activity-layout-checks.txt'
LAYOUT_COVERAGE = {
    'shared_view_cases': 174, 'metric_layout_cases': 12, 'negative_controls': 2,
    'widths_pt': [330, 350, 370], 'max_height_pt': 100, 'expanded_max_height_pt': 160, 'reserved_height_pt': 60, 'kinds': list(LIVE_KINDS),
    'dynamic_types': ['large', 'accessibility3'], 'variants': ['fresh', 'stale', 'nil-metadata'],
    'timer_modes': ['system-Text', 'multi-day-string'],
}
CHECKS = ('browser-checks.txt', 'download-checks.txt', 'download-restore.txt', 'download-screenshot.txt',
          'session-save.txt', 'session-restore.txt', 'learning-save.txt', 'learning-restore.txt',
          'live-activity-checks.txt', 'live-activity-data-checks.txt',
          LAYOUT_CHECK, ACADEMIC_WEB_CHECK, 'system-island-checks.txt') + tuple(f'{screen}-screenshot.txt' for screen in NATIVE_SCREENS)
MANIFEST = 'ui-preview.json'
ARCHIVE = 'NEU-Lumen-ui-preview.zip'


def png_info(path):
    raw = path.read_bytes()
    header = raw[:24]
    if len(header) != 24 or header[:8] != b'\x89PNG\r\n\x1a\n' or header[12:16] != b'IHDR':
        raise ValueError(f'Invalid PNG: {path.name}')
    width, height = struct.unpack('>II', header[16:24])
    if width <= 0 or height <= 0:
        raise ValueError(f'Invalid image size: {path.name}')
    offset, image_data, ended = 8, bytearray(), False
    while offset + 12 <= len(raw):
        length = struct.unpack('>I', raw[offset:offset + 4])[0]
        end = offset + 12 + length
        if end > len(raw):
            raise ValueError(f'Truncated PNG: {path.name}')
        kind = raw[offset + 4:offset + 8]
        data = raw[offset + 8:end - 4]
        crc = struct.unpack('>I', raw[end - 4:end])[0]
        if zlib.crc32(kind + data) != crc:
            raise ValueError(f'PNG checksum mismatch: {path.name}')
        if offset == 8 and (kind != b'IHDR' or length != 13):
            raise ValueError(f'Invalid PNG header: {path.name}')
        if kind == b'IDAT':
            image_data.extend(data)
        if kind == b'IEND':
            ended = length == 0 and end == len(raw)
            break
        offset = end
    if not ended or not image_data:
        raise ValueError(f'Incomplete PNG: {path.name}')
    try:
        if not zlib.decompress(image_data):
            raise ValueError('Empty image stream')
    except (zlib.error, ValueError):
        raise ValueError(f'Invalid PNG image stream: {path.name}') from None
    return {'file': path.name, 'width': width, 'height': height,
            'sha256': hashlib.sha256(raw).hexdigest()}


def layout_case_keys():
    shared = {f'{kind}.{variant}.{font} width={width}'
              for kind in LIVE_KINDS for variant in LAYOUT_COVERAGE['variants']
              for font in LAYOUT_COVERAGE['dynamic_types'] for width in LAYOUT_COVERAGE['widths_pt']}
    for mode in ('multi-day-system-Text', 'multi-day-string'):
        for font in LAYOUT_COVERAGE['dynamic_types']:
            for width in LAYOUT_COVERAGE['widths_pt']:
                shared.add(f'{mode}.{font} width={width}')
                shared.add(f'actual-metric-Layout.{mode}.{font} width={width}')
    return shared


def check_info(directory):
    evidence = []
    for name in CHECKS:
        raw = (directory / name).read_bytes()
        text = raw.decode('utf-8')
        lines = text.splitlines()
        if not any(line.startswith('PASS:') for line in lines) or any(line.startswith('FAIL:') for line in lines):
            raise ValueError(f'UI check did not pass: {name}')
        if name == 'system-island-checks.txt':
            expected = [f'PASS: actual system expanded {kind}; title and metric visible above Settings; simulator synthetic data'
                        for kind in ('nextCourse', 'custom', 'electricBalance')]
            if lines != expected:
                raise ValueError('Incomplete actual system expanded Island evidence')
        if name == ACADEMIC_WEB_CHECK:
            cases = [line[len('CASE: '):] for line in lines if line.startswith('CASE: ')]
            identities = [json.loads(line[len('IDENTITY: '):]) for line in lines if line.startswith('IDENTITY: ')]
            negative = [line[len('NEGATIVE-CONTROL: '):] for line in lines if line.startswith('NEGATIVE-CONTROL: ')]
            if (cases != list(ACADEMIC_WEB_CASES) or identities != ACADEMIC_IDENTITY_EVIDENCE
                    or any(type(item.get('requests')) is not int or type(item.get('accepted')) is not bool for item in identities)
                    or negative != ['unsafe-page-world-spoof-accepted']):
                raise ValueError('Incomplete actual WebKit identity/account evidence')
        if name == LAYOUT_CHECK:
            negative = [line[len('NEGATIVE-CONTROL: '):] for line in lines if line.startswith('NEGATIVE-CONTROL: ')]
            if negative != list(LAYOUT_NEGATIVE_CONTROLS):
                raise ValueError('Missing actual hosting negative-control rejection')
            coverage = [json.loads(line[len('COVERAGE: '):]) for line in lines if line.startswith('COVERAGE: ')]
            if coverage != [LAYOUT_COVERAGE]:
                raise ValueError('Incomplete actual simulator layout matrix')
            cases = [line[len('CASE: '):] for line in lines if line.startswith('CASE: ')]
            keys = [line.split(' intrinsic=', 1)[0] for line in cases]
            if len(keys) != 186 or set(keys) != layout_case_keys():
                raise ValueError('Missing/duplicate actual hosting measurements')
            for line in cases:
                fields = dict(field.split('=', 1) for field in line.split()[1:])
                if (any(not 0 < float(fields[key]) <= 100.5 for key in ('intrinsic', 'fitted', 'content'))
                        or int(fields['actual-bounds']) < 2):
                    raise ValueError('Invalid or overflowing actual hosting measurement')
        evidence.append({'file': name, 'sha256': hashlib.sha256(raw).hexdigest(), 'status': 'PASS'})
    return evidence


def package(directory, environment=None):
    directory = Path(directory)
    env = os.environ if environment is None else environment
    # All checks must belong to this run; validate_ui.sh clears its output first.
    checks = check_info(directory)
    images = [png_info(directory / name) for name in SCREENSHOTS]
    device = json.loads((directory / 'simulator-device.json').read_text(encoding='utf-8'))
    repo, run = env['GITHUB_REPOSITORY'], env['GITHUB_RUN_ID']
    manifest = {
        'schema_version': 2,
        'commit': env['GITHUB_SHA'], 'run_id': run, 'run_number': env['GITHUB_RUN_NUMBER'],
        'run_url': f'https://github.com/{repo}/actions/runs/{run}',
        'generated_at': datetime.now(timezone.utc).isoformat(),
        'capture_source': 'xcrun simctl io screenshot',
        'device_type': 'iPhone simulator', 'device': device,
        'data_source': 'UI validation fixtures; not a real campus account',
        'build_configuration': 'Debug simulator build from the same commit as the Release IPA',
        'required_checks': checks,
        'live_activity_layout': LAYOUT_COVERAGE,
        'system_island_preview': {'screenshots': list(SYSTEM_ISLAND_SCREENSHOTS),
            'source': 'SpringBoard ActivityKit expanded alert above Settings; OCR-confirmed title and metric; synthetic simulator data'},
        'live_activity_preview': {
            'screenshots': list(LIVE_SCREENSHOTS),
            'component': 'actual shared LiveActivityExpandedContent(state:isStale:)',
            'notice': '模拟器共享组件布局验证，非系统灵动岛截屏/非真机',
            'activitykit_lifecycle_evidence': 'live-activity-checks.txt (separate real ActivityKit tests)',
        },
        'native_preview': {
            'academic': 'actual AcademicCenterView / AcademicCalendarView / AcademicPlanView; explicit DEBUG seedAcademicPreview; synthetic only',
            'services': 'actual NativeServiceHost / payment / VPN / affairs / mail views; disposable Debug synthetic fixtures only; no real account',
        },
        'screenshots': images,
    }
    (directory / MANIFEST).write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    with zipfile.ZipFile(directory / ARCHIVE, 'w', compression=zipfile.ZIP_DEFLATED) as archive:
        for name in (*SCREENSHOTS, MANIFEST):
            archive.write(directory / name, name)
    return manifest


def release_assets(directory):
    directory = Path(directory)
    manifest = json.loads((directory / MANIFEST).read_text(encoding='utf-8'))
    if manifest['commit'] != os.environ['GITHUB_SHA'] or str(manifest['run_id']) != os.environ['GITHUB_RUN_ID']:
        raise ValueError('Screenshots do not belong to the publishing build')
    if tuple(item['file'] for item in manifest['screenshots']) != SCREENSHOTS:
        raise ValueError('Unexpected screenshot list')
    if manifest.get('required_checks') != check_info(directory) or manifest.get('live_activity_layout') != LAYOUT_COVERAGE:
        raise ValueError('UI validation evidence changed or is incomplete')
    for item in manifest['screenshots']:
        if png_info(directory / item['file']) != item:
            raise ValueError(f'Screenshot checksum mismatch: {item["file"]}')
    with zipfile.ZipFile(directory / ARCHIVE) as archive:
        expected = (*SCREENSHOTS, MANIFEST)
        if len(archive.namelist()) != len(expected) or set(archive.namelist()) != set(expected):
            raise ValueError('Unexpected screenshot archive contents')
        for name in expected:
            if archive.read(name) != (directory / name).read_bytes():
                raise ValueError(f'Screenshot archive mismatch: {name}')
    return [directory / name for name in (*SCREENSHOTS, ARCHIVE, MANIFEST)]


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('directory')
    parser.add_argument('--list-assets', action='store_true')
    args = parser.parse_args()
    if args.list_assets:
        print('\n'.join(str(path) for path in release_assets(args.directory)))
    else:
        package(args.directory)

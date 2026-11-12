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
CHECKS = ('browser-checks.txt', 'download-checks.txt', 'download-restore.txt', 'download-screenshot.txt',
          'session-save.txt', 'session-restore.txt', 'live-activity-checks.txt', 'live-activity-data-checks.txt')
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


def package(directory, environment=None):
    directory = Path(directory)
    env = os.environ if environment is None else environment
    # All checks must belong to this run; validate_ui.sh clears its output first.
    for name in CHECKS:
        text = (directory / name).read_text(encoding='utf-8')
        if not any(line.startswith('PASS:') for line in text.splitlines()) or any(line.startswith('FAIL:') for line in text.splitlines()):
            raise ValueError(f'UI check did not pass: {name}')
    images = [png_info(directory / name) for name in SCREENSHOTS]
    device = json.loads((directory / 'simulator-device.json').read_text(encoding='utf-8'))
    repo, run = env['GITHUB_REPOSITORY'], env['GITHUB_RUN_ID']
    manifest = {
        'schema_version': 1,
        'commit': env['GITHUB_SHA'], 'run_id': run, 'run_number': env['GITHUB_RUN_NUMBER'],
        'run_url': f'https://github.com/{repo}/actions/runs/{run}',
        'generated_at': datetime.now(timezone.utc).isoformat(),
        'capture_source': 'xcrun simctl io screenshot',
        'device_type': 'iPhone simulator', 'device': device,
        'data_source': 'UI validation fixtures; not a real campus account',
        'build_configuration': 'Debug simulator build from the same commit as the Release IPA',
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

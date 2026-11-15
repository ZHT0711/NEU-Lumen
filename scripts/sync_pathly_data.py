"""Import Pathly's published data literals without executing downloaded JavaScript."""
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import re
import urllib.request

ROOT = Path(__file__).resolve().parents[1]
ORIGIN = 'https://pathly.top'


def literal(source, offset):
    """Strict object/array/string/number subset; function calls are never accepted."""
    def space(i):
        while i < len(source) and source[i].isspace(): i += 1
        return i
    i = space(offset)
    if source[i] == '"': return json.JSONDecoder().raw_decode(source, i)
    if source[i] in '{[':
        container = {} if source[i] == '{' else []
        end = '}' if isinstance(container, dict) else ']'
        i = space(i + 1)
        while source[i] != end:
            if isinstance(container, dict):
                if source[i] == '"': key, i = json.JSONDecoder().raw_decode(source, i)
                else:
                    match = re.match(r'[A-Za-z_$][\w$]*|(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?', source[i:])
                    if not match: raise ValueError('Unsupported literal key')
                    key = match[0]; i += len(key)
                    if key[0].isdigit():
                        number = float(key)
                        key = str(int(number)) if number.is_integer() else str(number)
                i = space(i)
                if source[i] != ':': raise ValueError('Missing literal colon: ' + source[max(0,i-20):i+25])
                value, i = literal(source, i + 1)
                if key in container: raise ValueError('Duplicate data key')
                container[key] = value
            else:
                value, i = literal(source, i)
                container.append(value)
            i = space(i)
            if source[i] == end: break
            if source[i] != ',': raise ValueError('Unsupported data expression')
            i = space(i + 1)
        return container, i + 1
    match = re.match(r'-?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?|true|false|null', source[i:])
    if not match: raise ValueError('Only data literals are accepted: ' + source[i:i+30])
    token = match[0]
    value = json.loads(token) if token in ('true', 'false', 'null') else float(token) if any(c in token for c in '.eE') else int(token)
    return value, i + len(token)


def fetch(path):
    with urllib.request.urlopen(ORIGIN + path, timeout=25) as response:
        if response.geturl().split('/')[2] != 'pathly.top': raise ValueError('Unexpected data origin')
        data = response.read(4_000_001)
    if len(data) > 4_000_000: raise ValueError('Oversized data source')
    return data.decode('utf-8')


def assigned(source, name):
    match = re.search(r'(?:const\s+|,)\s*' + re.escape(name) + r'\s*=', source)
    if not match: raise ValueError('Missing published data assignment: ' + name)
    return literal(source, match.end())[0]


def sync():
    sources = {}
    def read(path):
        source = fetch(path)
        cache = ROOT / 'build/pathly-native-import'
        cache.mkdir(parents=True, exist_ok=True)
        (cache / (path.rsplit('/', 1)[-1] or 'index.html')).write_text(source, encoding='utf-8')
        sources[path] = hashlib.sha256(source.encode()).hexdigest()
        return source
    html = read('/')
    app_path = re.search(r'src="(/assets/index-[^"]+\.js)"', html)[1]
    app = read(app_path)
    def module(prefix):
        name = re.search(re.escape(prefix) + r'-[\w-]+\.js', app)[0]
        return read('/assets/' + name)
    building_source = module('UserPathSelectBuilding')
    # The catalog is the single literal with both published campus keys.
    offset = building_source.index('{main:{buildings:')
    building_config, _ = literal(building_source, offset)
    room_module = module('UserPathSelectEnd')
    rooms_path = '/assets/' + re.search(r'south-[\w-]+\.js', room_module)[0]
    rooms_source = read(rooms_path)
    exports = re.search(r'export\{(\w+) as a,(\w+) as b\}', rooms_source)
    room_data = dict(zip(('main', 'south'), (assigned(rooms_source, name) for name in exports.groups())))
    results = module('UserPathResult')
    chunks = dict(re.findall(r'/src/data/buildings/(\w+)\.ts":\(\)=>[^;]*?import\("\./([^"/]+\.js)"\)', results))
    buildings = []
    def load_building(entry):
        campus, index, name, identifier = entry
        coordinates_source = read('/assets/' + chunks[identifier])
        exported = re.search(r'export\{(\w+) as default\}', coordinates_source)[1]
        try: coordinates = assigned(coordinates_source, exported)
        except ValueError as error: raise ValueError(identifier + ': ' + str(error)) from error
        return {'id': identifier, 'name': name, 'campus': campus,
                'floors': room_data[campus][str(index)], 'maps': coordinates}
    entries = [(campus, index, name, config['buildingNameForFileName'][index])
               for campus, config in building_config.items() for index, name in enumerate(config['buildings'])]
    with ThreadPoolExecutor(max_workers=6) as pool: buildings = list(pool.map(load_building, entries))
    if len(buildings) != 19: raise ValueError('Published building coverage changed; review before import')
    data = {'version': 1, 'importedAt': datetime.now(timezone.utc).isoformat(),
            'source': ORIGIN, 'buildings': buildings, 'sourceHashes': sources}
    target = ROOT / 'NEU-Lumen/Resources/PathlyCatalog.json'
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(json.dumps(data, ensure_ascii=False, separators=(',', ':'), allow_nan=False) + '\n', encoding='utf-8')
    print(f'Imported {len(buildings)} Pathly buildings; {target.stat().st_size} bytes; no downloaded code executed')


if __name__ == '__main__': sync()

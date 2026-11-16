"""Build approximate outdoor gate coordinates from reviewed Pathly alignments.

No geocoder runs in the app and no building centre is substituted for a door.
The alignment file records the public references, diagram hashes and door pixels.
"""
import argparse
import json
import math
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
TARGET = ROOT / 'NEU-Lumen/Resources/CampusEntrances.json'


def build():
    alignment = json.loads((ROOT / 'data/campus-entrance-alignment.json').read_text(encoding='utf-8'))
    catalog = json.loads((ROOT / 'NEU-Lumen/Resources/PathlyCatalog.json').read_text(encoding='utf-8'))
    references = {row['buildingID']: row for row in alignment['buildings']}
    if len(references) != len(alignment['buildings']) or set(references) != {b['id'] for b in catalog['buildings']}:
        raise ValueError('Building coverage changed; review the entrance alignments')
    entries = []
    for building in catalog['buildings']:
        row = references[building['id']]
        gates = {room['value']: room['name'] for floor in building['floors'] for room in floor['rooms']
                 if isinstance(room, dict) and room['value'].startswith('G')}
        points = row.get('gatePixels', row.get('directGates', {}))
        if set(points) != set(gates.values()) or len(set(gates.values())) != len(gates):
            raise ValueError('Gate names changed: ' + building['id'])
        for gate_id, name in gates.items():
            if 'directGates' in row:
                point = row['directGates'][name]
                latitude, longitude = point['latitude'], point['longitude']
            else:
                left, top, right, bottom = row['imageBounds']
                west, south, east, north = row['geographicBounds']
                x, y = row['gatePixels'][name]
                longitude = west + (x - left) / (right - left) * (east - west)
                latitude = north - (y - top) / (bottom - top) * (north - south)
            lat_range = (41.64, 41.66) if building['campus'] == 'south' else (41.75, 41.78)
            if not (math.isfinite(latitude) and math.isfinite(longitude)
                    and lat_range[0] <= latitude <= lat_range[1] and 123.40 <= longitude <= 123.43):
                raise ValueError('Entrance outside its campus: ' + building['id'])
            entries.append({'buildingID': building['id'], 'gateID': gate_id,
                            'latitude': round(latitude, 7), 'longitude': round(longitude, 7),
                            'approximateAccuracyMeters': row['approximateAccuracyMeters']})
    return {'version': 1, 'alignedAt': alignment['alignedAt'], 'coordinateSystem': 'WGS84',
            'fieldVerified': False, 'attribution': alignment['attribution'], 'entrances': entries}


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check', action='store_true', help='Fail if the bundled output differs')
    args = parser.parse_args()
    result = json.dumps(build(), ensure_ascii=False, indent=2, allow_nan=False) + '\n'
    if args.check:
        if TARGET.read_text(encoding='utf-8') != result:
            raise SystemExit('CampusEntrances.json is stale; run scripts/build_campus_entrances.py')
    else:
        TARGET.write_text(result, encoding='utf-8')
    print(f'PASS: {len(build()["entrances"])} Pathly entrance coordinates with complete building/gate coverage')

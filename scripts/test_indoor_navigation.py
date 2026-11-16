"""Check the imported public data and the non-executable data-literal reader."""
import json
import math
from pathlib import Path
import unittest

from sync_pathly_data import literal
from build_campus_entrances import build

ROOT = Path(__file__).resolve().parents[1]


class PathlyDataTests(unittest.TestCase):
    def test_bundled_entrances_match_reviewed_alignments(self):
        data = json.loads((ROOT / 'NEU-Lumen/Resources/CampusEntrances.json').read_text(encoding='utf-8'))
        self.assertEqual(data, build())
        self.assertEqual(len(data['entrances']), 57)
        self.assertFalse(data['fieldVerified'])
        # Distinct gates in each building must never collapse to the building centre.
        by_building = {}
        for point in data['entrances']:
            by_building.setdefault(point['buildingID'], []).append((point['latitude'], point['longitude']))
        for points in by_building.values():
            self.assertEqual(len(points), len(set(points)))

    def test_data_literals_do_not_execute_expressions(self):
        value, end = literal('{x:.5,1e3:{x:2,y:3},rooms:["A102",{name:"A",value:"G01"}]}', 0)
        self.assertEqual(value['1000'], {'x': 2, 'y': 3})
        self.assertEqual(value['x'], .5)
        self.assertGreater(end, 0)
        for expression in ('{x:process.exit(1)}', '{x:1+2}', '{x:1,x:2}', '{x:()=>1}'):
            with self.subTest(expression=expression), self.assertRaises(ValueError):
                literal(expression, 0)

    def test_published_building_and_coordinate_coverage(self):
        data = json.loads((ROOT / 'NEU-Lumen/Resources/PathlyCatalog.json').read_text(encoding='utf-8'))
        buildings = data['buildings']
        self.assertEqual(len(buildings), 19)
        self.assertEqual(len({b['id'] for b in buildings}), 19)
        self.assertEqual(sum(b['campus'] == 'main' for b in buildings), 13)
        self.assertEqual(sum(b['campus'] == 'south' for b in buildings), 6)
        self.assertEqual(data['source'], 'https://pathly.top')
        for building in buildings:
            self.assertTrue(building['floors'])
            self.assertTrue(building['maps'])
            for name, points in building['maps'].items():
                self.assertTrue(name.startswith(building['id'] + '-'))
                for point in points.values():
                    self.assertTrue(all(math.isfinite(point[k]) and 0 <= point[k] <= 100 for k in ('x', 'y')))
        self.assertGreater(len(data['sourceHashes']), 19)


if __name__ == '__main__': unittest.main()

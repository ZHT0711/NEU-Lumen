"""Native schedule equivalence, cache behavior and optimized data-preparation benchmark."""
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class SchedulePerformanceTests(unittest.TestCase):
    def test_native_schedule_pipeline(self):
        swift = shutil.which('swiftc')
        if not swift:
            self.skipTest('Swift compiler unavailable on this host')
        sources = [
            'Core/Support/JSONHelpers.swift', 'Core/Models/PortalModels.swift',
            'Core/Models/CourseModels.swift', 'Core/Models/HolidayRules.swift',
            'Core/Models/SystemAgendaReadPolicy.swift', 'Core/Services/Semester.swift',
        ]
        with tempfile.TemporaryDirectory(prefix='lumen-schedule-') as temporary:
            binary = Path(temporary) / 'schedule-tests'
            subprocess.run([swift, '-swift-version', '5', '-warnings-as-errors', '-O',
                            *[str(ROOT / 'NEU-Lumen' / path) for path in sources],
                            str(ROOT / 'Tests/SchedulePerformance/main.swift'), '-o', str(binary)], check=True)
            subprocess.run([str(binary)], check=True)


if __name__ == '__main__':
    unittest.main(verbosity=2)

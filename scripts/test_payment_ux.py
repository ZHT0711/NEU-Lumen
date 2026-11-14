"""Native payment cache behavior; never contacts a school or creates an order."""
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class PaymentUXTests(unittest.TestCase):
    @unittest.skipUnless(shutil.which('swiftc'), 'Swift compiler is unavailable')
    def test_native_drafts_and_bill_presentation(self):
        with tempfile.TemporaryDirectory() as directory:
            executable = Path(directory) / 'payment-tests'
            files = ['NEU-Lumen/Core/Support/JSONHelpers.swift',
                     'NEU-Lumen/Core/Models/NativeServiceDocument.swift',
                     'NEU-Lumen/Core/Models/NativeFormDraftCache.swift',
                     'NEU-Lumen/Core/Models/CardModels.swift',
                     'NEU-Lumen/Core/Models/NativePaymentPresentation.swift',
                     'Tests/Payment/main.swift']
            result = subprocess.run(['swiftc', '-swift-version', '5', *[str(ROOT / f) for f in files], '-o', str(executable)],
                                    capture_output=True, text=True, encoding='utf-8')
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertNotRegex(result.stdout + result.stderr, r'(?im)\bwarning:')
            result = subprocess.run([str(executable)], capture_output=True, text=True, encoding='utf-8')
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_bill_refresh_never_mislabels_another_month(self):
        source = (ROOT / 'NEU-Lumen/Core/Services/PortalRepository.swift').read_text(encoding='utf-8')
        bills = source.split('func loadBills(', 1)[1].split('func shiftBillsMonth(', 1)[0]
        self.assertLess(bills.index('cardBills = billsCache[key] ?? []'), bills.index('billsState = .loading'))
        self.assertIn('billsUpdatedAt = billsDates[key]', bills)
        self.assertIn('billsWarning = "本次查询失败', bills)
        view = (ROOT / 'NEU-Lumen/Features/Services/NativeCampusPages.swift').read_text(encoding='utf-8').split('struct NativeVPNView:', 1)[0]
        self.assertNotIn('cardBills.prefix(', view)
        self.assertIn('loadBills(force: true)', view)


if __name__ == '__main__':
    unittest.main()

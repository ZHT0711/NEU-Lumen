"""The native HTTP-only card service needs its own ATS domain exception."""
from pathlib import Path
import plistlib
import unittest


class TransportPolicyTests(unittest.TestCase):
    def test_card_http_is_explicitly_allowed_for_url_session(self):
        path = Path(__file__).resolve().parents[1] / 'NEU-Lumen/Info.plist'
        ats = plistlib.loads(path.read_bytes())['NSAppTransportSecurity']
        self.assertTrue(ats['NSAllowsArbitraryLoadsInWebContent'])
        self.assertTrue(ats['NSExceptionDomains']['ecard.neu.edu.cn']['NSExceptionAllowsInsecureHTTPLoads'])
        self.assertNotIn('pass.neu.edu.cn', ats['NSExceptionDomains'])


if __name__ == '__main__':
    unittest.main()

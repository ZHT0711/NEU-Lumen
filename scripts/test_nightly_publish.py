import os
import unittest
from unittest.mock import patch

import check_build_diagnostics
import publish_manual_nightly


class NightlyPublishTests(unittest.TestCase):
    def test_beijing_date_and_retry_stability(self):
        identity = publish_manual_nightly.release_identity('2026-11-04T19:17:00Z', '61')
        self.assertEqual(identity, ('nightly-20261105-031700-61', '2026-11-05 03:17:00', '20261105-031700'))
        self.assertEqual(identity, publish_manual_nightly.release_identity('2026-11-04T19:17:00Z', '61'))
        self.assertNotEqual(identity, publish_manual_nightly.release_identity('2026-11-04T19:17:00Z', '62'))

    def test_automatic_events_do_not_publish_dated_releases(self):
        for event in ['push', 'schedule', 'pull_request']:
            with patch.dict(os.environ, {'GITHUB_EVENT_NAME': event}), patch('publish_manual_nightly.gh') as gh:
                publish_manual_nightly.main()
                gh.assert_not_called()

    def test_warning_detection(self):
        self.assertEqual(check_build_diagnostics.warnings('Build succeeded\n0 warnings'), [])
        for text in ['file.swift:1: warning: example', 'DeprecationWarning: example', '::warning::example']:
            self.assertEqual(check_build_diagnostics.warnings(text), [text])


if __name__ == '__main__':
    unittest.main()

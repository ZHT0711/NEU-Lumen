"""Notification policy execution and background registration source contracts."""
from pathlib import Path
import argparse
import plistlib
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]

class CampusReminderTests(unittest.TestCase):
    def test_background_registration_matches_bundle(self):
        info = plistlib.loads((ROOT/'NEU-Lumen/Info.plist').read_bytes())
        source = (ROOT/'NEU-Lumen/Core/Services/CampusBackgroundRefresh.swift').read_text(encoding='utf-8')
        app = (ROOT/'NEU-Lumen/App/NEULumenApp.swift').read_text(encoding='utf-8')
        self.assertEqual(info['BGTaskSchedulerPermittedIdentifiers'], ['edu.neu.lumen.refresh'])
        self.assertIn('fetch', info['UIBackgroundModes'])
        for key in ['BGTaskScheduler.shared.register', 'refresh.expirationHandler', 'operation.cancel()', 'setTaskCompleted',
                    'request.earliestBeginDate', 'schedule()', 'session.requestEpoch == epoch', 'saved.user.isSameAccount(as: user)']:
            self.assertIn(key, source)
        self.assertIn('@UIApplicationDelegateAdaptor(CampusApplicationDelegate.self)', app)

    def test_notification_mutations_are_account_scoped(self):
        source = (ROOT/'NEU-Lumen/Core/Services/CampusReminderStore.swift').read_text(encoding='utf-8')
        for key in ['account == accountKey', 'generation == epoch', 'request == token', 'removePendingNotificationRequests',
                    'removeDeliveredNotifications', 'preferences.detailsOnLockScreen', 'UNCalendarNotificationTrigger',
                    'UNNotificationAction(identifier: "SNOOZE_10"', 'restoring = true']:
            self.assertIn(key, source)
        self.assertNotIn('registerForRemoteNotifications', source)

    def test_actual_foundation_policy(self):
        swift = shutil.which('swiftc')
        if not swift: self.skipTest('Swift compiler unavailable on this host')
        with tempfile.TemporaryDirectory(prefix='lumen-reminders-') as temporary:
            binary = Path(temporary)/'reminder-tests'
            subprocess.run([swift, '-swift-version', '5', '-warnings-as-errors',
                            str(ROOT/'NEU-Lumen/Core/Models/CampusReminders.swift'), str(ROOT/'Tests/Notifications/main.swift'),
                            '-o', str(binary)], check=True)
            subprocess.run([str(binary)], check=True)

if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--require-swift', action='store_true')
    args = parser.parse_args()
    if args.require_swift and not shutil.which('swiftc'): raise SystemExit('Swift notification policy checks require swiftc')
    result = unittest.TextTestRunner(verbosity=2).run(unittest.defaultTestLoader.loadTestsFromTestCase(CampusReminderTests))
    raise SystemExit(0 if result.wasSuccessful() else 1)

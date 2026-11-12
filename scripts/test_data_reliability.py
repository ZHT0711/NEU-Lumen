"""Offline source contracts; these checks do not compile or execute Swift."""
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[1]
REPO = (ROOT / 'NEU-Lumen/Core/Services/PortalRepository.swift').read_text()
CLIENT = (ROOT / 'NEU-Lumen/Core/Networking/PortalClient.swift').read_text()
POLICY = (ROOT / 'NEU-Lumen/Core/Models/DataReliability.swift').read_text()
HOME = (ROOT / 'NEU-Lumen/Features/Home/HomeView.swift').read_text()
CARD = (ROOT / 'NEU-Lumen/Features/Card/CardView.swift').read_text()
SCHEDULE = (ROOT / 'NEU-Lumen/Features/Schedule/ScheduleView.swift').read_text()


def section(text, start, end):
    return text.split(start, 1)[1].split(end, 1)[0]


class DataReliabilityContracts(unittest.TestCase):
    def test_home_aggregate_validates_before_write(self):
        home = section(REPO, 'func refreshHome(', 'func dataCardURL(')
        guard = home.index('guard isCurrent(context), request == homeRequestID')
        self.assertLess(home.index('await (cards, appList, newsList, todoList, hot)'), guard)
        self.assertLess(guard, home.index('dataCards = value'))
        self.assertIn('guard !Task.isCancelled', home)
        self.assertNotIn('fetchApps()', home)
        self.assertIn('loadAppsIfNeeded(force: force)', home)

    def test_first_recovery_success_is_checked(self):
        recovery = section(REPO, 'private func withRecovery', 'private func run')
        self.assertRegex(recovery, r'let value = try await operation\(\)\s+try checkRequest\(\)\s+return value')
        self.assertIn('epoch == session.requestEpoch', recovery)
        self.assertIn('retryInterruptedRequest', recovery)
        self.assertIn('PortalAPIError)?.requiresAuthentication', recovery)

    def test_apps_share_owned_task_and_explicit_cache_owner(self):
        apps = section(REPO, 'func loadAppsIfNeeded(', 'func loadHotSearchIfNeeded(')
        self.assertIn('if let task = appsTask { return await task.value }', apps)
        self.assertIn('request == self.appsRequestID, !Task.isCancelled', apps)
        self.assertIn('self.saveAppsCache(account: context.account)', apps)
        self.assertNotIn('session.user', apps)
        self.assertIn('self.appsTask = nil', apps)

    def test_room_selection_invalidates_before_loading(self):
        setter = section(REPO, 'var electricRoomCode:', 'private var monthKey:')
        for value in ['ElectricRoomKey.normalize(newValue)', 'electricTask?.cancel()', 'electricRequestID = UUID()', 'electricInfo = cached?.info', 'context.account']:
            self.assertIn(value, setter)
        self.assertNotIn('string(forKey: "lumen.electric.room")', REPO)
        electric = section(REPO, 'func loadElectric(', 'func loadBills(')
        self.assertNotIn('cardState == .loading', electric)
        self.assertIn('key.room == self.electricRoom', electric)
        self.assertIn('self.electricRequestID == request', electric)
        self.assertIn('self.electricCache[key]', electric)
        self.assertIn('self.electricWarning', electric)

    def test_resource_freshness_and_force_are_separate(self):
        for name in ['loadCardOverview', 'loadCardBalance', 'loadNetInfo', 'loadElectric']:
            self.assertIn(f'func {name}(force: Bool = false)', REPO)
        for value in ['wallet: TimeInterval = 60', 'electric: TimeInterval = 120', 'age >= 0 && age < lifetime']:
            self.assertIn(value, POLICY)
        self.assertIn('repo.loadElectric(force: true)', CARD)
        self.assertIn('repo.loadNetInfo(force: true)', CARD)
        self.assertIn('cardBalanceWithWebRecovery()', REPO)

    def test_week_errors_are_not_overwritten_by_other_weeks(self):
        week = section(REPO, 'func loadWeek(', 'func portalOccurrences(')
        self.assertIn('self.weekStates[weekStart] = .failed', week)
        self.assertNotIn('weekState = .loaded', week)
        self.assertIn('self.weekRequests[weekStart] == request', week)
        self.assertIn('repo.displayWeekState(starting: weekStartSunday)', SCHEDULE)
        self.assertIn('requiredPortalWeeks(from: first, to: end)', REPO)
        self.assertIn('replacementsLoaded', REPO)
        export = (ROOT / 'NEU-Lumen/Features/Schedule/SystemCalendarSheet.swift').read_text()
        self.assertIn('displayWeekIsLoaded', export)

    def test_home_empty_requires_complete_data(self):
        self.assertIn('timeline.isEmpty && status == .loaded', HOME)
        for state in ['.unread', '.loading', '.failed', '.partial']:
            self.assertIn('case ' + state, HOME)
        next_course = section(REPO, 'func nextCourse(', 'private func activityRange')
        self.assertIn('activitySchedule(now: now).next', next_course)

    def test_http_envelope_and_empty_shape_are_validated(self):
        api = section(CLIENT, 'private func api(', 'func fetchWeek(')
        self.assertIn('guard (200..<300).contains(resp.status)', api)
        self.assertIn('PortalEnvelope.data(status: resp.status, body: resp.body)', api)
        self.assertIn('let dayMap = try PortalEnvelope.days(d)', CLIENT)
        self.assertNotIn('return j.obj("d")', api)
        self.assertIn('case .httpStatus(403)', POLICY)
        self.assertIn('if case .authenticationRequired = self { return true }', POLICY)

    def test_grade_cancellation_does_not_save_partial_report(self):
        grades = section(CLIENT, 'private func fetchGradeReport(', 'func browserLoginEntryURL(')
        self.assertLess(grades.index('NetworkError.isCancellation(error)'), grades.index('failed.append(term.name)'))
        self.assertGreaterEqual(grades.count('try Task.checkCancellation()'), 3)
        loading = section(REPO, 'func loadGrades(', 'func applyGradeReport(')
        self.assertIn('withRecovery(retryInterruptedRequest: false)', loading)
        self.assertIn('gradesState = gradesCache == nil ? .idle : .loaded', loading)

    def test_missing_wallet_values_are_not_zero(self):
        for invalid in ['balance?.balance ?? 0', 'net?.balance ?? 0', 'info.remainKwh ?? 0']:
            self.assertNotIn(invalid, CARD)
        for value in ['repo.netWarning', 'repo.electricWarning', 'repo.electricUpdatedAt', 'repo.netUpdatedAt']:
            self.assertIn(value, CARD)
        self.assertIn('LiveActivitySchedule.interval(for: occurrence)', SCHEDULE)
        self.assertIn('.weekday(.wide)', SCHEDULE)


if __name__ == '__main__':
    unittest.main()

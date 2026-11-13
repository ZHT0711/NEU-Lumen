"""Offline academic contracts + actual JS; Swift parser/policy runs if swiftc exists.
No real account, network access, automatic login, or school write operations.
Run: python3 scripts/test_academic_queries.py [--require-swift]
"""
from pathlib import Path
import argparse
import re
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
CORE = ROOT / 'NEU-Lumen/Core'
MODELS = CORE / 'Models'
CLIENT = (CORE / 'Networking/PortalClient.swift').read_text()
REPO = (CORE / 'Services/PortalRepository.swift').read_text()
MODEL = (MODELS / 'AcademicQueries.swift').read_text()
PARSER = (MODELS / 'AcademicQueryParser.swift').read_text()
READER = (MODELS / 'AcademicPageReader.swift').read_text()
WEB = (ROOT / 'NEU-Lumen/Features/Academic/AcademicWebSyncSheet.swift').read_text()
ACADEMIC = REPO.split('// MARK: - 原生教务只读查询', 1)[1].split('// MARK: - 一卡通 / 网费 / 电费', 1)[0]

class AcademicContracts(unittest.TestCase):
    def test_allowlist_only_confirmed_get_queries(self):
        paths = re.findall(r'"(api/[^"?]+\.do)', MODEL)
        self.assertEqual(set(paths), {'api/home/student/schoolCalendars.do', 'api/home/student/educational-program.do',
            'api/home/homeSchoolCalendar.do', 'api/home/student/academic-status.do', 'api/home/teachingSchedule/classWeek.do'})
        request = CLIENT.split('func fetchAcademicQuery(', 1)[1].split('func fetchJwxtGrades(', 1)[0]
        self.assertNotIn('http.post', request)
        self.assertEqual(request.count('validateIdentity('), 2)
        self.assertEqual(request.count('jwxtGet("api/home/currentUser.do")'), 2)
        self.assertIn('expectedAccount: context.account', ACADEMIC)

    def test_no_demo_or_persistent_academic_data(self):
        self.assertNotIn('DemoData', ACADEMIC)
        self.assertNotIn('UserDefaults', ACADEMIC)
        self.assertNotIn('CredentialStore', ACADEMIC)
        self.assertIn('#if DEBUG', ACADEMIC)
        self.assertNotIn('seedAcademicPreview(', (ROOT/'NEU-Lumen/Features/Academic/AcademicCenterView.swift').read_text())

    def test_epoch_generation_and_request_checked_before_write(self):
        self.assertIn('guard self.isCurrent(context), self.academicRequests[key] == request', ACADEMIC)
        self.assertIn('academicTasks[key]?.cancel()', ACADEMIC)
        self.assertIn('if !force, let task = academicTasks[key]', ACADEMIC)
        self.assertIn('withTaskCancellationHandler', ACADEMIC)
        self.assertIn('session.user?.sid == context.account', ACADEMIC)
        reset = REPO.split('func ensureLoadedForCurrentUser()',1)[1].split('private func withRecovery',1)[0]
        for name in ['academicCache','academicStates','academicDates','academicWarnings','academicTasks','academicRequests']:
            self.assertIn(name+'.removeAll()', reset)
        self.assertIn('academicPageCache = nil', reset)

    def test_failures_keep_previous_timestamp_and_values(self):
        catch = ACADEMIC.split('} catch {',1)[1].split('academicTasks[key] = task',1)[0]
        self.assertNotIn('academicDates[key] =', catch)
        self.assertNotRegex(catch, r'academicCache\[key\]\s*=(?!=)')
        self.assertIn('self.academicWarnings[key]', catch)
        self.assertIn('self.academicCache[key] == nil ? .idle : .loaded', catch)

    def test_exact_envelope_and_missing_values_not_zero(self):
        self.assertIn('code == "0"', PARSER)
        self.assertIn('map["datas"]', PARSER)
        self.assertNotIn('?? 0', PARSER)
        for field in ['itemCode','itemName','selected','planId','planName','academicRate','academicUnusual','flunkList','classWeek','startDate','endDate']:
            self.assertIn('"'+field+'"', PARSER)
        self.assertNotIn('nutrientSum', PARSER)

    def test_page_sync_is_read_only_account_scoped(self):
        script = READER.split('static let browserScript = #"""',1)[1].split('"""#',1)[0]
        for forbidden in ['.click(', '.submit(', 'XMLHttpRequest(', 'localStorage', 'password', "method:'POST'", 'collect-growthvalue', 'record-failscore']:
            self.assertNotIn(forbidden, script)
        self.assertIn("method:'GET'", script)
        self.assertIn('await identity() !== account', script)
        self.assertIn('expectedSourceURL', READER)
        self.assertIn('.nonPersistent()', WEB)
        self.assertIn('static let readerWorld = WKContentWorld.world(name: "NEULumen.AcademicReader")', WEB)
        self.assertIn('contentWorld: Self.readerWorld)', WEB)
        self.assertNotIn('contentWorld: .page)', WEB)
        self.assertNotIn('absorbBrowserCookies', WEB)
        self.assertNotIn('persistWebSession', WEB)

    def test_calendar_does_not_replace_personal_calibration(self):
        view = (ROOT/'NEU-Lumen/Features/Academic/AcademicCalendarView.swift').read_text()
        self.assertNotIn('SemesterSettings', view)
        self.assertNotIn('UserDefaults', view)
        self.assertIn('environment.session.requestEpoch.uuidString', view)
        self.assertIn('暂不可原生读取', view)

    def test_original_portal_routes_and_single_native_entry(self):
        navigation = (ROOT/'NEU-Lumen/App/Navigation.swift').read_text()
        services = (ROOT/'NEU-Lumen/Features/Services/ServicesView.swift').read_text()
        profile = (ROOT/'NEU-Lumen/Features/Profile/ProfileView.swift').read_text()
        grades = (ROOT/'NEU-Lumen/Features/Grades/GradesView.swift').read_text()
        self.assertNotIn('nativeDestination', navigation)
        self.assertIn('return .web(url)', navigation)
        self.assertIn('NativeServicesCarousel(services: services)', services)
        self.assertEqual(services.count('path.append(.nativeService(service))'), 1)
        self.assertNotIn('AcademicCenterView()', grades)
        self.assertNotIn('AcademicCenterView()', profile.split('var body:',1)[1].split('.navigationDestination',1)[0])

    def test_navigation_and_accessibility_contract(self):
        hub = (ROOT/'NEU-Lumen/Features/Academic/AcademicCenterView.swift').read_text()
        plan = (ROOT/'NEU-Lumen/Features/Academic/AcademicPlanView.swift').read_text()
        self.assertIn('@Environment(AppEnvironment.self)', hub)
        self.assertIn('NavigationLink { AcademicCalendarView()', hub)
        self.assertIn('NavigationLink { AcademicPlanView()', hub)
        self.assertNotIn('academicMode: true', hub+plan+WEB)
        self.assertIn('accessibilityElement(children: .combine)', plan)
        self.assertIn('AcademicWebSyncSheet(plan: plan)', plan)
        self.assertIn('repo.restoreAcademicPlan(id)', plan)

if __name__ == '__main__':
    args = argparse.ArgumentParser()
    args.add_argument('--require-swift', action='store_true')
    options = args.parse_args()
    result = unittest.TextTestRunner(verbosity=2).run(unittest.defaultTestLoader.loadTestsFromTestCase(AcademicContracts))
    if not result.wasSuccessful(): raise SystemExit(1)
    if not shutil.which('node'): raise SystemExit('node is required for the actual read-only JavaScript tests')
    subprocess.run(['node', str(ROOT/'Tests/Academic/reader.mjs')], check=True, cwd=ROOT)
    swift = shutil.which('swiftc')
    if swift:
        sources = [MODELS/'AcademicQueries.swift', MODELS/'AcademicQueryParser.swift', MODELS/'AcademicPageReader.swift',
                   MODELS/'AcademicPlanPresentation.swift', CORE/'Persistence/AcademicPlanCacheStore.swift',
                   MODELS/'DataReliability.swift', CORE/'Support/LoadState.swift', ROOT/'Tests/Academic/main.swift']
        with tempfile.TemporaryDirectory(prefix='lumen-academic-') as tmp:
            binary = Path(tmp)/'academic-tests'
            subprocess.run([swift, '-swift-version', '5', '-warnings-as-errors', *map(str,sources), '-o',str(binary)], check=True)
            subprocess.run([str(binary), str(ROOT/'Tests/Academic/fixtures/synthetic.json')], check=True, cwd=ROOT)
    elif options.require_swift:
        raise SystemExit('Swift parser/policy tests NOT RUN: swiftc is unavailable')
    else:
        print('SKIP Swift parser/policy execution: swiftc unavailable; source contracts and actual JS passed. No Xcode/iOS build claimed.')

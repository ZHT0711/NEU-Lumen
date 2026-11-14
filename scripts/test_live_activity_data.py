"""Linux source/asset contracts, not a substitute for the native Swift tests."""
from pathlib import Path
import struct
import unittest
import zlib
import package_ui_preview as preview

ROOT = Path(__file__).resolve().parents[1]
REPOSITORY = (ROOT / 'NEU-Lumen/Core/Services/PortalRepository.swift').read_text()
COORDINATOR = (ROOT / 'NEU-Lumen/Features/LiveActivity/LiveActivitySettingsView.swift').read_text()


class LiveActivityDataContracts(unittest.TestCase):
    def test_all_sources_publish_and_future_selection_is_shared(self):
        state = REPOSITORY.split('func liveActivityState(', 1)[1]
        for kind in ['nextCourse', 'cardBalance', 'netBalance', 'electricBalance', 'assignments', 'planner', 'dayOverview', 'academicOverview', 'custom']:
            self.assertIn('.' + kind, state)
        self.assertNotIn('case .netBalance, .electricBalance, .assignments, .dayOverview, .academicOverview:', state)
        next_course = REPOSITORY.split('func nextCourse(', 1)[1].split('private func activityRange', 1)[0]
        self.assertIn('activitySchedule(now: now).next', next_course)
        self.assertNotIn('todayTimeline()', next_course)
        self.assertIn('dayOnly ? 1 : 7', REPOSITORY)
        self.assertIn('let schedule = activitySchedule(now: now, localOnly: local)', state)

    def test_loading_is_foreground_account_mode_day_scoped(self):
        self.assertIn('.task(id: loadKey)', COORDINATOR)
        self.assertIn('loadKey.foreground, loadKey.enabled, loadKey.account != nil', COORDINATOR)
        self.assertIn('day: PortalDate.isoDay(context.date)', COORDINATOR)
        self.assertNotIn('.task(id: context.date)', COORDINATOR)
        self.assertIn('prepareLiveActivityData(for: store, force: true)', COORDINATOR)
        prepare = REPOSITORY.split('func prepareLiveActivityData(', 1)[1].split('// MARK: - 成绩', 1)[0]
        self.assertIn('case .planner, .assignments, .custom:', prepare)
        self.assertNotIn('loadCGAssignments', prepare)

    def test_optional_payload_and_countdown_target_contract(self):
        attributes = (ROOT / 'NEU-Lumen/Core/Services/DynamicIslandActivityAttributes.swift').read_text()
        self.assertIn('typealias ContentState = LiveActivityContentState', attributes)
        attributes += (ROOT / 'NEU-Lumen/Core/Models/LiveActivityPresentation.swift').read_text()
        for field, kind in [('accent', 'String'), ('symbolName', 'String'), ('secondaryValue', 'String'), ('progress', 'Double'), ('countdownTitle', 'String'), ('destinationPath', 'String'), ('detailItems', '[LiveActivityDetail]'), ('phase', 'String')]:
            self.assertIn(f'var {field}: {kind}? = nil', attributes)
        widget = (ROOT / 'NEU-LumenLiveActivity/NEULumenLiveActivity.swift').read_text()
        self.assertIn('countdownTitle == "距开始"', attributes)
        self.assertIn('countdownTitle == "距上课"', attributes)
        self.assertIn('state.countdownDate', widget)
        compact = widget.split('} compactTrailing: {', 1)[1].split('} minimal:', 1)[0]
        self.assertIn('Text(timerInterval:', compact)
        self.assertIn('func boundedText()', attributes)
        self.assertIn('encoder.encode(copy).count', attributes)
        self.assertIn('var staleAfter: Date? = nil', attributes)
        self.assertIn('activityAccent(context.state.accent)', widget)
        self.assertNotIn('Text("距下课")', widget)
        self.assertIn('let query = kind == "academicOverview"', attributes)
        self.assertIn('pendingLearningSection', (ROOT / 'NEU-Lumen/App/MainTabView.swift').read_text())
        self.assertIn('pendingLearningSection', (ROOT / 'NEU-Lumen/Features/Grades/GradesView.swift').read_text())

    def test_all_nine_sources_have_fact_based_expanded_metadata(self):
        state = REPOSITORY.split('func liveActivityState(', 1)[1]
        expected = {
            'nextCourse, .planner': ['expandedDetails(for: next', 'planner.events.first', 'phase: ongoing'],
            'cardBalance': ['cardBalance?.status', 'cardBalance?.subsidy', 'syncDetail(updatedAt)'],
            'netBalance': ['net.flowFromPortal', 'net.usageFacts', 'syncDetail(netUpdatedAt)'],
            'electricBalance': ['electric.roomLabel', 'electric.roomNo', 'electric.lastReadAt', 'electric.unbound'],
            'assignments': ['assignments.loadedPlatformCount', 'assignments.completedCount', 'next.deadline', 'details: nearestDetails'],
            'dayOverview': ['courseCount', 'schedule.remainingCount', 'next.occurrence.slot.name', 'min(dayEnd, boundary)'],
            'academicOverview': ['academic.semester?.name', 'academic.credits', 'academic.weightedAverage', 'academic.scoredCount'],
            'custom': ['store.customSubtitle', 'store.customValue', 'customDetails', 'snapshot.expiration', 'store.customIcon'],
        }
        for source, fields in expected.items():
            with self.subTest(source=source):
                block = state.split('case .' + source + ':', 1)[1].split('\n        case .', 1)[0]
                for field in fields:
                    self.assertIn(field, block)
                self.assertIn('details:', block)
        model = (ROOT / 'NEU-Lumen/Core/Models/LiveActivityPresentation.swift').read_text()
        self.assertIn('maximumDetails = 6', model)
        self.assertIn('payloadBudget = 3200', model)
        self.assertIn('fields.append(row.value); fields.append(row.label)', model)
        self.assertIn('isTimeSensitive != true', model)
        self.assertIn('displaySecondary(isStale:', model)
        self.assertIn('freshnessDeadline', model)
        manager = (ROOT / 'NEU-Lumen/Core/Services/DynamicIslandActivityManager.swift').read_text()
        self.assertIn('state.freshnessDeadline', manager)
        for guard in ['ActivityAuthorizationInfo().areActivitiesEnabled', '$0.attributes.accountID == request.accountID',
                      'stateBytes + attributeBytes < 4000', 'state = state.boundedText()']:
            self.assertIn(guard, manager)

    def test_net_usage_presence_is_independent_and_never_fabricated(self):
        models = (ROOT / 'NEU-Lumen/Core/Models/CardModels.swift').read_text()
        client = (ROOT / 'NEU-Lumen/Core/Networking/PortalClient.swift').read_text()
        self.assertIn('NetUsageInfo.fromPortal(balance: finalBalance, bytes: bytes, seconds: seconds, times: times)', client)
        self.assertIn('Int64(exactly: $0)', client)
        self.assertIn('secondsFromPortal: s != nil, timesFromPortal: t != nil', models)
        self.assertIn('if secondsFromPortal && monthSeconds >= 0', models)
        self.assertIn('if timesFromPortal && monthTimes >= 0', models)
        self.assertIn('let usage = net.usageFacts.map', REPOSITORY)
        native = (ROOT / 'Tests/LiveActivity/main.swift').read_text()
        for case in ['missingNetCounts', 'zeroNetCounts', 'partialNetCounts', 'invalidNetCounts']:
            self.assertIn(case, native)

    def test_native_regressions_use_production_schema_and_geometry(self):
        native = (ROOT / 'Tests/LiveActivity/main.swift').read_text()
        for executable_check in ['JSONDecoder().decode(LiveActivityContentState.self', 'liveEncoder.encode(bounded)',
                                 'bounded.boundedText() == bounded', 'metricPlan(width: width',
                                 'plan.label.intersects(plan.value)', 'expandedDetails(for: detailedSchedule.next!',
                                 'irregularDetails', 'manualDetails']:
            self.assertIn(executable_check, native)

    def test_emblem_is_rgba_and_corner_is_transparent(self):
        raw = (ROOT / 'NEU-Lumen/Assets.xcassets/FutureTechnologyEmblem.imageset/emblem.png').read_bytes()
        self.assertEqual(raw[:8], b'\x89PNG\r\n\x1a\n')
        width, height, depth, kind = struct.unpack('>IIBB', raw[16:26])
        self.assertEqual((width, height, depth, kind), (512, 512, 8, 6))
        data, position = bytearray(), 8
        while position < len(raw):
            length = struct.unpack('>I', raw[position:position + 4])[0]
            if raw[position + 4:position + 8] == b'IDAT':
                data.extend(raw[position + 8:position + 8 + length])
            position += 12 + length
        # At the top-left pixel all predictors are zero for every PNG filter.
        self.assertEqual(zlib.decompress(data)[4], 0)

    def test_native_and_real_repository_checks_gate_publication(self):
        workflow = (ROOT / '.github/workflows/build-unsigned.yml').read_text()
        self.assertIn('Tests/LiveActivity/main.swift', workflow)
        self.assertIn('live-activity-data-tests.log', workflow)
        self.assertIn('live-activity-data-checks.txt', preview.CHECKS)
        shell = (ROOT / 'scripts/validate_ui.sh').read_text()
        self.assertIn('--live-activity-data-checks', shell)
        self.assertIn('live-activity-custom', shell)
        self.assertEqual(len(preview.SCREENSHOTS), 49)
        for kind in ['nextCourse', 'cardBalance', 'netBalance', 'electricBalance', 'assignments', 'planner', 'dayOverview', 'academicOverview', 'custom']:
            self.assertIn(f'live-expanded-{kind}-light.png', preview.SCREENSHOTS)
        self.assertIn('live-activity-layout-checks.txt', preview.CHECKS)
        self.assertIn('PBXFileSystemSynchronizedRootGroup', (ROOT / 'NEU-Lumen.xcodeproj/project.pbxproj').read_text())


if __name__ == '__main__':
    unittest.main()

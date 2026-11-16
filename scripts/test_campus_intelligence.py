"""Native intelligence policy/cache tests use an injected generator; no real model or account."""
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class CampusIntelligenceTests(unittest.TestCase):
    def test_native_policy_and_generation_lifecycle(self):
        swift = shutil.which('swiftc')
        if not swift:
            self.skipTest('Swift compiler unavailable on this host')
        sources = ['Core/Support/JSONHelpers.swift', 'Core/Models/PortalModels.swift',
                   'Core/Models/HTMLInputFields.swift', 'Core/Models/PortalContent.swift',
                   'Core/Models/CampusIntelligence.swift', 'Core/Services/AppleIntelligenceProvider.swift',
                   'Core/Services/CampusIntelligenceStore.swift']
        with tempfile.TemporaryDirectory(prefix='lumen-intelligence-') as temporary:
            binary = Path(temporary) / 'intelligence-tests'
            subprocess.run([swift, '-swift-version', '5', '-warnings-as-errors',
                            *[str(ROOT / 'NEU-Lumen' / path) for path in sources],
                            str(ROOT / 'Tests/Intelligence/main.swift'), '-o', str(binary)], check=True)
            subprocess.run([str(binary)], check=True, timeout=30)

    def test_optional_ui_uses_real_system_availability(self):
        source = (ROOT / 'NEU-Lumen/Core/Services/AppleIntelligenceProvider.swift').read_text(encoding='utf-8')
        for token in ['canImport(FoundationModels)', '#available(iOS 26.0', 'model.availability',
                      'model.supportsLocale', 'LanguageModelSession', 'generating: CampusGeneratedSummary.self']:
            self.assertIn(token, source)
        self.assertNotIn('URLSession', source)
        self.assertNotIn('apiKey', source)
        root = (ROOT / 'NEU-Lumen/App/AppRootView.swift').read_text(encoding='utf-8')
        self.assertIn('CampusIntelligenceCoordinator()', root)
        view = (ROOT / 'NEU-Lumen/Features/Shared/CampusIntelligenceViews.swift').read_text(encoding='utf-8')
        self.assertIn('key.foreground, key.available, key.preferences.enabled', view)
        self.assertIn('phase == .background', view)
        home = (ROOT / 'NEU-Lumen/Features/Home/HomeView.swift').read_text(encoding='utf-8')
        self.assertLess(home.index('repo.intelligenceDigest(for: .news)'), home.index('if repo.news.isEmpty'))
        profile = (ROOT / 'NEU-Lumen/Features/Profile/ProfileView.swift').read_text(encoding='utf-8')
        self.assertIn('if environment.repository.intelligence.available', profile)

    def test_journey_uses_map_alternatives_and_automatic_replanning(self):
        source = (ROOT / 'NEU-Lumen/Features/Services/CampusJourneyView.swift').read_text(encoding='utf-8')
        self.assertIn('query.requestsAlternateRoutes = true', source)
        self.assertIn('CampusWalkingRoutePolicy.shortestIndex(response.routes.map', source)
        self.assertIn('.task(id: store.selectionKey', source)
        self.assertIn('store.canPlan', source)
        self.assertIn('store.plan()', source)
        self.assertIn('directions?.cancel()', source)
        self.assertNotIn('response.routes.first', source)

    def test_simulator_generator_is_disposable_and_explicitly_synthetic(self):
        fixture = (ROOT / 'scripts/prepare_ui_validation.py').read_text(encoding='utf-8')
        self.assertIn('模拟器合成要闻摘要', fixture)
        production = (ROOT / 'NEU-Lumen/Core/Services/PortalRepository.swift').read_text(encoding='utf-8')
        self.assertNotIn('--screen=home', production)
        self.assertNotIn('模拟器合成要闻摘要', production)


if __name__ == '__main__':
    unittest.main(verbosity=2)

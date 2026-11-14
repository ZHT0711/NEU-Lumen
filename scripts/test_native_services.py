"""Native routing/UI source contracts plus execution of the shipped Coremail reader."""
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT=Path(__file__).resolve().parents[1]

class NativeServicesTests(unittest.TestCase):
    @unittest.skipUnless(shutil.which('swiftc'), 'Swift compiler is unavailable')
    def test_affairs_atomic_refresh_and_exact_retry(self):
        source=(ROOT/'NEU-Lumen/Features/Services/NativeCampusPages.swift').read_text(encoding='utf-8')
        store='import Foundation\nimport Observation\n@MainActor @Observable\nfinal class NativeAffairsStore {'+source.split('final class NativeAffairsStore {',1)[1].split('\nstruct NativeAffairsView:',1)[0]
        with tempfile.TemporaryDirectory() as directory:
            path=Path(directory)
            (path/'NativeAffairsStore.swift').write_text(store,encoding='utf-8')
            executable=path/'native-affairs-tests'
            result=subprocess.run(['swiftc','-swift-version','5','-parse-as-library',str(path/'NativeAffairsStore.swift'),
                                   str(ROOT/'Tests/NativeAffairs/main.swift'),'-o',str(executable)],
                                  capture_output=True,text=True,encoding='utf-8')
            self.assertEqual(result.returncode,0,result.stdout+result.stderr)
            self.assertNotRegex(result.stdout+result.stderr,r'(?im)\bwarning:')
            result=subprocess.run([str(executable)],capture_output=True,text=True,encoding='utf-8')
            self.assertEqual(result.returncode,0,result.stdout+result.stderr)

    def test_electricity_room_prefill(self):
        result=subprocess.run(['node',str(ROOT/'Tests/Learning/electricity-prefill.mjs')],capture_output=True,text=True,encoding='utf-8')
        self.assertEqual(result.returncode,0,result.stdout+result.stderr)

    def test_coremail_script(self):
        result=subprocess.run(['node',str(ROOT/'Tests/Learning/native-mail.mjs')],capture_output=True,text=True,encoding='utf-8')
        self.assertEqual(result.returncode,0,result.stdout+result.stderr)

    @unittest.skipUnless(shutil.which('swiftc'), 'Swift compiler is unavailable')
    def test_news_refresh_retry_and_search_ownership(self):
        source=(ROOT/'NEU-Lumen/Features/Services/NativeNewsView.swift').read_text(encoding='utf-8')
        store=source.split('struct NativeNewsView:',1)[0].replace('import SwiftUI','import Foundation')
        with tempfile.TemporaryDirectory() as directory:
            path=Path(directory)
            (path/'NativeNewsStore.swift').write_text(store,encoding='utf-8')
            executable=path/'native-news-tests'
            result=subprocess.run(['swiftc','-swift-version','5','-parse-as-library',str(path/'NativeNewsStore.swift'),
                                   str(ROOT/'Tests/NativeNews/main.swift'),'-o',str(executable)],
                                  capture_output=True,text=True,encoding='utf-8')
            self.assertEqual(result.returncode,0,result.stdout+result.stderr)
            self.assertNotRegex(result.stdout+result.stderr,r'(?im)\bwarning:')
            result=subprocess.run([str(executable)],capture_output=True,text=True,encoding='utf-8')
            self.assertEqual(result.returncode,0,result.stdout+result.stderr)

    def test_glass_is_on_navigation_with_accessible_fallback(self):
        source=(ROOT/'NEU-Lumen/Features/Services/NativeServicesCarousel.swift').read_text(encoding='utf-8')
        for key in ['GlassEffectContainer','glassEffect(', 'accessibilityReduceTransparency','accessibilityReduceMotion',
                    'colorSchemeContrast','minHeight: 44','tabViewStyle(.page','DisclosureGroup(isExpanded:', '@State private var expanded = false']:
            self.assertIn(key,source)
        self.assertNotIn('Timer.publish',source)

    def test_mail_uses_isolated_world_and_epoch_guards(self):
        source=(ROOT/'NEU-Lumen/Core/Services/NativeMailStore.swift').read_text(encoding='utf-8')
        self.assertIn('contentWorld: Self.world',source)
        self.assertNotIn('contentWorld: .page',source)
        for key in ['session.requestEpoch == ownerEpoch','page == pageGeneration','verifiedPage == pageGeneration','vault.save(snapshot)']:
            self.assertIn(key,source)
        reader=(ROOT/'NEU-Lumen/Core/Models/NativeMail.swift').read_text(encoding='utf-8')
        self.assertNotIn('mbox:compose',reader)
        self.assertNotIn('sendMessages',reader)
        self.assertIn('await getIdentity()!==email',reader)

    def test_new_pages_keep_official_confirmations(self):
        source=(ROOT/'NEU-Lumen/Features/Services/NativeCampusPages.swift').read_text(encoding='utf-8')
        self.assertIn('学校页面核对缴费项目、金额并完成支付',source)
        self.assertIn('session.requestEpoch == epoch',source)
        self.assertIn('fetchTodos(page: target, pageSize: 20)',source)
        self.assertNotIn('DemoData',source)

    def test_form_order_bridge_keeps_school_state_and_one_shot_actions(self):
        bridge=(ROOT/'NEU-Lumen/Core/Models/NativeServiceDocument.swift').read_text(encoding='utf-8')
        for key in ['state.token!==token','state.url!==location.href','state.consumed',
                    'state.hidden.some', 'context(selected.node)!==selected.context', 'form.checkValidity()',
                    "command==='fill'", "el.dispatchEvent(new win.Event('input'", 'el.click()']:
            self.assertIn(key,bridge)
        for forbidden in ['method:', 'fetch(', 'localStorage', '.submit();']:
            self.assertNotIn(forbidden,bridge)
        view=(ROOT/'NEU-Lumen/Features/Services/NativeServiceDocumentView.swift').read_text(encoding='utf-8')
        self.assertIn('session.requestEpoch == epoch',view)
        self.assertIn('contentWorld: Self.world',view)
        self.assertIn('service.owns(host: host)',view)
        self.assertIn('pendingAction = action',view)
        fixture=(ROOT/'Tests/BrowserDownloads/WebKitValidation.swift').read_text(encoding='utf-8')
        self.assertIn('NativeServiceDocument.bridge',fixture)
        self.assertIn('changed order amount invalidates confirmation',fixture)
        self.assertIn('fill never resubmits form',fixture)

if __name__=='__main__': unittest.main()

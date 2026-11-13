"""Native routing/UI source contracts plus execution of the shipped Coremail reader."""
from pathlib import Path
import subprocess
import unittest

ROOT=Path(__file__).resolve().parents[1]

class NativeServicesTests(unittest.TestCase):
    def test_coremail_script(self):
        result=subprocess.run(['node',str(ROOT/'Tests/Learning/native-mail.mjs')],capture_output=True,text=True,encoding='utf-8')
        self.assertEqual(result.returncode,0,result.stdout+result.stderr)

    def test_glass_is_on_navigation_with_accessible_fallback(self):
        source=(ROOT/'NEU-Lumen/Features/Services/NativeServicesCarousel.swift').read_text(encoding='utf-8')
        for key in ['GlassEffectContainer','glassEffect(', 'accessibilityReduceTransparency','accessibilityReduceMotion',
                    'colorSchemeContrast','minHeight: 44','tabViewStyle(.page','scrollTargetBehavior(.viewAligned)']:
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

if __name__=='__main__': unittest.main()

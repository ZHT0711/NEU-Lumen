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

    def test_network_recharge_uses_the_official_account_payment_page(self):
        entries = (ROOT / 'NEU-Lumen/Core/Models/NativeCampusService.swift').read_text(encoding='utf-8')
        self.assertIn('static let netRecharge = URL(string: "https://pay.neu.edu.cn/netdetails51247N005.html")!', entries)
        self.assertIn('[electricity, cardRecharge, netRecharge].first { $0 == url }', entries)
        view = (ROOT / 'NEU-Lumen/Features/Services/NativeCampusPages.swift').read_text(encoding='utf-8')
        network = view.split('Section("校园网络")', 1)[1].split('Section("缴费服务")', 1)[0]
        self.assertIn('Button("充值网费", systemImage: "wifi") { openPaymentURL(CampusPaymentEntry.netRecharge) }', network)
        self.assertIn('.accessibilityIdentifier("payment.netRecharge")', network)
        self.assertNotIn('openPayment()', network)
        for field in ('electricRoomCode', 'elecroomno', 'roomDraft', 'hasUnsavedRoom', '.electricity'):
            self.assertNotIn(field, network)
        self.assertIn('openPayment(path: "/openApplication")', view)
        self.assertIn('openPayment(path: "/orders.html")', view)

    def test_electricity_prefill_cannot_touch_network_or_card_recharge(self):
        browser = (ROOT / 'NEU-Lumen/Features/Web/PortalWebView.swift').read_text(encoding='utf-8')
        prefill = browser.split('func prefillElectricityRoom(', 1)[1].split('private func resumePaymentAfterLogin(', 1)[0]
        self.assertIn('CampusPaymentEntry.isElectricity(url) else { return }', prefill)
        self.assertIn('session.requestEpoch == downloadSessionEpoch', prefill)
        script = (ROOT / 'NEU-Lumen/Core/Models/ElectricityPaymentPrefill.swift').read_text(encoding='utf-8')
        self.assertIn("location.pathname!=='/openPayElecPagesDbdx51414E039.html'", script)
        self.assertNotIn('netdetails51247N005', script)
        negative = (ROOT / 'Tests/Learning/electricity-prefill.mjs').read_text(encoding='utf-8')
        for path in ('/netdetails51247N005.html', '/scardrecharge51264Z006.html'):
            self.assertIn("{pathname:'" + path + "'}", negative)

    def test_payment_resume_is_once_and_stays_in_the_live_account(self):
        source = (ROOT / 'NEU-Lumen/Features/Web/PortalWebView.swift').read_text(encoding='utf-8')
        resume = source.split('private func resumePaymentAfterLogin() async {', 1)[1].split('func webView(_ webView: WKWebView, didFailProvisionalNavigation', 1)[0]
        for guard in ('!Task.isCancelled', '!isClosed', '!webView.isLoading', '!paymentResumeAttempted',
                      'session.phase == .loggedIn', 'session.requestEpoch == downloadSessionEpoch',
                      'client.sessionGeneration == clientEpoch', 'NativeCampusService.payment.allowsNativeDocument(source)'):
            self.assertIn(guard, resume)
        # Anonymous / is a meta-refresh to the login page, not an authenticated landing.
        self.assertNotIn('"/"', resume)
        self.assertLess(resume.index('paymentResumeAttempted = true'), resume.index('webView.load(URLRequest(url: paymentResumeURL))'))
        for unsafe in ('httpBody', 'postForm', '.submit(', 'prefillElectricityRoom(', 'electricRoomCode'):
            self.assertNotIn(unsafe, resume)
        self.assertIn('await resumePaymentAfterLogin()', source)

    def test_payment_pages_remain_separate_and_clear_on_account_change(self):
        view = (ROOT / 'NEU-Lumen/Features/Services/NativeCampusPages.swift').read_text(encoding='utf-8').split('@MainActor @Observable', 1)[0]
        self.assertIn('if paymentBrowsers[url] == nil { paymentBrowsers[url] = PortalBrowser() }', view)
        self.assertIn('retainedBrowser: paymentBrowsers[item.url]', view)
        self.assertIn('roomOwner != environment.session.requestEpoch', view)
        self.assertIn('for browser in paymentBrowsers.values { browser.close() }', view)
        self.assertIn('paymentBrowsers = [:]; web = nil', view)

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

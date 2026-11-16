"""Linux source/layout contracts, NOT an Xcode build or actual iOS UI test.

Run: python3 scripts/test_native_mail_toolbar.py
The width arithmetic checks the declared flexible indicator layout only; SwiftUI
rendering, Dynamic Type and iOS 17/26 glass navigation require simulator validation.
Uses only the Python standard library and never reads or copies private screenshots.
"""
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[1]


class NativeMailToolbarTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        services = ROOT / "NEU-Lumen/Features/Services"
        carousel = (services / "NativeServicesCarousel.swift").read_text(encoding="utf-8")
        mail = (services / "NativeMailView.swift").read_text(encoding="utf-8")
        cls.host = carousel.split("struct NativeServiceHost: View {", 1)[1].split(
            "private struct NativeServiceScrubber: View {", 1)[0]
        cls.scrubber = carousel.split("private struct NativeServiceScrubber: View {", 1)[1].split(
            "struct NativeServiceWebLink:", 1)[0]
        cls.mail = mail.split("struct NativeMailView: View {", 1)[1].split(
            "private enum MailWebReason:", 1)[0]
        cls.reader = mail.split("private struct NativeMailReadingView: View {", 1)[1].split(
            "/// Sending stays an explicit action", 1)[0]
        cls.model = (ROOT / "NEU-Lumen/Core/Models/NativeCampusService.swift").read_text(encoding="utf-8")
        cases = re.search(r"enum NativeCampusService[^\n]*\{\s*case ([^\n]+)", cls.model)
        cls.services = [name.strip() for name in cases.group(1).split(",")]
        cls.batch = cls.mail.split("if active {", 1)[1].split(
            '.accessibilityIdentifier("mail.batch-selection")', 1)[0]

    def test_switcher_is_in_leading_navigation_slot(self):
        body = self.host.split("var body: some View {", 1)[1]
        self.assertIn("VStack(spacing: 0)", body)
        self.assertIn("ToolbarItem(placement: .topBarLeading)", body)
        toolbar = body.split(".toolbar {", 1)[1]
        self.assertIn("NativeServiceScrubber(selected: $selected, preview: $preview)", toolbar)
        self.assertNotIn("placement: .principal", body)
        self.assertNotIn(".safeAreaInset(edge: .top", body)
        self.assertIn('.navigationTitle("")', body)

    def test_pages_are_clipped_and_all_routes_are_retained(self):
        self.assertIn(".tabViewStyle(.page(indexDisplayMode: .never))", self.host)
        self.assertIn(".clipped()", self.host)
        self.assertNotIn(".ignoresSafeArea", self.host)
        tags = re.findall(r"\.tag\(NativeCampusService\.(\w+)\)", self.host)
        self.assertEqual(tags, self.services)
        self.assertIn("NativeMailView(active: selected == .mail)", self.host)
        self.assertNotIn(".id(selected", self.host)

    def test_directory_and_school_web_remain_visible_compact_actions(self):
        toolbar = self.host.split(".toolbar {", 1)[1].split(".sheet(item: $originalWeb)", 1)[0]
        self.assertEqual(toolbar.count("placement: .topBarTrailing"), 2)
        self.assertEqual(toolbar.count(".labelStyle(.iconOnly)"), 2)
        self.assertEqual(toolbar.count(".frame(minWidth: 44, minHeight: 44)"), 2)
        for token in ['Menu("切换服务", systemImage: "square.grid.2x2")',
                      "NativeCampusService.groups", "selected = service",
                      'Button("学校原站", systemImage: "globe")',
                      "selected.entryURL(apps: environment.repository.apps)",
                      '.accessibilityLabel("切换原生服务")',
                      '.accessibilityIdentifier("services.school-web")']:
            self.assertIn(token, toolbar)
        self.assertIn("PortalWebViewScreen(url: link.url)", self.host)

    def test_drag_index_uses_measured_width_not_navigation_title_width(self):
        self.assertIn("GeometryReader { geometry in", self.scrubber)
        self.assertEqual(self.scrubber.count("width: geometry.size.width"), 2)
        self.assertIn("service(at x: CGFloat, width: CGFloat)", self.scrubber)
        self.assertIn("NativeServicePosition.index(at: Double(x), width: Double(width)", self.scrubber)
        self.assertNotIn("144", self.scrubber)
        self.assertIn(".frame(width: 120, height: 44", self.scrubber)
        self.assertIn(".contentShape(Rectangle())", self.scrubber)
        self.assertIn("width > 0, count > 0", self.model)

    def test_preview_and_voiceover_switching_are_preserved(self):
        for token in ["LongPressGesture(minimumDuration: 0.3)", "DragGesture(minimumDistance: 0)",
                      "preview = nil", "onChange(of: dragging)", "sensoryFeedback(.selection",
                      "visible.title", "accessibilityAdjustableAction",
                      "case .increment:", "case .decrement:", 'accessibilityIdentifier("services.scrubber")']:
            self.assertIn(token, self.scrubber)
        self.assertIn("services.count", self.scrubber)

    def test_dynamic_title_falls_back_to_symbol_in_bounded_toolbar(self):
        self.assertIn("ViewThatFits(in: .horizontal)", self.scrubber)
        self.assertIn("Image(systemName: visible.symbol)", self.scrubber)
        self.assertIn("height: 44", self.scrubber)
        self.assertIn(".frame(maxWidth: .infinity)", self.scrubber)
        self.assertNotIn("minimumScaleFactor", self.scrubber)
        self.assertNotIn("lineLimit(1)", self.scrubber)
        self.assertIn(".fixedSize(horizontal: false, vertical: true)", self.batch)
        self.assertIn("minHeight: 44", self.batch)

    def test_indicator_width_arithmetic_on_narrow_screens(self):
        # This is a layout arithmetic model, not executed Swift or pixel evidence.
        gap = int(re.search(r"HStack\(spacing: (\d+)\)", self.scrubber).group(1))
        for width in (240, 320, 375, 402, 430, 744):
            with self.subTest(width=width):
                available = 120
                pill = (available - gap * (len(self.services) - 1)) / len(self.services)
                self.assertGreater(pill, 0)
                self.assertAlmostEqual(pill * len(self.services) + gap * (len(self.services) - 1), available)

    def test_batch_entry_is_in_list_not_parent_toolbar(self):
        self.assertIn("List {\n            Section {\n                if active {", self.mail)
        self.assertNotIn(".toolbar", self.mail)
        self.assertIn('Label(selecting ? "完成选择" : "批量操作"', self.batch)
        self.assertIn('systemImage: selecting ? "checkmark.circle" : "checklist"', self.batch)
        self.assertIn("selecting.toggle(); selection = []", self.batch)
        self.assertIn(".disabled(!selecting && (store.messages.isEmpty || store.busy || store.loadingWeb))", self.batch)
        self.assertIn("selection.count", self.batch)

    def test_service_switch_does_not_reset_mail_selection(self):
        self.assertIn('@State private var selection = Set<String>()', self.mail)
        self.assertNotIn("onChange(of: active)", self.mail)
        self.assertNotIn(".id(active", self.mail)
        self.assertIn("selection.formIntersection(Set(messages.map(\\.id)))", self.mail)
        self.assertIn("let ids = selection", self.mail)
        self.assertIn("store.update(ids, mutation: mutation)", self.mail)
        self.assertIn("selectedMessage = message", self.mail)
        self.assertIn(".sheet(item: $selectedMessage", self.mail)

    def test_batch_mutations_and_bottom_selection_bar_are_retained(self):
        self.assertIn(".safeAreaInset(edge: .bottom)", self.mail)
        for mutation in [".read(true)", ".read(false)", ".flagged(true)", ".flagged(false)", ".move(folder.id)"]:
            self.assertIn("updateSelection(" + mutation + ")", self.mail)
        self.assertIn("Set(store.messages.map(\\.id))", self.mail)
        self.assertIn(".confirmationDialog", self.mail)

    def test_reading_toolbars_and_reply_navigation_remain_separate(self):
        for token in ['.navigationTitle("邮件")', 'ToolbarItem(placement: .topBarLeading)',
                      'Menu("邮件操作", systemImage: "ellipsis.circle")',
                      'ToolbarItemGroup(placement: .bottomBar)', 'Button("上一封"',
                      'Button("下一封"', 'web = .reply(message.id, "reply")',
                      'web = .reply(message.id, "replyall")', 'web = .reply(message.id, "forward")']:
            self.assertIn(token, self.reader)
        self.assertNotIn("mail.batch-selection", self.reader)
        self.assertIn(".privacySensitive()", self.mail)

    def test_layout_does_not_depend_on_ios26_glass_apis(self):
        for source in (self.host, self.scrubber, self.batch):
            for api in (".glassEffect", ".toolbarBackgroundVisibility", "#available(iOS 26"):
                self.assertNotIn(api, source)


if __name__ == "__main__":
    unittest.main()

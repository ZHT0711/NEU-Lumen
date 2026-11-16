"""Linux-only source regressions for the home card route and opt-in recharge.

These checks do not compile Swift, run an iOS UI, contact the school, or pay.
Run: python3 scripts/test_home_card_entry.py -v
"""
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[1]
HOME = (ROOT / "NEU-Lumen/Features/Home/HomeView.swift").read_text(encoding="utf-8")
CARD = (ROOT / "NEU-Lumen/Features/Card/CardView.swift").read_text(encoding="utf-8")


def block(source, marker):
    """Extract a balanced Swift block, ignoring quoted text and comments."""
    start = source.index("{", source.index(marker))
    masked = re.sub(r'//[^\n]*|/\*[\s\S]*?\*/|"(?:\\.|[^"\\])*"',
                    lambda match: " " * len(match.group()), source)
    depth = 0
    for index in range(start, len(source)):
        if masked[index] == "{":
            depth += 1
        elif masked[index] == "}":
            depth -= 1
            if depth == 0:
                return source[start + 1:index]
    raise AssertionError("Unbalanced Swift block: " + marker)


class HomeCardEntryTests(unittest.TestCase):
    def test_home_tile_opens_native_card_not_recharge(self):
        tile = block(HOME, "private var cardEntrySection:")
        action = block(tile, "Button {")
        self.assertEqual(action.strip(), "path.append(.card)")
        self.assertNotIn("CampusPaymentEntry.cardRecharge", HOME)
        self.assertNotIn(".web(", tile)
        self.assertIn('Text("校园卡")', tile)
        self.assertIn('.accessibilityIdentifier("home.card")', tile)

    def test_native_card_destination_remains_available(self):
        self.assertRegex(HOME, r"case \.card:\s*CardView\(\)")
        self.assertIn("NavigationStack(path: $path)", HOME)
        self.assertIn(".navigationDestination(for: AppDestination.self)", HOME)

    def test_home_summary_describes_the_original_overview(self):
        subtitle = block(HOME, "private var cardEntrySubtitle:")
        self.assertIn("余额 · 流水 · 网费 · 电费", subtitle)
        self.assertIn("repo.cardBalance", subtitle)
        self.assertIn("repo.netInfo", subtitle)
        self.assertIn('parts.joined(separator: " · ")', subtitle)
        self.assertNotIn("充值", subtitle)
        # Flow metadata is not a prerequisite for showing a known net balance.
        self.assertNotIn("net.flowFromPortal", subtitle)
        self.assertIn("case .loading:", subtitle)

    def test_recharge_is_an_independent_explicit_control(self):
        body = block(CARD, "var body: some View")
        self.assertRegex(body, r"balanceCard\s+rechargeEntry")
        self.assertLess(body.index("rechargeEntry"), body.index("billsSection"))
        entry = block(CARD, "private var rechargeEntry:")
        self.assertIn('Button("校园卡充值", systemImage:', entry)
        self.assertEqual(block(entry, "Button(").strip(), "showCardRecharge = true")
        self.assertIn(".buttonStyle(.bordered)", entry)
        self.assertIn(".frame(minHeight: 44)", entry)
        self.assertIn('.accessibilityIdentifier("card.recharge")', entry)
        self.assertIn(".accessibilityHint(", entry)
        self.assertNotIn("showCardRecharge", block(CARD, "private var balanceCard:"))

    def test_recharge_sheet_reuses_the_payment_browser(self):
        self.assertIn("@State private var showCardRecharge = false", CARD)
        sheet = block(CARD, ".sheet(isPresented: $showCardRecharge)")
        self.assertIn("NavigationStack", sheet)
        self.assertIn("PortalWebViewScreen(url: CampusPaymentEntry.cardRecharge, nativeService: .payment)", sheet)
        self.assertNotIn("cardMode:", sheet)
        self.assertNotIn("cardQuery:", sheet)
        self.assertEqual(CARD.count("CampusPaymentEntry.cardRecharge"), 1)

    def test_recharge_does_not_create_or_submit_a_payment(self):
        # Only a user button can enable presentation; initial state is false.
        self.assertEqual(CARD.count("showCardRecharge = true"), 1)
        entry = block(CARD, "private var rechargeEntry:")
        sheet = block(CARD, ".sheet(isPresented: $showCardRecharge)")
        for source in (entry, sheet):
            self.assertNotRegex(source, r"URLSession|WKWebView|evaluateJavaScript|\.submit\(|\.click\(|httpMethod|URL\(string:")
        self.assertNotIn("https://pay.neu.edu.cn", HOME + CARD)
        task = block(CARD, ".task(id:")
        self.assertNotIn("showCardRecharge", task)
        self.assertNotIn("CampusPaymentEntry.cardRecharge", task)

    def test_all_original_overview_sections_and_queries_remain(self):
        body = block(CARD, "var body: some View")
        sections = ["balanceCard", "billsSection", "querySection", "netSection", "electricSection"]
        positions = [body.index(section) for section in sections]
        self.assertEqual(positions, sorted(positions))
        balance = block(CARD, "private var balanceCard:")
        for token in ("repo.cardBalance", "balance?.subsidy", "balance?.status", "repo.cardState"):
            self.assertIn(token, balance)
        bills = block(CARD, "private var billsSection:")
        for token in ("repo.shiftBillsMonth(-1)", "repo.shiftBillsMonth(1)", "Chart(spends)",
                      "repo.cardBills.enumerated()", "repo.billTruncated", "repo.billsWarning", "repo.billsUpdatedAt"):
            self.assertIn(token, bills)
        self.assertNotIn("cardBills.prefix(", bills)
        queries = block(CARD, "private var querySection:")
        for title in ("存款信息查询", "补助信息查询", "圈存信息查询", "取款信息查询",
                      "消费信息查询", "交易汇总信息", "捡到卡信息"):
            self.assertIn(title, queries)
        self.assertIn("cardQuery = title", queries)
        self.assertIn("showCardWeb = true", queries)
        self.assertIn("cardMode: true, cardQuery: cardQuery", CARD)

    def test_electricity_room_binding_and_net_data_are_preserved(self):
        electric = block(CARD, "private var electricSection:")
        for token in ("repo.electricRoomCode = roomDraft", "ElectricRoomKey.isValid(roomDraft)",
                      "ElectricRoomKey.normalize(roomDraft) != repo.electricRoomCode",
                      "roomDraft = repo.electricRoomCode", "editingRoom = true", "editingRoom = false",
                      "repo.loadElectric(force: true)", "info.unbound", "info.remainKwh", "info.lastReadAt"):
            self.assertIn(token, electric)
        self.assertIn('Button("缴纳电费", systemImage: "bolt.fill") { electricityWeb = true }', electric)
        sheet = block(CARD, ".sheet(isPresented: $electricityWeb)")
        self.assertIn("PortalWebViewScreen(url: CampusPaymentEntry.electricity, nativeService: .payment)", sheet)
        net = block(CARD, "private var netSection:")
        for token in ("repo.netInfo", "$0.balance", "net?.usedFlowText", "net?.monthTimes", "repo.loadNetInfo(force: true)"):
            self.assertIn(token, net)

    def test_account_refresh_and_cached_data_provenance_remain(self):
        task = block(CARD, ".task(id:")
        for token in ("repo.ensureLoadedForCurrentUser()", "roomDraft = repo.electricRoomCode",
                      "editingRoom = false", "repo.loadCardOverview()",
                      "repo.loadBills(year: repo.billsYear, month: repo.billsMonth)"):
            self.assertIn(token, task)
        refresh = block(CARD, ".refreshable")
        self.assertIn("repo.loadCardOverview(force: true)", refresh)
        self.assertIn("repo.loadBills(year: repo.billsYear, month: repo.billsMonth, force: true)", refresh)
        for prefix in ("card", "bills", "net", "electric"):
            self.assertIn(f"repo.{prefix}Warning", CARD)
            self.assertIn(f"repo.{prefix}UpdatedAt", CARD)
        self.assertIn("environment.session.user?.sid", CARD)
        self.assertIn("environment.session.user?.uid", CARD)


if __name__ == "__main__":
    unittest.main()

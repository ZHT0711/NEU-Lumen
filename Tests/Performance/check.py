"""Linux source/regex smoke checks; NOT a Swift compiler or Foundation runtime test.
Run: python3 Tests/Performance/check.py
Native behavioral regressions live in ServiceCatalog and OffCampusLogin/main.swift
and run through the existing macOS CI swiftc commands.
"""
from pathlib import Path
import html
import re
import unittest

ROOT = Path(__file__).resolve().parents[2]
MODELS = ROOT / "NEU-Lumen/Core/Models"
CG = (MODELS / "CGAssignments.swift").read_text()
CARD = (MODELS / "CardBalanceDocument.swift").read_text()
COURSES = (MODELS / "CourseModels.swift").read_text()
INPUTS = (MODELS / "HTMLInputFields.swift").read_text()


def literal(source, name):
    match = re.search(r"\b" + re.escape(name) + r' = try! NSRegularExpression\(pattern: #"(.*?)"#', source, re.S)
    if not match:
        raise AssertionError("Missing immutable regex: " + name)
    return match.group(1)


class PerformanceContracts(unittest.TestCase):
    def test_filter_before_merge(self):
        layout = COURSES.split("static func layout(", 1)[1].split("/// 手动添加", 1)[0]
        self.assertIn("let calendar = Calendar.current", layout)
        self.assertIn("occurrences.filter { calendar.isDate($0.date, inSameDayAs: date) }.mergeConsecutive()", layout)
        self.assertEqual(layout.count("mergeConsecutive()"), 1)

    def test_cg_regexes_and_single_result_scan(self):
        expected = {
            "scoreRegex": r"得分\s*[:：]\s*([\d.]+)",
            "submittedAtRegex": r"最后一次提交时间\s*[:：]\s*(\d{4}-\d{2}-\d{2}\s+\d{2}:\d{2}(?::\d{2})?)",
            "testResultsRegex": r"测试数据\s*\d+\s*[^测]+?(?=测试数据\s*\d+|详细|$)",
            "testCountRegex": r"共有测试数据\s*[:：]\s*(\d+)",
        }
        for name, pattern in expected.items():
            self.assertEqual(literal(CG, name), pattern)
            self.assertIn("private static let " + name, CG)
        status = CG.split("var status: Status {", 1)[1].split("var statusLabel", 1)[0]
        self.assertEqual(status.count("testResults"), 1)
        self.assertIn("let results = testResults", status)
        self.assertIn("count > results.count", status)
        self.assertIn("results.allSatisfy", status)
        capture = CG.split("private func capture(", 1)[1].split("var status:", 1)[0]
        self.assertIn("_ regex: NSRegularExpression", capture)
        self.assertNotIn("NSRegularExpression(pattern:", capture)

    def test_card_parses_inputs_once_per_call(self):
        parser = CARD.split("static func parse(", 1)[1].split("private static func plainText", 1)[0]
        self.assertEqual(parser.count("HTMLInputFields.parse("), 1)
        self.assertEqual(parser.count("field(in: page, inputs: inputs, names:"), 3)
        self.assertIn("for attributes in inputs where matches(attributes)", parser)
        self.assertNotIn("static var", CARD)
        self.assertEqual(literal(CARD, "labels"), r"<(span|label|output)\b([^>]*)>(.*?)</\1\s*>")
        self.assertIn("options: [.caseInsensitive, .dotMatchesLineSeparators]", CARD)

    def test_native_regressions_are_in_existing_ci_entrypoints(self):
        catalog = (ROOT / "Tests/ServiceCatalog/main.swift").read_text()
        login = (ROOT / "Tests/OffCampusLogin/main.swift").read_text()
        workflow = (ROOT / ".github/workflows/build-unsigned.yml").read_text()
        self.assertIn("checkLayoutEquivalence", catalog)
        self.assertIn("cachedInputFixtures", login)
        self.assertIn("cgStatusFixtures", login)
        for path in ["Tests/ServiceCatalog/main.swift", "Tests/OffCampusLogin/main.swift"]:
            self.assertIn(path, workflow)

    def test_cg_regex_fixture_outputs(self):
        patterns = {name: re.compile(literal(CG, name)) for name in
                    ["scoreRegex", "submittedAtRegex", "testResultsRegex", "testCountRegex"]}
        text = "😀 最后一次提交时间: 2026-11-02 12:13:14 得分：10.00 共有测试数据:2 测试数据1 完全正确 测试数据2 答案错误 详细"
        self.assertEqual(patterns["scoreRegex"].search(text)[1], "10.00")
        self.assertEqual(patterns["submittedAtRegex"].search(text)[1], "2026-11-02 12:13:14")
        self.assertEqual(patterns["testCountRegex"].search(text)[1], "2")
        self.assertEqual([m[0].strip() for m in patterns["testResultsRegex"].finditer(text)],
                         ["测试数据1 完全正确", "测试数据2 答案错误"])
        self.assertIsNone(patterns["scoreRegex"].search("未提交"))

    def test_card_field_regex_fixture_equivalence(self):
        # Executes the unchanged Swift regex literals in Python, not Foundation.
        # Compare the old three parses against one local parse, with noisy forms.
        input_regex = re.compile(literal(INPUTS, "inputs"), re.I)
        attrs_regex = re.compile(literal(INPUTS, "attributeRegex"))
        labels_regex = re.compile(literal(CARD, "labels"), re.I | re.S)
        parse_count = 0

        def attributes(tag):
            return {m[1].lower(): html.unescape(next(v for v in m.groups()[1:] if v is not None))
                    for m in attrs_regex.finditer(tag)}

        def parse_inputs(page):
            nonlocal parse_count
            parse_count += 1
            return [attributes(m[0]) for m in input_regex.finditer(page)]

        def field(page, inputs, names):
            def matches(attrs):
                return any(value.lower() == name.lower() or
                           value.lower().endswith("_" + name.lower()) or
                           value.lower().endswith("$" + name.lower())
                           for key in ["id", "name"] if (value := attrs.get(key)) is not None
                           for name in names)
            for attrs in inputs:
                if matches(attrs) and attrs.get("value", "").strip():
                    return attrs["value"]
            for label in labels_regex.finditer(page):
                if matches(attributes(label[2])):
                    value = re.sub(r"\s+", " ", html.unescape(re.sub(r"<[^>]+>", " ", label[3]))).strip()
                    if value:
                        return value
            return None

        names = [["txtOddFare", "lblOddFare", "labOddFare"],
                 ["txtSpecialOddFare", "lblSpecialOddFare", "txtSubsidy", "lblSubsidy"],
                 ["txtStatus", "lblStatus", "labStatus"]]
        fixtures = [
            ("<input id='ctl00$TXTODDFARE' value='12.50'><input name=txtSubsidy value='0'><input id='prefix_txtStatus' value='正&#24120;卡'><span id='lblOddFare'>999</span>", ["12.50", "0", "正常卡"]),
            ("<input id=txtOddFare value=' '><span id='lblOddFare'>7.50</span><output id='lblSubsidy'><b>2.25</b></output>", ["7.50", "2.25", None]),
            ("<input id=txtOddFare value='***'><span id='lblOddFare'>99</span>", ["***", None, None]),
            ("<input id=notxtOddFare value='99'><input data-name=txtOddFare data-value=99><label id=labStatus>冻结</label>", [None, None, "冻结"]),
            ("<INPUT NAME=txtOddFare VALUE='0'><input name=txtSpecialOddFare value='1.25'><input name=txtStatus value='挂失'>", ["0", "1.25", "挂失"]),
        ]
        noise = "".join(f"<input type=hidden name='noise{i}' value='x&gt;y'>" for i in range(100))
        for _ in range(20):
            for page, expected in fixtures:
                page = noise + page
                before = parse_count
                old = [field(page, parse_inputs(page), group) for group in names]
                self.assertEqual(parse_count - before, 3)
                before = parse_count
                inputs = parse_inputs(page)
                new = [field(page, inputs, group) for group in names]
                self.assertEqual(parse_count - before, 1)
                self.assertEqual(new, old)
                self.assertEqual(new, expected)


if __name__ == "__main__":
    unittest.main(verbosity=2)

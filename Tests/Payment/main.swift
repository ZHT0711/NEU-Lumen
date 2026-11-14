import Foundation

func require(_ condition: Bool, _ message: String) {
    precondition(condition, message)
}

func document(prefix: String = "f", order: String = "SYNTH-ORDER-A", identity: String? = "SYNTH-DOCUMENT-A",
              amount: String = "", readOnly: Bool = false, option: String = "one") throws -> NativeServiceDocument {
    var raw: [String: Any] = [
        "token": UUID().uuidString, "title": "合成缴费表单",
        "fields": [
            ["id": prefix + "1", "key": "room", "label": "房间码", "kind": "text", "value": "", "required": true, "readOnly": false, "options": []],
            ["id": prefix + "2", "key": "amount", "label": "缴费金额", "kind": "text", "value": amount, "required": true, "readOnly": readOnly, "options": []],
            ["id": prefix + "3", "key": "channel", "label": "渠道", "kind": "select", "value": option, "required": false, "readOnly": false,
             "options": [["value": "one", "title": "学校渠道一"], ["value": "two", "title": "学校渠道二"]]]
        ],
        "actions": [], "tables": [["id": "t1", "title": "待核对订单", "headers": ["订单"], "rows": [[order]], "truncated": false]],
        "notices": [], "needsWeb": false
    ]
    if let identity { raw["draftIdentity"] = identity }
    return try JSONDecoder().decode(NativeServiceDocument.self, from: JSONSerialization.data(withJSONObject: raw))
}

let page = URL(string: "https://pay.neu.edu.cn/synthetic-payment")!
let epoch = UUID()
let original = try document()
let edits = ["f1": "1010203", "f2": "12.50", "f3": "two"]
var cache = NativeFormDraftCache()
require(cache.matchesContext(original, original), "unchanged school context can preserve local edits")
require(cache.matchesContext(original, try document(prefix: "new")), "read tokens and generated field IDs do not change the business context")
require(!cache.matchesContext(original, try document(order: "SYNTH-PROJECT-B")), "same document identity with a changed visible order or project invalidates local edits")
require(!cache.matchesContext(original, try document(amount: "99.00")), "same document identity with a changed school amount invalidates local edits")
cache.save(document: original, values: edits, url: page, epoch: epoch)
var restored = cache.take(for: try document(prefix: "new"), url: page, epoch: epoch)
require(restored == ["new1": "1010203", "new2": "12.50", "new3": "two"], "same living document restores drafts using stable field keys, not stale generated IDs")
require(cache.take(for: original, url: page, epoch: epoch).isEmpty, "draft restoration is consumed once")

for changed in [try document(order: "SYNTH-ORDER-B"), try document(identity: "SYNTH-DOCUMENT-B"),
                try document(identity: nil), try document(amount: "99.00"), try document(readOnly: true), try document(option: "two")] {
    cache.save(document: original, values: edits, url: page, epoch: epoch)
    require(cache.take(for: changed, url: page, epoch: epoch).isEmpty, "changed order/document/hidden identity/field baseline cannot receive an old amount")
}
cache.save(document: original, values: edits, url: page, epoch: epoch)
require(cache.take(for: original, url: page, epoch: UUID()).isEmpty, "new account epoch cannot receive old native drafts")
cache.save(document: original, values: edits, url: page, epoch: epoch)
require(cache.take(for: original, url: page.appendingPathComponent("other"), epoch: epoch).isEmpty, "different page cannot receive old native drafts")
cache.save(document: original, values: edits, url: page, epoch: epoch)
cache.clear()
require(cache.take(for: original, url: page, epoch: epoch).isEmpty, "navigation/logout explicitly clears drafts")
cache.save(document: try document(identity: nil), values: edits, url: page, epoch: epoch)
require(cache.take(for: try document(identity: nil), url: page, epoch: epoch).isEmpty, "unverifiable document identity cannot cache edits")
cache.save(document: original, values: ["f1": "1010203", "f3": "invalid-school-option"], url: page, epoch: epoch)
restored = cache.take(for: original, url: page, epoch: epoch)
require(restored == ["f1": "1010203"], "unknown school choices are discarded without discarding valid text edits")

let rows = [
    CardBill(time: nil, timeText: "2031-01-02 12:00", subject: "校园餐厅", amount: -12.5, fee: 0, balanceAfter: 30, station: "南湖 Campus CAFE"),
    CardBill(time: nil, timeText: "2031-01-01 09:00", subject: "自助充值", amount: 50, fee: 0, balanceAfter: 42.5, station: "圈存机"),
    CardBill(time: nil, timeText: "2031-01-01 08:00", subject: "状态查询", amount: 0, fee: 0, balanceAfter: 0, station: "")
]
require(NativePaymentPresentation.bills(rows, matching: "ＣＡＦＥ -12.50", filter: .all).map(\.subject) == ["校园餐厅"], "search normalizes full-width input and combines location/amount terms")
require(NativePaymentPresentation.bills(rows, matching: "", filter: .recharges).map(\.subject) == ["自助充值"], "recharge filter uses actual signed school amount")
require(NativePaymentPresentation.bills(rows, matching: "2031-01-02", filter: .expenses).count == 1, "selected month records remain searchable by school date text")
require(NativePaymentPresentation.bills(rows, matching: "不存在", filter: .all).isEmpty, "no matching result is explicit")
let now = ISO8601DateFormatter().date(from: "2030-12-31T16:30:00Z")!
let month = NativePaymentPresentation.currentMonth(now: now)
require(month.year == 2031 && month.month == 1, "school month changes at Shanghai midnight")
print("PASS: native payment drafts, hidden/document/order changes, identity and page isolation, one-shot restore, signed bill filtering and Shanghai month")

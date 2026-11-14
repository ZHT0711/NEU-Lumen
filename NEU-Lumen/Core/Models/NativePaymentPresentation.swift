import Foundation

enum PaymentBillFilter: String, CaseIterable, Identifiable {
    case all = "全部", expenses = "消费", recharges = "充值"
    var id: String { rawValue }
}

enum NativePaymentPresentation {
    static func bills(_ source: [CardBill], matching query: String, filter: PaymentBillFilter) -> [CardBill] {
        let terms = query.folding(options: [.caseInsensitive, .widthInsensitive], locale: Locale(identifier: "zh_CN"))
            .split(whereSeparator: \.isWhitespace).map(String.init)
        return source.filter { bill in
            guard filter == .all || (filter == .expenses ? bill.amount < 0 : bill.amount > 0) else { return false }
            let searchable = [bill.subject, bill.station, bill.timeText, String(format: "%.2f", bill.amount)]
                .joined(separator: " ").folding(options: [.caseInsensitive, .widthInsensitive], locale: Locale(identifier: "zh_CN"))
            return terms.allSatisfy { searchable.contains($0) }
        }
    }

    static func currentMonth(now: Date = Date()) -> (year: Int, month: Int) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return (calendar.component(.year, from: now), calendar.component(.month, from: now))
    }
}

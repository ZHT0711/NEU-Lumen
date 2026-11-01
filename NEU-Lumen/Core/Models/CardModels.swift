import Foundation

/// 一卡通余额（主钱包 / 补助 / 卡状态）。
struct CardBalance: Hashable {
    let balance: Double
    let subsidy: Double
    let status: String
}

/// 一卡通流水一行。amount 负=消费，正=充值。
struct CardBill: Identifiable, Hashable {
    let time: Date?
    let timeText: String
    let subject: String
    let amount: Double
    let fee: Double
    let balanceAfter: Double
    let station: String

    var id: String {
        "\(timeText)|\(subject)|\(amount)|\(balanceAfter)|\(station)"
    }

    var isRecharge: Bool { amount > 0 }
}

/// 按自然日聚合的当月消费柱。
struct CardDaySpend: Identifiable, Hashable {
    let date: Date
    let spend: Double
    let recharge: Double
    let count: Int

    var id: String { PortalDate.isoDay(date) }
}

/// 网费（余额来自缴费大厅，用量来自门户）。
struct NetUsageInfo: Hashable {
    let balance: Double
    let monthBytes: Int64
    let monthSeconds: Int64
    let monthTimes: Int64
    let flowFromPortal: Bool

    /// 已用流量文案：≥1 GiB 用 GB 一位小数，否则 MB 整数。
    var usedFlowText: String {
        let gib = Double(monthBytes) / 1024 / 1024 / 1024
        if gib >= 1 {
            return String(format: "%.2f GB", gib)
        }
        let mib = Double(monthBytes) / 1024 / 1024
        return String(format: "%.0f MB", mib)
    }
}

/// 电费余量（unbound 表示还没填房间码）。
struct ElectricInfo: Hashable {
    let unbound: Bool
    let remainKwh: Double?
    let roomNo: String?
    let roomLabel: String?
    let lastReadAt: String?
}

import Foundation

/// 一卡通余额（主钱包 / 补助 / 卡状态）。
struct CardBalance: Hashable {
    let balance: Double
    let subsidy: Double?
    let status: String
}

/// 一卡通流水一行。amount 负=消费，正=充值。
struct CardBill: Identifiable, Hashable {
    let time: Date?
    let timeText: String
    let subject: String
    let amount: Double
    let fee: Double?
    let balanceAfter: Double?
    let station: String

    var id: String {
        "\(timeText)|\(subject)|\(amount)|\(balanceAfter.map { String($0) } ?? "unknown")|\(station)"
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
    let secondsFromPortal: Bool
    let timesFromPortal: Bool

    init(balance: Double, monthBytes: Int64, monthSeconds: Int64, monthTimes: Int64,
         flowFromPortal: Bool, secondsFromPortal: Bool = false, timesFromPortal: Bool = false) {
        self.balance = balance; self.monthBytes = monthBytes; self.monthSeconds = monthSeconds; self.monthTimes = monthTimes
        self.flowFromPortal = flowFromPortal; self.secondsFromPortal = secondsFromPortal; self.timesFromPortal = timesFromPortal
    }
    /// Preserve each actual presence independently. A missing field is not zero;
    /// an explicitly returned nonnegative zero is a valid observed value.
    static func fromPortal(balance: Double, bytes: Int64?, seconds: Int64?, times: Int64?) -> Self {
        let b = bytes.flatMap { $0 >= 0 ? $0 : nil }, s = seconds.flatMap { $0 >= 0 ? $0 : nil }, t = times.flatMap { $0 >= 0 ? $0 : nil }
        return Self(balance: balance, monthBytes: b ?? 0, monthSeconds: s ?? 0, monthTimes: t ?? 0,
                    flowFromPortal: b != nil, secondsFromPortal: s != nil, timesFromPortal: t != nil)
    }
    /// Production cards/activity consume these same facts; callers do not infer
    /// missing timing fields from whether the flow field happened to be present.
    var usageFacts: [(String, String)] {
        var facts: [(String, String)] = []
        if flowFromPortal && monthBytes >= 0 { facts.append(("本月流量", usedFlowText)) }
        else { facts.append(("用量", "本月流量尚未读取")) }
        if secondsFromPortal && monthSeconds >= 0 { facts.append(("在线时长", "\(monthSeconds / 3600)小时\((monthSeconds % 3600) / 60)分")) }
        if timesFromPortal && monthTimes >= 0 { facts.append(("本月连接", "\(monthTimes) 次")) }
        return facts
    }

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

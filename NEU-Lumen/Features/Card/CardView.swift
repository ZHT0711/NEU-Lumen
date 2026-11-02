import Charts
import SwiftUI

/// 校园卡：余额、月流水、网费、电费（校外自动经 WebVPN 网关）。
struct CardView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var showCardWeb = false
    @State private var roomDraft = ""
    @State private var editingRoom = false

    private var repo: PortalRepository {
        environment.repository
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                balanceCard
                if let warning = repo.cardWarning {
                    Text(warning).font(.caption).foregroundStyle(.orange)
                }
                if let updated = repo.cardUpdatedAt {
                    Text("来源：一卡通自助平台 · \(updated.formatted(date: .omitted, time: .shortened)) 同步")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                billsSection
                netSection
                electricSection
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 32)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("校园卡")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showCardWeb) {
            NavigationStack { PortalWebViewScreen(url: URL(string: PortalClient.serviceCard)!, cardMode: true) }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("一卡通网页", systemImage: "safari") { showCardWeb = true }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task {
                        await repo.loadCardOverview()
                        await repo.loadBills(year: repo.billsYear, month: repo.billsMonth, force: true)
                    }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
            }
        }
        .refreshable {
            await repo.loadCardOverview()
        }
        .task {
            roomDraft = repo.electricRoomCode
            await repo.loadCardOverview()
            await repo.loadBills(year: repo.billsYear, month: repo.billsMonth)
        }
    }

    // MARK: - 余额

    private var balanceCard: some View {
        Group {
            switch repo.cardState {
            case .idle, .loading:
                GlassCard {
                    HStack {
                        ProgressView()
                        Text("正在同步一卡通…")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
                }
            case .failed(let message):
                GlassCard {
                    ErrorStateView(message: message) {
                        Task { await repo.loadCardOverview() }
                    }
                }
            case .loaded:
                let balance = repo.cardBalance
                VStack(alignment: .leading, spacing: 10) {
                    Text("校园卡余额（元）")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.85))
                    Text(String(format: "%.2f", balance?.balance ?? 0))
                        .font(.system(size: 40, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .monospacedDigit()
                    HStack(spacing: 8) {
                        Text(balance?.subsidy.map { "补助 \(String(format: "%.2f", $0))" } ?? "补助未提供")
                        Text("·")
                        Text(balance?.status.isEmpty == false ? balance!.status : "状态未提供")
                    }
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.85))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(18)
                .background(
                    LinearGradient(colors: [AppTheme.accent, AppTheme.accentDeep], startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: RoundedRectangle(cornerRadius: 20, style: .continuous)
                )
            }
        }
    }

    // MARK: - 月流水

    private var billsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("本月流水", icon: "chart.bar.xaxis")
            GlassCard {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Button {
                            Task { await repo.shiftBillsMonth(-1) }
                        } label: {
                            Image(systemName: "chevron.left")
                        }
                        .buttonStyle(.borderless)
                        Spacer()
                        Text("\(String(repo.billsYear)) 年 \(repo.billsMonth) 月")
                            .font(.subheadline.bold())
                        Spacer()
                        Button {
                            Task { await repo.shiftBillsMonth(1) }
                        } label: {
                            Image(systemName: "chevron.right")
                        }
                        .buttonStyle(.borderless)
                    }

                    switch repo.billsState {
                    case .idle, .loading:
                        HStack {
                            Spacer()
                            ProgressView()
                            Spacer()
                        }
                        .padding(.vertical, 40)
                    case .failed(let message):
                        ErrorStateView(message: message) {
                            Task { await repo.loadBills(year: repo.billsYear, month: repo.billsMonth, force: true) }
                        }
                    case .loaded:
                        let spends = repo.daySpends()
                        Chart(spends) { day in
                            BarMark(
                                x: .value("日期", day.date, unit: .day),
                                y: .value("消费", day.spend)
                            )
                            .foregroundStyle(AppTheme.accent.gradient)
                            .cornerRadius(2)
                        }
                        .frame(height: 130)

                        let total = spends.reduce(0) { $0 + $1.spend }
                        let billCount = spends.reduce(0) { $0 + $1.count }
                        HStack {
                            Text("合计消费 \(String(format: "%.2f", total)) 元")
                            Spacer()
                            Text("\(billCount) 笔")
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)

                        if repo.billTruncated {
                            Label("本月流水较多，可能不完整", systemImage: "exclamationmark.triangle")
                                .font(.caption2)
                                .foregroundStyle(.orange)
                        }

                        if !repo.cardBills.isEmpty {
                            Divider()
                            ForEach(Array(repo.cardBills.enumerated()), id: \.element.id) { index, bill in
                                BillRow(bill: bill)
                                if index < repo.cardBills.count - 1 {
                                    Divider().padding(.leading, 14)
                                }
                            }
                        }
                    }
                }
                .padding(14)
            }
        }
    }

    // MARK: - 网费

    private var netSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("网费", icon: "wifi")
            GlassCard {
                Group {
                    switch repo.netState {
                    case .idle, .loading:
                        HStack {
                            Spacer()
                            ProgressView()
                            Spacer()
                        }
                        .padding(.vertical, 18)
                    case .failed(let message):
                        ErrorStateView(message: message) {
                            Task { await repo.loadCardOverview() }
                        }
                    case .loaded:
                        let net = repo.netInfo
                        HStack(alignment: .firstTextBaseline, spacing: 14) {
                            statBlock("余额（元）", String(format: "%.2f", net?.balance ?? 0))
                            if net?.flowFromPortal == true {
                                statBlock("本月已用", net?.usedFlowText ?? "—")
                            }
                            if let times = net?.monthTimes, times > 0 {
                                statBlock("连接次数", "\(times)")
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                    }
                }
            }
        }
    }

    // MARK: - 电费

    private var electricSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("电费", icon: "bolt.fill")
            GlassCard {
                VStack(alignment: .leading, spacing: 10) {
                    if editingRoom || repo.electricRoomCode.isEmpty {
                        HStack(spacing: 8) {
                            TextField("宿舍房间码（3位宿舍+4位寝室）", text: $roomDraft)
                                .keyboardType(.numbersAndPunctuation)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                            Button("保存") {
                                repo.electricRoomCode = roomDraft
                                editingRoom = false
                                Task { await repo.loadCardOverview() }
                            }
                            .disabled(roomDraft.trimmingCharacters(in: .whitespaces).count < 7)
                        }
                        .font(.subheadline)
                    } else {
                        HStack {
                            Text("房间码 \(repo.electricRoomCode)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button("修改") {
                                roomDraft = repo.electricRoomCode
                                editingRoom = true
                            }
                            .font(.caption)
                        }
                    }

                    switch repo.electricState {
                    case .idle, .loading where repo.electricInfo == nil:
                        HStack {
                            Spacer()
                            ProgressView()
                            Spacer()
                        }
                        .padding(.vertical, 14)
                    case .failed(let message):
                        ErrorStateView(message: message) {
                            Task { await repo.loadCardOverview() }
                        }
                    default:
                        if let info = repo.electricInfo {
                            if info.unbound {
                                Text("填写宿舍房间码后可查询电费余量（抄表约每日 0:00）")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            } else {
                                HStack(alignment: .firstTextBaseline, spacing: 14) {
                                    statBlock("剩余电量（度）", String(format: "%.1f", info.remainKwh ?? 0))
                                    if let label = info.roomLabel, !label.isEmpty {
                                        statBlock("房间", label)
                                    }
                                }
                                if let read = info.lastReadAt, !read.isEmpty {
                                    Text("抄表时间 \(read) · 单价 0.51 元/度")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
                .padding(14)
            }
        }
    }

    private func statBlock(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(.title3.bold())
                .foregroundStyle(AppTheme.accent)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private func sectionHeader(_ title: String, icon: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.footnote)
                .foregroundStyle(AppTheme.accent)
            Text(title)
                .font(.subheadline.bold())
        }
    }
}

/// 流水一行。
struct BillRow: View {
    let bill: CardBill

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(bill.subject)
                    .font(.footnote)
                    .lineLimit(1)
                Text("\(bill.timeText)  \(bill.station.isEmpty ? "" : "· " + bill.station)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                Text(String(format: "%+.2f", bill.amount))
                    .font(.subheadline.bold())
                    .monospacedDigit()
                    .foregroundStyle(bill.isRecharge ? Color.green : .primary)
                Text("余额 \(String(format: "%.2f", bill.balanceAfter))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 8)
    }
}

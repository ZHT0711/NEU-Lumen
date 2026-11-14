import Foundation
import Observation
import UserNotifications
import CryptoKit

@MainActor @Observable
final class CampusReminderStore {
    static let shared = CampusReminderStore()
    static let prefix = "neu.reminder."
    static let category = "NEU_CAMPUS_REMINDER"
    var preferences = CampusReminderPreferences() { didSet { request = UUID(); persist() } }
    private(set) var personal: [CampusPersonalReminder] = []
    private(set) var upcoming: [CampusReminderCandidate] = []
    private(set) var history: [CampusReminderCandidate] = []
    private(set) var accountKey = ""
    private(set) var authorization: UNAuthorizationStatus = .notDetermined
    private(set) var message: String?
    private(set) var lastBackgroundAttempt: Date?
    private(set) var lastBackgroundSuccess: Date?
    private(set) var backgroundMessage: String?
    private(set) var lastTrigger: String?
    private(set) var syncing = false
    private(set) var lastMailRefreshAt: Date?
    private(set) var openRequest: OpenRequest?
    private var fingerprints: [String: String] = [:]
    private var lastAlerts: [String: Date] = [:]
    private var generation = UUID()
    private var request = UUID()
    private var pendingOpen: (String, String, String)?
    private var restoring = false
    private var activated = false
    private let center: UNUserNotificationCenter
    private let defaults: UserDefaults

    struct OpenRequest { let id = UUID(); let url: URL }
    private struct Saved: Codable {
        var preferences: CampusReminderPreferences
        var personal: [CampusPersonalReminder]
        var history: [CampusReminderCandidate]
        var fingerprints: [String: String]
        var alerts: [String: Date]
        var lastAttempt: Date?
        var lastSuccess: Date?
        var backgroundMessage: String?
        var lastTrigger: String?
        var pending: [CampusReminderCandidate]?
    }

    init(center: UNUserNotificationCenter = .current(), defaults: UserDefaults = .standard) {
        self.center = center; self.defaults = defaults
        center.delegate = CampusReminderDelegate.shared
        center.setNotificationCategories([UNNotificationCategory(identifier: Self.category, actions: [
            UNNotificationAction(identifier: "OPEN", title: "查看详情", options: [.foreground]),
            UNNotificationAction(identifier: "SNOOZE_10", title: "10 分钟后提醒", options: []),
            UNNotificationAction(identifier: "READ", title: "标记已读", options: [])
        ], intentIdentifiers: [], options: [])])
    }
    static func key(_ account: String) -> String {
        SHA256.hash(data: Data(account.utf8)).map { String(format: "%02x", $0) }.joined()
    }
    private var storageKey: String { "lumen.reminders.v1." + accountKey }
    var unreadCount: Int { history.filter { !$0.read && !$0.cancelled && $0.fireAt <= Date() }.count }
    var authorized: Bool { [.authorized, .provisional, .ephemeral].contains(authorization) }

    func activate(account: String?) async {
        let key = account.flatMap { $0.isEmpty ? nil : Self.key($0) } ?? ""
        guard !activated || accountKey != key else { await refreshAuthorization(); return }
        activated = true
        restoring = true
        generation = UUID(); request = UUID()
        accountKey = ""; preferences = CampusReminderPreferences(); personal = []; history = []; upcoming = []
        fingerprints = [:]; lastAlerts = [:]; openRequest = nil
        lastBackgroundAttempt = nil; lastBackgroundSuccess = nil; backgroundMessage = nil; lastTrigger = nil; message = nil
        lastMailRefreshAt = nil
        accountKey = key
        if !key.isEmpty, let data = defaults.data(forKey: storageKey), let saved = try? JSONDecoder().decode(Saved.self, from: data) {
            preferences = saved.preferences; personal = saved.personal; history = saved.history
            upcoming = (saved.pending ?? saved.history).filter { !$0.cancelled && $0.fireAt > Date() }.sorted { $0.fireAt < $1.fireAt }
            fingerprints = saved.fingerprints; lastAlerts = saved.alerts
            lastBackgroundAttempt = saved.lastAttempt; lastBackgroundSuccess = saved.lastSuccess; backgroundMessage = saved.backgroundMessage
            lastTrigger = saved.lastTrigger
        }
        restoring = false
        let token = generation
        let pending = await center.pendingNotificationRequests()
        guard generation == token else { return }
        let stale = pending.map(\.identifier).filter { $0.hasPrefix(Self.prefix) && !($0.hasPrefix(Self.prefix + key + ".") && !key.isEmpty) }
        center.removePendingNotificationRequests(withIdentifiers: stale)
        let delivered = await center.deliveredNotifications()
        guard generation == token else { return }
        center.removeDeliveredNotifications(withIdentifiers: delivered.map { $0.request.identifier }.filter {
            $0.hasPrefix(Self.prefix) && !($0.hasPrefix(Self.prefix + key + ".") && !key.isEmpty)
        })
        await refreshAuthorization()
        if let pendingOpen, !key.isEmpty {
            self.pendingOpen = nil
            handle(account: pendingOpen.0, record: pendingOpen.1, destination: pendingOpen.2, action: "OPEN")
        }
    }

    func refreshAuthorization() async { authorization = await center.notificationSettings().authorizationStatus }
    func setEnabled(_ enabled: Bool) async {
        if enabled {
            do { _ = try await center.requestAuthorization(options: [.alert, .badge, .sound]) }
            catch { message = error.localizedDescription }
            await refreshAuthorization()
            preferences.enabled = authorized
            if !authorized { message = "通知尚未获准，请在系统设置中允许 NEU-Lumen 发送通知。" }
        } else { preferences.enabled = false; await cancelPending() }
    }

    func apply(_ snapshot: CampusReminderSnapshot, now: Date = Date()) async {
        let owner = accountKey, epoch = generation, token = UUID()
        request = token
        guard !owner.isEmpty else { return }
        await refreshAuthorization()
        guard accountKey == owner, generation == epoch, request == token, !Task.isCancelled else { return }
        guard preferences.enabled, authorized else { upcoming = []; await cancelPending(); return }
        var candidates = snapshot.planned + personal.map(\.candidate)
        var changesToCommit: [String: CampusReminderChange] = [:]
        for change in snapshot.changes where preferences.allows(change.kind) {
            guard now.timeIntervalSince(change.updatedAt) >= -60, now.timeIntervalSince(change.updatedAt) < 1800 else { continue }
            let previous = fingerprints[change.id]
            guard !change.title.isEmpty else { fingerprints[change.id] = change.fingerprint; continue }
            if previous == nil, !change.notifyFirst { fingerprints[change.id] = change.fingerprint; continue }
            guard previous != change.fingerprint else { continue }
            if change.kind == .mail, let previous,
               Set(change.fingerprint.split(separator: "|")).subtracting(previous.split(separator: "|")).isEmpty {
                fingerprints[change.id] = change.fingerprint; continue
            }
            let cooldown: TimeInterval = change.kind == .balance ? 86400 : 300
            guard lastAlerts[change.id].map({ now.timeIntervalSince($0) >= cooldown }) ?? true else { continue }
            let id = "change:" + change.id + ":" + Self.key(change.fingerprint)
            changesToCommit[id] = change
            candidates.append(.init(id: id, kind: change.kind,
                title: change.title, body: change.body, fireAt: now.addingTimeInterval(3), destination: change.destination, sourceKey: "change:" + change.id))
        }
        // Unread/failed sources must not erase reminders already arranged by a prior run.
        // Each successful week/platform/term replaces only its own schedule.
        let replacedChanges = Set(candidates.filter { $0.id.hasPrefix("change:") }.compactMap(\.sourceKey))
        let selected = CampusReminderPolicy.reconciled(candidates, previous: upcoming, readySources: snapshot.readySources.union(replacedChanges),
            history: history, preferences: preferences, now: now)
        let pending = await center.pendingNotificationRequests()
        guard accountKey == owner, generation == epoch, request == token, !Task.isCancelled else { return }
        let selectedIDs = Set(selected.map { notificationID($0.id, owner: owner) })
        center.removePendingNotificationRequests(withIdentifiers: pending.map(\.identifier).filter {
            $0.hasPrefix(Self.prefix + owner + ".") && !selectedIDs.contains($0)
        })
        let selectedRawIDs = Set(selected.map(\.id))
        for index in history.indices where history[index].fireAt > now && !selectedRawIDs.contains(history[index].id) { history[index].cancelled = true }
        upcoming = selected
        for item in selected {
            if let change = changesToCommit[item.id] { fingerprints[change.id] = change.fingerprint; lastAlerts[change.id] = now }
        }
        // Persist queued intents before the async OS handoff so interrupted adds can retry.
        persist()
        let existingRequests = Dictionary(uniqueKeysWithValues: pending.map { ($0.identifier, $0) })
        for var item in selected {
            guard accountKey == owner, generation == epoch, request == token, !Task.isCancelled else { return }
            let identifier = notificationID(item.id, owner: owner)
            let content = UNMutableNotificationContent()
            content.title = preferences.detailsOnLockScreen ? item.title : "校园提醒 · " + item.kind.title
            content.body = preferences.detailsOnLockScreen ? item.body : "打开 NEU-Lumen 查看详情。"
            content.categoryIdentifier = Self.category
            content.threadIdentifier = Self.prefix + item.kind.rawValue
            content.userInfo = ["account": owner, "record": item.id, "destination": item.destination]
            if preferences.sound { content.sound = .default }
            let components = CampusReminderPolicy.calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: item.fireAt)
            var dated = components; dated.timeZone = CampusReminderPolicy.calendar.timeZone
            do {
                let existing = existingRequests[identifier]
                let existingDate = existing?.trigger?.nextTriggerDate()
                let sameTime = existingDate.map { abs($0.timeIntervalSince(item.fireAt)) < 1 } == true
                let unchanged = sameTime && existing?.content.title == content.title && existing?.content.body == content.body &&
                    (existing?.content.sound != nil) == preferences.sound && (existing?.content.userInfo["destination"] as? String) == item.destination
                if !unchanged {
                    try await center.add(UNNotificationRequest(identifier: identifier, content: content,
                        trigger: UNCalendarNotificationTrigger(dateMatching: dated, repeats: false)))
                }
                guard accountKey == owner, generation == epoch, request == token, !Task.isCancelled else {
                    if accountKey != owner || generation != epoch || !preferences.allows(item.kind) {
                        center.removePendingNotificationRequests(withIdentifiers: [identifier])
                    }
                    return
                }
                if let index = history.firstIndex(where: { $0.id == item.id }) { item.read = history[index].read; history[index] = item }
                else { history.append(item) }
            } catch { message = "部分提醒未能安排：" + error.localizedDescription }
        }
        let future = history.filter { !$0.cancelled && $0.fireAt > now }
        let recent = history.filter { !$0.cancelled && $0.fireAt <= now }.sorted { $0.fireAt > $1.fireAt }.prefix(80)
        let cancelled = history.filter(\.cancelled).sorted { $0.fireAt > $1.fireAt }.prefix(10)
        history = (future + Array(recent) + Array(cancelled)).sorted { $0.fireAt > $1.fireAt }
        personal.removeAll { $0.date < now.addingTimeInterval(-7 * 86400) }
        persist()
    }

    private func notificationID(_ id: String, owner: String) -> String { Self.prefix + owner + "." + Self.key(id) }
    private func cancelPending() async {
        let owner = accountKey
        let items = await center.pendingNotificationRequests()
        if owner == accountKey, preferences.enabled, authorized { return }
        center.removePendingNotificationRequests(withIdentifiers: items.map(\.identifier).filter {
            owner.isEmpty ? $0.hasPrefix(Self.prefix) : $0.hasPrefix(Self.prefix + owner + ".")
        })
        if owner == accountKey {
            for index in history.indices where history[index].fireAt > Date() { history[index].cancelled = true }
            upcoming = []; persist()
        }
    }
    func add(_ reminder: CampusPersonalReminder) { personal.append(reminder); persist() }
    func removePersonal(_ id: String) { personal.removeAll { $0.id == id }; persist() }
    func markAllRead() { for index in history.indices { history[index].read = true }; persist() }
    func clearOpenRequest() { openRequest = nil }
    func open(_ item: CampusReminderCandidate) { handle(account: accountKey, record: item.id, destination: item.destination, action: "OPEN") }
    func handle(account: String, record: String, destination: String, action: String) {
        guard !accountKey.isEmpty else {
            if action == "OPEN" { pendingOpen = (account, record, destination) }
            return
        }
        guard account == accountKey else { return }
        if let index = history.firstIndex(where: { $0.id == record }) {
            history[index].read = true
            if action == "SNOOZE_10" {
                let item = history[index]
                add(.init(title: item.title, body: item.body, date: Date().addingTimeInterval(600), kind: item.kind, destination: item.destination))
            }
        }
        if action == "OPEN" {
            let item = CampusReminderCandidate(id: record, kind: .custom, title: "", body: "", fireAt: Date(), destination: destination)
            openRequest = OpenRequest(url: item.url)
        }
        persist()
    }
    func test() async {
        guard preferences.enabled, authorized, !accountKey.isEmpty else { message = "请先开启并授权通知。"; return }
        add(.init(title: "通知测试", body: "NEU-Lumen 的本地提醒已配置，可以关闭应用等待提醒。", date: Date().addingTimeInterval(5)))
        await refreshPersonalSchedule()
    }
    func refreshPersonalSchedule() async { await apply(.init(planned: upcoming.filter { $0.sourceKey != "personal" })) }
    func recordMail(account: String, messages: [NativeMailMessage], unread: Int?) async {
        guard Self.key(account) == accountKey, preferences.allows(.mail) else { return }
        lastMailRefreshAt = Date()
        let ids = messages.filter { $0.unread == true }.map(\.id).sorted()
        let change = CampusReminderChange(id: "mail:inbox", kind: .mail, fingerprint: ids.joined(separator: "|"),
            title: ids.isEmpty ? "" : "学校邮箱有新未读邮件", body: unread.map { "收件箱共有 \($0) 封未读邮件。" } ?? "打开学校邮箱查看未读邮件。",
            destination: "mail", updatedAt: Date())
        await apply(.init(planned: upcoming, changes: [change]))
    }
    func recordBackground(started: Bool, success: Bool = false, message: String? = nil, manual: Bool = false) {
        if started { lastBackgroundAttempt = Date(); lastTrigger = manual ? "手动同步" : "系统后台任务" }
        if success { lastBackgroundSuccess = Date() }
        backgroundMessage = message; persist()
    }
    func setSyncing(_ value: Bool) { syncing = value }
    private func persist() {
        guard !accountKey.isEmpty, !restoring else { return }
        let value = Saved(preferences: preferences, personal: personal, history: history, fingerprints: fingerprints,
            alerts: lastAlerts, lastAttempt: lastBackgroundAttempt, lastSuccess: lastBackgroundSuccess, backgroundMessage: backgroundMessage, lastTrigger: lastTrigger, pending: upcoming)
        do { defaults.set(try JSONEncoder().encode(value), forKey: storageKey) }
        catch { message = "提醒设置未能保存：" + error.localizedDescription }
    }
}

private final class CampusReminderDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = CampusReminderDelegate()
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let info = response.notification.request.content.userInfo
        guard let account = info["account"] as? String, let record = info["record"] as? String,
              let destination = info["destination"] as? String else { return }
        let action = response.actionIdentifier == UNNotificationDefaultActionIdentifier ? "OPEN" : response.actionIdentifier
        await MainActor.run { CampusReminderStore.shared.handle(account: account, record: record, destination: destination, action: action) }
        if action == "SNOOZE_10" { await CampusReminderStore.shared.refreshPersonalSchedule() }
    }
}

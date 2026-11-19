import Foundation
import BackgroundTasks
import UIKit

/// Registration happens at application launch, before iOS can deliver a refresh task.
final class CampusApplicationDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        _ = BGTaskScheduler.shared.register(forTaskWithIdentifier: CampusBackgroundRefresh.identifier, using: nil) { task in
            guard let refresh = task as? BGAppRefreshTask else { task.setTaskCompleted(success: false); return }
            let lease = CampusRefreshLease(refresh)
            let operation = Task { @MainActor in
                let success = await CampusBackgroundRefresh.shared.run()
                lease.finish(success && !Task.isCancelled)
            }
            refresh.expirationHandler = { operation.cancel(); lease.finish(false) }
        }
        return true
    }
}

/// Expiration and completion may arrive on different queues; complete the OS lease once.
private final class CampusRefreshLease: @unchecked Sendable {
    private let task: BGAppRefreshTask
    private let lock = NSLock()
    private var finished = false
    init(_ task: BGAppRefreshTask) { self.task = task }
    func finish(_ success: Bool) {
        lock.lock()
        let shouldFinish = !finished
        finished = true
        lock.unlock()
        if shouldFinish { task.setTaskCompleted(success: success) }
    }
}

@MainActor
final class CampusBackgroundRefresh {
    static let shared = CampusBackgroundRefresh()
    static let identifier = "edu.neu.lumen.refresh"
    private weak var session: SessionStore?
    private weak var repository: PortalRepository?
    private var running = false

    func configure(session: SessionStore, repository: PortalRepository) {
        self.session = session; self.repository = repository
    }

    func schedule() {
        let store = CampusReminderStore.shared
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: Self.identifier)
        guard let session, session.phase == .loggedIn, let user = session.user,
              store.preferences.background else { return }
        let account = user.sid.isEmpty ? user.uid : user.sid
        guard !account.isEmpty, store.accountKey == CampusReminderStore.key(account) else { return }
        let remindersEnabled = store.preferences.enabled && store.authorized
        let moocEnabled = store.preferences.backgroundLearning
            && canRefreshMOOC(savedLearningCookies(account: account, user: user), account: account)
        guard remindersEnabled || moocEnabled else { return }
        let request = BGAppRefreshTaskRequest(identifier: Self.identifier)
        // Earliest opportunity, not a promise of a fixed polling interval.
        request.earliestBeginDate = Date().addingTimeInterval(15 * 60)
        do { try BGTaskScheduler.shared.submit(request) }
        catch { store.recordBackground(started: false, message: "后台刷新暂未安排：" + error.localizedDescription) }
    }

    func run(manual: Bool = false) async -> Bool {
        guard !running, let session, let repository else { return false }
        running = true
        CampusReminderStore.shared.setSyncing(true)
        defer { running = false; CampusReminderStore.shared.setSyncing(false); schedule() }
        if session.phase == .booting { await session.restoreSession(validatePortal: manual) }
        guard session.phase == .loggedIn, let user = session.user, !Task.isCancelled else { return false }
        let account = user.sid.isEmpty ? user.uid : user.sid
        let epoch = session.requestEpoch
        let retainedCookies = session.client.browserCookies().filter { !LearningPlatform.mooc.ownsCookie($0) }
        defer {
            if session.phase == .loggedIn, session.requestEpoch == epoch {
                session.client.retainMissingCookies(retainedCookies)
                session.persistWebSession()
            }
        }
        let store = CampusReminderStore.shared
        await store.activate(account: account)
        guard !account.isEmpty, store.accountKey == CampusReminderStore.key(account),
              session.requestEpoch == epoch, store.preferences.background || manual, !Task.isCancelled else { return false }
        let preferences = store.preferences
        let remindersEnabled = preferences.enabled && store.authorized
        let learningCookies = preferences.backgroundLearning ? savedLearningCookies(account: account, user: user) : []
        let moocEnabled = manual ? learningCookies.contains(where: LearningPlatform.mooc.ownsCookie)
            : canRefreshMOOC(learningCookies, account: account)
        guard remindersEnabled || moocEnabled else { return false }
        store.recordBackground(started: true, manual: manual)
        let started = Date()
        await repository.ensureLoadedForCurrentUser()
        session.restoreLearningSession()
        // Publish each completed source while the OS lease is still available.
        // A slow/expired learning reader must not gate already-fetched portal data.
        let applyAvailable: @MainActor () async -> Void = {
            guard remindersEnabled, !Task.isCancelled, session.phase == .loggedIn, session.requestEpoch == epoch,
                  store.accountKey == CampusReminderStore.key(account) else { return }
            await store.apply(repository.reminderSnapshot(preferences: store.preferences))
        }
        var jobs: [Task<Void, Never>] = []
        if remindersEnabled {
            jobs.append(Task { @MainActor in
                await repository.prepareReminderData(preferences: preferences, background: true, onUpdate: applyAvailable)
            })
        }
        for platform in LearningPlatform.allCases where learningCookies.contains(where: platform.ownsCookie) {
            let eligible = platform == .mooc ? moocEnabled : (remindersEnabled && preferences.allows(.assignment))
            guard eligible else { continue }
            jobs.append(Task { @MainActor in
                await repository.loadAssignments(platform, force: true, background: !manual)
                await applyAvailable()
            })
        }
        if remindersEnabled, preferences.backgroundMail, preferences.allows(.mail) {
            jobs.append(Task { @MainActor in
                let reader = NativeMailStore()
                _ = await reader.readInBackground(session: session, apps: repository.apps)
            })
        }
        let requests = jobs
        await withTaskCancellationHandler {
            for task in requests { await task.value }
        } onCancel: { requests.forEach { $0.cancel() } }
        guard !Task.isCancelled, session.phase == .loggedIn, session.requestEpoch == epoch,
              store.accountKey == CampusReminderStore.key(account) else { return false }
        await applyAvailable()
        guard !Task.isCancelled else { return false }
        let reminderUpdates = [repository.gradesUpdatedAt, repository.cardUpdatedAt, repository.netUpdatedAt,
            repository.electricUpdatedAt, repository.todosUpdatedAt, repository.newsUpdatedAt,
            repository.cgUpdatedAt, repository.latestAcademicExamUpdate, repository.latestReminderWeekUpdate, store.lastMailRefreshAt] + Array(repository.assignmentUpdatedAt.values).map(Optional.some)
        let updated = remindersEnabled ? reminderUpdates : [repository.assignmentUpdatedAt[.mooc]]
        let fresh = updated.contains { $0.map { $0 >= started } == true }
        let message: String
        if remindersEnabled {
            message = fresh
                ? (manual ? "手动同步完成，已更新可用提醒。" : "后台读取完成，已更新可用提醒；需重新认证的来源保留上次记录。")
                : "本次未取得新数据，保留已有提醒；可打开应用查看连接与认证状态。"
        } else {
            message = fresh ? "已同步慕课作业。" : "本次未取得新的慕课作业，已保留上次同步结果。"
        }
        store.recordBackground(started: false, success: fresh,
            message: message)
        return fresh
    }

    private func savedLearningCookies(account: String, user: PortalUser) -> [HTTPCookie] {
        guard let saved = KeychainWebSessionStore(account: "learning." + account).load(),
              saved.user.isSameAccount(as: user) else { return [] }
        return saved.restoredCookies()
    }

    private func canRefreshMOOC(_ cookies: [HTTPCookie], account: String) -> Bool {
        if LearningWebReader.hasMOOCSessionCookie(in: cookies) { return true }
        // Preserve a previously verified account if the site changes its sign-in cookie names.
        let hasOtherCookies = cookies.contains { LearningPlatform.mooc.ownsCookie($0)
            && !["NTESSTUDYSI", "EDUWEBDEVICE"].contains($0.name.uppercased()) }
        return hasOtherCookies && AssignmentCacheStore(account: account).load()?.reports[.mooc]?.accountKey.isEmpty == false
    }
}

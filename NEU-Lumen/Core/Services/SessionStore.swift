import Foundation
import Observation

/// 全局会话状态机：booting → loggedOut / loggedIn。
/// 「保持登录」凭据经 Keychain 加密保存，重启后静默续登。
@MainActor
@Observable
final class SessionStore {
    enum Phase: Equatable {
        case booting
        case loggedOut
        case loggingIn
        case loggedIn
    }

    private(set) var phase: Phase = .booting
    private(set) var user: PortalUser?
    private(set) var lastError: String?
    private(set) var refreshingProfile = false
    private(set) var profileSyncError: String?
    private(set) var usesWebSession = false
    private(set) var sessionSaveError: String?
    private(set) var credentialSaveError: String?
    /// 统一认证要求新设备短信二次认证（图形码已就绪）。
    private(set) var needsSecondAuth = false
    /// 二次认证发起时使用的凭据（登录页字段可能为空，完成时兜底）。
    private var sessionEpoch = UUID()
    var requestEpoch: UUID { sessionEpoch }
    private var keepSession = false
    private var learningSessionGeneration: UUID?
    private var learningSessionAccount: String?
    private var lastSavedLearningSession: SavedWebSession?
    private var recoveryTask: Task<Bool, Never>?
    private var lastNetworkRecovery = Date.distantPast
    private var lastForegroundValidation = Date.distantPast
    private var lastIdentityAttempt = Date.distantPast
    private var pendingUsername: String?
    private var pendingPassword: String?

    let client: PortalClient
    private let webSessions: any WebSessionPersisting
    private let defaults: UserDefaults

    init(client: PortalClient = PortalClient(), webSessions: any WebSessionPersisting = KeychainWebSessionStore(), defaults: UserDefaults = .standard) {
        self.client = client
        self.webSessions = webSessions
        self.defaults = defaults
    }

    private static let rememberedKey = "lumen.remembered.username"
    private static let suppressRestoreKey = "lumen.session.suppressAutomaticRestore"

    private func saveCredentials(username: String, password: String) {
        credentialSaveError = CredentialStore.save(username: username, password: password) ? nil : "凭据未能完整保存到本机钥匙串，重启后可能需要重新登录"
    }

    private func clearCredentials() {
        if !CredentialStore.clear() { credentialSaveError = "旧凭据未能从钥匙串完全清除，已禁止自动恢复" }
    }

    private func clearWebSession(_ store: any WebSessionPersisting) {
        if !store.clearAndReport() { sessionSaveError = "登录会话未能完全清除，已禁止自动恢复" }
    }

    var rememberedUsername: String {
        defaults.string(forKey: Self.rememberedKey) ?? ""
    }

    var hasSavedCredentials: Bool {
        CredentialStore.hasPassword
    }

    /// 启动恢复：有保存凭据则静默续登，否则进登录页。
    func restoreSession() async {
        guard phase == .booting else { return }
        guard !defaults.bool(forKey: Self.suppressRestoreKey) else { phase = .loggedOut; return }
        if await restoreWebSession() { return }
        if let cred = CredentialStore.load() {
            let ok = await performLogin(username: cred.username, password: cred.password, keep: true)
            if !ok {
                phase = .loggedOut
            }
        } else {
            phase = .loggedOut
        }
    }

    @discardableResult
    func performLogin(username: String, password: String, keep: Bool) async -> Bool {
        sessionEpoch = UUID()
        let epoch = sessionEpoch
        refreshingProfile = false
        recoveryTask?.cancel()
        recoveryTask = nil
        let previous = webSessions.load()
        let previousUser = user ?? previous?.user
        let retained = (previous?.restoredCookies() ?? []) + client.browserCookies()
        phase = .loggingIn
        lastError = nil
        needsSecondAuth = false
        pendingUsername = username
        pendingPassword = password
        do {
            let info = try await client.login(username: username, password: password)
            guard epoch == sessionEpoch, !Task.isCancelled else { return false }
            if keep {
                saveCredentials(username: username, password: password)
            } else {
                clearCredentials()
            }
            defaults.set(username, forKey: Self.rememberedKey)
            if previousUser?.isSameAccount(as: info) == true { client.retainMissingCookies(retained) }
            user = info
            usesWebSession = false
            keepSession = keep
            if !keep { clearWebSession(webSessions) }
            defaults.set(!keep, forKey: Self.suppressRestoreKey)
            lastForegroundValidation = Date()
            lastIdentityAttempt = .distantPast
            phase = .loggedIn
            persistWebSession()
            return true
        } catch let e as NetworkError where e.needsSecondAuth {
            guard epoch == sessionEpoch, !Task.isCancelled else { return false }
            // 新设备二次认证：凭据先本机记住，图形码+短信完成后回填
            needsSecondAuth = true
            lastError = nil
            if keep {
                saveCredentials(username: username, password: password)
                defaults.set(username, forKey: Self.rememberedKey)
            }
            phase = .loggedOut
            return false
        } catch let e as NetworkError {
            guard epoch == sessionEpoch, !Task.isCancelled else { return false }
            lastError = e.message
            phase = .loggedOut
            return false
        } catch {
            guard epoch == sessionEpoch, !Task.isCancelled else { return false }
            lastError = error.localizedDescription
            phase = .loggedOut
            return false
        }
    }

    /// 二次认证（图形码 + 短信）完成后的收尾：保存凭据并进入主界面。
    func completeSecondAuth(username: String, password: String, keep: Bool, user: PortalUser) {
        sessionEpoch = UUID()
        let finalUsername = username.isEmpty ? (pendingUsername ?? "") : username
        let finalPassword = password.isEmpty ? (pendingPassword ?? "") : password
        if keep, !finalUsername.isEmpty, !finalPassword.isEmpty {
            saveCredentials(username: finalUsername, password: finalPassword)
            defaults.set(finalUsername, forKey: Self.rememberedKey)
        } else if !keep {
            clearCredentials()
        }
        pendingUsername = nil
        pendingPassword = nil
        if let saved = webSessions.load(), saved.user.isSameAccount(as: user) {
            client.retainMissingCookies(saved.restoredCookies())
        }
        self.user = user
        usesWebSession = false
        keepSession = keep
        if !keep { clearWebSession(webSessions) }
        defaults.set(!keep, forKey: Self.suppressRestoreKey)
        lastForegroundValidation = Date()
        lastIdentityAttempt = .distantPast
        needsSecondAuth = false
        lastError = nil
        phase = .loggedIn
        persistWebSession()
    }

    /// 网页方式登录完成：吸收 WKWebView 里的会话 Cookie 并拉取用户信息。
    /// 校外门户被学校重定向进 WebVPN 网关时，WebView 会落在网关域上：
    /// 此时 CASTGC 已到手，先换网关票据再经网关读取门户。
    func completeWebLogin(_ browser: WebLoginSession) async -> Bool {
        guard PortalLoginDocument.canComplete(user: browser.user, cookies: browser.cookies,
                                              hasLoginForm: browser.hasLoginForm) else {
            lastError = "请先在网页中完成认证，登录页会保持打开"
            return false
        }
        let wasLoggedIn = phase == .loggedIn
        let previousAgent = client.browserUserAgent
        sessionEpoch = UUID()
        let epoch = sessionEpoch
        refreshingProfile = false
        recoveryTask?.cancel()
        recoveryTask = nil
        let previous = webSessions.load()
        let previousUser = user ?? previous?.user
        let retained = (previous?.restoredCookies() ?? []) + client.browserCookies()
        if !wasLoggedIn { phase = .loggingIn }
        lastError = nil
        needsSecondAuth = false
        profileSyncError = nil
        client.clearSession()
        client.setUserAgent(browser.userAgent)
        client.absorbCookies(browser.cookies)
        client.adoptGatewayTicket()
        guard client.hasLoginSession else {
            lastError = "未取得登录会话，请在页面中完成统一身份认证"
            if wasLoggedIn {
                client.clearSession()
                client.setUserAgent(previousAgent ?? HTTPClient.userAgent)
                client.absorbCookies(retained)
                client.adoptGatewayTicket()
            }
            phase = wasLoggedIn ? .loggedIn : .loggedOut
            return false
        }
        var info = browser.user
        if info?.hasCoreProfile != true {
            if !client.isLoggedIn && !client.webvpnOn { _ = await client.ensureWebVPN() }
            if let fetched = try? await client.fetchUserInfo() {
                info = info?.merging(fetched) ?? fetched
            }
        }
        guard epoch == sessionEpoch else { return false }
        guard !Task.isCancelled else {
            if wasLoggedIn {
                client.clearSession()
                client.setUserAgent(previousAgent ?? HTTPClient.userAgent)
                client.absorbCookies(retained)
                client.adoptGatewayTicket()
            }
            phase = wasLoggedIn ? .loggedIn : .loggedOut
            return false
        }
        if wasLoggedIn, info?.hasProfile != true {
            client.clearSession()
            client.setUserAgent(previousAgent ?? HTTPClient.userAgent)
            client.absorbCookies(retained)
            client.adoptGatewayTicket()
            lastError = "暂未确认账号资料，请进入门户页面后重试"
            return false
        }
        // Cookie 会话已到手时不因门户 HTML 被风控拦截而否定整个登录。
        if let info, previousUser?.isSameAccount(as: info) == true { client.retainMissingCookies(retained) }
        user = info ?? .pending
        if let sid = info?.sid, !sid.isEmpty {
            if let saved = CredentialStore.load(), saved.username != sid { clearCredentials() }
            defaults.set(sid, forKey: Self.rememberedKey)
        }
        usesWebSession = true
        keepSession = true
        defaults.set(false, forKey: Self.suppressRestoreKey)
        lastForegroundValidation = Date()
        lastIdentityAttempt = .distantPast
        phase = .loggedIn
        persistWebSession()
        return true
    }

    /// 优先恢复网页登录；网络/风控暂时失败时仍保留会话，只有明确过期才清除。
    private func restoreWebSession() async -> Bool {
        guard let saved = webSessions.load() else { return false }
        client.clearSession()
        client.setUserAgent(saved.userAgent)
        client.absorbCookies(saved.restoredCookies())
        client.adoptGatewayTicket()
        guard client.hasLoginSession else {
            webSessions.clear()
            return false
        }
        var restoredUser = saved.user
        do {
            if let fresh = try await client.validateSavedSession() { restoredUser = restoredUser.merging(fresh) }
        } catch {
            // Route-specific login pages / campus gateway restrictions do not revoke the other realm.
            profileSyncError = NetworkError.from(error).isSessionExpired
                ? "当前网络需要更新认证，可在下方更新网页登录；已保留其它网络的会话"
                : "暂时无法同步个人资料，已保留登录会话"
        }
        user = restoredUser
        usesWebSession = true
        keepSession = true
        defaults.set(false, forKey: Self.suppressRestoreKey)
        lastForegroundValidation = Date()
        lastIdentityAttempt = .distantPast
        phase = .loggedIn
        persistWebSession()
        return true
    }

    /// 登录成功立即保存，切到后台时再保存一次续期后的 Cookie。
    func persistWebSession() {
        restoreLearningSession()
        persistLearningSession()
        guard keepSession, phase == .loggedIn, let user else { return }
        do {
            try webSessions.save(SavedWebSession(user: user, userAgent: client.browserUserAgent ?? HTTPClient.userAgent,
                                                 cookies: client.browserCookies()))
        } catch { sessionSaveError = NetworkError.from(error).message }
    }

    private var learningSessions: KeychainWebSessionStore? {
        guard phase == .loggedIn, let user else { return nil }
        let account = user.sid.isEmpty ? user.uid : user.sid
        guard !account.isEmpty else { return nil }
        return KeychainWebSessionStore(account: "learning." + account)
    }

    func restoreLearningSession() {
        guard let store = learningSessions else { return }
        guard learningSessionGeneration != client.sessionGeneration || learningSessionAccount != store.account else { return }
        learningSessionGeneration = client.sessionGeneration
        learningSessionAccount = store.account
        lastSavedLearningSession = nil
        guard let saved = store.load(), user?.isSameAccount(as: saved.user) == true else { return }
        client.restoreLearningCookies(saved.restoredCookies())
    }

    func learningBrowserIdentifier(for platform: LearningPlatform) -> UUID? {
        guard phase == .loggedIn, let user else { return nil }
        return LearningBrowserProfiles(defaults: defaults).identifier(
            account: user.sid.isEmpty ? user.uid : user.sid, platform: platform)
    }

    func cleanRetiredLearningBrowsers() async {
        #if canImport(WebKit)
        if #available(iOS 17.0, macOS 14.0, *) {
            await LearningBrowserProfiles(defaults: defaults).cleanRetiredStores()
        }
        #endif
    }

    /// 作业平台登录态按门户账号保存在本机，即使未勾选门户的保持登录也可恢复。
    func persistLearningSession() {
        guard let store = learningSessions, let user else { return }
        let cookies = client.browserCookies().filter { cookie in
            LearningPlatform.allCases.contains { $0.ownsCookie(cookie) }
        }
        let snapshot = SavedWebSession(user: user, userAgent: client.browserUserAgent ?? HTTPClient.userAgent, cookies: cookies)
        guard snapshot != lastSavedLearningSession else { return }
        do {
            try store.save(snapshot)
            lastSavedLearningSession = snapshot
            sessionSaveError = nil
        } catch { sessionSaveError = NetworkError.from(error).message }
    }

    var hasConfirmedIdentity: Bool { !(user?.sid.isEmpty ?? true) || !(user?.uid.isEmpty ?? true) }

    /// Only the existing, unchanged cookie session may bind an initially unknown
    /// identity. An unknown identity never authorizes falling back to old passwords.
    func ensureIdentity() async -> Bool {
        guard phase == .loggedIn else { return false }
        if hasConfirmedIdentity { return true }
        if let task = recoveryTask { return await task.value }
        guard Date().timeIntervalSince(lastIdentityAttempt) > 20 else { return false }
        lastIdentityAttempt = Date()
        return await silentRelogin()
    }

    private func canBind(_ fresh: PortalUser) -> Bool {
        guard !fresh.sid.isEmpty || !fresh.uid.isEmpty else { return false }
        return !hasConfirmedIdentity || user?.isSameAccount(as: fresh) == true
    }

    /// 手动刷新可补齐网页登录时尚未提供的学院、身份和邮箱。
    func refreshUserProfile() async {
        guard phase == .loggedIn, !refreshingProfile else { return }
        let epoch = sessionEpoch
        refreshingProfile = true
        defer { if epoch == sessionEpoch { refreshingProfile = false } }
        do {
            let fetched = try await client.fetchUserInfo()
            guard epoch == sessionEpoch, phase == .loggedIn, !Task.isCancelled, canBind(fetched) else { return }
            user = user?.merging(fetched) ?? fetched
            profileSyncError = user?.hasCoreProfile == true ? nil : "门户尚未提供完整个人资料"
            persistWebSession()
        } catch {
            guard epoch == sessionEpoch, !Task.isCancelled else { return }
            profileSyncError = "个人资料同步失败，请稍后重试"
        }
    }

    /// 用户放弃二次认证，回到账号密码登录。
    func cancelSecondAuth() {
        needsSecondAuth = false
        lastError = nil
        client.clearSession()
    }

    /// 等待正在进行的续登完成，避免业务请求使用即将失效的旧会话。
    func waitForRecovery() async {
        if let task = recoveryTask { _ = await task.value }
    }

    /// 会话过期后的静默重登（接口报会话失效时由仓储调用并重试一次）。
    func silentRelogin() async -> Bool {
        if let task = recoveryTask { return await task.value }
        let epoch = sessionEpoch
        let task = Task { @MainActor [weak self] () -> Bool in
            guard let self, self.phase == .loggedIn else { return false }
            let retained = self.client.browserCookies()
            defer {
                if epoch == self.sessionEpoch, self.phase == .loggedIn {
                    self.client.retainMissingCookies(retained)
                    self.persistWebSession()
                }
            }
            self.client.invalidateAccessRoute()
            await self.client.prepareAccess()
            if let fresh = try? await self.client.fetchUserInfo(), epoch == self.sessionEpoch, !Task.isCancelled,
               self.canBind(fresh) {
                self.user = self.user?.merging(fresh) ?? fresh
                self.profileSyncError = nil
                return true
            }
            guard epoch == self.sessionEpoch, !Task.isCancelled else { return false }
            // Native credentials are a last resort, without changing the app's root navigation.
            if let cred = CredentialStore.load(), self.user?.sid.isEmpty == false, self.user?.sid == cred.username {
                do {
                    let fresh = try await self.client.login(username: cred.username, password: cred.password)
                    guard epoch == self.sessionEpoch, !Task.isCancelled, self.user?.isSameAccount(as: fresh) != false else { return false }
                    self.user = self.user?.merging(fresh) ?? fresh
                    self.profileSyncError = nil
                    return true
                } catch { }
            }
            guard epoch == self.sessionEpoch, !Task.isCancelled else { return false }
            self.profileSyncError = "当前网络的认证暂不可用，已保留登录信息；可更新网页登录"
            return false
        }
        recoveryTask = task
        let result = await task.value
        if epoch == sessionEpoch { recoveryTask = nil }
        return result
    }

    /// Returning from a sheet or another app is not a network-path change.
    /// Preserve the route cache; revalidate only occasionally or for unknown identity.
    func applicationDidBecomeActive() {
        guard phase == .loggedIn else { return }
        if !hasConfirmedIdentity {
            Task { _ = await ensureIdentity() }
            return
        }
        guard Date().timeIntervalSince(lastForegroundValidation) > 10 * 60 else { return }
        lastForegroundValidation = Date()
        Task { _ = await silentRelogin() }
    }

    func networkDidChange() {
        client.invalidateAccessRoute()
        guard phase == .loggedIn, Date().timeIntervalSince(lastNetworkRecovery) > 10 else { return }
        lastNetworkRecovery = Date()
        Task { _ = await silentRelogin() }
    }

    func logout() {
        // Persist the user's intent first: deletion can fail or the app can stop
        // between Keychain operations. Nothing may resurrect this session on launch.
        defaults.set(true, forKey: Self.suppressRestoreKey)
        sessionSaveError = nil
        credentialSaveError = nil
        if let learning = learningSessions { clearWebSession(learning) }
        if let user {
            LearningBrowserProfiles(defaults: defaults).retire(account: user.sid.isEmpty ? user.uid : user.sid)
            Task { await cleanRetiredLearningBrowsers() }
        }
        lastSavedLearningSession = nil
        sessionEpoch = UUID()
        recoveryTask?.cancel()
        recoveryTask = nil
        lastIdentityAttempt = .distantPast
        lastForegroundValidation = .distantPast
        refreshingProfile = false
        keepSession = false
        clearWebSession(webSessions)
        usesWebSession = false
        clearCredentials()
        client.clearSession()
        user = nil
        profileSyncError = nil
        lastError = nil
        phase = .loggedOut
    }
}

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
    /// 统一认证要求新设备短信二次认证（图形码已就绪）。
    private(set) var needsSecondAuth = false
    /// 二次认证发起时使用的凭据（登录页字段可能为空，完成时兜底）。
    private var sessionEpoch = UUID()
    private var keepSession = false
    private var recoveryTask: Task<Bool, Never>?
    private var lastNetworkRecovery = Date.distantPast
    private var pendingUsername: String?
    private var pendingPassword: String?

    let client: PortalClient
    private let webSessions: any WebSessionPersisting

    init(client: PortalClient = PortalClient(), webSessions: any WebSessionPersisting = KeychainWebSessionStore()) {
        self.client = client
        self.webSessions = webSessions
    }

    private static let rememberedKey = "lumen.remembered.username"

    var rememberedUsername: String {
        UserDefaults.standard.string(forKey: Self.rememberedKey) ?? ""
    }

    var hasSavedCredentials: Bool {
        CredentialStore.hasPassword
    }

    /// 启动恢复：有保存凭据则静默续登，否则进登录页。
    func restoreSession() async {
        guard phase == .booting else { return }
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
            if keep {
                CredentialStore.save(username: username, password: password)
            } else {
                CredentialStore.clear()
            }
            UserDefaults.standard.set(username, forKey: Self.rememberedKey)
            if previousUser?.isSameAccount(as: info) == true { client.retainMissingCookies(retained) }
            user = info
            usesWebSession = false
            keepSession = keep
            if !keep { webSessions.clear() }
            phase = .loggedIn
            persistWebSession()
            return true
        } catch let e as NetworkError where e.needsSecondAuth {
            // 新设备二次认证：凭据先本机记住，图形码+短信完成后回填
            needsSecondAuth = true
            lastError = nil
            if keep {
                CredentialStore.save(username: username, password: password)
                UserDefaults.standard.set(username, forKey: Self.rememberedKey)
            }
            phase = .loggedOut
            return false
        } catch let e as NetworkError {
            lastError = e.message
            phase = .loggedOut
            return false
        } catch {
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
            CredentialStore.save(username: finalUsername, password: finalPassword)
            UserDefaults.standard.set(finalUsername, forKey: Self.rememberedKey)
        } else if !keep {
            CredentialStore.clear()
        }
        pendingUsername = nil
        pendingPassword = nil
        if let saved = webSessions.load(), saved.user.isSameAccount(as: user) {
            client.retainMissingCookies(saved.restoredCookies())
        }
        self.user = user
        usesWebSession = false
        keepSession = keep
        if !keep { webSessions.clear() }
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
            if let saved = CredentialStore.load(), saved.username != sid { CredentialStore.clear() }
            UserDefaults.standard.set(sid, forKey: Self.rememberedKey)
        }
        usesWebSession = true
        keepSession = true
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
        phase = .loggedIn
        persistWebSession()
        return true
    }

    /// 登录成功立即保存，切到后台时再保存一次续期后的 Cookie。
    func persistWebSession() {
        guard keepSession, phase == .loggedIn, let user else { return }
        do {
            try webSessions.save(SavedWebSession(user: user, userAgent: client.browserUserAgent ?? HTTPClient.userAgent,
                                                 cookies: client.browserCookies()))
            sessionSaveError = nil
        } catch { sessionSaveError = NetworkError.from(error).message }
    }

    /// 手动刷新可补齐网页登录时尚未提供的学院、身份和邮箱。
    func refreshUserProfile() async {
        guard phase == .loggedIn, !refreshingProfile else { return }
        refreshingProfile = true
        defer { refreshingProfile = false }
        do {
            let fetched = try await client.fetchUserInfo()
            user = user?.merging(fetched) ?? fetched
            profileSyncError = user?.hasCoreProfile == true ? nil : "门户尚未提供完整个人资料"
            persistWebSession()
        } catch {
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
               self.user?.isSameAccount(as: fresh) != false {
                self.user = self.user?.merging(fresh) ?? fresh
                self.profileSyncError = nil
                return true
            }
            guard epoch == self.sessionEpoch, !Task.isCancelled else { return false }
            // Native credentials are a last resort, without changing the app's root navigation.
            if let cred = CredentialStore.load(), self.user?.sid.isEmpty != false || self.user?.sid == cred.username {
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

    func networkDidChange() {
        client.invalidateAccessRoute()
        guard phase == .loggedIn, Date().timeIntervalSince(lastNetworkRecovery) > 10 else { return }
        lastNetworkRecovery = Date()
        Task { _ = await silentRelogin() }
    }

    func logout() {
        sessionEpoch = UUID()
        recoveryTask?.cancel()
        recoveryTask = nil
        keepSession = false
        webSessions.clear()
        usesWebSession = false
        sessionSaveError = nil
        CredentialStore.clear()
        client.clearSession()
        user = nil
        profileSyncError = nil
        lastError = nil
        phase = .loggedOut
    }
}

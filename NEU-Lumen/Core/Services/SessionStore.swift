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
            user = info
            usesWebSession = false
            webSessions.clear()
            phase = .loggedIn
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
        self.user = user
        usesWebSession = false
        webSessions.clear()
        needsSecondAuth = false
        lastError = nil
        phase = .loggedIn
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
        phase = .loggingIn
        lastError = nil
        needsSecondAuth = false
        profileSyncError = nil
        client.clearSession()
        client.setUserAgent(browser.userAgent)
        client.absorbCookies(browser.cookies)
        client.adoptGatewayTicket()
        guard client.hasLoginSession else {
            lastError = "未取得登录会话，请在页面中完成统一身份认证"
            phase = .loggedOut
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
            phase = .loggedOut
            return false
        }
        // Cookie 会话已到手时不因门户 HTML 被风控拦截而否定整个登录。
        user = info ?? .pending
        if let sid = info?.sid, !sid.isEmpty {
            if let saved = CredentialStore.load(), saved.username != sid { CredentialStore.clear() }
            UserDefaults.standard.set(sid, forKey: Self.rememberedKey)
        }
        usesWebSession = true
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
        } catch let error as NetworkError where error.isSessionExpired {
            webSessions.clear()
            client.clearSession()
            lastError = "保存的登录会话已过期，请重新登录"
            return false
        } catch {
            profileSyncError = "暂时无法同步个人资料，已恢复上次登录"
        }
        user = restoredUser
        usesWebSession = true
        phase = .loggedIn
        persistWebSession()
        return true
    }

    /// 登录成功立即保存，切到后台时再保存一次续期后的 Cookie。
    func persistWebSession() {
        guard usesWebSession, phase == .loggedIn, let user else { return }
        do {
            try webSessions.save(SavedWebSession(user: user, userAgent: client.browserUserAgent ?? "",
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

    /// 会话过期后的静默重登（接口报会话失效时由仓储调用并重试一次）。
    func silentRelogin() async -> Bool {
        guard let cred = CredentialStore.load() else { return false }
        return await performLogin(username: cred.username, password: cred.password, keep: true)
    }

    func logout() {
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

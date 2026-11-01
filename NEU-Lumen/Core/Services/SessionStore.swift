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
    /// 统一认证要求新设备短信二次认证（图形码已就绪）。
    private(set) var needsSecondAuth = false
    /// 二次认证发起时使用的凭据（登录页字段可能为空，完成时兜底）。
    private var pendingUsername: String?
    private var pendingPassword: String?

    let client = PortalClient()

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
        needsSecondAuth = false
        lastError = nil
        phase = .loggedIn
    }

    /// 网页方式登录完成：吸收 WKWebView 里的会话 Cookie 并拉取用户信息。
    /// 说明：网页登录不经过 App 的密码表单，不写钥匙串；下次启动需重新网页登录。
    func completeWebLogin(cookies: [HTTPCookie]) async -> Bool {
        phase = .loggingIn
        lastError = nil
        needsSecondAuth = false
        client.absorbCookies(cookies)
        do {
            let info = try await client.fetchUserInfo()
            user = info
            phase = .loggedIn
            return true
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
        CredentialStore.clear()
        client.clearSession()
        user = nil
        lastError = nil
        phase = .loggedOut
    }
}

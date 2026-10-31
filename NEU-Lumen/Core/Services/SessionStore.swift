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

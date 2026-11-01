import Foundation

struct PortalLoginDocument {
    let hasLoginForm: Bool
    let user: PortalUser?

    static func decode(_ value: Any?) -> PortalLoginDocument {
        guard let raw = value as? String, let data = raw.data(using: .utf8),
              let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            // 不能读取页面时不假定认证成功。
            return PortalLoginDocument(hasLoginForm: true, user: nil)
        }
        var user = (object["user"] as? [String: Any]).map(PortalUser.fromInfoJson)
        for source in object["sources"] as? [String] ?? [] {
            if let found = PortalClient.extractUser(fromHTML: source) { user = user?.merging(found) ?? found }
        }
        return PortalLoginDocument(hasLoginForm: object["loginForm"] as? Bool ?? true,
                                   user: user?.hasProfile == true ? user : nil)
    }

    /// 可见密码/短信验证表单优先于 Cookie；匿名 SESS_ID 不是登录凭据。
    static func canComplete(user: PortalUser?, cookies: [HTTPCookie], hasLoginForm: Bool) -> Bool {
        guard !hasLoginForm else { return false }
        return user?.hasProfile == true || cookies.contains {
            let domain = $0.domain.trimmingCharacters(in: CharacterSet(charactersIn: ".")).lowercased()
            return $0.name == "CASTGC" && !$0.value.isEmpty &&
                (domain == "pass.neu.edu.cn" || domain == "neu.edu.cn") &&
                !($0.expiresDate.map { $0 <= Date() } ?? false)
        }
    }

    static let script = #"""
    (() => {
      const visible = (el) => !!el && !el.disabled &&
        el.getClientRects().length > 0 && getComputedStyle(el).visibility !== 'hidden';
      const loginForm = Array.from(document.querySelectorAll('input[type="password"]')).some(visible) ||
        !!document.querySelector('#second_auth_form');
      let user = {};
      try {
        if (typeof userInfoDSL !== 'undefined') user = userInfoDSL;
        else if (window.userInfoDSL) user = window.userInfoDSL;
        if (typeof user === 'string') user = JSON.parse(user);
      } catch (_) {}
      return JSON.stringify({user, loginForm,
        sources: Array.from(document.scripts).map(s => s.textContent || '')
          .filter(s => s.includes('userInfoDSL'))});
    })()
    """#
}

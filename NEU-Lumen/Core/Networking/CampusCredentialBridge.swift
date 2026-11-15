import Foundation

/// Short-lived login draft. It is never part of the persisted web-session snapshot.
struct CampusLoginCredentials: Equatable {
    let username: String
    let password: String

    init?(username: String, password: String) {
        let account = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !account.isEmpty, account.count <= 128, !password.isEmpty, password.count <= 4096,
              !account.contains(where: \.isWhitespace), !password.contains("\0") else { return nil }
        self.username = account
        self.password = password
    }
}

enum CampusCredentialBridge {
    static let handler = "campusLoginDraft"

    static func isLoginURL(_ url: URL) -> Bool {
        url.scheme == "https" && url.host?.lowercased() == "pass.neu.edu.cn" &&
            (url.port == nil || url.port == 443) && url.user == nil && url.password == nil &&
            ["/tpass/login", "/tpass/login/"].contains(url.path)
    }

    static func canResume(_ url: URL) -> Bool {
        guard isLoginURL(url), let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return false }
        let services = components.queryItems?.filter { $0.name == "service" } ?? []
        guard services.count == 1, let raw = services.first?.value, let service = URL(string: raw),
              service.user == nil, service.password == nil else { return false }
        return service.absoluteString == WebVPN.casService || WebVPN.shouldProxyBrowserURL(service)
    }

    // Runs only in a named isolated world, in the main frame of the exact CAS
    // origin. Read a submitted draft before the school's RSA handler clears it.
    // No password is read when the native "save password" toggle is off.
    static let script = #"""
    (() => {
      if (location.protocol !== 'https:' || location.hostname !== 'pass.neu.edu.cn' ||
          (location.port && location.port !== '443') || !['/tpass/login','/tpass/login/'].includes(location.pathname)) return;
      let draft = null;
      const fields = () => {
        const username = document.querySelector('#un, input[name="username"]');
        const password = document.querySelector('#pd, input[name="password"][type="password"]');
        if (!username || !password || password.type !== 'password' || !username.form ||
            username.form !== password.form || username.form.method.toLowerCase() !== 'post' || username.disabled || password.disabled) return null;
        const action = new URL(username.form.action || location.href, location.href);
        if (action.origin !== location.origin || !['/tpass/login','/tpass/login/'].includes(action.pathname)) return null;
        return {username, password, form: username.form};
      };
      const sample = event => {
        if (window.__lumenRememberLogin !== true) { draft = null; return null; }
        const f = fields();
        if (!f) { draft = null; return null; }
        const username = f.username.value.trim(), password = f.password.value;
        if (username && password) draft = {username, password};
        else if (event && event.type === 'input' || !draft || draft.username !== username) draft = null;
        return f;
      };
      const submit = event => {
        const f = sample();
        if (!f || !draft || document.querySelector('#second_auth_form')) return;
        const target = event.target;
        const button = target && target.closest ? target.closest('button, input[type="submit"], #index_login_btn, #loginBtn, #login') : null;
        if (event.type === 'submit' ? target !== f.form :
            event.type === 'keydown' ? event.key !== 'Enter' || (target !== f.username && target !== f.password) :
            !button || button.form && button.form !== f.form ||
            button.type !== 'submit' && !['index_login_btn','loginBtn','login'].includes(button.id)) return;
        window.webkit.messageHandlers.campusLoginDraft.postMessage(draft);
      };
      document.addEventListener('input', sample, true);
      document.addEventListener('change', sample, true);
      document.addEventListener('submit', submit, true);
      document.addEventListener('click', submit, true);
      document.addEventListener('keydown', submit, true);
    })();
    """#

    /// Fill only the known same-origin form and invoke the school's own login
    /// control, preserving its RSA, device-trust and challenge handling.
    static let autofillScript = #"""
    if (location.protocol !== 'https:' || location.hostname !== 'pass.neu.edu.cn' ||
        (location.port && location.port !== '443') || !['/tpass/login','/tpass/login/'].includes(location.pathname)) return 'untrusted';
    if (document.querySelector('#second_auth_form')) return 'challenge';
    const account = document.querySelector('#un, input[name="username"]');
    const secret = document.querySelector('#pd, input[name="password"][type="password"]');
    if (!account || !secret || secret.type !== 'password' || !account.form || account.form !== secret.form ||
        account.form.method.toLowerCase() !== 'post' || account.disabled || secret.disabled) return 'unrecognized';
    const target = new URL(account.form.action || location.href, location.href);
    if (target.origin !== location.origin || !['/tpass/login','/tpass/login/'].includes(target.pathname)) return 'untrusted';
    if ((account.value && account.value.trim() !== username) || secret.value) return 'edited';
    const challenges = Array.from(document.querySelectorAll('input')).filter(input =>
      /captcha|verify|scendAuthCode|graphicCode|smsCode|code/i.test(input.name || input.id || '') &&
      input.type !== 'hidden' && input.getClientRects().length && !input.disabled);
    const button = document.querySelector('#index_login_btn, #loginBtn, #login, button[type="submit"], input[type="submit"]');
    if (!button || button.disabled || button.form && button.form !== account.form) return 'unrecognized';
    account.value = username; secret.value = password;
    for (const input of [account, secret]) {
      input.dispatchEvent(new Event('input', {bubbles:true}));
      input.dispatchEvent(new Event('change', {bubbles:true}));
    }
    if (challenges.length) return 'challenge';
    button.click();
    return 'submitted';
    """#

    static let rejectionScript = #"""
    if (location.protocol !== 'https:' || location.hostname !== 'pass.neu.edu.cn' ||
        (location.port && location.port !== '443') || !['/tpass/login','/tpass/login/'].includes(location.pathname)) return false;
    const message = (document.querySelector('#errormsg, #msg, #msg_i18n')?.textContent || '').trim();
    return /密码.*(?:错误|不正确)|账号.*(?:不存在|错误)|用户.*不存在|锁定|次数.*(?:超过|过多)/.test(message);
    """#
}

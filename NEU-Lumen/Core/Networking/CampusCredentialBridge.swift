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
        isLoginEndpoint(url, host: "pass.neu.edu.cn", path: "/tpass/login")
    }

    static func isGatewayLoginURL(_ url: URL) -> Bool {
        isLoginEndpoint(url, host: "webvpn.neu.edu.cn", path: WebVPN.proxiedCASLoginPath) && usesGatewayService(url)
    }

    static func usesGatewayService(_ url: URL) -> Bool {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return false }
        return components.queryItems?.filter { $0.name == "service" }.map(\.value) == [WebVPN.casService]
    }

    private static func isLoginEndpoint(_ url: URL, host: String, path: String) -> Bool {
        guard url.scheme == "https", url.host?.lowercased() == host,
              url.port == nil || url.port == 443, url.user == nil, url.password == nil,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return false }
        return components.percentEncodedPath == path || components.percentEncodedPath == path + "/"
    }

    static func canResume(_ url: URL) -> Bool {
        guard isLoginURL(url), let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return false }
        let services = components.queryItems?.filter { $0.name == "service" } ?? []
        guard services.count == 1, let raw = services.first?.value, let service = URL(string: raw),
              service.user == nil, service.password == nil else { return false }
        return service.absoluteString == WebVPN.casService || WebVPN.shouldProxyBrowserURL(service)
    }

    static func draftScript(rememberCredentials: Bool) -> String {
        """
        window.__lumenRememberLogin = \(rememberCredentials ? "true" : "false");
        window.__lumenGatewayCASPath = '\(WebVPN.proxiedCASLoginPath)';
        window.__lumenGatewayCASService = '\(WebVPN.casService)';
        """ + "\n" + script
    }

    // Capture the user's own submission on either official CAS form. Automatic
    // WebKit password entry remains limited to the dedicated public CAS origin.
    static let script = #"""
    (() => {
      const allowed = url => {
        if (url.protocol !== 'https:' || (url.port && url.port !== '443') || url.username || url.password) return false;
        if (url.hostname === 'pass.neu.edu.cn') return ['/tpass/login','/tpass/login/'].includes(url.pathname);
        const path = window.__lumenGatewayCASPath;
        return url.hostname === 'webvpn.neu.edu.cn' && !!path && [path, path + '/'].includes(url.pathname);
      };
      const usesGatewayService = url => {
        const services = url.searchParams.getAll('service');
        return services.length === 1 && services[0] === window.__lumenGatewayCASService;
      };
      const entry = new URL(location.href);
      if (!allowed(entry)) return;
      const viaGateway = entry.hostname === 'webvpn.neu.edu.cn';
      if (viaGateway && !usesGatewayService(entry)) return;
      let draft = null;
      const fields = () => {
        const current = new URL(location.href);
        if (current.origin !== entry.origin || !allowed(current) || viaGateway && !usesGatewayService(current)) return null;
        const username = document.querySelector('#un, input[name="username"]');
        const password = document.querySelector('#pd, input[name="password"][type="password"]');
        if (!username || !password || password.type !== 'password' || !username.form ||
            username.form !== password.form || username.form.method.toLowerCase() !== 'post' || username.disabled || password.disabled) return null;
        const action = new URL(username.form.action || location.href, location.href);
        if (action.origin !== entry.origin || !allowed(action)) return null;
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
        if (viaGateway && !event.isTrusted) return;
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

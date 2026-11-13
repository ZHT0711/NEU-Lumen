"""Synthetic localhost WebKit identity cases; never accesses a school account."""
from http.cookies import SimpleCookie
from urllib.parse import parse_qs, urlsplit
import json
import re
import threading

_counts = {}
_lock = threading.Lock()
_MODES = {'same', 'wrong', 'spoof', 'change'}

def reply(handler, payload, cookies=()):
    raw = json.dumps(payload).encode('utf-8')
    handler.send_response(200)
    handler.send_header('Content-Type', 'application/json; charset=utf-8')
    handler.send_header('Cache-Control', 'no-store')
    for cookie in cookies:
        handler.send_header('Set-Cookie', cookie)
    handler.send_header('Content-Length', str(len(raw)))
    handler.end_headers()
    handler.wfile.write(raw)

def handle_academic_fixture(handler):
    entry = urlsplit(handler.path)
    query = parse_qs(entry.query)
    if entry.path == '/academic-fixture/evidence':
        identifier = query.get('id', [''])[0]
        with _lock:
            count = _counts.get(identifier, 0)
        reply(handler, {'requests': count})
        return True
    if entry.path == '/jwapp/sys/homeapp/api/home/currentUser.do':
        cookies = SimpleCookie()
        cookies.load(handler.headers.get('Cookie', ''))
        def value(name):
            return cookies[name].value if name in cookies else ''
        identifier, mode, expected = map(value, ('academic-fixture-id', 'academic-fixture-mode', 'academic-fixture-account'))
        if not identifier or mode not in _MODES or not re.fullmatch(r'[A-Za-z0-9_-]{1,64}', expected):
            reply(handler, {'code': '401'})
            return True
        with _lock:
            _counts[identifier] = _counts.get(identifier, 0) + 1
            count = _counts[identifier]
        account = 'SYNTH-B' if mode in {'wrong', 'spoof'} or (mode == 'change' and count >= 2) else expected
        reply(handler, {'code': '0', 'datas': {'userId': account}})
        return True
    if entry.path != '/jwapp/sys/synthetic/identity.html':
        return False
    identifier, mode, expected = (query.get(name, [''])[0] for name in ('id', 'mode', 'account'))
    if (mode not in _MODES or not re.fullmatch(r'[A-Za-z0-9_-]{1,64}', expected)
            or not re.fullmatch(r'[A-Za-z0-9_-]{1,64}', identifier)):
        handler.html('Invalid synthetic identity case', 400)
        return True
    with _lock:
        _counts[identifier] = 0
    spoof = ''
    if mode == 'spoof':
        spoof = '''<script>
        window.__academicSpoofFetchCalls = 0;
        const expected = ACCOUNT;
        const realFetch = window.fetch.bind(window);
        const realParse = JSON.parse.bind(JSON);
        window.fetch = (input, init) => {
            const url = new URL(typeof input === 'string' ? input : input.url, location.href);
            if (url.pathname.endsWith('/api/home/currentUser.do')) {
                window.__academicSpoofFetchCalls++;
                return Promise.resolve({ok:true, url:url.href,
                    json:async () => ({code:'0', datas:{userId:expected}})});
            }
            return realFetch(input, init);
        };
        JSON.parse = (text, reviver) => {
            const result = realParse(text, reviver);
            if (result && result.datas && result.datas.userId) result.datas.userId = expected;
            return result;
        };
        </script>'''.replace('ACCOUNT', json.dumps(expected))
    body = '''<!doctype html><meta charset="utf-8"><title>Synthetic academic identity test</title>
        <style>body{font:16px system-ui}table{width:100%;border-collapse:collapse}td,th{padding:12px}</style>
        <p>Only synthetic data. No school login.</p><table><tr><th>课程名称</th><th>学分</th><th>修读状态</th></tr>
        <tr><td>合成账号隔离课程</td><td>2.5</td><td>已修读</td></tr></table>''' + spoof
    raw = body.encode('utf-8')
    handler.send_response(200)
    handler.send_header('Content-Type', 'text/html; charset=utf-8')
    handler.send_header('Cache-Control', 'no-store')
    for name, value in (('id', identifier), ('mode', mode), ('account', expected)):
        handler.send_header('Set-Cookie', f'academic-fixture-{name}={value}; Path=/jwapp/; HttpOnly; SameSite=Lax')
    handler.send_header('Content-Length', str(len(raw)))
    handler.end_headers()
    handler.wfile.write(raw)
    return True

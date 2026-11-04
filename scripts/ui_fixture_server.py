"""Local simulator fixture: signed card SSO and ASP.NET paging, no real credentials."""
from http.server import ThreadingHTTPServer, SimpleHTTPRequestHandler
from urllib.parse import parse_qs, urlsplit
import sys


class Handler(SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=sys.argv[1], **kwargs)

    def html(self, body, status=200):
        data = body.encode('utf-8')
        self.send_response(status)
        self.send_header('Content-Type', 'text/html; charset=utf-8')
        self.send_header('Content-Length', str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def authenticated(self):
        return 'card-fixture=ready' in self.headers.get('Cookie', '')

    def do_GET(self):
        path = urlsplit(self.path).path
        if path.startswith('/mooc/learn/'):
            return self.html('<title>MOOC course</title>')
        if path.startswith('/spoc/learn/'):
            return self.html('<title>SPOC course</title><script>window.moocTermDto={id:99};</script>')
        cg_path = path.removeprefix('/http/fixture')
        if cg_path.startswith('/assignment/'):
            number = parse_qs(urlsplit(self.path).query).get('assignID', ['1'])[0]
            if number == '3':
                return self.html('Temporarily unavailable', 503)
            sidebar = '''<div class="col-2"><span class="text-muted">当前作业</span>
                <a href="/assignment/index.jsp?assignID=1">第一次作业</a>
                <a href="index.jsp?assignID=2">第二次作业 <span class="badge">补交中</span></a>
                <span class="text-muted">历史作业</span><a href="index.jsp?assignID=3">历史作业</a></div>'''
            statuses = ['最后一次提交时间：2026-11-02 10:00:00 得分：100 完全正确', '还未提交'] if number == '1' else [
                '最后一次提交时间：2026-11-02 10:00:00 得分：70 完全正确 答案错误', '最后一次提交时间：2026-11-02 11:00:00 得分：100']
            if number == '1':
                rows = ''.join(f'<tr><td><a href="programList.jsp?proNum={i}&amp;assignID={number}">题目{i}</a></td><td><small>{status}</small></td></tr>'
                               for i, status in enumerate(statuses, 1))
            else:
                # Current CG markup uses an AI side-panel URL with opaque problem IDs.
                rows = ''.join(f'''<tr><td>{i}.</td><td><a href="javascript:openAILeftFrame('题目内容', '/assignment/problemContent.jsp?problemID=opaque-{i}')">题目{i}</a></td>
                    <td>100</td><td><p>{status}</p><table><tr><td>测试数据1</td><td>{'答案错误' if i == 1 else '结果待公布'}</td></tr></table></td></tr>'''
                               for i, status in enumerate(statuses, 1))
            return self.html(f'<html><title>CG 作业</title>{sidebar}<h4>第{number}次作业</h4>'
                             f'<p>作业时间：2026-11-01 08:00:00 至 2026-11-10 23:59:59</p><table>{rows}</table></html>')
        if path == '/card-login.html' and self.authenticated():
            return self.html('Repeated SSO is forbidden while the card session is valid', 403)
        if path.startswith('/selfsearch/'):
            if not self.authenticated():
                return self.html('Forbidden', 403)
            referer = urlsplit(self.headers.get('Referer', ''))
            if referer.netloc != self.headers.get('Host') or referer.path not in [
                '/card-login.html', '/selfsearch/SSOLogin.aspx',
                '/selfsearch/User/Home.aspx', '/selfsearch/User/baseinfo.aspx', '/selfsearch/User/ConsumeInfo.aspx',
            ]:
                return self.html('Card navigation requires its authenticated page Referer', 403)
            if path.endswith('Home.aspx'):
                if 'hide-wallet=1' in self.headers.get('Cookie', ''):
                    return self.html('<html><p>Authenticated card page without wallet fields</p></html>')
                return self.html('<html><iframe src="wallet.aspx"></iframe></html>')
            if path.endswith('baseinfo.aspx'):
                return self.html('<html><p>个人信息设置</p></html>')
            if path.endswith('wallet.aspx'):
                return self.html("""<html><input id='NewContent_txtOddFare' value=''>
                    <input id='NewContent_txtSpecialOddFare' value=''>
                    <script>setTimeout(() => {
                      document.querySelector('#NewContent_txtOddFare').value = '66.50';
                      document.querySelector('#NewContent_txtSpecialOddFare').value = '7.50';
                    }, 300);</script></html>""")
            if path.endswith('ConsumeInfo.aspx'):
                return self.html("<html><input type='hidden' name='__VIEWSTATE' value='first&amp;state'></html>")
        super().do_GET()

    def do_POST(self):
        fields = parse_qs(self.rfile.read(int(self.headers.get('Content-Length', '0'))).decode('utf-8'))
        path = urlsplit(self.path).path
        if path.endswith('SSOLogin.aspx'):
            if not all(fields.get(key) for key in ['username', 'timestamp', 'auid']):
                return self.html('Bad SSO', 400)
            self.send_response(302)
            self.send_header('Set-Cookie', 'card-fixture=ready; Path=/; HttpOnly')
            self.send_header('Location', '/selfsearch/User/Home.aspx')
            self.end_headers()
            return
        if path.endswith('ConsumeInfo.aspx') and self.authenticated():
            page = fields.get('__EVENTARGUMENT', ['1'])[0]
            expected_state = 'first&state' if page == '1' else 'second&state'
            if fields.get('__VIEWSTATE', [''])[0] != expected_state:
                return self.html('Missing ASP.NET state', 400)
            if page == '1' and fields.get('ctl00$ContentPlaceHolder1$txtStartDate', [''])[0] != '2026-10-01':
                return self.html('Incorrect search range', 400)
            pager = "<div>AspNetPager <a href=\"javascript:go('2')\">2</a></div>" if page == '1' else ''
            return self.html("<html><input type='hidden' name='__VIEWSTATE' value='second&amp;state'>"
                             f"<table><tr><td>2026-10-0{page} 12:30:00</td><td>食堂消费</td><td>5.00</td><td>0.00</td><td>66.50</td></tr></table>{pager}</html>")
        self.html('Forbidden', 403)


if __name__ == '__main__':
    ThreadingHTTPServer(('127.0.0.1', 8787), Handler).serve_forever()

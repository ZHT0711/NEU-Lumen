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
        if path.startswith('/selfsearch/'):
            if not self.authenticated():
                return self.html('Forbidden', 403)
            if path.endswith('baseinfo.aspx'):
                return self.html("<html><input id='ContentPlaceHolder1_txtOddFare' value='66.50'><input id='ContentPlaceHolder1_txtSpecialOddFare' value='7.50'></html>")
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
            self.send_header('Set-Cookie', 'card-fixture=ready; Path=/selfsearch; HttpOnly')
            self.send_header('Location', '/selfsearch/User/baseinfo.aspx')
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

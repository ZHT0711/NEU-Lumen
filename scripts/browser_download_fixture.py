"""Synthetic localhost-only download endpoints. Import/mix into the existing fixture server.
Call `if handle_download_fixture(self, 'GET'): return` at the start of do_GET,
and `if handle_download_fixture(self, 'POST'): return` BEFORE consuming the POST body.
No production account, cookie, signed URL, gateway or school server is involved.
"""
import base64
import json
import threading
import time
from urllib.parse import urlsplit, parse_qs


def fixture_pdf():
    stream = b'BT /F1 18 Tf 40 100 Td (NEU-Lumen original PDF fixture) Tj ET'
    objects = [b'<< /Type /Catalog /Pages 2 0 R >>',
               b'<< /Type /Pages /Kids [3 0 R] /Count 1 >>',
               b'<< /Type /Page /Parent 2 0 R /MediaBox [0 0 400 180] /Resources << /Font << /F1 4 0 R >> >> /Contents 5 0 R >>',
               b'<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>',
               b'<< /Length ' + str(len(stream)).encode() + b' >>\nstream\n' + stream + b'\nendstream']
    data = b'%PDF-1.4\n%\xe2\xe3\xcf\xd3\n'
    offsets = [0]
    for number, obj in enumerate(objects, 1):
        offsets.append(len(data))
        data += str(number).encode() + b' 0 obj\n' + obj + b'\nendobj\n'
    xref = len(data)
    data += b'xref\n0 6\n0000000000 65535 f \n'
    data += b''.join(f'{offset:010d} 00000 n \n'.encode() for offset in offsets[1:])
    data += f'trailer\n<< /Size 6 /Root 1 0 R >>\nstartxref\n{xref}\n%%EOF\n'.encode()
    return data


PDF = fixture_pdf()
STATS = {'document': 0, 'post': 0, 'post_get': 0}
LOCK = threading.Lock()


def handle_download_fixture(handler, method):
    parsed = urlsplit(handler.path)
    path = parsed.path
    if not path.startswith('/dl/'):
        return False

    def send(data, mime='text/html; charset=utf-8', status=200, headers=()):
        if isinstance(data, str):
            data = data.encode()
        handler.send_response(status)
        handler.send_header('Content-Type', mime)
        handler.send_header('Content-Length', str(len(data)))
        handler.send_header('Cache-Control', 'no-store')
        for key, value in headers:
            handler.send_header(key, value)
        handler.end_headers()
        handler.wfile.write(data)
        return True

    def auth():
        ref = urlsplit(handler.headers.get('Referer', ''))
        return ('dl-fixture=ready' in handler.headers.get('Cookie', '') and
                ref.netloc == handler.headers.get('Host') and ref.path == '/dl/index')

    if path == '/dl/index':
        encoded = base64.b64encode(PDF).decode()
        html = f'''<!doctype html><meta name="viewport" content="width=device-width"><title>Download fixture</title>
        <a id="attachment" href="/dl/attachment">attachment</a>
        <a id="inline" href="/dl/document">inline PDF without extension</a>
        <a id="same1" href="/dl/same?v=1" download>same 1</a>
        <a id="same2" href="/dl/same?v=2" download>same 2</a>
        <a id="slow" href="/dl/slow">slow</a><a id="broken" href="/dl/broken">broken</a>
        <form id="post" action="/dl/post" method="post"><input name="document" value="fixture"><button>POST PDF</button></form>
        <form id="postAttachment" action="/dl/post-attachment" method="post"><input name="document" value="fixture"><button>POST attachment</button></form>
        <a id="dataPDF" download="data.pdf" href="data:application/pdf;base64,{encoded}">data PDF</a>
        <a id="blobPDF" download="blob.pdf">blob PDF</a>
        <script>document.getElementById('blobPDF').href=URL.createObjectURL(new Blob([Uint8Array.from(atob('{encoded}'),c=>c.charCodeAt(0))],{{type:'application/pdf'}}));</script>'''
        return send(html, headers=[('Set-Cookie', 'dl-fixture=ready; Path=/dl/; HttpOnly; SameSite=Lax')])
    if path == '/dl/reference':
        return send(PDF, 'application/pdf')
    if path == '/dl/stats':
        with LOCK:
            body = json.dumps(STATS)
        return send(body, 'application/json')
    if path == '/dl/document':
        with LOCK:
            STATS['document'] += 1
        if not auth():
            return send('<title>Login required</title>Not a PDF', status=200)
        return send(PDF, 'application/pdf', headers=[('Content-Disposition', 'inline; filename="original.pdf"')])
    if path in ['/dl/post', '/dl/post-attachment']:
        if method != 'POST':
            with LOCK:
                STATS['post_get'] += 1
            return send('GET replay forbidden', status=405)
        body = handler.rfile.read(int(handler.headers.get('Content-Length', '0')))
        with LOCK:
            STATS['post'] += 1
        if not auth() or b'document=fixture' not in body:
            return send('Missing session or POST body', status=403)
        kind = 'attachment' if path.endswith('attachment') else 'inline'
        return send(PDF, 'application/pdf', headers=[('Content-Disposition', f'{kind}; filename="post.pdf"')])
    if path == '/dl/attachment':
        return send(b'NEU-Lumen original attachment', 'application/octet-stream', headers=[('Content-Disposition', 'attachment; filename="attachment.bin"')])
    if path == '/dl/same':
        value = parse_qs(parsed.query).get('v', ['1'])[0]
        return send(('same-' + value).encode(), 'text/plain', headers=[('Content-Disposition', 'attachment; filename="same.txt"')])
    if path in ['/dl/slow', '/dl/broken']:
        size = (32 if parse_qs(parsed.query).get('long') == ['1'] else 4) * 1024 * 1024
        handler.send_response(200)
        handler.send_header('Content-Type', 'application/octet-stream')
        handler.send_header('Content-Disposition', 'attachment; filename="transfer.bin"')
        handler.send_header('Content-Length', str(size))
        handler.send_header('Cache-Control', 'no-store')
        handler.end_headers()
        try:
            if path.endswith('broken'):
                handler.wfile.write(b'TRUNCATED')
                handler.wfile.flush()
                handler.close_connection = True
                return True
            for _ in range(size // 65536):
                handler.wfile.write(b'x' * 65536)
                handler.wfile.flush()
                time.sleep(0.08)  # Intentional server-side stream pacing, not shell polling.
        except (BrokenPipeError, ConnectionResetError):
            pass
        return True
    return send('Unknown download fixture', status=404)


if __name__ == '__main__':
    from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
    import sys
    class Handler(BaseHTTPRequestHandler):
        def do_GET(self):
            if not handle_download_fixture(self, 'GET'):
                self.send_error(404)
        def do_POST(self):
            if not handle_download_fixture(self, 'POST'):
                self.send_error(404)
        def log_message(self, *args):
            pass  # No header/URL credential logging.
    ThreadingHTTPServer(('127.0.0.1', int(sys.argv[1]) if len(sys.argv) > 1 else 8788), Handler).serve_forever()

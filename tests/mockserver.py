import http.server, socketserver, os, sys, re
# usage: python3 mockserver.py <port> [folder]   (serves tests/fixtures by default)
ROOT=sys.argv[2] if len(sys.argv)>2 else os.path.join(os.path.dirname(os.path.abspath(__file__)),'fixtures')
class H(http.server.BaseHTTPRequestHandler):
    protocol_version='HTTP/1.1'
    def log_message(self,*a): pass
    def send_file(self, name, ranges, nolen=False, ctype='application/octet-stream'):
        data=open(os.path.join(ROOT,name),'rb').read(); total=len(data)
        rng=self.headers.get('Range')
        if ranges and rng:
            m=re.match(r'bytes=(\d+)-(\d*)',rng); a=int(m.group(1)); b=int(m.group(2)) if m.group(2) else total-1
            b=min(b,total-1); body=data[a:b+1]
            self.send_response(206); self.send_header('Content-Range',f'bytes {a}-{b}/{total}')
        else:
            body=data; self.send_response(200)
        self.send_header('Content-Type',ctype)
        self.send_header('Content-Disposition',f'attachment; filename="{name}"')
        if ranges: self.send_header('Accept-Ranges','bytes')
        if nolen: self.send_header('Connection','close')
        else: self.send_header('Content-Length',str(len(body)))
        self.end_headers(); self.wfile.write(body)
        if nolen: self.close_connection=True
    def do_GET(self):
        p=self.path.split('?')[0]
        if p.startswith('/range/'): return self.send_file(p[7:].replace('%20',' '),True)
        if p.startswith('/norange/'): return self.send_file(p[9:].replace('%20',' '),False)
        if p.startswith('/nolen/'): return self.send_file(p[7:].replace('%20',' '),False,nolen=True)
        if p=='/html':
            body=b'<!DOCTYPE html><html><body>Sign in</body></html>'
            self.send_response(200); self.send_header('Content-Type','text/html; charset=utf-8'); self.send_header('Content-Length',str(len(body))); self.end_headers(); self.wfile.write(body); return
        if p=='/fakezip':
            body=b'<html>not really a zip</html>'*100
            self.send_response(200); self.send_header('Content-Type','application/octet-stream'); self.send_header('Content-Length',str(len(body))); self.end_headers(); self.wfile.write(body); return
        self.send_response(404); self.send_header('Content-Length','0'); self.end_headers()
class S(socketserver.ThreadingMixIn, http.server.HTTPServer):
    daemon_threads=True; allow_reuse_address=True
    def handle_error(self, request, client_address): pass   # clients hang up on purpose in the resume tests
S(('127.0.0.1',int(sys.argv[1])),H).serve_forever()

import http.client
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
import sys
import threading
import unittest
from server import Server
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))
from deployment_probe import probe


class DeploymentProbeTests(unittest.TestCase):
    def test_lowercase_proxy_headers_and_owned_probe_cleanup(self):
        server = Server()
        self.addCleanup(server.close)

        class Proxy(BaseHTTPRequestHandler):
            def forward(self):
                body = self.rfile.read(int(self.headers.get('Content-Length', 0)))
                conn = http.client.HTTPConnection('127.0.0.1', server.port, timeout=5)
                try:
                    conn.request(self.command, self.path, body, dict(self.headers))
                    result = conn.getresponse()
                    data = result.read()
                    self.send_response(result.status)
                    for name, value in result.getheaders():
                        self.send_header(name.lower(), value)
                    self.end_headers()
                    self.wfile.write(data)
                finally:
                    conn.close()
            do_GET = forward
            do_POST = forward
            def log_message(self, *_):
                pass

        proxy = ThreadingHTTPServer(('127.0.0.1', 0), Proxy)
        thread = threading.Thread(target=proxy.serve_forever, daemon=True)
        thread.start()
        try:
            probe(f'http://127.0.0.1:{proxy.server_port}', server.root/'data')
            self.assertEqual(list((server.root/'data').glob('todos-*')), [])
            # The shared import mutex must never be unlinked by a user probe.
            self.assertTrue((server.root/'data'/'.import.lock').is_file())
        finally:
            proxy.shutdown(); proxy.server_close(); thread.join(timeout=5)

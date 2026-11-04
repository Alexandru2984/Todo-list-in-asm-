"""Disposable server: never uses production paths, ports, or task identifiers."""
from pathlib import Path
import http.client
import os
import socket
import subprocess
import tempfile
import time
from urllib.parse import urlencode

BINARY = Path(__file__).resolve().parents[1] / 'build/server'


class Server:
    def __init__(self):
        self.temp = tempfile.TemporaryDirectory(prefix='asm-test-')
        self.root = Path(self.temp.name)
        self.process = None
        self.start()

    def start(self):
        # A rare port-selection race must fail, never scan onto another listener.
        for _ in range(5):
            with socket.socket() as sock:
                sock.bind(('127.0.0.1', 0))
                self.port = sock.getsockname()[1]
            self.process = subprocess.Popen(
                [str(BINARY), str(self.port)], cwd=self.root,
                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                start_new_session=True,
            )
            for _ in range(50):
                if self.process.poll() is not None:
                    break
                try:
                    status, _, body = self.request('GET', '/healthz')
                    if status == 200 and body == b'{"status":"ok"}\n':
                        return
                except OSError:
                    time.sleep(.02)
            self.stop()
        raise RuntimeError('Disposable server failed to start')

    def stop(self):
        if self.process and self.process.poll() is None:
            import signal
            os.killpg(self.process.pid, signal.SIGTERM)
            self.process.wait(timeout=5)

    def close(self):
        self.stop()
        self.temp.cleanup()

    def request(self, method, path, data=None, cookie=None, headers=None):
        body = urlencode(data) if isinstance(data, dict) else data
        request_headers = dict(headers or {})
        if method == 'POST':
            request_headers.setdefault('Content-Type', 'application/x-www-form-urlencoded')
        if cookie:
            request_headers['Cookie'] = cookie
        conn = http.client.HTTPConnection('127.0.0.1', self.port, timeout=5)
        try:
            conn.request(method, path, body=body, headers=request_headers)
            response = conn.getresponse()
            return response.status, dict(response.getheaders()), response.read()
        finally:
            conn.close()

    def mutate(self, path, data=None, cookie=None, headers=None):
        # Real protocol client: never overwrite an explicitly supplied stale pair.
        if isinstance(data, dict) and cookie and not any(key in data for key in ['_state', '_request']):
            status, _, body = self.request('GET', '/state.json', cookie=cookie)
            if status == 200:
                import json
                state = json.loads(body)
                data = dict(data, _state=state['state'], _request=state['operationId'])
        return self.request('POST', path, data, cookie=cookie, headers=headers)

    def session(self):
        status, headers, _ = self.request('POST', '/start', '')
        assert status == 303, status
        return headers['Set-Cookie'].split(';')[0]

    def file(self, cookie):
        return self.root / 'data' / f'todos-{cookie.split("=", 1)[1]}.txt'

    def raw(self, request, split_at=None):
        with socket.create_connection(('127.0.0.1', self.port), timeout=5) as sock:
            if split_at:
                sock.sendall(request[:split_at])
                time.sleep(.05)
                sock.sendall(request[split_at:])
            else:
                sock.sendall(request)
            sock.shutdown(socket.SHUT_WR)
            result = b''
            while True:
                try:
                    chunk = sock.recv(65536)
                except ConnectionResetError:
                    if result:
                        return result
                    raise
                if not chunk:
                    return result
                result += chunk

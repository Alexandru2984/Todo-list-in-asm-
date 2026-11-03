"""Disposable nginx validates actual proxy snippets; never uses live config/ports."""
import http.client
import json
import os
from pathlib import Path
import re
import shutil
import socket
import subprocess
import tempfile
import time
import unittest
from urllib.parse import urlencode
from server import Server

ROOT=Path(__file__).resolve().parents[1]
NGINX=shutil.which('nginx')


def ngx_quote(value):return '"'+str(value).replace('\\','\\\\').replace('"','\\"')+'"'


@unittest.skipUnless(NGINX,'nginx is needed for isolated proxy-policy checks')
class ProxyPolicyTests(unittest.TestCase):
    def setUp(self):
        self.backend=Server();self.addCleanup(self.backend.close)
        self.cookie=self.backend.session()
        self.temp=tempfile.TemporaryDirectory(prefix='asm-proxy-policy-');self.addCleanup(self.temp.cleanup)
        self.root=Path(self.temp.name)
        with socket.socket() as sock:
            sock.bind(('127.0.0.1',0));self.port=sock.getsockname()[1]
        snippet=(ROOT/'deploy/asm-proxy.conf').read_text()
        needle='proxy_pass http://127.0.0.1:34624;'
        self.assertEqual(snippet.count(needle),1)
        snippet=snippet.replace(needle,f'proxy_pass http://127.0.0.1:{self.backend.port};')
        proxy=self.root/'proxy.conf';proxy.write_text(snippet)
        limits=self.root/'limits.conf';limits.write_text((ROOT/'deploy/asm-limits.conf').read_text())
        site=(ROOT/'deploy/asm.nginx.conf').read_text()
        default_size=re.search(r'client_max_body_size (\w+);',site).group(1)
        self.assertEqual(default_size,'4k')
        locations=''
        for uri in ['/import-preview','/import']:
            block=re.search(r'location = '+re.escape(uri)+r'\s*\{([^}]+)\}',site).group(1)
            size=re.search(r'client_max_body_size (\w+);',block).group(1)
            self.assertEqual(size,'7m')
            locations+=f'location = {uri} {{ client_max_body_size {size}; include {ngx_quote(proxy)}; }}\n'
        conf=self.root/'nginx.conf'
        conf.write_text(('user root;\n' if os.geteuid()==0 else '')+f'''
daemon off;
master_process off;
pid {ngx_quote(self.root/'nginx.pid')};
error_log {ngx_quote(self.root/'error.log')} error;
events {{ worker_connections 64; }}
http {{
  include {ngx_quote(limits)};
  access_log {ngx_quote(self.root/'access.log')} asm_private;
  client_body_temp_path {ngx_quote(self.root/'body')};
  proxy_temp_path {ngx_quote(self.root/'proxy')};
  server {{
    listen 127.0.0.1:{self.port};
    server_name asm.micutu.com;
    client_max_body_size {default_size};
    client_body_timeout 5s;
    limit_req_status 429;
    limit_conn_status 429;
    {locations}
    location / {{ include {ngx_quote(proxy)}; }}
  }}
}}
''')
        checked=subprocess.run([NGINX,'-t','-p',str(self.root)+'/', '-c',str(conf)],capture_output=True,timeout=5)
        self.assertEqual(checked.returncode,0,checked.stderr.decode())
        self.proxy=subprocess.Popen([NGINX,'-p',str(self.root)+'/','-c',str(conf)],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
        self.addCleanup(self.stop_proxy)
        for _ in range(100):
            if self.proxy.poll() is not None:break
            try:
                if self.request('GET','/healthz')[0]==200:return
            except OSError:pass
            time.sleep(.01)
        self.fail('Disposable nginx failed: '+(self.root/'error.log').read_text())

    def stop_proxy(self):
        if self.proxy.poll() is None:
            self.proxy.terminate()
            try:self.proxy.wait(timeout=5)
            except subprocess.TimeoutExpired:self.proxy.kill();self.proxy.wait(timeout=5)

    def request(self,method,path,fields=None):
        body=urlencode(fields) if isinstance(fields,dict) else fields
        headers=dict(Cookie=self.cookie)
        if method=='POST':headers['Content-Type']='application/x-www-form-urlencoded'
        conn=http.client.HTTPConnection('127.0.0.1',self.port,timeout=5)
        try:
            conn.request(method,path,body=body,headers=headers)
            response=conn.getresponse();return response.status,dict(response.getheaders()),response.read()
        finally:conn.close()

    def test_nginx_large_body_exceptions_are_limited_to_import(self):
        self.assertEqual(self.request('POST','/add',dict(title='x'*5000))[0],413)
        payload=json.dumps(dict(version=1,tasks=[dict(id=str(i),title='Proxy fixture',completed=False,createdAt=None) for i in range(1,201)]))
        self.assertGreater(len(urlencode(dict(payload=payload))),4095)
        status,headers,body=self.request('POST','/import-preview',dict(payload=payload))
        self.assertEqual(status,200);self.assertEqual(int(headers['Content-Length']),len(body))
        self.assertIn(b'Review your import',body)
        self.assertFalse(self.backend.file(self.cookie).exists())

    def test_nginx_single_import_slot_does_not_limit_ordinary_requests(self):
        first=socket.create_connection(('127.0.0.1',self.port),timeout=5);self.addCleanup(first.close)
        first.sendall((f'POST /import-preview HTTP/1.1\r\nHost: asm.micutu.com\r\nCookie: {self.cookie}\r\nContent-Type: application/x-www-form-urlencoded\r\nContent-Length: 10000\r\n\r\n').encode())
        time.sleep(.03)
        self.assertEqual(self.request('POST','/import-preview',dict(payload='{}'))[0],429)
        self.assertEqual(self.request('GET','/healthz')[0],200)
        self.assertEqual(self.request('POST','/add',dict(title='Ordinary work remains available'))[0],303)
        first.close()
        payload=json.dumps(dict(version=1,tasks=[]))
        for _ in range(30):
            status,_,_=self.request('POST','/import-preview',dict(payload=payload))
            if status!=429:break
            time.sleep(.01)
        self.assertEqual(status,200)

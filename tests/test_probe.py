"""Native health acceptance and capacity checks against independent local oracles."""
import http.server
import json
import os
from pathlib import Path
import re
import shlex
import socket
import ssl
import subprocess
import sys
import tempfile
import threading
import time
import unittest

ROOT=Path(__file__).resolve().parents[1]
BINARY=ROOT/'build/probe'
HEALTH=b'{"status":"ok"}\n'


class ProbeTests(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory(prefix='asm-probe-');self.addCleanup(self.temp.cleanup)
        self.root=Path(self.temp.name);self.body=self.root/'body'

    def run_probe(self,*args,**kwargs):
        return subprocess.run([str(BINARY),*map(str,args)],capture_output=True,timeout=16,**kwargs)

    def server(self,status=200,body=HEALTH,chunked=False,cert=None):
        requests=[]
        class Handler(http.server.BaseHTTPRequestHandler):
            def handle(self):
                try:super().handle()
                except (BrokenPipeError,ConnectionResetError,ssl.SSLError):pass
            def do_GET(self):
                requests.append(self.path)
                self.send_response(status)
                if chunked:self.send_header('Transfer-Encoding','chunked')
                else:self.send_header('Content-Length',str(len(body)))
                self.end_headers()
                try:
                    if chunked:
                        for start in range(0,len(body),16):
                            part=body[start:start+16]
                            self.wfile.write(f'{len(part):x}\r\n'.encode()+part+b'\r\n');self.wfile.flush()
                        self.wfile.write(b'0\r\n\r\n')
                    else:self.wfile.write(body)
                except (BrokenPipeError,ConnectionResetError,ssl.SSLError):pass
            def log_message(self,*args):pass
        server=http.server.ThreadingHTTPServer(('127.0.0.1',0),Handler)
        if cert:
            context=ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER);context.load_cert_chain(*cert)
            server.socket=context.wrap_socket(server.socket,server_side=True)
        thread=threading.Thread(target=server.serve_forever,daemon=True);thread.start()
        self.addCleanup(lambda:(server.shutdown(),server.server_close(),thread.join(timeout=2)))
        return f'{"https" if cert else "http"}://127.0.0.1:{server.server_port}/healthz',requests

    def test_exact_health_file_is_read_only_and_accepts_only_the_contract(self):
        self.body.write_bytes(HEALTH);before=self.body.read_bytes()
        result=self.run_probe('--health-file',self.body);self.assertEqual(result.returncode,0,result.stderr)
        self.assertEqual(self.body.read_bytes(),before)
        for body in [b'',HEALTH[:-1],HEALTH+b'x',HEALTH.replace(b'ok',b'no'),b'<html>challenge</html>',b'{"secret":"fixture"}']:
            self.body.write_bytes(body);result=self.run_probe('--health-file',self.body)
            self.assertNotEqual(result.returncode,0)
            if len(body)>10:self.assertNotIn(body,result.stdout+result.stderr)

    def test_unsafe_health_file_inodes_fail_promptly(self):
        outside=self.root/'outside';outside.write_bytes(HEALTH)
        for kind in ['symlink','hardlink','fifo','directory']:
            if kind=='symlink':self.body.symlink_to(outside)
            elif kind=='hardlink':os.link(outside,self.body)
            elif kind=='fifo':os.mkfifo(self.body)
            else:self.body.mkdir()
            start=time.monotonic();self.assertNotEqual(self.run_probe('--health-file',self.body).returncode,0)
            self.assertLess(time.monotonic()-start,2)
            if self.body.is_dir():self.body.rmdir()
            else:self.body.unlink()
        self.assertEqual(outside.read_bytes(),HEALTH)

    def test_http_accepts_exact_200_response_and_does_not_redirect(self):
        url,calls=self.server()
        result=self.run_probe('--http',url);self.assertEqual(result.returncode,0,result.stderr)
        self.assertEqual(calls,['/healthz'])
        url,_=self.server(301,HEALTH)
        self.assertNotEqual(self.run_probe('--http',url).returncode,0)

    def test_http_rejects_other_statuses_even_with_a_healthy_body(self):
        for status in [204,302,403,500]:
            url,_=self.server(status,HEALTH)
            self.assertNotEqual(self.run_probe('--http',url).returncode,0)

    def test_http_rejects_200_html_malformed_truncated_and_oversized_data(self):
        for body in [b'',HEALTH[:-1],HEALTH+b'\0',b'<html>CHALLENGE</html>',b'PRIVATE_FIXTURE'*2048]:
            url,_=self.server(200,body)
            result=self.run_probe('--http',url);self.assertNotEqual(result.returncode,0)
            self.assertNotIn(b'PRIVATE_FIXTURE',result.stdout+result.stderr)

    def test_chunked_response_is_bounded_and_cannot_leak_body(self):
        url,_=self.server(200,b'PRIVATE_BODY'*10000,chunked=True)
        started=time.monotonic();result=self.run_probe('--http',url)
        self.assertNotEqual(result.returncode,0);self.assertLess(time.monotonic()-started,5)
        self.assertNotIn(b'PRIVATE_BODY',result.stdout+result.stderr)
        url,_=self.server(200,HEALTH,chunked=True)
        self.assertEqual(self.run_probe('--http',url).returncode,0)

    def test_curl_config_and_environment_cannot_inject_an_extra_request(self):
        config=self.root/'curl-config';config.mkdir()
        url,calls=self.server()
        (config/'.curlrc').write_text('url = '+url+'\noutput = '+str(self.root/'leak')+'\n')
        (config/'curlrc').write_text('url = '+url+'\n')
        env=dict(os.environ,CURL_HOME=str(config),http_proxy='http://127.0.0.1:1',ALL_PROXY='http://127.0.0.1:1')
        result=self.run_probe('--http',url,env=env)
        self.assertEqual(result.returncode,0,result.stderr);self.assertEqual(len(calls),1)
        self.assertFalse((self.root/'leak').exists())

    def test_refused_connection_fails_within_retry_deadline(self):
        with socket.socket() as sock:sock.bind(('127.0.0.1',0));port=sock.getsockname()[1]
        start=time.monotonic();result=self.run_probe('--http',f'http://127.0.0.1:{port}/healthz')
        self.assertEqual(result.returncode,6);self.assertLess(time.monotonic()-start,8)

    def test_tls_verification_is_not_bypassed_for_a_self_signed_server(self):
        cert=self.root/'cert.pem';key=self.root/'key.pem'
        subprocess.run(['openssl','req','-x509','-newkey','rsa:2048','-nodes','-keyout',str(key),
                        '-out',str(cert),'-days','1','-subj','/CN=127.0.0.1'],
                       check=True,capture_output=True,timeout=10)
        url,_=self.server(cert=(cert,key))
        self.assertEqual(self.run_probe('--http',url).returncode,6)

    def test_capacity_matches_independent_statvfs_accounting(self):
        oracle=os.statvfs(self.root)
        result=self.run_probe('--space',self.root,0,0,0)
        self.assertEqual(result.returncode,0,result.stderr)
        values={key:int(value) for key,value in re.findall(rb'([a-z_]+)=(\d+)',result.stdout)}
        expected=oracle.f_bavail*oracle.f_frsize
        self.assertLess(abs(values[b'available_bytes']-expected),1<<30)
        self.assertLessEqual(abs(values[b'block_free_percent']-oracle.f_bavail*100//oracle.f_blocks),1)
        self.assertLessEqual(abs(values[b'inode_free_percent']-oracle.f_ffree*100//oracle.f_files),1)

    def test_capacity_thresholds_fail_without_consuming_storage(self):
        before=set(self.root.iterdir())
        self.assertEqual(self.run_probe('--space',self.root,9223372036854775807,0,0).returncode,4)
        self.assertEqual(self.run_probe('--space',self.root,0,100,0).returncode,4)
        self.assertEqual(self.run_probe('--space',self.root,0,0,100).returncode,5)
        self.assertEqual(set(self.root.iterdir()),before)

    def test_capacity_uses_path_only_access_to_a_private_directory(self):
        directory=self.root/'private';directory.mkdir();directory.chmod(0)
        try:self.assertEqual(self.run_probe('--space',directory,0,0,0).returncode,0)
        finally:directory.chmod(0o700)
        link=self.root/'link';link.symlink_to(directory,target_is_directory=True)
        self.assertNotEqual(self.run_probe('--space',link,0,0,0).returncode,0)

    def test_invalid_arguments_never_start_a_transport_or_change_files(self):
        for args in [[],['--unknown'],['--http','file:///etc/passwd'],['--http','x'],
                     ['--http','http://'+'a'*1024],['--space',self.root,'-1','15','10'],
                     ['--space',self.root,'0','101','10'],['--space',self.root,'0','15','101'],
                     ['--space',self.root,'18446744073709551615','15','10']]:
            self.assertEqual(self.run_probe(*args).returncode,2,args)
        self.assertEqual(list(self.root.iterdir()),[])

    def test_binary_is_static_with_a_non_executable_stack(self):
        output=subprocess.check_output(['readelf','-lW',str(BINARY)],text=True)
        self.assertNotIn('INTERP',output)
        self.assertNotIn('RWE',next(line for line in output.splitlines() if 'GNU_STACK' in line))


class NotificationPolicyTests(unittest.TestCase):
    def test_exec_environment_overrides_shared_log_settings_without_exposing_credentials(self):
        for unit in ['asm-alert@.service','asm-resolved@.service','asm-notify-test.service']:
            with self.subTest(unit=unit),tempfile.TemporaryDirectory(prefix='asm-notify-policy-') as root:
                content=(ROOT/'deploy'/unit).read_text()
                command=next(line.split('=',1)[1] for line in content.splitlines() if line.startswith('ExecStart='))
                state=next(line.split('=',1)[1] for line in content.splitlines() if line.startswith('StateDirectory='))
                args=shlex.split(command)
                relay=args.index('/usr/local/libexec/swift-vapor/alert-notify.sh')
                args=[arg.replace('/var/lib/'+state,root).replace('%d',root).replace('%i','asm-fixture.service') for arg in args]
                receiver="import json,os;print(json.dumps({k:os.environ.get(k) for k in ['ALERT_INCLUDE_LOGS','ALERT_LOG_LINES','ALERT_MAX_BODY_BYTES','ALERT_API_KEY_FILE','TELEGRAM_CREDENTIALS_FILE','ALERT_STATE_DIR']}))"
                result=subprocess.run(args[:relay]+[sys.executable,'-c',receiver],env=dict(os.environ,ALERT_INCLUDE_LOGS='true',ALERT_LOG_LINES='999'),
                                      capture_output=True,text=True,check=True,timeout=5)
                actual=json.loads(result.stdout)
                self.assertEqual(actual['ALERT_INCLUDE_LOGS'],'false');self.assertEqual(actual['ALERT_LOG_LINES'],'0')
                self.assertEqual(actual['ALERT_MAX_BODY_BYTES'],'1024');self.assertEqual(actual['ALERT_STATE_DIR'],root)
                self.assertEqual(actual['ALERT_API_KEY_FILE'],root+'/smtp-pass')
                self.assertEqual(actual['TELEGRAM_CREDENTIALS_FILE'],root+'/telegram')
                self.assertIn('ConditionPathExists=/etc/asm-ops/alerts-enabled',content)
                self.assertNotIn('ALERT_API_KEY=',content)

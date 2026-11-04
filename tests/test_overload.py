"""Real per-process resource failures must sleep and recover on a spare port."""
import http.client
import os
from pathlib import Path
import resource
import select
import signal
import socket
import subprocess
import tempfile
import time
import unittest
from server import BINARY


class OverloadTests(unittest.TestCase):
    def exercise(self,kind):
        with tempfile.TemporaryDirectory(prefix='asm-overload-') as root:
            with socket.socket() as selector:
                selector.bind(('127.0.0.1',0));port=selector.getsockname()[1]
            limit=resource.RLIMIT_NOFILE if kind=='accept' else resource.RLIMIT_NPROC
            previous=resource.getrlimit(limit)
            def restricted():resource.setrlimit(limit,(4 if kind=='accept' else 0,previous[1]))
            process=subprocess.Popen([str(BINARY),str(port)],cwd=root,stdout=subprocess.PIPE,stderr=subprocess.DEVNULL,preexec_fn=restricted,start_new_session=True)
            try:
                self.assertTrue(select.select([process.stdout],[],[],5)[0]);line=process.stdout.readline()
                self.assertIn(b'listening on 127.0.0.1:',line)
                with socket.create_connection(('127.0.0.1',port),timeout=2) as blocked:
                    blocked.sendall(b'GET /healthz HTTP/1.1\r\nHost: localhost\r\n\r\n')
                    status_path=Path('/proc')/str(process.pid)/'status'
                    stat_path=Path('/proc')/str(process.pid)/'stat'
                    first=stat_path.read_text().split();ticks=int(first[13])+int(first[14])
                    time.sleep(.4)
                    second=stat_path.read_text().split();used=int(second[13])+int(second[14])-ticks
                    self.assertLess(used,max(3,os.sysconf('SC_CLK_TCK')//5),'Resource error caused a CPU retry loop')
                    switches=next(line for line in status_path.read_text().splitlines() if line.startswith('voluntary_ctxt_switches:'))
                    self.assertGreaterEqual(int(switches.split()[-1]),2)
                    self.assertIsNone(process.poll())
                    if kind=='fork':
                        started=time.monotonic()
                        for _ in range(3):
                            with socket.create_connection(('127.0.0.1',port),timeout=2) as attempt:
                                attempt.sendall(b'GET /healthz HTTP/1.1\r\nHost: localhost\r\n\r\n')
                                try:self.assertEqual(attempt.recv(1),b'')
                                except ConnectionResetError:pass
                        self.assertGreaterEqual(time.monotonic()-started,.15,'Fork overload did not pace connection rejection')
                # Raise this child's soft limit only; no system/user-wide setting changes.
                resource.prlimit(process.pid,limit,previous)
                ready=False
                for _ in range(30):
                    connection=http.client.HTTPConnection('127.0.0.1',port,timeout=1)
                    try:
                        connection.request('GET','/healthz');response=connection.getresponse();body=response.read()
                        if response.status==200 and body==b'{"status":"ok"}\n':ready=True;break
                    except (OSError,http.client.HTTPException):pass
                    finally:connection.close()
                    time.sleep(.05)
                self.assertTrue(ready,'Listener did not recover after resource pressure was removed')
            finally:
                if process.poll() is None:os.killpg(process.pid,signal.SIGTERM)
                process.wait(timeout=5);process.stdout.close()

    def test_accept_emfile_backs_off_and_recovers(self):self.exercise('accept')

    @unittest.skipIf(os.geteuid()==0,'Linux exempts root from RLIMIT_NPROC')
    def test_fork_eagain_closes_connection_backs_off_and_recovers(self):self.exercise('fork')

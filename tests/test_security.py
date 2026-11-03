import concurrent.futures
import os
from pathlib import Path
import re
import socket
import subprocess
import unittest
from server import BINARY, Server


class SecurityTests(unittest.TestCase):
    def setUp(self):
        self.server = Server()
        self.addCleanup(self.server.close)
        self.cookie = self.server.session()

    def post(self, path, data, **kwargs):
        return self.server.request('POST', path, data, cookie=self.cookie, **kwargs)

    def add(self, title='first'):
        self.assertEqual(self.post('/add', {'title': title})[0], 303)

    def test_session_randomness_and_cookie_flags(self):
        status, headers, _ = self.server.request('POST', '/start', '')
        self.assertEqual(status, 303)
        cookie = headers['Set-Cookie']
        self.assertRegex(cookie, r'^asm_uid=[a-f0-9]{32};')
        for flag in ['HttpOnly', 'Secure', 'SameSite=Strict', 'Path=/']:
            self.assertIn(flag, cookie)
        self.assertNotEqual(cookie.split(';')[0], self.cookie)
        self.assertEqual(headers['Location'], '/app')

    def test_private_workspace_requires_session(self):
        self.assertEqual(self.server.request('GET', '/app')[0], 303)
        self.assertEqual(self.server.request('POST', '/add', {'title': 'x'})[0], 401)

    def test_crud_and_monotonic_ids(self):
        self.add()
        self.assertIn('|0|', self.server.file(self.cookie).read_text())
        self.assertEqual(self.post('/complete', {'id': '1'})[0], 303)
        self.assertIn('1|1|', self.server.file(self.cookie).read_text())
        self.assertEqual(self.post('/reopen', {'id': '1'})[0], 303)
        self.assertEqual(self.post('/edit', {'id': '1', 'title': 'renamed'})[0], 303)
        self.assertIn('|renamed\n', self.server.file(self.cookie).read_text())
        self.assertEqual(self.post('/delete', {'id': '1'})[0], 303)
        self.add('second')
        self.assertIn('\n2|0|', self.server.file(self.cookie).read_text())
        self.assertEqual(self.post('/delete', {'id': '1'})[0], 404)

    def test_clear_completed_preserves_active(self):
        self.add('done'); self.add('active')
        self.assertEqual(self.post('/complete', {'id': '1'})[0], 303)
        self.assertEqual(self.post('/clear-done', {})[0], 303)
        stored = self.server.file(self.cookie).read_text()
        self.assertNotIn('|done\n', stored)
        self.assertIn('|active\n', stored)

    def test_isolation_and_no_capability_in_html(self):
        self.add('private A')
        other = self.server.session()
        status, _, body = self.server.request('GET', '/app', cookie=other)
        self.assertEqual(status, 200)
        self.assertNotIn(b'private A', body)
        self.assertNotIn(other.split('=')[1].encode(), body)
        status, _, _ = self.server.request('POST', '/delete', {'id': '1'}, cookie=other)
        self.assertEqual(status, 404)
        self.assertIn('private A', self.server.file(self.cookie).read_text())

    def test_csrf_origin_and_fetch_metadata(self):
        for headers in [{'Origin': 'https://evil.example'}, {'Origin': 'null'},
                        {'Sec-Fetch-Site': 'cross-site'}, {'Sec-Fetch-Site': 'same-site'},
                        {'Origin': f'http://127.0.0.1:{self.server.port}.evil.example'}]:
            with self.subTest(headers=headers):
                self.assertEqual(self.post('/add', {'title': 'bad'}, headers=headers)[0], 403)
        self.assertFalse(self.server.file(self.cookie).exists())
        self.assertEqual(self.post('/add', {'title': 'ok'}, headers={
            'Origin': f'http://127.0.0.1:{self.server.port}',
            'Sec-Fetch-Site': 'same-origin'})[0], 303)

    def test_explicit_restore_preserves_legacy_records(self):
        token = 'ab' * 16
        data = self.server.root / 'data' / f'todos-{token}.txt'
        data.write_text('1|0|1700000000|legacy\n1|1|1700000000|legacy\n')
        status, headers, _ = self.server.request('POST', '/restore', {'token': token})
        self.assertEqual(status, 303)
        cookie = headers['Set-Cookie'].split(';')[0]
        body = self.server.request('GET', '/app', cookie=cookie)[2]
        self.assertIn(b'legacy', body)
        self.assertEqual(body.count(b'data-id="1"'), 1)
        self.assertEqual(self.server.request('POST', '/reopen', {'id': '1'}, cookie=cookie)[0], 303)
        self.assertIn('#next=2\n1|0|', data.read_text())

    def test_legacy_url_migration_and_no_session_replacement(self):
        token = 'a' * 32
        status, headers, _ = self.server.request('GET', f'/?uid={token}')
        self.assertEqual(status, 303)
        self.assertEqual(headers['Location'], '/app')
        self.assertIn(f'asm_uid={token};', headers['Set-Cookie'])
        self.assertEqual(self.server.request('GET', f'/?uid={token}', cookie=self.cookie)[0], 409)

    def test_exact_tokens_and_cookie_boundaries(self):
        for token in ['a' * 31, 'a' * 33, 'a' * 32 + 'extra', '../' + 'a' * 29, 'A' * 32, 'g' * 32]:
            with self.subTest(token=token):
                self.assertEqual(self.server.request('GET', '/?uid=' + token)[0], 400)
                self.assertEqual(self.server.request('POST', '/restore', {'token': token})[0], 400)
        for cookie in ['xasm_uid=' + 'a' * 32, 'x=' + self.cookie]:
            self.assertEqual(self.server.request('GET', '/app', cookie=cookie)[0], 303)
        self.assertEqual(self.server.request('GET', '/app', cookie='foo=bar; ' + self.cookie + '; x=y')[0], 200)
        self.assertEqual(self.server.request('GET', '/app', cookie=self.cookie + '; ' + self.cookie)[0], 400)

    def test_exact_form_fields_and_duplicate_rejection(self):
        for body in ['subtitle=bad', 'xuid=' + 'a' * 32 + '&title=bad', 'title=one&title=two',
                     'title=bad&uid=' + 'a' * 32, 'title=bad&', '=bad', 'title']:
            with self.subTest(body=body):
                self.assertEqual(self.post('/add', body)[0], 400)
        self.assertFalse(self.server.file(self.cookie).exists())

    def test_strict_numeric_ids(self):
        self.add()
        for value in ['0', '-1', '1evil', '18446744073709551616', '9223372036854775808', '', '1%0A']:
            with self.subTest(value=value):
                self.assertEqual(self.post('/delete', 'id=' + value)[0], 400)
        self.assertIn('|first\n', self.server.file(self.cookie).read_text())

    def test_xss_escaped_and_storage_injection_stripped(self):
        self.add('<script>alert("x")</script>')
        self.add('safe|title\nnew\rline\x00')
        body = self.server.request('GET', '/app', cookie=self.cookie)[2]
        self.assertIn(b'&lt;script&gt;alert(&#34;x&#34;)&lt;/script&gt;', body)
        self.assertNotIn(b'<script>alert(', body)
        self.assertIn('|safetitlenewline\n', self.server.file(self.cookie).read_text())

    def test_utf8_and_length_limits(self):
        self.add('ședință 😀')
        self.add('x' * 110)
        for title in ['', '  ', 'x' * 111, '😀' * 28]:
            with self.subTest(title=title):
                self.assertEqual(self.post('/add', {'title': title})[0], 422)
        for value in ['%ff', '%c0%af', '%ed%a0%80', '%f4%90%80%80', '%e2%82', '%', '%x0']:
            with self.subTest(value=value):
                self.assertEqual(self.post('/add', 'title=' + value)[0], 400)
        self.assertEqual(self.post('/add', 'title=%f4%8f%bf%bf')[0], 303)

    def test_protocol_rejects_truncation_without_mutation(self):
        body = b'title=never-written'
        raw = (f'POST /add HTTP/1.1\r\nHost: localhost\r\nCookie: {self.cookie}\r\n'
               'Content-Type: application/x-www-form-urlencoded\r\nContent-Length: 999\r\n\r\n').encode() + body
        self.assertIn(b'400 Bad Request', self.server.raw(raw))
        self.assertFalse(self.server.file(self.cookie).exists())

    def test_split_packets_and_case_insensitive_headers(self):
        body = b'title=split'
        raw = (f'POST /add HTTP/1.1\r\nHost: localhost\r\nCookie: {self.cookie}\r\n'
               f'cOnTeNt-TyPe: Application/X-Www-Form-Urlencoded; charset=UTF-8\r\ncOnTeNt-LeNgTh: {len(body)}\r\n\r\n').encode() + body
        self.assertIn(b'303 See Other', self.server.raw(raw, split_at=len(raw)-len(body)))
        self.assertIn('|split\n', self.server.file(self.cookie).read_text())

    def test_ambiguous_or_invalid_framing(self):
        prefix = b'POST /add HTTP/1.1\r\nHost: localhost\r\nContent-Type: application/x-www-form-urlencoded\r\n'
        cases = [
            (b'Content-Length: 1\r\nContent-Length: 1\r\n\r\nx', 400),
            (b'Transfer-Encoding: chunked\r\nContent-Length: 0\r\n\r\n', 400),
            (b'Content-Length: -1\r\n\r\n', 400),
            (b'Content-Length: 1x\r\n\r\nx', 400),
            (b'Content-Length : 0\r\n\r\n', 400),
            (b'Content-Length: 99999999999999999999999\r\n\r\n', 413),
            (b'Content-Length: 0\r\n\r\nextra', 400),
            (b'Content-Length: 1\r\n\r\n\0', 400),
            (b'Expect: 100-continue\r\nContent-Length: 0\r\n\r\n', 417),
            (b'\r\n', 411),
        ]
        for tail, status in cases:
            with self.subTest(tail=tail):
                response = self.server.raw(prefix+tail)
                self.assertTrue(response.startswith(f'HTTP/1.1 {status} '.encode()), response[:80])
        self.assertFalse(self.server.file(self.cookie).exists())

    def test_oversized_headers_bad_lines_and_media_type(self):
        for raw, status in [
            (b'GET / HTTP/1.1\r\nX: ' + b'x' * 5000, 413),
            (b'GET / HTTP/1.1\r\nHost: x\nX: y\r\n\r\n', 400),
            (b'GET / HTTP/1.1\r\nHost: x\r\n folded: y\r\n\r\n', 400),
            (b'GET / HTTP/1.1\r\nHost: x\r\nHost: x\r\n\r\n', 400),
            (b'GET / HTTP/1.1\r\n\r\n', 400),
            (b'GET / HTTP/9.9\r\nHost: x\r\n\r\n', 400),
            (b'GET / HTTP/1.1\r\nHost: x\r\nContent-Length: 1\r\n\r\nx', 400),
        ]:
            with self.subTest(raw=raw[:40]):
                response = self.server.raw(raw)
                self.assertTrue(response.startswith(f'HTTP/1.1 {status} '.encode()), response[:80])
        for media in ['application/json', 'application/x-www-form-urlencodedEVIL']:
            self.assertEqual(self.post('/add', 'title=x', headers={'Content-Type': media})[0], 415)

    def test_security_headers_head_and_static_mime(self):
        routes = {'/': 'text/html', '/app.css': 'text/css', '/app.js': 'text/javascript',
                  '/favicon.svg': 'image/svg+xml', '/sitemap.xml': 'application/xml', '/robots.txt': 'text/plain'}
        for route, mime in routes.items():
            with self.subTest(route=route):
                status, headers, body = self.server.request('GET', route)
                self.assertEqual(status, 200)
                self.assertEqual(int(headers['Content-Length']), len(body))
                self.assertTrue(headers['Content-Type'].startswith(mime))
                self.assertEqual(headers['Referrer-Policy'], 'strict-origin')
                self.assertEqual(headers['X-Frame-Options'], 'DENY')
                self.assertNotIn('unsafe-inline', headers['Content-Security-Policy'])
                hs, hh, hb = self.server.request('HEAD', route)
                self.assertEqual(hs, 200); self.assertEqual(hb, b'')
                self.assertEqual(hh['Content-Length'], headers['Content-Length'])
        self.assertIn('noindex', self.server.request('GET', '/app', cookie=self.cookie)[1]['X-Robots-Tag'])
        self.assertEqual(self.server.request('GET', '/add')[0], 405)
        self.assertEqual(self.server.request('PUT', '/')[0], 405)
        self.assertEqual(self.server.request('GET', '/nope')[0], 404)

    def test_concurrent_writes_all_persist(self):
        def add(i):
            return self.post('/add', {'title': f'parallel {i}'})[0]
        with concurrent.futures.ThreadPoolExecutor(max_workers=8) as pool:
            self.assertEqual(list(pool.map(add, range(40))), [303]*40)
        records = self.server.file(self.cookie).read_text().splitlines()[1:]
        self.assertEqual(len(records), 40)
        self.assertEqual(len({line.split('|')[0] for line in records}), 40)

    def test_survives_restart_and_private_permissions(self):
        self.add('persistent')
        self.server.stop(); self.server.start()
        self.assertIn(b'persistent', self.server.request('GET', '/app', cookie=self.cookie)[2])
        self.assertEqual(self.server.file(self.cookie).stat().st_mode & 0o777, 0o600)
        self.assertEqual((self.server.root/'data').stat().st_mode & 0o777, 0o700)

    def test_capacity_is_explicit_and_deletion_reclaims_slot(self):
        path = self.server.file(self.cookie)
        path.write_text(''.join(f'{i}|0|1700000000|item {i}\n' for i in range(1, 1001)))
        original = path.read_bytes()
        self.assertEqual(self.post('/add', {'title': 'overflow'})[0], 409)
        self.assertEqual(path.read_bytes(), original)
        self.assertEqual(self.post('/delete', {'id': '500'})[0], 303)
        self.add('new task')
        text = path.read_text()
        self.assertIn('1001|0|', text)
        self.assertLess(path.stat().st_size, 262144)

    def test_failed_snapshot_preserves_original_and_returns_error(self):
        self.add('original')
        path = self.server.file(self.cookie)
        original = path.read_bytes()
        Path(str(path)+'.tmp').mkdir()
        self.assertEqual(self.post('/add', {'title': 'not saved'})[0], 507)
        self.assertEqual(path.read_bytes(), original)

    def test_corrupt_truncated_oversized_files_not_overwritten(self):
        path = self.server.file(self.cookie)
        for data in [b'1|0|1|torn', b'bad\n', b'1|0|1|a\0b\n', b'x'*262145, b'0|0|1|zero\n']:
            with self.subTest(data=data[:20]):
                path.write_bytes(data)
                self.assertEqual(self.post('/add', {'title': 'no overwrite'})[0], 500)
                self.assertEqual(path.read_bytes(), data)

    def test_symlink_files_lock_and_temp_fail_closed(self):
        outside = self.server.root/'unrelated.txt'
        outside.write_text('DO NOT TOUCH')
        path = self.server.file(self.cookie)
        for suffix, expected in [('', 500), ('.lock', 503), ('.tmp', 507)]:
            with self.subTest(suffix=suffix):
                target = Path(str(path)+suffix)
                target.unlink(missing_ok=True)
                target.symlink_to(outside)
                self.assertEqual(self.post('/add', {'title': 'bad'})[0], expected)
                self.assertEqual(outside.read_text(), 'DO NOT TOUCH')
                target.unlink()

    def test_maximum_render_and_content_length(self):
        self.server.file(self.cookie).write_text(''.join(f'{i}|0|1700000000|' + '"'*110 + '\n' for i in range(1, 1001)))
        status, headers, body = self.server.request('GET', '/app', cookie=self.cookie)
        self.assertEqual(status, 200)
        self.assertEqual(int(headers['Content-Length']), len(body))
        self.assertEqual(body.count(b'<li data-id='), 1000)
        self.assertLess(len(body), 2097152)

    def test_binding_conflict_fails_without_port_scan(self):
        process = subprocess.run([str(BINARY), str(self.server.port)], cwd=self.server.root,
                                 stdout=subprocess.DEVNULL, timeout=2)
        self.assertNotEqual(process.returncode, 0)

    def test_binary_stack_is_explicitly_non_executable(self):
        output = subprocess.check_output(['readelf', '-lW', str(BINARY)], text=True)
        stack = next(line for line in output.splitlines() if 'GNU_STACK' in line)
        self.assertIn('RW ', stack)
        self.assertNotIn('RWE', stack)

    def test_recovery_key_requires_cookie_and_is_attachment(self):
        self.assertEqual(self.server.request('GET', '/recovery')[0], 401)
        status, headers, body = self.server.request('GET', '/recovery', cookie=self.cookie)
        self.assertEqual(status, 200)
        self.assertEqual(body.decode().strip(), self.cookie.split('=')[1])
        self.assertIn('attachment', headers['Content-Disposition'])
        self.assertIn('noindex', headers['X-Robots-Tag'])

    def test_child_absolute_deadline_bounds_slow_drip_feeding(self):
        import time
        with socket.create_connection(('127.0.0.1', self.server.port), timeout=4) as sock:
            start = time.monotonic()
            disconnected = False
            for _ in range(10):
                try:
                    sock.sendall(b'G')
                    time.sleep(2)
                    sock.setblocking(False)
                    try:
                        if sock.recv(1) == b'':
                            disconnected = True
                            break
                    except BlockingIOError:
                        pass
                    finally:
                        sock.setblocking(True)
                except (BrokenPipeError, ConnectionResetError):
                    disconnected = True
                    break
            self.assertTrue(disconnected)
            self.assertLess(time.monotonic() - start, 19)

    def test_forget_clears_cookie_without_deleting_tasks(self):
        self.add()
        status, headers, _ = self.post('/forget', {})
        self.assertEqual(status, 303)
        self.assertIn('Max-Age=0', headers['Set-Cookie'])
        self.assertTrue(self.server.file(self.cookie).exists())

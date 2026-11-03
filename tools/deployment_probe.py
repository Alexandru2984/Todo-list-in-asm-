#!/usr/bin/env python3
"""Create and test a fresh probe workspace; never reads existing users' tasks."""
import argparse
import http.client
import json
from pathlib import Path
import re
import time
from urllib.parse import urlencode, urlsplit


def probe(base, cleanup_data=None):
    target = urlsplit(base)
    cookie = None
    token = None

    def request(method, path, data=None):
        connection = (http.client.HTTPSConnection if target.scheme == 'https' else http.client.HTTPConnection)(target.netloc, timeout=10)
        headers = {'Content-Type': 'application/x-www-form-urlencoded', 'Origin': f'{target.scheme}://{target.netloc}'}
        if cookie:
            headers['Cookie'] = cookie
        try:
            connection.request(method, path, body=urlencode(data) if data is not None else None, headers=headers)
            response = connection.getresponse()
            return response.status, response.headers, response.read()
        finally:
            connection.close()

    try:
        for attempt in range(50):
            try:
                if request('GET', '/healthz')[0] == 200:
                    break
            except (OSError, http.client.HTTPException):
                pass
            if attempt == 49:
                raise RuntimeError('Health check failed after readiness deadline')
            time.sleep(.1)
        status, headers, _ = request('POST', '/start', {})
        assert status == 303, 'Session creation failed'
        cookie = headers['Set-Cookie'].split(';')[0]
        token = cookie.removeprefix('asm_uid=')
        assert re.fullmatch('[a-f0-9]{32}', token), 'Invalid session token'
        assert request('POST', '/add', {'title': 'Release verification'})[0] == 303, 'Add failed'
        status, headers, body = request('GET', '/app')
        assert status == 200 and b'Release verification' in body, 'Workspace read failed'
        assert token.encode() not in body and 'noindex' in headers['X-Robots-Tag'], 'Private-page policy failed'
        assert 'unsafe-inline' not in headers['Content-Security-Policy'], 'CSP failed'
        assert 'no-transform' in headers['Cache-Control'], 'Edge transformation policy failed'
        assert b'challenge-platform' not in body and b'static.cloudflareinsights.com' not in body, 'Unexpected edge script injection'
        status, exported_headers, exported_body = request('GET', '/export.json')
        assert status == 200 and 'attachment' in exported_headers['Content-Disposition'], 'Native JSON download failed'
        assert json.loads(exported_body)['tasks'][0]['title'] == 'Release verification', 'Native JSON contents failed'
        status, exported_headers, exported_body = request('GET', '/export.csv')
        assert status == 200 and b'Release verification' in exported_body, 'Native CSV download failed'
        status, _, filtered = request('GET', '/app?q=definitely-no-match')
        assert status == 200 and b'<li data-id=' not in filtered, 'Native search failed'
        assert b'data-count="total">1<' in filtered, 'Native counts failed'
        for path, data in [('/complete', {'id': '1'}), ('/reopen', {'id': '1'}),
                           ('/edit', {'id': '1', 'title': 'Verified'}), ('/delete', {'id': '1'})]:
            assert request('POST', path, data)[0] == 303, f'{path} failed'
        assert b'Release verification' not in request('GET', '/app')[2], 'Delete did not persist'
        print('Release probe passed: health, session, native search/counts/exports and full task lifecycle')
    finally:
        # Only the fresh getrandom session created by this invocation is removed.
        if cleanup_data and token and re.fullmatch('[a-f0-9]{32}', token):
            for suffix in ['', '.tmp', '.lock']:
                (cleanup_data / f'todos-{token}.txt{suffix}').unlink(missing_ok=True)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--base', required=True)
    parser.add_argument('--cleanup-data-dir', type=Path)
    args = parser.parse_args()
    probe(args.base, args.cleanup_data_dir)

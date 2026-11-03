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
    last_post = 0.0

    def request(method, path, data=None):
        nonlocal last_post
        # Respect the production write bucket without retrying an ambiguous POST.
        if target.scheme == 'https' and method == 'POST':
            remaining = last_post + 2.1 - time.monotonic()
            if remaining > 0:
                time.sleep(remaining)
            last_post = time.monotonic()
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
        assert request('POST', '/restore-task', {'id': '1'})[0] == 303, 'Trash restore failed'
        assert request('POST', '/edit', {'id': '1', 'title': 'Verified', 'priority': 'high',
                       'due': '2031-01-31', 'repeat': 'monthly', 'project': 'Probe', 'tags': 'asm'})[0] == 303, 'Planner properties failed'
        assert request('POST', '/complete', {'id': '1'})[0] == 303, 'Recurring completion failed'
        records = json.loads(request('GET', '/export.json')[2])['tasks']
        assert len(records) == 2 and records[-1]['dueDate'] == '2031-02-28', 'Native recurrence date failed'
        assert records[-1]['recurrenceAnchor'] == 31, 'Native recurrence anchor failed'
        assert request('POST', '/board/start-work', {'id': '2'})[0] == 303, 'Board workflow failed'
        assert b'board-column' in request('GET', '/app?layout=board')[2], 'Native board render failed'
        query = urlencode({'q': 'priority:high #asm project:Probe status:active'})
        status, _, filtered = request('GET', '/app?' + query)
        assert status == 200 and b'data-id="2"' in filtered and b'data-id="1"' not in filtered, 'Structured search failed'
        assert b'data-day="2031-02-28" data-due-count="1"' in request('GET', '/app?layout=calendar&month=2031-02')[2], 'Native calendar failed'
        status, svg_headers, svg = request('GET', '/stats.svg')
        assert status == 200 and svg_headers['Content-Type'].startswith('image/svg+xml'), 'Private SVG failed'
        assert token.encode() not in svg and b'<rect ' in svg, 'SVG contents failed'
        assert request('POST', '/undo', {})[0] == 303, 'Undo failed'
        assert json.loads(request('GET', '/export.json')[2])['tasks'][-1]['stage'] == 'todo', 'Undo workflow state failed'
        assert request('POST', '/redo', {})[0] == 303, 'Redo failed'
        # Exceed ordinary body limits on the import path, using one fixture row.
        payload = json.dumps({'version': 1, 'tasks': [{'id': '999', 'title': 'Imported release verification',
                             'completed': False, 'createdAt': None}]}) + ' ' * 5000
        fields = {'payload': payload, 'format': 'json', 'mode': 'merge'}
        status, preview_headers, preview = request('POST', '/import-preview', fields)
        assert status == 200 and b'Confirm import' in preview, 'Native large import preview failed'
        assert 'no-transform' in preview_headers['Cache-Control'], 'Import edge policy failed'
        assert b'challenge-platform' not in preview and b'static.cloudflareinsights.com' not in preview, 'Import edge script injection'
        assert len(json.loads(request('GET', '/export.json')[2])['tasks']) == 2, 'Preview mutated workspace'
        assert request('POST', '/import', dict(fields, confirmed='1'))[0] == 303, 'Native import confirmation failed'
        assert len(json.loads(request('GET', '/export.json')[2])['tasks']) == 3, 'Native import contents failed'
        assert request('POST', '/undo', {})[0] == 303, 'Atomic import undo failed'
        assert len(json.loads(request('GET', '/export.json')[2])['tasks']) == 2, 'Import undo contents failed'
        assert request('POST', '/delete', {'id': '1'})[0] == 303, 'Planner delete failed'
        assert request('POST', '/purge', {'id': '1'})[0] == 303, 'Permanent purge failed'
        assert request('POST', '/undo', {})[0] == 409, 'Purge did not clear undo'
        robots = request('GET', '/robots.txt')[2]
        assert b'Allow: /app.css' in robots and b'Allow: /app.js' in robots, 'Public asset crawl policy failed'
        print('Release probe passed: native planner, recurrence, board/calendar, SVG, import/undo, trash/purge and edge policy')
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

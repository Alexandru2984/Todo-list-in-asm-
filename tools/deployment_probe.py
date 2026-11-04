#!/usr/bin/env python3
"""Create and test a fresh probe workspace; never reads existing users' tasks."""
import argparse
import http.client
import json
from html.parser import HTMLParser
from pathlib import Path
import re
import time
from urllib.parse import urlencode, urlsplit


class Rotation(HTMLParser):
    def __init__(self, body):
        super().__init__()
        self.fields = {}
        self.in_key = False
        self.feed(body.decode())

    def handle_starttag(self, tag, attrs):
        attrs = dict(attrs)
        if tag == 'input' and attrs.get('name') in ['_state', '_request']:
            self.fields[attrs['name']] = attrs['value']
        if tag == 'textarea' and attrs.get('name') == 'new_key':
            self.in_key = True
            self.fields['new_key'] = ''

    def handle_endtag(self, tag):
        if tag == 'textarea':
            self.in_key = False

    def handle_data(self, data):
        if self.in_key:
            self.fields['new_key'] += data


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
        if method == 'POST' and cookie and path not in ['/start', '/restore', '/forget'] and not any(key in (data or {}) for key in ['_state', '_request']):
            state_status, _, state_body = request('GET', '/state.json')
            assert state_status == 200, 'Private mutation protocol discovery failed'
            state = json.loads(state_body)
            data = dict(data or {}, _state=state['state'], _request=state['operationId'])
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
        capture = {'payload': 'Captured release task\nȘedință release task', 'format': 'lines', 'mode': 'merge'}
        status, _, body = request('POST', '/import-preview', capture)
        assert status == 200 and b'data-import-live="2"' in body, 'Native quick capture preview failed'
        assert len(json.loads(request('GET', '/export.json')[2])['tasks']) == 1, 'Capture preview mutated data'
        assert request('POST', '/import', dict(capture, confirmed='1'))[0] == 303, 'Native quick capture failed'
        records = json.loads(request('GET', '/export.json')[2])['tasks']
        assert [task['title'] for task in records[-2:]] == ['Captured release task', 'Ședință release task'], 'Captured title round trip failed'
        status, calendar_headers, calendar = request('GET', '/export.ics')
        assert status == 200 and calendar_headers['Content-Type'].startswith('text/calendar'), 'Native calendar download failed'
        assert 'attachment' in calendar_headers['Content-Disposition'] and 'noindex' in calendar_headers['X-Robots-Tag'], 'Calendar privacy failed'
        assert calendar.count(b'BEGIN:VEVENT\r\n') == 1 and b'DTSTART;VALUE=DATE:20310228\r\n' in calendar, 'Calendar dated-task snapshot failed'
        assert token.encode() not in calendar, 'Calendar exposed the workspace key'
        assert request('POST', '/undo', {})[0] == 303, 'Quick capture atomic undo failed'
        assert len(json.loads(request('GET', '/export.json')[2])['tasks']) == 1, 'Quick capture undo contents failed'
        state = json.loads(request('GET', '/state.json')[2])
        fields = {'title': 'Persistent replay verification', '_state': state['state'], '_request': state['operationId']}
        assert request('POST', '/add', fields)[0] == 303, 'Guarded action failed'
        assert request('POST', '/add', fields)[0] == 303, 'Successful replay did not return the original redirect'
        assert len(json.loads(request('GET', '/export.json')[2])['tasks']) == 2, 'Replay duplicated a task'
        assert request('POST', '/add', dict(fields, title='Rejected different payload'))[0] == 412, 'Reused operation key was not rejected'
        assert request('POST', '/undo', {})[0] == 303, 'Guarded replay verification undo failed'
        assert len(json.loads(request('GET', '/export.json')[2])['tasks']) == 1, 'Guarded replay verification changed final fixture'
        before_rotation = json.loads(request('GET', '/export.json')[2])
        status, _, page = request('GET', '/rotate-key')
        assert status == 200, 'Rotation preparation failed'
        fields = Rotation(page).fields
        candidate = fields['new_key']
        assert re.fullmatch('[a-f0-9]{64}', candidate) and candidate.startswith(token), 'Invalid prepared key'
        status, key_headers, key_body = request('POST', '/rotation-key', fields)
        assert status == 200 and key_body == candidate.encode() + b'\n', 'Prepared-key download failed'
        assert 'attachment' in key_headers['Content-Disposition'], 'Prepared key was not an attachment'
        previous_cookie = cookie
        fields['saved'] = '1'
        status, key_headers, _ = request('POST', '/rotate-key', fields)
        assert status == 303, 'Rotation confirmation failed'
        cookie = key_headers['Set-Cookie'].split(';')[0]
        assert cookie == 'asm_uid=' + candidate, 'Rotated session cookie failed'
        after_rotation = json.loads(request('GET', '/export.json')[2])
        assert all(after_rotation[key] == before_rotation[key] for key in ['tasks', 'trash']), 'Rotation changed task contents'
        before_retry = request('GET', '/state.json')[2]
        cookie = previous_cookie
        assert request('GET', '/state.json')[0] == 410, 'Old key was not revoked'
        status, key_headers, _ = request('POST', '/rotate-key', fields)
        assert status == 303, 'Lost-response recovery failed'
        cookie = key_headers['Set-Cookie'].split(';')[0]
        after_retry = request('GET', '/state.json')[2]
        assert json.loads(before_retry)['revision'] == json.loads(after_retry)['revision'], 'Recovery retried rotation'
        assert request('GET', '/recovery')[2] == candidate.encode() + b'\n', 'Rotated recovery download failed'
        robots = request('GET', '/robots.txt')[2]
        assert b'Allow: /app.css' in robots and b'Allow: /app.js' in robots, 'Public asset crawl policy failed'
        print('Release probe passed: native planner, recurrence, board/calendar, SVG, import/undo, quick capture, ICS, conflicts/replay, key rotation/revocation/recovery, trash/purge and edge policy')
        return cookie
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

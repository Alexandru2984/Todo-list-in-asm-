"""No JavaScript: assert server-selected rows, counts, forms and ordering."""
from html.parser import HTMLParser
import json
import random
import re
import unittest
from urllib.parse import urlencode
from server import Server


class Rows(HTMLParser):
    def __init__(self, body):
        super().__init__(); self.ids = []; self.counters = {}; self.text_target = None
        self.feed(body.decode())
    def handle_starttag(self, tag, attrs):
        attrs = dict(attrs)
        if tag == 'li' and 'data-id' in attrs: self.ids.append(int(attrs['data-id']))
        if 'data-count' in attrs: self.text_target = attrs['data-count']
    def handle_data(self, data):
        if self.text_target:
            self.counters[self.text_target] = int(data); self.text_target = None


class NativeViewTests(unittest.TestCase):
    def setUp(self):
        self.server = Server(); self.addCleanup(self.server.close)
        self.cookie = self.server.session()
        self.server.file(self.cookie).write_text('1|0|0|Zulu\n2|1|1700000000|alpha\n3|0|1700000000|Ședință 😀\n')

    def get(self, query=''):
        return self.server.request('GET', '/app'+('?' + query if query else ''), cookie=self.cookie)

    def test_server_counts_progress_and_native_dates(self):
        status, _, body = self.get()
        self.assertEqual(status, 200)
        rows = Rows(body)
        self.assertEqual(rows.ids, [3, 2, 1])
        self.assertEqual(rows.counters, {'total': 3, 'active': 2, 'done': 1})
        self.assertIn(b'id="progress-percent">33%</strong>', body)
        self.assertIn(b'<time class="task-date">1970-01-01</time>', body)
        self.assertNotIn(b'{{', body)

    def test_filters_and_search_keep_global_counts(self):
        for query, expected in [('f=active',[3,1]), ('f=done',[2]), ('q=ALPHA',[2]),
                                (urlencode({'q':'șEDINȚĂ'}),[3]), ('q=missing',[])]:
            with self.subTest(query=query):
                status, _, body = self.get(query)
                self.assertEqual(status, 200)
                parsed = Rows(body)
                self.assertEqual(parsed.ids, expected)
                self.assertEqual(parsed.counters['total'], 3)
                self.assertEqual(parsed.counters['done'], 1)

    def test_deterministic_sorting_and_large_ids(self):
        for sort, expected in [('oldest',[1,2,3]),('newest',[3,2,1]),('az',[2,1,3]),('active',[3,1,2])]:
            self.assertEqual(Rows(self.get('sort='+sort)[2]).ids, expected)
        path = self.server.file(self.cookie)
        path.write_text('9007199254740992|0|0|same\n9007199254740993|0|0|SAME\n')
        self.assertEqual(Rows(self.get('sort=az')[2]).ids, [9007199254740993,9007199254740992])

    def test_merge_sort_full_capacity_against_independent_order(self):
        rng = random.Random(2026)
        titles = [str(rng.randrange(1000000)).zfill(7) for _ in range(1000)]
        self.server.file(self.cookie).write_text(''.join(f'{i}|0|0|{title}\n' for i,title in enumerate(titles,1)))
        status, headers, body = self.get('sort=az')
        self.assertEqual(status, 200)
        self.assertEqual(Rows(body).ids, sorted(range(1,1001),key=lambda i:(titles[i-1],-i)))
        self.assertEqual(int(headers['Content-Length']), len(body))

    def test_query_names_values_duplicates_and_invalid_utf8_fail_closed(self):
        for query in ['f=bad','sort=bad','xq=a','q=%ff','q=%00','q=%0a','q=%',
                      'q=a&q=b','f=all&f=done','sort=az&sort=oldest','edit=0',
                      'edit=1&delete=2','confirm=bad','q='+('x'*111),'q=a&','q']:
            with self.subTest(query=query):
                self.assertEqual(self.get(query)[0], 400)

    def test_query_echo_is_html_escaped_and_links_url_encoded(self):
        _, _, body = self.get(urlencode({'q':'"<>&😀', 'sort':'az','f':'done'}))
        self.assertIn(b'value="&#34;&lt;&gt;&amp;', body)
        self.assertIn(b'q=%22%3C%3E%26%F0%9F%98%80', body)
        self.assertNotIn(b'value=""<', body)

    def test_edit_and_delete_confirmation_gets_do_not_mutate(self):
        path = self.server.file(self.cookie); before = path.read_bytes()
        for query in ['edit=1','delete=1','confirm=clear','confirm=forget']:
            status, _, body = self.get(query)
            self.assertEqual(status, 200)
            self.assertIn(b'id="action-form"', body)
            self.assertEqual(path.read_bytes(), before)
        self.assertIn(b'name="title" required maxlength="110" value="Zulu"', self.get('edit=1')[2])
        self.assertEqual(self.get('edit=999')[0], 404)
        self.assertEqual(self.get('delete=999')[0], 404)

    def test_duplicate_creates_new_active_task_without_changing_original(self):
        status, _, _ = self.server.request('POST','/duplicate',{'id':2},cookie=self.cookie)
        self.assertEqual(status,303)
        records = json.loads(self.server.request('GET','/export.json',cookie=self.cookie)[2])['tasks']
        self.assertTrue(records[1]['completed'])
        self.assertEqual(records[-1]['title'],'alpha')
        self.assertFalse(records[-1]['completed'])
        self.assertEqual(records[-1]['id'],'4')
        self.assertEqual(self.server.request('GET','/duplicate',cookie=self.cookie)[0],405)
        self.assertEqual(self.server.request('POST','/duplicate',{'id':999},cookie=self.cookie)[0],404)

    def test_duplicate_obeys_capacity_and_cookie_isolation(self):
        other = self.server.session()
        self.assertEqual(self.server.request('POST','/duplicate',{'id':1},cookie=other)[0],404)
        self.assertEqual(self.server.request('POST','/duplicate',{'id':1})[0],401)
        path = self.server.file(self.cookie)
        path.write_text(''.join(f'{i}|0|0|full\n' for i in range(1,1001)))
        before = path.read_bytes()
        self.assertEqual(self.server.request('POST','/duplicate',{'id':1},cookie=self.cookie)[0],409)
        self.assertEqual(path.read_bytes(),before)

    def test_empty_workspace_renders_correctly_without_client_script(self):
        cookie = self.server.session()
        status, _, body = self.server.request('GET','/app',cookie=cookie)
        self.assertEqual(status,200)
        self.assertIn(b'id="empty-state" class="empty-state" >',body)
        self.assertIn(b'id="progress-percent">0%</strong>',body)
        self.assertEqual(Rows(body).counters['total'],0)

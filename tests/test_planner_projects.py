"""Native project/tag parsing, folded exact filters and worst-case rendering."""
import json
import unittest
from urllib.parse import urlencode
from server import Server
from test_native_views import Rows
from test_planner_storage import snapshot


class PlannerProjectTests(unittest.TestCase):
    def setUp(self):
        self.server = Server();self.addCleanup(self.server.close)
        self.cookie = self.server.session();self.path = self.server.file(self.cookie)

    def post(self, route, fields):
        return self.server.request('POST',route,fields,cookie=self.cookie)

    def get(self, fields=None):
        return self.server.request('GET','/app'+('?' + urlencode(fields) if fields else ''),cookie=self.cookie)

    def tasks(self):
        return json.loads(self.server.request('GET','/export.json',cookie=self.cookie)[2])['tasks']

    def test_native_fields_normalize_tags_and_preserve_through_lifecycle(self):
        self.assertEqual(self.post('/add',dict(title='work',project='  Ședință 😀  ',tags=' asm, security ,ședință '))[0],303)
        task = self.tasks()[0]
        self.assertEqual(task['project'],'Ședință 😀');self.assertEqual(task['tags'],'asm,security,ședință')
        self.assertEqual(self.post('/edit',dict(id=1,title='edited'))[0],303)
        self.assertEqual(self.post('/duplicate',dict(id=1))[0],303)
        self.assertTrue(all(task['project']=='Ședință 😀' for task in self.tasks()))
        self.assertTrue(all(task['tags']=='asm,security,ședință' for task in self.tasks()))
        self.assertEqual(self.post('/edit',dict(id=1,title='cleared',project='',tags='   '))[0],303)
        self.assertEqual(self.tasks()[0]['project'],'');self.assertEqual(self.tasks()[0]['tags'],'')

    def test_exact_unicode_filters_combine_with_status_title_and_sort(self):
        for title, project, tags in [('one meeting','Ședință','asm,mobile'),('two meeting','ȘEDINȚĂ','asm'),('three','personal','asm')]:
            self.assertEqual(self.post('/add',dict(title=title,project=project,tags=tags))[0],303)
        self.assertEqual(self.post('/complete',dict(id=2))[0],303)
        for fields, expected in [({'project':'ședință'},[2,1]),({'tag':'ASM'},[3,2,1]),
                                 ({'tag':'as'},[]),({'project':'ședință','tag':'mobile'},[1]),
                                 ({'project':'ședință','f':'active','q':'MEETING'},[1]),
                                 ({'project':'ședință','f':'done'},[2]),
                                 ({'project':'ședință','sort':'oldest'},[1,2])]:
            with self.subTest(fields=fields):
                status, _, body = self.get(fields)
                self.assertEqual(status,200);self.assertEqual(Rows(body).ids,expected)
                self.assertEqual(Rows(body).counters['total'],3)

    def test_scalar_and_tag_bounds_duplicate_folding_controls_and_unknowns(self):
        self.assertEqual(self.post('/add',dict(title='original'))[0],303)
        original = self.path.read_bytes()
        values = [dict(project='ș'*17),dict(tags='x'*25),dict(tags='a,'),dict(tags=',a'),
                  dict(tags='a,,b'),dict(tags='asm,ASM'),dict(tags='ș,Ș'),
                  dict(tags=','.join(str(i) for i in range(9))),dict(tags='a'*65),
                  dict(project='bad\n'),dict(tags='bad|field')]
        for fields in values:
            with self.subTest(fields=fields):
                self.assertEqual(self.post('/add',dict(title='invalid',**fields))[0],400)
                self.assertEqual(self.path.read_bytes(),original)
        for body in ['title=x&project=a&project=b','title=x&tags=a&tags=b']:
            self.assertEqual(self.post('/add',body)[0],400)
        self.assertEqual(self.post('/add',dict(title='bounded',project='ș'*16,tags=','.join(str(i) for i in range(8))))[0],303)
        for fields in [{'project':'x'*33},{'tag':'x'*25},{'tag':'a,b'},{'tag':'\n'}]:
            self.assertEqual(self.get(fields)[0],400)
        for query in ['project=a&project=b','tag=a&tag=b']:
            self.assertEqual(self.server.request('GET','/app?'+query,cookie=self.cookie)[0],400)

    def test_property_and_filter_html_are_escaped_and_links_preserve_filters(self):
        project = '\"><img src=x>'
        self.assertEqual(self.post('/add',dict(title='safe',project=project,tags='a&b'))[0],303)
        status, _, body = self.get({'edit':1,'project':project,'tag':'a&b'})
        self.assertEqual(status,200)
        self.assertNotIn(b'<img src=x>',body)
        self.assertIn(b'&#34;&gt;&lt;img src=x&gt;',body)
        self.assertIn(b'project=%22%3E%3Cimg%20src%3Dx%3E',body)
        self.assertIn(b'tag=a%26b',body)

    def test_maximum_escaped_metadata_render_stays_inside_declared_buffer(self):
        values = dict(priority=3,due=1793664000,repeat=5,anchor=1231,project='"'*32,tags='"'*64)
        self.path.write_text(snapshot([(i,0,'"'*110,values) for i in range(1,1001)]))
        status, headers, body = self.get()
        self.assertEqual(status,200)
        self.assertEqual(int(headers['Content-Length']),len(body))
        self.assertEqual(len(Rows(body).ids),1000)
        self.assertLess(len(body),4194304)
        self.assertTrue(body.endswith(b'</body></html>\n'))

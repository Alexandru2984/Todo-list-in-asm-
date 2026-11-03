"""Native date/priority forms, calendar boundaries, filters and export contracts."""
import csv
from datetime import date, datetime, timedelta, timezone
import io
import json
import random
import unittest
from server import Server
from test_native_views import Rows
from test_planner_storage import metadata, snapshot


class PlannerDatesTests(unittest.TestCase):
    def setUp(self):
        self.server = Server(); self.addCleanup(self.server.close)
        self.cookie = self.server.session(); self.path = self.server.file(self.cookie)

    def post(self, route, fields):
        return self.server.request('POST', route, fields, cookie=self.cookie)

    def get(self, query=''):
        return self.server.request('GET', '/app'+('?' + query if query else ''), cookie=self.cookie)

    def export(self):
        return json.loads(self.server.request('GET','/export.json',cookie=self.cookie)[2])

    def test_native_forms_save_properties_and_legacy_edits_preserve_them(self):
        self.assertEqual(self.post('/add',{'title':'first','priority':'urgent','due':'2026-12-31'})[0],303)
        task = self.export()['tasks'][0]
        self.assertEqual((task['priority'],task['dueDate']),('urgent','2026-12-31'))
        self.assertIsNone(task['completedAt'])
        self.assertEqual(self.post('/edit',{'id':1,'title':'renamed'})[0],303)
        body = self.get('edit=1')[2]
        self.assertIn(b'<option value="urgent" selected>',body)
        self.assertIn(b'value="2026-12-31"',body)
        self.assertIn(b'data-priority="urgent">urgent priority',body)
        self.assertEqual(self.post('/complete',{'id':1})[0],303)
        completed = self.export()['tasks'][0]['completedAt']
        self.assertAlmostEqual(datetime.fromisoformat(completed.replace('Z','+00:00')).timestamp(), datetime.now(timezone.utc).timestamp(), delta=5)
        self.assertEqual(self.post('/complete',{'id':1})[0],303)
        self.assertEqual(self.export()['tasks'][0]['completedAt'],completed)
        self.assertEqual(self.post('/reopen',{'id':1})[0],303)
        self.assertIsNone(self.export()['tasks'][0]['completedAt'])
        self.assertEqual(self.post('/edit',{'id':1,'title':'cleared','priority':'normal','due':''})[0],303)
        task = self.export()['tasks'][0]
        self.assertEqual(task['priority'],'normal'); self.assertIsNone(task['dueDate'])

    def test_strict_dates_and_duplicate_fields_fail_without_mutation(self):
        self.assertEqual(self.post('/add',{'title':'original'})[0],303)
        before = self.path.read_bytes()
        dates = ['2026-02-29','2100-02-29','2000-02-30','2026-04-31','2026-00-01',
                 '2026-13-01','2026-01-00','1969-12-31','1970-01-01','10000-01-01',
                 '2026-1-01','2026-01-1','2026-01-01extra','2026-01-01\n','0000-01-01']
        for due in dates:
            with self.subTest(due=due):
                self.assertEqual(self.post('/edit',{'id':1,'title':'invalid','due':due})[0],400)
                self.assertEqual(self.path.read_bytes(),before)
        for body in ['title=x&priority=high&priority=low','title=x&due=&due=',
                     'title=x&priority=HIGH','title=x&priority=','title=x&priority=high%00']:
            self.assertEqual(self.post('/add',body)[0],400)
        for route, fields in [('/complete',{'id':1,'priority':'high'}),('/start',{'due':''}),
                              ('/clear-done',{'priority':'low'}),('/delete',{'id':1,'due':''})]:
            self.assertEqual(self.post(route,fields)[0],400)
        self.assertEqual(self.path.read_bytes(),before)

    def test_native_date_parser_matches_independent_gregorian_calendar(self):
        rng = random.Random(2984)
        dates = [date(1970,1,2),date(2000,2,29),date(2100,3,1),date(2400,2,29),date(9999,12,31)]
        dates += [date.fromordinal(rng.randrange(date(1970,1,2).toordinal(),date(9999,12,31).toordinal()+1)) for _ in range(150)]
        for i, due in enumerate(dates,1):
            self.assertEqual(self.post('/add',{'title':str(i),'due':due.isoformat()})[0],303)
        tasks = self.export()['tasks']
        for i, (due, task) in enumerate(zip(dates,tasks),1):
            self.assertEqual(task['dueDate'],due.isoformat())
            expected = int(datetime.combine(due,datetime.min.time(),timezone.utc).timestamp())
            self.assertIn(metadata(i,due=expected),self.path.read_text())

    def test_date_views_and_deterministic_priority_due_sorts(self):
        today = datetime.now(timezone.utc).date()
        rows = [(-1,'low'), (0,'normal'), (1,'high'), (7,'urgent'), (8,'high'), (None,'urgent')]
        for i,(delta,priority) in enumerate(rows,1):
            self.assertEqual(self.post('/add',{'title':str(i),'priority':priority,
                'due':'' if delta is None else (today+timedelta(days=delta)).isoformat()})[0],303)
        self.assertEqual(Rows(self.get('f=today')[2]).ids,[2])
        self.assertEqual(Rows(self.get('f=upcoming')[2]).ids,[4,3])
        self.assertEqual(Rows(self.get('f=overdue')[2]).ids,[1])
        self.assertEqual(Rows(self.get('sort=priority')[2]).ids,[6,4,5,3,2,1])
        self.assertEqual(Rows(self.get('sort=due')[2]).ids,[1,2,3,4,5,6])
        self.assertEqual(self.post('/complete',{'id':2})[0],303)
        self.assertEqual(Rows(self.get('f=today')[2]).ids,[])
        self.assertEqual(Rows(self.get('f=done&sort=due')[2]).ids,[2])

    def test_full_metadata_and_trash_exports_preserve_spreadsheet_escape_flags(self):
        meta = dict(priority=2,due=1793664000,completed=1700000100,parent=2,
                    repeat=5,anchor=229,project='=SUM(A1)',tags='+asm',deps='2',stage=1)
        # parent->child and child->parent dependency would cycle: use third prerequisite.
        meta['deps']='3'
        self.path.write_text(snapshot([(1,1,'=title',meta),(2,0,'parent',{}),(3,1,'prerequisite',{}),
                                      (4,2,'old deleted',{'deleted':1700000001,'previous':1})]))
        document = self.export()
        self.assertEqual(document['version'],2)
        task = document['tasks'][0]
        self.assertEqual(task['priority'],'high')
        self.assertEqual(task['project'],'=SUM(A1)'); self.assertEqual(task['tags'],'+asm')
        self.assertEqual(task['parentId'],'2'); self.assertEqual(task['dependencies'],['3'])
        self.assertEqual(task['recurrence'],'yearly'); self.assertEqual(task['recurrenceAnchor'],229)
        self.assertEqual(task['stage'],'done')
        self.assertEqual(document['trash'][0]['id'],'4')
        self.assertTrue(document['trash'][0]['previousCompleted'])
        status, _, body = self.server.request('GET','/export.csv',cookie=self.cookie)
        self.assertEqual(status,200)
        records = list(csv.DictReader(io.StringIO(body.decode('utf-8-sig'))))
        self.assertEqual(len(records),4)
        self.assertEqual(records[0]['escapeFlags'],'7')
        for field in ['title','project','tags']: self.assertTrue(records[0][field].startswith("'"))
        self.assertEqual(records[0]['dependencies'],'3')
        self.assertEqual(records[-1]['deletedAt'],'2023-11-14T22:13:21Z')

    def test_storage_failure_draft_keeps_priority_and_due_date(self):
        self.assertEqual(self.post('/add',{'title':'original'})[0],303)
        self.path.with_suffix('.txt.tmp').mkdir()
        status, _, body = self.post('/edit',{'id':1,'title':'draft','priority':'high','due':'2027-01-01'})
        self.assertEqual(status,507)
        self.assertIn(b'action="/edit"',body)
        self.assertIn(b'<option value="high" selected>',body)
        self.assertIn(b'value="2027-01-01"',body)
        self.assertEqual(self.export()['tasks'][0]['title'],'original')

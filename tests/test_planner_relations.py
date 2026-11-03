"""Native relationship mutations validate the union graph before one commit."""
import json
import unittest
from server import Server
from test_native_views import Rows
from test_planner_storage import snapshot


class PlannerRelationTests(unittest.TestCase):
    def setUp(self):
        self.server=Server();self.addCleanup(self.server.close)
        self.cookie=self.server.session();self.path=self.server.file(self.cookie)

    def post(self,route,values):
        return self.server.request('POST',route,values,cookie=self.cookie)[0]

    def tasks(self):
        return json.loads(self.server.request('GET','/export.json',cookie=self.cookie)[2])['tasks']

    def get(self,query=''):
        return self.server.request('GET','/app'+('?' + query if query else ''),cookie=self.cookie)

    def add(self,title,**values):
        self.assertEqual(self.post('/add',dict(title=title,**values)),303)

    def test_subtask_prefill_blocked_view_completion_and_parent_reopening(self):
        self.add('parent')
        before=self.path.read_bytes()
        status,_,body=self.get('newparent=1')
        self.assertEqual(status,200)
        self.assertIn(b'name="parent" min="0" max="9223372036854775806" value="1"',body)
        self.assertEqual(self.path.read_bytes(),before)
        self.add('child',parent=1)
        self.assertEqual(self.tasks()[1]['parentId'],'1')
        self.assertEqual(Rows(self.get('f=blocked')[2]).ids,[1])
        before=self.path.read_bytes()
        self.assertEqual(self.post('/complete',dict(id=1)),409)
        self.assertEqual(self.path.read_bytes(),before)
        self.assertIn(b'Waiting for prerequisites or subtasks',self.get()[2])
        self.assertEqual(self.post('/complete',dict(id=2)),303)
        self.assertEqual(self.post('/complete',dict(id=1)),303)
        self.assertEqual(self.post('/reopen',dict(id=2)),409)
        self.assertEqual(self.post('/reopen',dict(id=1)),303)
        self.assertEqual(self.post('/reopen',dict(id=2)),303)
        self.assertEqual(Rows(self.get('f=blocked')[2]).ids,[1])

    def test_prerequisites_need_completion_and_deleted_prerequisites_remain_blocking(self):
        self.add('prerequisite');self.add('dependent',deps='1')
        self.assertEqual(self.post('/complete',dict(id=2)),409)
        self.assertEqual(self.post('/complete',dict(id=1)),303)
        self.assertEqual(Rows(self.get('f=blocked')[2]).ids,[])
        self.assertEqual(self.post('/delete',dict(id=1)),303)
        self.assertEqual(self.post('/complete',dict(id=2)),409)
        self.assertEqual(self.post('/edit',dict(id=2,title='detached',deps='')),303)
        self.assertEqual(self.post('/complete',dict(id=2)),303)

    def test_union_graph_cycles_self_links_and_missing_references_do_not_save(self):
        self.add('one');self.add('two');self.add('three')
        invalid=[dict(id=1,title='self',parent=1),dict(id=1,title='self',deps='1'),
                 dict(id=1,title='missing',parent=99),dict(id=1,title='missing',deps='99'),
                 dict(id=1,title='duplicate',deps='2,2'),dict(id=1,title='empty',deps='2,'),
                 dict(id=1,title='overflow',deps='9223372036854775808'),
                 dict(id=1,title='negative',parent='-1')]
        for values in invalid:
            with self.subTest(values=values):
                before=self.path.read_bytes()
                self.assertEqual(self.post('/edit',values),400)
                self.assertEqual(self.path.read_bytes(),before)
        self.assertEqual(self.post('/edit',dict(id=1,title='one',deps='2')),303)
        before=self.path.read_bytes()
        self.assertEqual(self.post('/edit',dict(id=2,title='two',deps='1')),400)
        self.assertEqual(self.path.read_bytes(),before)
        # Parent -> child combined with child -> prerequisite-parent is a cycle.
        self.assertEqual(self.post('/edit',dict(id=1,title='one',parent=2)),400)
        self.assertEqual(self.path.read_bytes(),before)
        self.assertEqual(self.post('/edit',dict(id=2,title='two',parent=1)),303)
        before=self.path.read_bytes()
        self.assertEqual(self.post('/edit',dict(id=1,title='one',parent=2)),400)
        self.assertEqual(self.path.read_bytes(),before)

    def test_eight_dependencies_strict_duplicates_controls_and_large_ids(self):
        for i in range(1,10):self.add(str(i))
        deps=','.join(str(i) for i in range(1,9))
        self.assertEqual(self.post('/edit',dict(id=9,title='dependent',deps=deps)),303)
        self.assertEqual(self.tasks()[-1]['dependencies'],[str(i) for i in range(1,9)])
        before=self.path.read_bytes()
        for body in ['id=9&title=x&deps=1&deps=2','id=9&title=x&parent=0&parent=1',
                     'id=9&title=x&deps=1%00','id=9&title=x&parent=1%0A',
                     'id=9&title=x&deps='+','.join(str(i) for i in range(1,10))]:
            self.assertEqual(self.post('/edit',body),400)
            self.assertEqual(self.path.read_bytes(),before)
        self.path.write_text('9007199254740992|0|0|large parent\n9007199254740993|0|0|large child\n')
        self.assertEqual(self.post('/edit',dict(id='9007199254740993',title='large child',parent='9007199254740992')),303)
        self.assertEqual(self.tasks()[1]['parentId'],'9007199254740992')

    def test_completed_parent_and_done_task_cannot_gain_unfinished_work(self):
        self.add('parent');self.add('prerequisite')
        self.assertEqual(self.post('/complete',dict(id=1)),303)
        before=self.path.read_bytes()
        self.assertEqual(self.post('/add',dict(title='child',parent=1)),409)
        self.assertEqual(self.path.read_bytes(),before)
        self.assertEqual(self.post('/edit',dict(id=1,title='parent',deps='2')),409)
        self.assertEqual(self.path.read_bytes(),before)
        self.assertEqual(self.get('newparent=1')[0],409)
        self.assertEqual(self.get('newparent=999')[0],404)
        for query in ['newparent=0','newparent=1&newparent=2']:
            self.assertEqual(self.get(query)[0],400)

    def test_subtree_delete_preserves_other_tasks_and_duplicate_keeps_relationships(self):
        self.add('parent');self.add('child',parent=1);self.add('grandchild',parent=2)
        self.add('independent prerequisite');self.add('dependent',parent=1,deps='4')
        self.assertEqual(self.post('/duplicate',dict(id=5)),303)
        self.assertEqual(self.tasks()[-1]['parentId'],'1')
        self.assertEqual(self.tasks()[-1]['dependencies'],['4'])
        self.assertEqual(self.post('/delete',dict(id=1)),303)
        self.assertEqual([task['id'] for task in self.tasks()],['4'])
        document=json.loads(self.server.request('GET','/export.json',cookie=self.cookie)[2])
        self.assertEqual(len(document['trash']),5)

    def test_maximum_graph_and_escaped_metadata_render_have_explicit_headroom(self):
        records=[]
        first=9223372036854774000
        for i in range(1000):
            values=dict(priority=3,due=1793664000,project='"'*32,tags='"'*64,
                        deps=','.join(str(first+j) for j in range(max(0,i-8),i)))
            records.append((first+i,0,'"'*110,values))
        self.path.write_text(snapshot(records))
        status,headers,body=self.get()
        self.assertEqual(status,200)
        self.assertEqual(int(headers['Content-Length']),len(body))
        self.assertEqual(len(Rows(body).ids),1000)
        self.assertGreater(len(body),2097152)
        self.assertLess(len(body),4194304)

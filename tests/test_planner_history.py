"""Undo/redo/trash are native atomic workspace transactions, not browser state."""
from datetime import date, datetime, timezone
import json
from pathlib import Path
import subprocess
import tarfile
import unittest
from server import Server
from test_native_views import Rows
from test_planner_storage import snapshot


class PlannerHistoryTests(unittest.TestCase):
    def setUp(self):
        self.server=Server();self.addCleanup(self.server.close)
        self.cookie=self.server.session();self.path=self.server.file(self.cookie)

    def post(self,route,values=None):
        return self.server.request('POST',route,values or {},cookie=self.cookie)[0]

    def document(self):
        status,_,body=self.server.request('GET','/export.json',cookie=self.cookie)
        self.assertEqual(status,200)
        return json.loads(body)

    def get(self,query=''):
        return self.server.request('GET','/app'+('?' + query if query else ''),cookie=self.cookie)

    def add(self,title,**values):self.assertEqual(self.post('/add',dict(title=title,**values)),303)

    def test_add_undo_redo_new_branch_and_restart_keep_monotonic_ids(self):
        self.assertEqual(self.post('/undo'),409)
        self.add('first')
        self.assertIn('#undo=1\n',self.path.read_text())
        self.assertEqual(self.post('/undo'),303)
        self.assertEqual(self.document()['tasks'],[])
        before=self.path.read_bytes()
        self.assertEqual(self.post('/undo'),409);self.assertEqual(self.path.read_bytes(),before)
        self.assertEqual(self.post('/redo'),303)
        self.assertEqual(self.document()['tasks'][0]['id'],'1')
        self.assertEqual(self.post('/undo'),303)
        self.server.stop();self.server.start()
        self.add('second')
        self.assertEqual(self.document()['tasks'][0]['id'],'2')
        self.assertEqual(self.post('/redo'),409)
        self.assertEqual(self.post('/undo'),303)
        self.assertEqual(self.document()['tasks'],[])

    def test_recurrence_undo_swaps_entire_task_set_and_completion_metrics(self):
        self.add('monthly',repeat='monthly',due='2031-01-31',project='Work',tags='asm')
        original=self.document()['tasks']
        self.assertEqual(self.post('/complete',dict(id=1)),303)
        after=self.document()['tasks']
        self.assertEqual(len(after),2)
        day=int(datetime.now(timezone.utc).timestamp())//86400
        self.assertIn(f'M|{day}|1\n',self.path.read_text())
        self.assertEqual(self.post('/undo'),303)
        self.assertEqual(self.document()['tasks'],original)
        self.assertNotIn(f'M|{day}|1\n',self.path.read_text())
        self.assertEqual(self.post('/redo'),303)
        self.assertEqual(self.document()['tasks'],after)
        self.assertIn(f'M|{day}|1\n',self.path.read_text())

    def test_delete_subtree_restore_child_detach_and_undo_restore(self):
        self.add('parent');self.add('child',parent=1);self.add('grandchild',parent=2)
        self.assertEqual(self.post('/delete',dict(id=1)),303)
        self.assertEqual(Rows(self.get('f=trash')[2]).ids,[3,2,1])
        self.assertEqual(self.document()['tasks'],[])
        self.assertEqual(self.post('/restore-task',dict(id=2)),303)
        tasks=self.document()['tasks']
        self.assertEqual([task['id'] for task in tasks],['2','3'])
        self.assertIsNone(tasks[0]['parentId']);self.assertEqual(tasks[1]['parentId'],'2')
        self.assertEqual(self.post('/undo'),303)
        self.assertEqual(len(self.document()['trash']),3)
        self.assertEqual(self.post('/restore-task',dict(id=1)),303)
        tasks=self.document()['tasks']
        self.assertEqual([task['id'] for task in tasks],['1','2','3'])
        self.assertEqual(tasks[1]['parentId'],'1')

    def test_purge_detaches_references_clears_undo_and_removes_private_title(self):
        secret='private permanently removed title'
        self.add(secret);self.add('dependent',deps='1')
        self.assertEqual(self.post('/delete',dict(id=1)),303)
        before=self.path.read_bytes()
        status,_,body=self.get('purge=1')
        self.assertEqual(status,200);self.assertIn(b'Permanently remove',body)
        self.assertEqual(self.path.read_bytes(),before)
        self.assertEqual(self.post('/purge',dict(id=1)),303)
        self.assertNotIn(secret,self.path.read_text())
        self.assertIn('#undo=0\n',self.path.read_text())
        document=self.document()
        self.assertEqual(document['trash'],[]);self.assertEqual(document['tasks'][0]['dependencies'],[])
        self.assertEqual(self.post('/undo'),409)
        self.assertEqual(self.post('/redo'),409)
        self.assertEqual(self.post('/complete',dict(id=2)),303)

    def test_empty_trash_confirmation_is_read_only_and_bulk_purge_clears_content(self):
        self.add('delete one');self.add('delete two')
        for task_id in [1,2]:self.assertEqual(self.post('/delete',dict(id=task_id)),303)
        before=self.path.read_bytes()
        self.assertEqual(self.get('confirm=empty-trash')[0],200)
        self.assertEqual(self.path.read_bytes(),before)
        self.assertEqual(self.post('/empty-trash'),303)
        self.assertEqual(self.document()['trash'],[])
        self.assertNotIn('delete one',self.path.read_text());self.assertNotIn('delete two',self.path.read_text())
        self.assertEqual(self.post('/undo'),409)

    def test_restore_capacity_and_failed_undo_or_purge_preserve_original_file(self):
        records=[(i,0,'live',{}) for i in range(1,1001)]
        records.append((1001,2,'trashed',dict(deleted=1700000001)))
        self.path.write_text(snapshot(records))
        before=self.path.read_bytes()
        self.assertEqual(self.post('/restore-task',dict(id=1001)),409)
        self.assertEqual(self.path.read_bytes(),before)
        self.path.unlink();self.add('original')
        before=self.path.read_bytes();self.path.with_suffix('.txt.tmp').mkdir()
        self.assertEqual(self.post('/undo'),507);self.assertEqual(self.path.read_bytes(),before)
        self.path.with_suffix('.txt.tmp').rmdir()
        self.assertEqual(self.post('/delete',dict(id=1)),303)
        before=self.path.read_bytes();self.path.with_suffix('.txt.tmp').mkdir()
        self.assertEqual(self.post('/purge',dict(id=1)),507);self.assertEqual(self.path.read_bytes(),before)

    def test_activity_is_bounded_numeric_and_not_a_capability_leak(self):
        self.add('title never in activity')
        for i in range(25):self.assertEqual(self.post('/edit',dict(id=1,title=f'edited {i}')),303)
        lines=self.path.read_text().splitlines()
        events=[line for line in lines if line.startswith('E|')]
        self.assertEqual(len(events),20)
        self.assertTrue(all(len(line.split('|'))==4 for line in events))
        body=self.get()[2]
        self.assertIn(b'Recent changes',body)
        self.assertNotIn(self.cookie.split('=')[1].encode(),body)
        self.assertEqual(body.count(b'<li><time>'),20)

    def test_history_endpoints_require_auth_origin_and_exact_fields(self):
        self.add('one')
        before=self.path.read_bytes()
        for route,fields in [('/undo',{}),('/redo',{}),('/restore-task',dict(id=1)),('/purge',dict(id=1)),('/empty-trash',{})]:
            self.assertEqual(self.server.request('GET',route,cookie=self.cookie)[0],405)
            self.assertEqual(self.server.request('POST',route,fields)[0],401)
            self.assertEqual(self.server.request('POST',route,fields,cookie=self.cookie,headers={'Origin':'https://evil.example'})[0],403)
        for route,fields in [('/undo',dict(id=1)),('/redo',dict(title='x')),('/empty-trash',dict(id=1)),('/restore-task',{}),('/purge',dict(id=1,title='x'))]:
            self.assertEqual(self.post(route,fields),400)
        self.assertEqual(self.path.read_bytes(),before)

    def test_corrupt_history_and_previous_graph_fail_closed(self):
        self.add('one');self.add('two')
        base=self.path.read_text()
        variants=[base.replace('#undo=1','#undo=3'),base+'#undo=1\n',
                  base+'E|1|13|0\n',base+'M|1|1000000001\n',base+'M|1|1\nM|91|1\n',
                  base+'N|1|0\n',base.replace('V|1|0|0|0|0|0|','V|1|0|0|0|1|0|'),
                  base+'U|1|0|0|duplicate\n',base.replace('#undo=1','#undo=0')]
        for invalid in variants:
            with self.subTest(invalid=invalid[-180:]):
                self.path.write_text(invalid);original=self.path.read_bytes()
                self.assertEqual(self.post('/add',dict(title='do not overwrite')),500)
                self.assertEqual(self.path.read_bytes(),original)

    def test_verified_native_archive_restores_undo_and_task_metadata(self):
        self.add('before archive',project='Ședință',tags='asm')
        self.assertEqual(self.post('/edit',dict(id=1,title='after archive')),303)
        binary=Path(__file__).resolve().parents[1]/'build/backup'
        output=self.server.root/'snapshots'
        result=subprocess.run([str(binary),str(self.path.parent),str(output)],capture_output=True,timeout=5)
        self.assertEqual(result.returncode,0,result.stderr)
        archive=next(output.glob('*.tar'))
        self.assertEqual(subprocess.run([str(binary),'--verify',str(archive)],capture_output=True,timeout=5).returncode,0)
        restored=Server();self.addCleanup(restored.close)
        destination=restored.file(self.cookie)
        with tarfile.open(archive) as reader:destination.write_bytes(reader.extractfile(self.path.name).read())
        status,_,body=restored.request('GET','/export.json',cookie=self.cookie)
        self.assertEqual(status,200);self.assertEqual(json.loads(body)['tasks'][0]['project'],'Ședință')
        self.assertEqual(restored.request('POST','/undo',{},cookie=self.cookie)[0],303)
        task=json.loads(restored.request('GET','/export.json',cookie=self.cookie)[2])['tasks'][0]
        self.assertEqual(task['title'],'before archive');self.assertEqual(task['tags'],'asm')

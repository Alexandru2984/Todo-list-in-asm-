"""Independent fixtures for the native versioned planner and offline rollback."""
import json
import os
from pathlib import Path
import subprocess
import unittest
from server import BINARY, Server


def metadata(task_id, **values):
    defaults = dict(priority=0, due=0, completed=0, parent=0, repeat=0,
                    project='', tags='', deps='', stage=0, deleted=0, previous=0, anchor=0)
    defaults.update(values)
    return 'A|' + str(task_id) + '|' + '|'.join(str(value) for value in defaults.values()) + '\n'


def snapshot(records):
    return '#asm=2\n#next=100\n' + ''.join(
        f'{task_id}|{status}|1700000000|{title}\n' + metadata(task_id, **values)
        for task_id, status, title, values in records)


class PlannerStorageTests(unittest.TestCase):
    def setUp(self):
        self.server = Server(); self.addCleanup(self.server.close)
        self.cookie = self.server.session()
        self.path = self.server.file(self.cookie)

    def post(self, route, values):
        return self.server.request('POST', route, values, cookie=self.cookie)[0]

    def live(self):
        status, _, body = self.server.request('GET', '/export.json', cookie=self.cookie)
        self.assertEqual(status, 200)
        return json.loads(body)['tasks']

    def downgrade(self):
        self.server.stop()
        return subprocess.run([str(BINARY), '--downgrade'], cwd=self.server.root,
                              capture_output=True, timeout=5)

    def test_legacy_get_unchanged_and_mutation_versions_preserves_sequence(self):
        original = b'#next=90\n1|0|1|old\n2|2|2|legacy deleted\n'
        self.path.write_bytes(original)
        self.assertEqual(len(self.live()), 1)
        self.assertEqual(self.path.read_bytes(), original)
        self.assertEqual(self.post('/add', {'title': 'Ședință 😀'}), 303)
        content = self.path.read_text()
        self.assertTrue(content.startswith('#asm=3\n#next=91\n'))
        self.assertNotIn('legacy deleted', content)
        self.assertEqual([task['id'] for task in self.live()], ['1', '90'])

    def test_metadata_survives_edit_restart_duplicate_and_native_downgrade(self):
        meta = dict(priority=3, due=1793664000, project='Lucru 😀', tags='asm,ședință',
                    deps='2', repeat=4, anchor=31, stage=1)
        self.path.write_text(snapshot([(1,0,'original',meta), (2,1,'prerequisite',{})]))
        self.assertEqual(self.post('/edit', {'id':1,'title':'edited'}), 303)
        self.assertIn(metadata(1, **meta), self.path.read_text())
        self.server.stop(); self.server.start()
        self.assertEqual([task['title'] for task in self.live()], ['edited','prerequisite'])
        result = self.downgrade()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(self.path.read_text(), '#next=100\n1|0|1700000000|edited\n2|1|1700000000|prerequisite\n')
        self.server.start()
        self.assertEqual(len(self.live()),2)

    def test_invalid_metadata_and_graph_never_overwrite_data(self):
        base = snapshot([(1,0,'one',{}),(2,0,'two',{})])
        bad_meta = [dict(priority=4), dict(priority=-1), dict(due=1), dict(due=253402300800),
                    dict(completed=1), dict(repeat=6), dict(repeat=1),
                    dict(repeat=4,due=1793664000,anchor=32),
                    dict(repeat=5,due=1793664000,anchor=231), dict(anchor=1),
                    dict(project='x'*33), dict(tags='x'*65), dict(project='bad\x7f'),
                    dict(project='bad|field'), dict(stage=2), dict(previous=2),
                    dict(deleted=1), dict(parent=1),dict(parent=99),dict(deps='1'),
                    dict(deps='99'),dict(deps='2,2'),dict(deps='2,'),
                    dict(deps=','.join(['2']*9))]
        variants = [base.replace(metadata(1), metadata(1, **values)) for values in bad_meta]
        variants += [base.replace('#asm=2','#asm=3'), base.replace('#next=100\n',''),
                     base + metadata(1), base + '1|0|0|duplicate\n',
                     base.replace(metadata(1),''), base + '#next=101\n',
                     snapshot([(1,0,'one',{'deps':'2'}),(2,0,'two',{'deps':'1'})]),
                     snapshot([(1,0,'one',{'parent':2}),(2,0,'two',{'parent':1})]),
                     snapshot([(1,0,'one',{'parent':2,'deps':'2'}),(2,0,'two',{})])]
        for invalid in variants:
            with self.subTest(invalid=invalid[:180]):
                self.path.write_text(invalid)
                original = self.path.read_bytes()
                self.assertEqual(self.post('/add', {'title':'must not save'}),500)
                self.assertEqual(self.path.read_bytes(),original)

    def test_valid_deep_graph_and_trash_limits(self):
        # Maximal parent chain also exercises bounded native DFS stack depth.
        self.path.write_text(snapshot([(i,0,'chain',{'parent':i-1}) for i in range(1,1001)]))
        self.assertEqual(len(self.live()),1000)
        self.assertEqual(self.post('/delete', {'id':1}),303)
        self.assertEqual(self.live(),[])
        contents = self.path.read_text()
        retained = [line for line in contents.splitlines() if line[:1].isdigit()]
        self.assertEqual(len(retained),200)
        self.assertEqual(self.post('/add', {'title':'room again'}),303)
        self.assertEqual(len(self.live()),1)

    def test_downgrade_preflight_preserves_every_file_on_corruption(self):
        self.path.write_text(snapshot([(1,0,'valid',{})]))
        other = self.server.file(self.server.session()); other.write_text('#asm=3\n')
        original = self.path.read_bytes()
        result = self.downgrade()
        self.assertNotEqual(result.returncode,0)
        self.assertEqual(self.path.read_bytes(),original)
        self.assertEqual(other.read_text(),'#asm=3\n')
        self.assertNotIn(self.cookie.split('=')[1].encode(),result.stdout+result.stderr)

    def test_downgrade_leaves_v1_bytes_and_unrelated_names_untouched(self):
        original = b'#next=20\n1|0|1|before\n1|1|1|after\n'
        self.path.write_bytes(original)
        unrelated = self.path.parent/'notes.txt'; unrelated.write_text('private unrelated')
        result = self.downgrade()
        self.assertEqual(result.returncode,0,result.stdout)
        self.assertEqual(self.path.read_bytes(),original)
        self.assertEqual(unrelated.read_text(),'private unrelated')

    def test_opened_inode_checks_cover_data_and_temp_without_truncating_aliases(self):
        outside = self.server.root/'outside'; outside.write_text('private unrelated')
        for suffix in ['', '.tmp']:
            for kind in ['hardlink','fifo']:
                with self.subTest(suffix=suffix,kind=kind):
                    target = Path(str(self.path)+suffix)
                    target.unlink(missing_ok=True)
                    if kind == 'fifo': os.mkfifo(target)
                    else: os.link(outside,target)
                    self.assertEqual(self.post('/add',{'title':'must fail'}),500 if not suffix else 507)
                    self.assertEqual(outside.read_text(),'private unrelated')
                    target.unlink()

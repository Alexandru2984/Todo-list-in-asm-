"""Native first-write admission bounds identities without deleting user data."""
import fcntl
from html.parser import HTMLParser
import json
import os
from pathlib import Path
import unittest
from server import Server


class AdmissionTests(unittest.TestCase):
    def setUp(self):
        self.server=Server();self.addCleanup(self.server.close);self.cookie=self.server.session()
        self.data=self.server.root/'data'

    def reserve(self,count,start=1,suffix='.lock'):
        for i in range(start,start+count):(self.data/f'todos-{i:032x}.txt{suffix}').touch(mode=0o600)

    def test_readonly_requests_for_unknown_workspaces_never_create_lock_inodes(self):
        for i in range(32):
            cookie=f'asm_uid={i+1:032x}'
            for path in ['/app','/app?layout=board','/export.json','/state.json']:
                self.assertEqual(self.server.request('GET',path,cookie=cookie)[0],200)
        self.assertEqual(list(self.data.iterdir()),[])

    def test_full_reservation_budget_rejects_new_identity_without_creating_files(self):
        self.reserve(1024)
        before={p.name for p in self.data.iterdir()}
        fields=dict(title='Preserved draft')
        status,_,body=self.server.mutate('/add',fields,cookie=self.cookie)
        self.assertEqual(status,503);self.assertIn(b'Preserved draft',body)
        self.assertIn(b'name="_state"',body);self.assertIn(b'name="_request"',body)
        after={p.name for p in self.data.iterdir()}
        self.assertEqual(after-before,{'.admission.lock'})
        self.assertTrue(all((self.data/name).exists() for name in before))
        (self.data/'todos-00000000000000000000000000000001.txt.lock').unlink()
        self.assertEqual(self.server.mutate('/add',fields,cookie=self.cookie)[0],303)

    def test_existing_data_and_writers_work_at_capacity_and_with_admission_mutex_held(self):
        self.server.file(self.cookie).write_bytes(b'1|0|0|Existing\n')
        self.reserve(1023)
        self.assertEqual(self.server.mutate('/edit',dict(id='1',title='Still usable'),cookie=self.cookie)[0],303)
        other=self.server.session()
        with (self.data/'.admission.lock').open('r+b') as handle:
            fcntl.flock(handle,fcntl.LOCK_EX)
            self.assertEqual(self.server.mutate('/edit',dict(id='1',title='Existing writer'),cookie=self.cookie)[0],303)
            self.assertEqual(self.server.mutate('/add',dict(title='New'),cookie=other)[0],503)
        self.assertFalse(self.server.file(other).exists())
        self.assertIn(b'Existing writer',self.server.file(self.cookie).read_bytes())

    def test_data_lock_and_tmp_names_for_one_identity_count_as_one_reservation(self):
        self.reserve(512)
        self.reserve(512,suffix='')
        self.reserve(512,suffix='.tmp')
        (self.data/'unrelated-file').write_text('Do not remove')
        self.assertEqual(self.server.mutate('/add',dict(title='New identity'),cookie=self.cookie)[0],303)
        self.assertEqual((self.data/'unrelated-file').read_text(),'Do not remove')
        self.assertEqual(len(list(self.data.glob('*.lock'))),514) # 512 reserved + own + global gate

    def test_admission_gate_and_existing_lock_reject_links_and_special_inodes(self):
        outside=self.server.root/'outside';outside.write_text('Unrelated data')
        gate=self.data/'.admission.lock'
        for kind in ['symlink','hardlink','fifo']:
            with self.subTest(kind=kind):
                if kind=='symlink':gate.symlink_to(outside)
                elif kind=='hardlink':os.link(outside,gate)
                else:os.mkfifo(gate)
                self.assertEqual(self.server.mutate('/add',dict(title='Draft'),cookie=self.cookie)[0],503)
                self.assertEqual(outside.read_text(),'Unrelated data');gate.unlink()
        self.assertEqual(self.server.mutate('/add',dict(title='Normal'),cookie=self.cookie)[0],303)
        lock=self.server.file(self.cookie).with_suffix('.txt.lock');lock.unlink();os.link(outside,lock)
        self.assertEqual(self.server.mutate('/add',dict(title='Blocked'),cookie=self.cookie)[0],503)
        self.assertEqual(outside.read_text(),'Unrelated data')

    def test_import_preview_is_readonly_and_full_admission_preserves_confirmed_source(self):
        self.reserve(1024)
        status,_,body=self.server.mutate('/import-preview',dict(payload='Read-only draft',format='lines'),cookie=self.cookie)
        self.assertEqual(status,200)
        from test_native_import_http import Preview
        fields=Preview(body).fields
        self.assertFalse(self.server.file(self.cookie).with_suffix('.txt.lock').exists())
        status,_,body=self.server.request('POST','/import',fields,cookie=self.cookie)
        self.assertEqual(status,503);self.assertEqual(Preview(body).fields['payload'],'Read-only draft')
        self.assertIn(b'workspace could not be loaded',body)
        self.assertFalse(self.server.file(self.cookie).exists())

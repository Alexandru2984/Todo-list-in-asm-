"""One-title-per-line capture uses real native preview and atomic transactions."""
from datetime import datetime, timezone
import json
import random
import time
import unittest
from server import Server
from test_native_import_http import Preview


class QuickCaptureTests(unittest.TestCase):
    def setUp(self):
        self.server=Server();self.addCleanup(self.server.close)
        self.cookie=self.server.session();self.path=self.server.file(self.cookie)

    def post(self,route,fields):
        return self.server.mutate(route,fields,cookie=self.cookie)

    def preview(self,payload,**fields):
        return self.post('/import-preview',dict(payload=payload,format='lines',mode='merge',**fields))

    def tasks(self):
        return json.loads(self.server.request('GET','/export.json',cookie=self.cookie)[2])['tasks']

    def test_literal_titles_crlf_bom_and_preview_then_one_step_undo(self):
        self.assertEqual(self.post('/add',dict(title='Existing'))[0],303)
        before=self.path.read_bytes();start=int(time.time())
        payload='\ufeff  Plan the week \r\n\r\n\tȘedință 😀\t\n<script>alert(1)</script>\n- literal bullet\n=literal formula\nPlan the week\n'
        status,headers,body=self.preview(payload)
        self.assertEqual(status,200);self.assertIn('no-store',headers['Cache-Control'])
        self.assertNotIn(b'<script>alert(1)</script>',body);self.assertEqual(self.path.read_bytes(),before)
        preview=Preview(body);self.assertEqual(preview.counts,dict(live=6,trash=0))
        self.assertEqual(preview.fields['payload'],payload);self.assertEqual(preview.fields['format'],'lines')
        self.assertEqual(self.post('/import',preview.fields)[0],303)
        rows=self.tasks();self.assertEqual([row['title'] for row in rows],['Existing','Plan the week','Ședință 😀','<script>alert(1)</script>','- literal bullet','=literal formula','Plan the week'])
        for row in rows[1:]:
            self.assertFalse(row['completed']);self.assertEqual(row['priority'],'normal')
            self.assertIsNone(row['dueDate']);self.assertIsNone(row['parentId'])
            self.assertGreaterEqual(datetime.fromisoformat(row['createdAt'].replace('Z','+00:00')).timestamp(),start)
        self.assertEqual(self.post('/undo',{})[0],303);self.assertEqual([row['title'] for row in self.tasks()],['Existing'])
        self.assertEqual(self.post('/redo',{})[0],303);self.assertEqual(len(self.tasks()),7)

    def test_invalid_titles_and_tampered_confirmation_never_write(self):
        self.assertEqual(self.post('/add',dict(title='Existing'))[0],303);before=self.path.read_bytes()
        invalid=['',' \t\r\n\n ','Good\rBad','Good\r','Bad\tinside','Good\nBad\x01','Good\n'+'x'*111,'😀'*28,b'bad\xff']
        for payload in invalid:
            with self.subTest(payload=repr(payload)[:60]):
                self.assertEqual(self.preview(payload)[0],422);self.assertEqual(self.path.read_bytes(),before)
        status,_,body=self.preview('Good');self.assertEqual(status,200)
        fields=Preview(body).fields;fields['payload']='Good\nInvalid\rline'
        self.assertEqual(self.post('/import',fields)[0],422);self.assertEqual(self.path.read_bytes(),before)
        self.assertEqual(self.post('/import-preview',dict(payload='Good',format='lines',mode='replace'))[0],400)
        self.assertEqual(self.post('/import',dict(payload='Good',format='lines',mode='replace',confirmed='1'))[0],400)
        self.assertEqual(self.path.read_bytes(),before)

    def test_utf8_byte_boundary_and_seeded_literal_roundtrip(self):
        rng=random.Random(2984)
        titles=['😀'*27+'ab','a,b; \\ "quoted"','[ ] keep checkbox','{not json}']
        alphabet='abcdef Șț😀<>&;,+-=\\"'
        titles+=['z'+''.join(rng.choice(alphabet) for _ in range(25)).strip() for _ in range(60)]
        payload='\n'.join('\t '+title+' \t' for title in titles)
        status,_,body=self.preview(payload);self.assertEqual(status,200)
        self.assertEqual(self.post('/import',Preview(body).fields)[0],303)
        self.assertEqual([row['title'] for row in self.tasks()],titles)

    def test_capacity_and_failed_save_preserve_workspace_and_draft(self):
        self.assertEqual(self.post('/add',dict(title='Existing'))[0],303);before=self.path.read_bytes()
        status,_,body=self.preview('First\nSecond');self.assertEqual(status,200)
        fields=Preview(body).fields;self.path.with_suffix('.txt.tmp').mkdir()
        status,_,body=self.post('/import',fields)
        self.assertEqual(status,507);self.assertEqual(Preview(body).fields['payload'],'First\nSecond')
        self.assertEqual(self.path.read_bytes(),before);self.path.with_suffix('.txt.tmp').rmdir()
        self.path.write_text(''.join(f'{i}|0|0|Existing\n' for i in range(1,1000)))
        before=self.path.read_bytes();self.assertEqual(self.preview('First\nSecond')[0],409)
        self.assertEqual(self.post('/import',fields)[0],412);self.assertEqual(self.path.read_bytes(),before)
        self.path.write_bytes(b'')
        status,_,body=self.preview('\n'.join('Task '+str(i) for i in range(1000)))
        self.assertEqual(status,200);self.assertEqual(Preview(body).counts['live'],1000)
        self.assertEqual(body.count(b'<li><strong>'),20)
        self.assertEqual(self.post('/import',Preview(body).fields)[0],303);self.assertEqual(len(self.tasks()),1000)
        before=self.path.read_bytes();self.assertEqual(self.preview('Task\n'*1001)[0],422);self.assertEqual(self.path.read_bytes(),before)

    def test_decoded_source_cap_with_many_blank_lines(self):
        payload='Task\n'+'\n'*(2097152-5)
        status,_,body=self.preview(payload)
        self.assertEqual(status,200);self.assertEqual(Preview(body).counts['live'],1)
        self.assertEqual(Preview(body).fields['payload'],payload);self.assertFalse(self.path.exists())
        self.assertEqual(self.preview(payload+'\n')[0],413)

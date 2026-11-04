"""Persistent V4 compare-and-swap and replay protection over real native HTTP."""
from concurrent.futures import ThreadPoolExecutor
import hashlib
from html.parser import HTMLParser
import json
from pathlib import Path
import re
import socket
import subprocess
import tarfile
import tempfile
import time
import unittest
from urllib.parse import urlencode
from server import Server, BINARY
from test_native_import_http import Preview


class Forms(HTMLParser):
    def __init__(self, body):
        super().__init__(); self.forms=[]; self.current=None; self.feed(body.decode())
    def handle_starttag(self, tag, attrs):
        attrs=dict(attrs)
        if tag=='form':
            self.current=dict(method=attrs.get('method','get'),action=attrs.get('action'),inputs={})
            self.forms.append(self.current)
        if tag=='input' and self.current is not None and 'name' in attrs:
            self.current['inputs'].setdefault(attrs['name'],[]).append(attrs.get('value',''))
    def handle_endtag(self,tag):
        if tag=='form':self.current=None


class WorkspaceGuardTests(unittest.TestCase):
    def setUp(self):
        self.server=Server();self.addCleanup(self.server.close)
        self.cookie=self.server.session();self.path=self.server.file(self.cookie)

    def pair(self):
        status,headers,body=self.server.request('GET','/state.json',cookie=self.cookie)
        self.assertEqual(status,200);self.assertIn('no-store',headers['Cache-Control']);self.assertIn('noindex',headers['X-Robots-Tag'])
        state=json.loads(body);return dict(_state=state['state'],_request=state['operationId'])

    def post(self,route,fields,**kw):return self.server.request('POST',route,fields,cookie=self.cookie,**kw)
    def fresh(self,route,fields):return self.post(route,dict(fields,**self.pair()))
    def tasks(self):return json.loads(self.server.request('GET','/export.json',cookie=self.cookie)[2])['tasks']
    def revision(self):return int(json.loads(self.server.request('GET','/state.json',cookie=self.cookie)[2])['revision'])

    def test_scoped_state_oracle_private_discovery_and_get_never_migrates(self):
        first=self.pair();second=self.pair();self.assertEqual(first['_state'],second['_state']);self.assertNotEqual(first['_request'],second['_request'])
        expected=hashlib.sha256(self.cookie.split('=')[1].encode()+b'\0'+hashlib.sha256(b'').digest()).hexdigest()
        self.assertEqual(first['_state'],expected);self.assertEqual(self.revision(),0);self.assertFalse(self.path.exists())
        self.assertEqual(self.server.request('GET','/state.json')[0],401)
        other=self.server.session();other_state=json.loads(self.server.request('GET','/state.json',cookie=other)[2])
        self.assertNotEqual(other_state['state'],first['_state'])
        self.path.write_text('1|0|0|Legacy\n');before=self.path.read_bytes();self.pair();self.assertEqual(self.path.read_bytes(),before)

    def test_all_native_post_forms_have_one_pair_get_forms_do_not(self):
        self.assertEqual(self.fresh('/add',dict(title='One',due='2031-01-07'))[0],303)
        self.assertEqual(self.fresh('/add',dict(title='Trash'))[0],303);self.assertEqual(self.fresh('/delete',dict(id='2'))[0],303)
        for route in ['/app','/app?layout=board','/app?layout=calendar','/app?f=trash','/app?edit=1','/app?confirm=clear']:
            status,_,body=self.server.request('GET',route,cookie=self.cookie);self.assertEqual(status,200)
            forms=Forms(body).forms;self.assertTrue(forms)
            for form in forms:
                for key,length in [('_state',64),('_request',32)]:
                    if form['method']=='post':
                        self.assertEqual(len(form['inputs'][key]),1);self.assertRegex(form['inputs'][key][0],f'^[a-f0-9]{{{length}}}$')
                    else:self.assertNotIn(key,form['inputs'])
            self.assertNotIn(self.cookie.split('=')[1].encode(),body)

    def test_exact_retry_persists_across_restart_and_different_payload_conflicts(self):
        fields=dict(title='One',**self.pair());self.assertEqual(self.post('/add',fields)[0],303)
        before=self.path.read_bytes();self.assertTrue(before.startswith(b'#asm=4\n#next=2\n'))
        self.assertEqual(self.post('/add',fields)[0],303);self.assertEqual(self.path.read_bytes(),before)
        self.server.stop();self.server.start();self.assertEqual(self.post('/add',fields)[0],303)
        status,_,body=self.post('/add',dict(fields,title='Changed draft'))
        self.assertEqual(status,412);self.assertIn(b'Changed draft',body);self.assertEqual(self.path.read_bytes(),before)
        self.assertEqual(self.revision(),1);self.assertEqual(len(self.tasks()),1)
        self.assertEqual(self.post('/add',dict(title='Missing guards'))[0],428)

    def test_concurrent_retries_commit_once(self):
        fields=dict(title='One',**self.pair())
        def retry(_):
            # First admission may contend with another worker until it exits.
            # Retry the identical operation, including its original guard pair.
            for _ in range(30):
                status=self.post('/add',fields)[0]
                if status!=503:return status
                time.sleep(.01)
            return status
        with ThreadPoolExecutor(max_workers=4) as pool:
            codes=list(pool.map(retry,range(4)))
        self.assertEqual(codes,[303]*4);self.assertEqual(len(self.tasks()),1);self.assertEqual(self.revision(),1)

    def test_concurrent_distinct_requests_have_one_winner(self):
        # Reserve this ID before testing the independent workspace CAS lock.
        self.assertEqual(self.fresh('/add',dict(title='Seed'))[0],303)
        first=dict(title='First',**self.pair());second=dict(title='Second',**self.pair())
        with ThreadPoolExecutor(max_workers=2) as pool:
            results=list(pool.map(lambda fields:self.post('/add',fields),[first,second]))
        self.assertEqual(sorted(result[0] for result in results),[303,412]);self.assertEqual(len(self.tasks()),2)
        self.assertIn(b'Workspace changed',next(body for code,_,body in results if code==412))

    def test_stale_edit_preserves_draft_and_reviewed_retry_uses_fresh_pair(self):
        self.assertEqual(self.fresh('/add',dict(title='Original'))[0],303)
        old=self.pair();self.assertEqual(self.fresh('/edit',dict(id='1',title='Newer'))[0],303)
        status,_,body=self.post('/edit',dict(old,id='1',title='Draft <&>',project='Ședință',tags='asm',priority='urgent',due='2031-01-07'))
        self.assertEqual(status,412);self.assertEqual(self.tasks()[0]['title'],'Newer')
        self.assertIn(b'Draft &lt;&amp;&gt;',body)
        form=next(form for form in Forms(body).forms if form['action']=='/edit')
        values={key:items[0] for key,items in form['inputs'].items()}
        self.assertEqual(values['title'],'Draft <&>');self.assertEqual(values['project'],'Ședință')
        # Browser select values are submitted as well; this focuses on preserved inputs.
        values.update(priority='urgent',repeat='none')
        self.assertEqual(self.post('/edit',values)[0],303);self.assertEqual(self.tasks()[0]['title'],'Draft <&>')

    def test_replay_after_undo_or_purge_never_resurrects_tasks(self):
        original=dict(title='One',**self.pair());self.assertEqual(self.post('/add',original)[0],303)
        self.assertEqual(self.fresh('/undo',{})[0],303);before=self.path.read_bytes()
        self.assertEqual(self.post('/add',original)[0],303);self.assertEqual(self.path.read_bytes(),before);self.assertEqual(self.tasks(),[])
        self.assertEqual(self.fresh('/redo',{})[0],303);self.assertEqual(self.fresh('/delete',dict(id='1'))[0],303)
        self.assertEqual(self.fresh('/purge',dict(id='1'))[0],303);before=self.path.read_bytes()
        self.assertEqual(self.post('/add',original)[0],303);self.assertEqual(self.path.read_bytes(),before);self.assertEqual(self.tasks(),[])

    def test_receipt_window_is_bounded_expired_requests_fail_stale(self):
        first=dict(title='Original',**self.pair());self.assertEqual(self.post('/add',first)[0],303)
        for i in range(20):self.assertEqual(self.fresh('/edit',dict(id='1',title='Edit '+str(i)))[0],303)
        data=self.path.read_bytes();self.assertEqual(sum(line.startswith(b'R|') for line in data.splitlines()),16)
        self.assertEqual(self.post('/add',first)[0],412);self.assertEqual(self.path.read_bytes(),data);self.assertEqual(self.revision(),21)

    def test_successful_noop_consumes_key_without_overwriting_history(self):
        self.assertEqual(self.fresh('/add',dict(title='One'))[0],303);self.assertEqual(self.fresh('/complete',dict(id='1'))[0],303)
        before=self.path.read_text();events=[line for line in before.splitlines() if line.startswith(('E|','U|','V|','M|','N|','#undo'))]
        fields=dict(id='1',**self.pair());self.assertEqual(self.post('/complete',fields)[0],303)
        after=self.path.read_text();self.assertEqual(self.revision(),3)
        self.assertEqual([line for line in after.splitlines() if line.startswith(('E|','U|','V|','M|','N|','#undo'))],events)
        self.assertEqual(self.post('/complete',fields)[0],303);self.assertEqual(self.path.read_text(),after)

    def test_failed_save_does_not_publish_receipt_and_exact_retry_can_succeed(self):
        self.assertEqual(self.fresh('/add',dict(title='Existing'))[0],303);before=self.path.read_bytes()
        fields=dict(title='Draft',**self.pair());self.path.with_suffix('.txt.tmp').mkdir()
        self.assertEqual(self.post('/add',fields)[0],507);self.assertEqual(self.path.read_bytes(),before)
        self.path.with_suffix('.txt.tmp').rmdir();self.assertEqual(self.post('/add',fields)[0],303)
        self.assertEqual(self.post('/add',fields)[0],303);self.assertEqual(len(self.tasks()),2)

    def test_import_stale_preview_preserves_source_and_fresh_confirmation_replays(self):
        payload=json.dumps(dict(version=1,tasks=[dict(id='1',title='Imported',completed=False,createdAt=None)]))
        status,_,body=self.post('/import-preview',dict(payload=payload,**self.pair()));self.assertEqual(status,200)
        fields=Preview(body).fields
        self.assertEqual(self.fresh('/add',dict(title='Other tab'))[0],303)
        status,_,body=self.post('/import',fields);self.assertEqual(status,412)
        self.assertIn(b'Workspace changed',body);self.assertIn(b'Workspace loaded for this preview',body);review=Preview(body);self.assertEqual(review.fields['payload'],payload)
        self.assertEqual(len(self.tasks()),1)
        self.assertEqual(self.post('/import',review.fields)[0],303);before=self.path.read_bytes()
        # The first import worker retains the global large-body slot until exit;
        # a retry may arrive after its response but before that descriptor closes.
        for _ in range(30):
            status=self.post('/import',review.fields)[0]
            if status!=503:break
            time.sleep(.01)
        self.assertEqual(status,303);self.assertEqual(self.path.read_bytes(),before)
        self.assertEqual([task['title'] for task in self.tasks()],['Other tab','Imported'])

    def test_guards_are_strict_and_still_require_cookie_and_origin(self):
        pair=self.pair()
        bad=[dict(_state=pair['_state']),dict(_request=pair['_request']),dict(pair,_state='A'*64),dict(pair,_request='0'*31),dict(pair,_state='0'*65)]
        for extra in bad:
            with self.subTest(extra=extra):self.assertEqual(self.post('/add',dict(title='One',**extra))[0],400)
        encoded=urlencode(dict(title='One',**pair))+'&_request='+pair['_request']
        self.assertEqual(self.post('/add',encoded)[0],400)
        self.assertEqual(self.server.request('POST','/add',dict(title='One',**pair))[0],401)
        self.assertEqual(self.post('/add',dict(title='One',**pair),headers={'Origin':'https://evil.example'})[0],403)
        self.assertFalse(self.path.exists())

    def test_corrupt_v4_records_fail_closed_and_native_downgrade_preserves_live_fields(self):
        self.assertEqual(self.fresh('/add',dict(title='One'))[0],303);original=self.path.read_bytes()
        lines=original.splitlines(keepends=True);generation=next(line for line in lines if line.startswith(b'#generation='));receipt=next(line for line in lines if line.startswith(b'R|'));revision=next(line for line in lines if line.startswith(b'#revision='))
        invalid=[original.replace(generation,b''),original.replace(revision,b''),original+generation,original+receipt,original.replace(revision,b'#revision=0\n'),original.replace(generation,b'#generation=oops\n'),original.replace(receipt,receipt[:-3]+b'X\n'),original.replace(b'#asm=4',b'#asm=3')]
        for data in invalid:
            with self.subTest(data=data[:30]):
                self.path.write_bytes(data);self.assertEqual(self.server.request('GET','/app',cookie=self.cookie)[0],500);self.assertEqual(self.path.read_bytes(),data)
        self.path.write_bytes(original);self.server.stop()
        result=subprocess.run([str(BINARY),'--check-storage'],cwd=self.server.root,capture_output=True,timeout=5);self.assertEqual(result.returncode,0)
        self.assertEqual(self.path.read_bytes(),original)
        self.assertEqual(subprocess.run([str(BINARY),'--storage-version'],capture_output=True).stdout,b'5\n')
        self.assertEqual(subprocess.run([str(BINARY),'--downgrade'],cwd=self.server.root,capture_output=True,timeout=5).returncode,0)
        self.assertEqual(self.path.read_bytes(),b'#next=2\n1|0|'+original.split(b'1|0|',1)[1].split(b'\n',1)[0]+b'\n')
        self.server.start();self.assertEqual(self.tasks()[0]['title'],'One')

    def test_verified_native_backup_restore_keeps_receipts_and_replay_protection(self):
        fields=dict(title='One',**self.pair());self.assertEqual(self.post('/add',fields)[0],303);before=self.path.read_bytes()
        binary=BINARY.parent/'backup'
        with tempfile.TemporaryDirectory(prefix='asm-guard-backup-') as root:
            subprocess.run([str(binary),str(self.path.parent),root],check=True,capture_output=True,timeout=5)
            archive=next(Path(root).glob('*.tar'));subprocess.run([str(binary),'--verify',str(archive)],check=True,capture_output=True,timeout=5)
            with tarfile.open(archive) as reader:restored=reader.extractfile(self.path.name).read()
            self.assertEqual(restored,before);self.path.write_bytes(restored)
            self.server.stop();self.server.start();self.assertEqual(self.post('/add',fields)[0],303);self.assertEqual(self.path.read_bytes(),before)

    def test_v3_downgrade_preserves_metadata_undo_metrics_and_skips_older_files(self):
        self.assertEqual(self.fresh('/add',dict(title='One',priority='urgent',project='Lucru',tags='asm',due='2031-01-31',repeat='monthly'))[0],303)
        self.assertEqual(self.fresh('/complete',dict(id='1'))[0],303)
        before=self.path.read_bytes();expected=self.tasks();other=self.server.file(self.server.session());other.write_bytes(b'1|0|0|Legacy\n')
        self.server.stop()
        self.assertEqual(subprocess.run([str(BINARY),'--downgrade-v3'],cwd=self.server.root,capture_output=True,timeout=5).returncode,0)
        converted=self.path.read_bytes();self.assertTrue(converted.startswith(b'#asm=3\n'));self.assertNotIn(b'R|',converted);self.assertNotIn(b'#revision=',converted)
        self.assertEqual([line for line in before.splitlines() if not line.startswith((b'#asm=',b'#revision=',b'#generation=',b'R|'))],converted.splitlines()[1:])
        self.assertEqual(other.read_bytes(),b'1|0|0|Legacy\n')
        self.server.start();self.assertEqual(self.tasks(),expected)

    def test_lost_response_retry_uses_committed_receipt_and_route_is_bound(self):
        fields=dict(title='Acknowledgement lost',**self.pair());body=urlencode(fields).encode()
        with socket.create_connection(('127.0.0.1',self.server.port),timeout=5) as sock:
            headers=(f'POST /board/add HTTP/1.1\r\nHost: 127.0.0.1:{self.server.port}\r\nCookie: {self.cookie}\r\nContent-Type: application/x-www-form-urlencoded\r\nContent-Length: {len(body)}\r\n\r\n').encode()
            sock.sendall(headers+body);sock.shutdown(socket.SHUT_WR)
            for _ in range(100):
                if self.path.exists():break
                time.sleep(.005)
            # Close without reading the response, then restart the native process.
        self.server.stop();self.server.start()
        status,headers,_=self.post('/board/add',fields);self.assertEqual(status,303);self.assertEqual(headers['Location'],'/app?layout=board')
        before=self.path.read_bytes();self.assertEqual(self.post('/add',fields)[0],412);self.assertEqual(self.path.read_bytes(),before)
        self.assertEqual(len(self.tasks()),1)

    def test_revision_exhaustion_fails_without_replacing_snapshot(self):
        self.assertEqual(self.fresh('/add',dict(title='One'))[0],303)
        self.path.write_bytes(self.path.read_bytes().replace(b'#revision=1\n',b'#revision=9223372036854775807\n'))
        pair=self.pair();before=self.path.read_bytes();self.assertEqual(self.post('/edit',dict(pair,id='1',title='Draft'))[0],507)
        self.assertEqual(self.path.read_bytes(),before)

    def test_maximal_form_injection_is_bounded_and_escaped_text_never_becomes_a_form(self):
        title='method="post"> <form action="/fake" method="post">'
        self.path.write_text(''.join(f'{i}|0|0|{title}\n' for i in range(1,1001)))
        before=self.path.read_bytes();status,headers,body=self.server.request('GET','/app',cookie=self.cookie)
        self.assertEqual(status,200);self.assertEqual(int(headers['Content-Length']),len(body));self.assertLess(len(body),8388608)
        forms=Forms(body).forms
        for form in forms:
            self.assertNotEqual(form['action'],'/fake')
            for key in ['_state','_request']:
                if form['method']=='post':self.assertEqual(len(form['inputs'][key]),1)
                else:self.assertNotIn(key,form['inputs'])
        self.assertEqual(self.path.read_bytes(),before)

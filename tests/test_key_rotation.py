"""Native credential rotation, revocation, response loss and offline restore."""
from concurrent.futures import ThreadPoolExecutor
import hashlib
from html.parser import HTMLParser
import json
from pathlib import Path
import shutil
import socket
import subprocess
import tarfile
import tempfile
import time
import unittest
from urllib.parse import urlencode
from server import BINARY,Server
from test_native_import_http import Preview


class Rotation(HTMLParser):
    def __init__(self,body):
        super().__init__();self.fields={};self.parts=[];self.active=False;self.feed(body.decode())
        self.fields['new_key']=''.join(self.parts)
    def handle_starttag(self,tag,attrs):
        attrs=dict(attrs)
        if tag=='input' and attrs.get('name','').startswith('_'):self.fields[attrs['name']]=attrs.get('value','')
        if tag=='textarea' and attrs.get('name')=='new_key':
            assert 'readonly' in attrs;self.active=True
    def handle_endtag(self,tag):
        if tag=='textarea':self.active=False
    def handle_data(self,data):
        if self.active:self.parts.append(data)


class KeyRotationTests(unittest.TestCase):
    def setUp(self):
        self.server=Server();self.addCleanup(self.server.close);self.old=self.server.session();self.path=self.server.file(self.old)

    def prepare(self,cookie=None):
        cookie=cookie or self.old
        status,headers,body=self.server.request('GET','/rotate-key',cookie=cookie)
        self.assertEqual(status,200);self.assertIn('no-store',headers['Cache-Control']);self.assertIn('noindex',headers['X-Robots-Tag'])
        fields=Rotation(body).fields
        self.assertRegex(fields['new_key'],r'^[a-f0-9]{64}$');self.assertEqual(fields['new_key'][:32],cookie.split('=')[1][:32])
        return fields

    def rotate(self,cookie=None,fields=None):
        cookie=cookie or self.old;fields=dict(fields or self.prepare(cookie),saved='1')
        status,headers,body=self.server.request('POST','/rotate-key',fields,cookie=cookie)
        self.assertEqual(status,303,body[:200]);new=headers['Set-Cookie'].split(';')[0]
        self.assertEqual(new,'asm_uid='+fields['new_key']);return new,fields

    def mutate(self,path,fields,cookie=None):
        result=self.server.mutate(path,fields,cookie=cookie or self.old);self.assertEqual(result[0],303,result[2][:100]);return result

    def exported(self,cookie):
        status,_,body=self.server.request('GET','/export.json',cookie=cookie);self.assertEqual(status,200);return json.loads(body)

    def test_prepare_download_are_read_only_and_candidate_inactive(self):
        self.mutate('/add',dict(title='Fixture'));before=self.path.read_bytes()
        one=self.prepare();two=self.prepare();self.assertNotEqual(one['new_key'],two['new_key'])
        status,headers,body=self.server.request('POST','/rotation-key',one,cookie=self.old)
        self.assertEqual(status,200);self.assertEqual(body,(one['new_key']+'\n').encode());self.assertIn('attachment',headers['Content-Disposition'])
        self.assertEqual(self.path.read_bytes(),before)
        status,headers,_=self.server.request('POST','/restore',dict(token=one['new_key']))
        self.assertEqual(status,410);self.assertNotIn('Set-Cookie',headers)
        self.assertEqual(self.server.request('GET','/export.json',cookie='asm_uid='+one['new_key'])[0],410)
        self.assertEqual(self.server.request('GET','/rotation-key',cookie=self.old)[0],405)
        self.assertEqual(self.server.request('GET','/rotate-key')[0],401)
        self.assertEqual(self.server.request('POST','/rotation-key',one)[0],401)
        self.assertEqual(self.server.request('POST','/rotation-key',one,cookie=self.old,headers={'Origin':'https://evil.example'})[0],403)

    def test_atomic_rotation_preserves_tasks_metadata_history_undo_and_calendar_identity(self):
        self.mutate('/add',dict(title='Fixture',due='2031-01-31',repeat='monthly',priority='high',project='Ședință',tags='asm'))
        self.mutate('/add',dict(title='Trash'));self.mutate('/delete',dict(id='2'))
        expected=self.exported(self.old);before=self.path.read_bytes()
        calendar=self.server.request('GET','/export.ics',cookie=self.old)[2].replace(b'\r\n ',b'')
        new,fields=self.rotate();after=self.path.read_bytes()
        self.assertTrue(after.startswith(b'#asm=5\n#next='));self.assertIn(b'#keyepoch=1\n',after)
        oracle=hashlib.sha256(b'ASM TODO active key v1\0'+fields['new_key'].encode()).hexdigest()
        self.assertIn(('#key='+oracle+'\n').encode(),after);self.assertNotIn(fields['new_key'].encode(),after)
        actual=self.exported(new)
        self.assertEqual(actual['tasks'],expected['tasks']);self.assertEqual(actual['trash'],expected['trash'])
        for prefixes in [(b'U|',b'V|',b'#undo'),(b'M|',b'N|')]:
            self.assertEqual([line for line in before.splitlines() if line.startswith(prefixes)],[line for line in after.splitlines() if line.startswith(prefixes)])
        new_calendar=self.server.request('GET','/export.ics',cookie=new)[2].replace(b'\r\n ',b'')
        self.assertEqual(next(line for line in calendar.splitlines() if line.startswith(b'UID:')),next(line for line in new_calendar.splitlines() if line.startswith(b'UID:')))
        self.assertEqual(len(list(self.path.parent.glob('todos-*.txt'))),1)
        self.assertEqual(self.server.request('GET','/recovery',cookie=new)[2],(fields['new_key']+'\n').encode())

    def test_revoked_key_cannot_read_write_restore_download_or_enter_large_import_gate(self):
        self.mutate('/add',dict(title='Fixture'));pair=json.loads(self.server.request('GET','/state.json',cookie=self.old)[2])
        new,fields=self.rotate();before=self.path.read_bytes()
        for method in ['GET','HEAD']:
            for route in ['/app','/state.json','/export.json','/export.csv','/export.ics','/stats.svg','/recovery','/rotate-key']:
                with self.subTest(route=route,method=method):
                    status,_,body=self.server.request(method,route,cookie=self.old);self.assertEqual(status,410);self.assertNotIn(fields['new_key'].encode(),body)
        self.assertEqual(self.server.request('POST','/add',dict(title='Rejected',_state=pair['state'],_request=pair['operationId']),cookie=self.old)[0],410)
        self.assertEqual(self.server.request('POST','/restore',dict(token=self.old.split('=')[1]))[0],410)
        self.assertEqual(self.server.request('GET','/?uid='+self.old.split('=')[1])[0],410)
        self.assertEqual(self.server.request('POST','/rotation-key',dict(new_key=fields['new_key']),cookie=self.old)[0],410)
        header=(f'POST /import-preview HTTP/1.1\r\nHost: localhost\r\nCookie: {self.old}\r\nContent-Type: application/x-www-form-urlencoded\r\nContent-Length: 10000\r\n\r\n').encode()
        self.assertIn(b' 410 ',self.server.raw(header).split(b'\r\n',1)[0])
        self.assertEqual(self.path.read_bytes(),before);self.assertEqual(len(self.exported(new)['tasks']),1)

    def test_second_rotation_revokes_all_predecessors_and_does_not_add_files(self):
        self.mutate('/add',dict(title='Fixture'));first,_=self.rotate();second,_=self.rotate(first)
        self.assertIn(b'#keyepoch=2\n',self.path.read_bytes());self.assertEqual(len(list(self.path.parent.glob('todos-*.txt'))),1)
        for old in [self.old,first]:self.assertEqual(self.server.request('GET','/export.json',cookie=old)[0],410)
        self.assertEqual(len(self.exported(second)['tasks']),1)

    def test_response_loss_replay_and_manual_restore_survive_restart_without_another_change(self):
        self.mutate('/add',dict(title='Fixture'));fields=dict(self.prepare(),saved='1');body=urlencode(fields).encode()
        with socket.create_connection(('127.0.0.1',self.server.port),timeout=5) as sock:
            header=(f'POST /rotate-key HTTP/1.1\r\nHost: localhost\r\nCookie: {self.old}\r\nContent-Type: application/x-www-form-urlencoded\r\nContent-Length: {len(body)}\r\n\r\n').encode()
            sock.sendall(header+body);sock.shutdown(socket.SHUT_WR)
            for _ in range(100):
                if self.path.read_bytes().startswith(b'#asm=5\n'):break
                time.sleep(.005)
        self.server.stop();self.server.start();before=self.path.read_bytes()
        new,_=self.rotate(fields=fields);self.assertEqual(self.path.read_bytes(),before)
        status,headers,_=self.server.request('POST','/restore',dict(token=fields['new_key']))
        self.assertEqual(status,303);self.assertEqual(headers['Set-Cookie'].split(';')[0],new)
        self.assertEqual(self.server.request('GET','/export.json',cookie=self.old)[0],410)
        self.assertEqual(self.path.read_bytes(),before)

    def test_failed_save_preserves_old_authorization_and_same_candidate_can_retry(self):
        self.mutate('/add',dict(title='Fixture'));before=self.path.read_bytes();fields=dict(self.prepare(),saved='1')
        self.path.with_suffix('.txt.tmp').mkdir()
        status,_,body=self.server.request('POST','/rotate-key',fields,cookie=self.old)
        self.assertEqual(status,507);self.assertEqual(Rotation(body).fields['new_key'],fields['new_key']);self.assertEqual(self.path.read_bytes(),before)
        self.assertEqual(self.server.request('GET','/recovery',cookie=self.old)[0],200)
        self.assertEqual(self.server.request('POST','/restore',dict(token=fields['new_key']))[0],410)
        self.path.with_suffix('.txt.tmp').rmdir();self.rotate(fields=fields)

    def test_stale_rotation_requires_review_and_preserves_saved_candidate(self):
        self.mutate('/add',dict(title='Fixture'));fields=dict(self.prepare(),saved='1')
        self.mutate('/edit',dict(id='1',title='Newer task'))
        status,_,body=self.server.request('POST','/rotate-key',fields,cookie=self.old)
        self.assertEqual(status,412);review=Rotation(body).fields;self.assertEqual(review['new_key'],fields['new_key'])
        self.assertEqual(self.server.request('GET','/recovery',cookie=self.old)[0],200)
        new,_=self.rotate(fields=review);self.assertEqual(self.exported(new)['tasks'][0]['title'],'Newer task')

    def test_concurrent_duplicate_rotation_commits_once(self):
        self.mutate('/add',dict(title='Fixture'));fields=dict(self.prepare(),saved='1')
        with ThreadPoolExecutor(max_workers=3) as pool:
            results=list(pool.map(lambda _:self.server.request('POST','/rotate-key',fields,cookie=self.old),range(3)))
        self.assertEqual([result[0] for result in results],[303]*3)
        self.assertEqual(len({result[1]['Set-Cookie'] for result in results}),1)
        self.assertEqual(sum(line.startswith(b'E|') and b'|13|' in line for line in self.path.read_bytes().splitlines()),1)
        self.assertIn(b'#keyepoch=1\n',self.path.read_bytes())

    def test_concurrent_distinct_rotations_have_one_winner(self):
        self.mutate('/add',dict(title='Fixture'));fields=[dict(self.prepare(),saved='1') for _ in range(2)]
        with ThreadPoolExecutor(max_workers=2) as pool:
            results=list(pool.map(lambda f:self.server.request('POST','/rotate-key',f,cookie=self.old),fields))
        self.assertEqual(sorted(result[0] for result in results),[303,410])
        winner=next(result[1]['Set-Cookie'].split(';')[0] for result in results if result[0]==303)
        loser=next(field['new_key'] for field,result in zip(fields,results) if result[0]==410)
        self.assertEqual(self.server.request('POST','/restore',dict(token=loser))[0],410);self.exported(winner)

    def test_pending_writer_and_rotation_never_silently_overwrite(self):
        self.mutate('/add',dict(title='Fixture'));rotation=dict(self.prepare(),saved='1')
        state=json.loads(self.server.request('GET','/state.json',cookie=self.old)[2])
        writer=dict(id='1',title='Writer won',_state=state['state'],_request=state['operationId'])
        with ThreadPoolExecutor(max_workers=2) as pool:
            rotate=pool.submit(self.server.request,'POST','/rotate-key',rotation,self.old)
            write=pool.submit(self.server.request,'POST','/edit',writer,self.old)
            a,b=rotate.result(),write.result()
        if a[0]==303:
            self.assertEqual(b[0],410);new=a[1]['Set-Cookie'].split(';')[0];self.assertEqual(self.exported(new)['tasks'][0]['title'],'Fixture')
        else:
            self.assertEqual(a[0],412);self.assertEqual(b[0],303);new,_=self.rotate(fields=Rotation(a[2]).fields);self.assertEqual(self.exported(new)['tasks'][0]['title'],'Writer won')

    def test_undo_replace_import_and_task_exports_cannot_restore_old_authorization(self):
        self.mutate('/add',dict(title='Fixture'));new,_=self.rotate();self.mutate('/undo',{},new)
        self.assertEqual(self.exported(new)['tasks'],[]);self.assertEqual(self.server.request('GET','/app',cookie=self.old)[0],410)
        self.mutate('/redo',{},new)
        payload=json.dumps(dict(version=1,tasks=[]))
        status,_,body=self.server.mutate('/import-preview',dict(payload=payload,mode='replace'),cookie=new);self.assertEqual(status,200)
        fields=Preview(body).fields;self.assertEqual(self.server.request('POST','/import',fields,cookie=new)[0],303)
        self.assertEqual(self.exported(new)['tasks'],[]);self.assertIn(b'#keyepoch=1\n',self.path.read_bytes())
        self.assertEqual(self.server.request('GET','/recovery',cookie=self.old)[0],410)
        for route in ['/app','/state.json','/export.json','/export.csv','/export.ics','/stats.svg']:
            self.assertNotIn(new.split('=')[1].encode(),self.server.request('GET',route,cookie=new)[2])

    def test_rotation_fields_scope_pair_acknowledgement_and_exact_formats(self):
        fields=self.prepare();before=self.path.read_bytes() if self.path.exists() else None
        invalid=[dict(fields),dict(fields,saved='0'),dict(fields,new_key='a'*63,saved='1'),dict(fields,new_key='a'*65,saved='1'),dict(fields,new_key='A'*64,saved='1'),dict(fields,new_key='f'*64,saved='1'),dict(fields,title='Ignored',saved='1')]
        for payload in invalid:self.assertEqual(self.server.request('POST','/rotate-key',payload,cookie=self.old)[0],400)
        self.assertEqual(self.server.request('POST','/rotate-key',dict(new_key=fields['new_key'],saved='1'),cookie=self.old)[0],428)
        self.assertEqual(self.server.request('POST','/add',dict(title='Ignored',**fields),cookie=self.old)[0],400)
        encoded=urlencode(dict(fields,saved='1'))+'&new_key='+fields['new_key']
        self.assertEqual(self.server.request('POST','/rotate-key',encoded,cookie=self.old)[0],400)
        self.assertEqual(self.server.request('POST','/rotate-key',dict(fields,saved='1'),cookie=self.old,headers={'Origin':'https://evil.example'})[0],403)
        self.assertEqual(self.path.read_bytes() if self.path.exists() else None,before)

    def test_rotation_keeps_one_admission_identity_even_at_global_capacity(self):
        self.mutate('/add',dict(title='Fixture'))
        for i in range(1023):(self.path.parent/f'todos-{i:032x}.txt.lock').touch(mode=0o600)
        before={p.name for p in self.path.parent.iterdir()};self.rotate()
        self.assertEqual({p.name for p in self.path.parent.iterdir()},before)

    def test_modern_cookie_formats_do_not_change_canonical_file_and_legacy_url_rejects_modern_key(self):
        self.mutate('/add',dict(title='Fixture'));new,fields=self.rotate()
        self.assertEqual(self.server.file(new),self.path)
        self.assertEqual(self.server.request('GET','/?uid='+fields['new_key'])[0],400)
        for token in [fields['new_key']+'a',fields['new_key'][:-1],fields['new_key'].upper(),fields['new_key'][:32]+'0'*32]:
            code=self.server.request('GET','/export.json',cookie='asm_uid='+token)[0];self.assertIn(code,[400,410])
        self.assertEqual(self.server.request('POST','/forget',{},cookie=new)[0],303)
        self.exported(new) # browser logout does not revoke the active key

    def test_v5_backup_restore_and_all_unsafe_downgrades_refuse_without_writes(self):
        self.mutate('/add',dict(title='Fixture'));new,_=self.rotate();before=self.path.read_bytes();binary=BINARY.parent/'backup'
        with tempfile.TemporaryDirectory(prefix='asm-keys-backup-') as root:
            subprocess.run([str(binary),str(self.path.parent),root],check=True,capture_output=True)
            archive=next(Path(root).glob('*.tar'));subprocess.run([str(binary),'--verify',str(archive)],check=True,capture_output=True)
            with tarfile.open(archive) as reader:self.assertEqual(reader.extractfile(self.path.name).read(),before)
        other=self.server.file(self.server.session());other.write_bytes(b'1|0|0|Legacy\n')
        self.server.stop();original={p.name:p.read_bytes() for p in self.path.parent.glob('todos-*.txt')}
        for flag in ['--downgrade','--downgrade-v3','--downgrade-v4']:
            result=subprocess.run([str(BINARY),flag],cwd=self.server.root,capture_output=True,timeout=5)
            self.assertNotEqual(result.returncode,0);self.assertEqual({p.name:p.read_bytes() for p in self.path.parent.glob('todos-*.txt')},original)
        self.assertEqual(subprocess.run([str(BINARY),'--check-storage'],cwd=self.server.root,capture_output=True).returncode,0)
        self.server.start();self.assertEqual(self.server.request('GET','/app',cookie=self.old)[0],410);self.exported(new)

    def test_offline_restore_preserves_latest_key_epoch_and_advances_revision(self):
        self.mutate('/add',dict(title='Backup task'));old_snapshot=self.path.read_bytes()
        first,_=self.rotate();self.mutate('/edit',dict(id='1',title='Later task'),first);latest,_=self.rotate(first)
        current=self.path.read_bytes();current_revision=int(json.loads(self.server.request('GET','/state.json',cookie=latest)[2])['revision'])
        self.server.stop()
        with tempfile.TemporaryDirectory(prefix='asm-current-key-policy-') as root:
            (Path(root)/self.path.name).write_bytes(current);self.path.write_bytes(old_snapshot)
            result=subprocess.run([str(BINARY),'--preserve-key-policy',root],cwd=self.server.root,capture_output=True,timeout=5)
            self.assertEqual(result.returncode,0,result.stdout);self.assertEqual((Path(root)/self.path.name).read_bytes(),current)
        self.server.start();self.assertEqual(self.exported(latest)['tasks'][0]['title'],'Backup task')
        self.assertIn(b'#keyepoch=2\n',self.path.read_bytes())
        self.assertGreater(int(json.loads(self.server.request('GET','/state.json',cookie=latest)[2])['revision']),current_revision)
        for old in [self.old,first]:self.assertEqual(self.server.request('GET','/app',cookie=old)[0],410)

    def test_policy_merge_missing_or_ambiguous_sources_fail_before_any_rewrite(self):
        self.mutate('/add',dict(title='Fixture'));self.rotate();self.server.stop();before=self.path.read_bytes()
        with tempfile.TemporaryDirectory(prefix='asm-policy-source-') as root:
            result=subprocess.run([str(BINARY),'--preserve-key-policy',root],cwd=self.server.root,capture_output=True,timeout=5)
            self.assertNotEqual(result.returncode,0);self.assertEqual(self.path.read_bytes(),before)
            key_line=next(line for line in before.splitlines(keepends=True) if line.startswith(b'#key='))
            (Path(root)/self.path.name).write_bytes(before.replace(key_line,b'#key='+b'0'*64+b'\n'))
            self.assertNotEqual(subprocess.run([str(BINARY),'--preserve-key-policy',root],cwd=self.server.root,capture_output=True,timeout=5).returncode,0)
            self.assertEqual(self.path.read_bytes(),before)
        self.assertNotEqual(subprocess.run([str(BINARY),'--preserve-key-policy','data'],cwd=self.server.root,capture_output=True,timeout=5).returncode,0)
        self.assertEqual(self.path.read_bytes(),before)

    def test_empty_workspace_rotation_creates_one_valid_authorized_snapshot(self):
        fields=self.prepare();self.assertFalse(self.path.exists());new,_=self.rotate(fields=fields)
        self.assertEqual(self.exported(new)['tasks'],[]);self.assertIn(b'#keyepoch=1\n',self.path.read_bytes())
        self.assertEqual(self.server.request('GET','/app',cookie=self.old)[0],410)

    def test_already_active_candidate_can_recover_login_after_receipt_eviction(self):
        self.mutate('/add',dict(title='Fixture'));new,fields=self.rotate()
        for i in range(17):self.mutate('/edit',dict(id='1',title='Later '+str(i)),new)
        before=self.path.read_bytes();again,_=self.rotate(fields=fields)
        self.assertEqual(again,new);self.assertEqual(self.path.read_bytes(),before)
        state=json.loads(self.server.request('GET','/state.json',cookie=new)[2])
        same=dict(new_key=new.split('=')[1],saved='1',_state=state['state'],_request=state['operationId'])
        self.assertEqual(self.server.request('POST','/rotate-key',same,cookie=new)[0],400);self.assertEqual(self.path.read_bytes(),before)

    def test_corrupt_policy_headers_fail_closed_and_cannot_be_used_for_restore(self):
        self.mutate('/add',dict(title='Fixture'));new,fields=self.rotate();before=self.path.read_bytes()
        key=next(line for line in before.splitlines(keepends=True) if line.startswith(b'#key='));epoch=b'#keyepoch=1\n'
        invalid=[before.replace(key,b''),before.replace(epoch,b''),before.replace(epoch,b'#keyepoch=0\n'),before.replace(key,b'#key=oops\n'),before.replace(b'#asm=5',b'#asm=4'),before.replace(b'#next=2',b'#next=' + b'0'*30+b'2')]
        for data in invalid:
            with self.subTest(header=data[:20]):
                self.path.write_bytes(data);self.assertEqual(self.server.request('GET','/app',cookie=new)[0],500)
                self.assertIn(self.server.request('POST','/restore',dict(token=fields['new_key']))[0],[410,500]);self.assertEqual(self.path.read_bytes(),data)
        self.path.write_bytes(before)

    def test_policy_merge_never_lowers_the_epoch_with_an_older_source(self):
        self.mutate('/add',dict(title='Fixture'));first,_=self.rotate();older=self.path.read_bytes();new,_=self.rotate(first)
        self.server.stop()
        with tempfile.TemporaryDirectory(prefix='asm-older-policy-') as root:
            (Path(root)/self.path.name).write_bytes(older)
            self.assertEqual(subprocess.run([str(BINARY),'--preserve-key-policy',root],cwd=self.server.root,capture_output=True,timeout=5).returncode,0)
        self.server.start();self.assertIn(b'#keyepoch=2\n',self.path.read_bytes())
        self.assertEqual(self.server.request('GET','/app',cookie=first)[0],410);self.exported(new)

"""End-to-end native preview, confirmation, limits, locking and rollback."""
import fcntl
import csv
import io
from html.parser import HTMLParser
import json
import os
from pathlib import Path
import socket
import time
import unittest
from urllib.parse import urlencode
from server import Server


def document(rows=None,version=1):
    return json.dumps(dict(version=version,tasks=rows or []),ensure_ascii=False)


def row(task_id=1,title='Imported task',**fields):
    return dict(id=str(task_id),title=title,completed=False,createdAt=None,**fields)


class Preview(HTMLParser):
    def __init__(self,body):
        super().__init__();self.fields={};self.parts=[];self.in_payload=False;self.counts={};self.feed(body.decode())
        self.fields['payload']=''.join(self.parts)
    def handle_starttag(self,tag,attrs):
        attrs=dict(attrs)
        if tag=='input' and 'name' in attrs:self.fields[attrs['name']]=attrs.get('value','')
        if tag=='textarea' and attrs.get('name')=='payload':self.in_payload=True
        for name in ['live','trash']:
            if 'data-import-'+name in attrs:self.counts[name]=int(attrs['data-import-'+name])
    def handle_endtag(self,tag):
        if tag=='textarea':self.in_payload=False
    def handle_data(self,data):
        if self.in_payload:self.parts.append(data)


class NativeImportHTTPTests(unittest.TestCase):
    def setUp(self):
        self.server=Server();self.addCleanup(self.server.close)
        self.cookie=self.server.session();self.path=self.server.file(self.cookie)

    def post(self,path,fields,**kwargs):
        return self.server.request('POST',path,fields,cookie=self.cookie,**kwargs)

    def export(self,cookie=None,path='/export.json'):
        status,_,body=self.server.request('GET',path,cookie=cookie or self.cookie)
        self.assertEqual(status,200)
        return json.loads(body) if path.endswith('json') else body

    def test_preview_is_read_only_confirmation_is_revalidated_and_merge_undo_works(self):
        self.assertEqual(self.post('/add',dict(title='existing'))[0],303)
        before=self.path.read_bytes()
        payload=document([row(9007199254740993,'Ședință 😀 <script>alert(1)</script>')])
        status,headers,body=self.post('/import-preview',dict(payload=payload,mode='merge',format='auto'))
        self.assertEqual(status,200);self.assertIn('no-store',headers['Cache-Control'])
        self.assertEqual(self.path.read_bytes(),before)
        self.assertNotIn(b'<script>alert(1)</script>',body)
        preview=Preview(body)
        self.assertEqual(preview.counts,dict(live=1,trash=0));self.assertEqual(preview.fields['payload'],payload)
        self.assertEqual(preview.fields['confirmed'],'1')
        tampered=dict(preview.fields,payload=document([row(2,parentId='999')],version=2))
        self.assertEqual(self.post('/import',tampered)[0],422);self.assertEqual(self.path.read_bytes(),before)
        self.assertEqual(self.post('/import',preview.fields)[0],303)
        tasks=self.export()['tasks']
        self.assertEqual([task['id'] for task in tasks],['1','2'])
        self.assertEqual(tasks[-1]['title'],'Ședință 😀 <script>alert(1)</script>')
        self.assertEqual(self.post('/undo',{})[0],303)
        self.assertEqual([task['title'] for task in self.export()['tasks']],['existing'])
        self.assertEqual(self.post('/redo',{})[0],303)
        self.assertEqual(len(self.export()['tasks']),2)

    def test_json_and_csv_native_exports_roundtrip_all_metadata_trash_and_workflow(self):
        source=self.server.session()
        def post(path,fields):self.assertEqual(self.server.request('POST',path,fields,cookie=source)[0],303)
        post('/add',dict(title='Parent',project='Ședință',tags='asm,mobile',repeat='monthly',due='2031-02-28'))
        post('/add',dict(title='Done prerequisite',priority='high'));post('/start-work',dict(id=2));post('/complete',dict(id=2))
        post('/add',dict(title='Child',parent=1,deps='2'))
        post('/add',dict(title='=formula, "quoted" 😀',project='=SUM(A1)',tags='+asm'))
        post('/complete',dict(id=4));post('/delete',dict(id=4))
        expected=self.export(source)
        for path,kind in [('/export.json','json'),('/export.csv','csv')]:
            with self.subTest(kind=kind):
                data=self.export(source,path)
                if isinstance(data,dict):data=json.dumps(data,ensure_ascii=False)
                else:data=data.decode()
                status,_,body=self.post('/import-preview',dict(payload=data,format='auto',mode='replace'))
                self.assertEqual(status,200)
                preview=Preview(body);self.assertEqual(preview.counts,dict(live=3,trash=1))
                self.assertEqual(preview.fields['format'],kind)
                self.assertEqual(self.post('/import',preview.fields)[0],303)
                actual=self.export()
                originals=expected['tasks']+expected['trash'];copies=actual['tasks']+actual['trash']
                mapping={old['id']:new['id'] for old,new in zip(originals,copies)}
                for original,restored in zip(originals,copies):
                    want=dict(original,id=mapping[original['id']])
                    want['parentId']=mapping.get(original['parentId'])
                    want['dependencies']=[mapping[dep] for dep in original['dependencies']]
                    self.assertEqual(restored,want)
        self.assertEqual(self.export()['tasks'][1]['workflowStage'],'doing')

    def test_large_preview_has_separate_body_limit_and_only_first_twenty_rows(self):
        payload=document([row(i,'Task '+str(i)) for i in range(1,1001)])
        self.assertGreater(len(urlencode(dict(payload=payload))),4095)
        status,headers,body=self.post('/import-preview',dict(payload=payload,mode='merge'))
        self.assertEqual(status,200);self.assertEqual(int(headers['Content-Length']),len(body))
        preview=Preview(body);self.assertEqual(preview.counts['live'],1000)
        self.assertEqual(body.count(b'<li><strong>'),20)
        self.assertFalse(self.path.exists())
        self.assertEqual(self.post('/import',preview.fields)[0],303)
        self.assertEqual(len(self.export()['tasks']),1000)

    def test_decoded_size_strict_fields_nuls_auth_and_missing_confirmation(self):
        self.assertEqual(self.post('/add',dict(title='original'))[0],303);before=self.path.read_bytes()
        payload=document([row()])
        self.assertEqual(self.post('/import',dict(payload=payload))[0],400)
        self.assertEqual(self.post('/import-preview',dict(payload=payload,confirmed='1'))[0],400)
        for fields in [dict(payload=payload,confirmed='0'),dict(payload=payload,uid='a'*32),
                       dict(payload=payload,format='bad'),dict(payload=payload,mode='bad')]:
            self.assertEqual(self.post('/import-preview',fields)[0],400)
        for fields in [f'payload={payload}&payload={payload}','payload=%00','payload=%','payload=%GG']:
            self.assertEqual(self.post('/import-preview',fields)[0],400)
        oversized=document()+' '*(2097153-len(document()))
        self.assertEqual(self.post('/import-preview',dict(payload=oversized))[0],413)
        for path in ['/import-preview','/import']:
            self.assertEqual(self.server.request('GET',path,cookie=self.cookie)[0],405)
            self.assertEqual(self.server.request('POST',path,dict(payload=payload))[0],401)
            self.assertEqual(self.post(path,dict(payload=payload),headers={'Origin':'https://evil.example'})[0],403)
        self.assertEqual(self.path.read_bytes(),before)

    def headers(self,path,length,cookie=None,extra=''):
        return (f'POST {path} HTTP/1.1\r\nHost: 127.0.0.1:{self.server.port}\r\n'
                'Content-Type: application/x-www-form-urlencoded\r\n'+
                (f'Cookie: {cookie}\r\n' if cookie else '')+
                f'Content-Length: {length}\r\n{extra}\r\n').encode()

    def test_large_body_does_not_relax_header_limit_or_ordinary_routes(self):
        for request,code in [(self.headers('/add',6000,self.cookie),413),
                             (self.headers('/import-preview',7340031,self.cookie),413),
                             (self.headers('/import-preview',6000,None),401),
                             (self.headers('/import-preview',6000,self.cookie,'Origin: https://evil.example\r\n'),403),
                             (self.headers('/import-preview',6000,self.cookie,'X-Pad: '+'x'*4100+'\r\n'),413)]:
            with self.subTest(code=code):self.assertIn(f' {code} '.encode(),self.server.raw(request).split(b'\r\n',1)[0])
        self.assertFalse(self.path.exists())

    def test_global_receive_gate_rejects_second_workspace_and_leaves_crud_available(self):
        other=self.server.session();gate=self.server.root/'data'/'.import.lock'
        first=socket.create_connection(('127.0.0.1',self.server.port),timeout=5)
        self.addCleanup(first.close)
        first.sendall(self.headers('/import-preview',10000,self.cookie))
        held=False
        for _ in range(200):
            if gate.exists():
                with gate.open('r+b') as handle:
                    try:
                        fcntl.flock(handle,fcntl.LOCK_EX|fcntl.LOCK_NB)
                        fcntl.flock(handle,fcntl.LOCK_UN)
                    except BlockingIOError:held=True
            if held:break
            time.sleep(.005)
        self.assertTrue(held)
        response=self.server.raw(self.headers('/import-preview',10000,other))
        self.assertIn(b' 503 ',response.split(b'\r\n',1)[0])
        self.assertEqual(self.post('/add',dict(title='CRUD remains available'))[0],303)
        first.close()
        for _ in range(100):
            status,_,_=self.post('/import-preview',dict(payload=document()))
            if status!=503:break
            time.sleep(.005)
        self.assertEqual(status,200)

    def test_gate_symlink_hardlink_and_fifo_fail_without_touching_other_files(self):
        outside=self.server.root/'outside';outside.write_text('unrelated data')
        gate=self.server.root/'data'/'.import.lock'
        for kind in ['symlink','hardlink','fifo']:
            with self.subTest(kind=kind):
                if kind=='symlink':gate.symlink_to(outside)
                elif kind=='hardlink':os.link(outside,gate)
                else:os.mkfifo(gate)
                response=self.server.raw(self.headers('/import-preview',10000,self.cookie))
                self.assertIn(b' 503 ',response.split(b'\r\n',1)[0])
                self.assertEqual(outside.read_text(),'unrelated data');gate.unlink()

    def test_capacity_and_write_failure_return_preserved_payload_without_partial_write(self):
        self.assertEqual(self.post('/add',dict(title='original'))[0],303)
        before=self.path.read_bytes();payload=document([row(title='draft')])
        fields=dict(payload=payload,format='json',mode='replace',confirmed='1')
        self.path.with_suffix('.txt.tmp').mkdir()
        status,_,body=self.post('/import',fields)
        self.assertEqual(status,507);self.assertEqual(Preview(body).fields['payload'],payload)
        self.assertEqual(self.path.read_bytes(),before)
        self.path.with_suffix('.txt.tmp').rmdir()
        self.path.write_text(''.join(f'{i}|0|0|full\n' for i in range(1,1001)))
        before=self.path.read_bytes()
        status,_,body=self.post('/import-preview',dict(payload=payload,mode='merge'))
        self.assertEqual(status,409);self.assertEqual(Preview(body).fields['payload'],payload)
        self.assertEqual(self.path.read_bytes(),before)

    def test_exact_decoded_limit_preview_remains_bounded_and_read_only(self):
        base=document()
        remaining=2097152-len(base.encode())
        payload=base+'\r\n'*(remaining//2)+' '*(remaining%2)
        self.assertGreater(len(urlencode(dict(payload=payload))),4194304)
        status,headers,body=self.post('/import-preview',dict(payload=payload))
        self.assertEqual(status,200)
        self.assertEqual(int(headers['Content-Length']),len(body))
        self.assertLess(len(body),8388608)
        self.assertEqual(Preview(body).fields['payload'],payload)
        self.assertFalse(self.path.exists())

    def test_maximal_escaped_csv_and_graph_preview_fit_declared_response_cap(self):
        fields=['id','title','completed','createdAt','priority','dueDate','completedAt','project','tags','parentId','dependencies','recurrence','recurrenceAnchor','stage','deletedAt','previousCompleted','escapeFlags','workflowStage']
        stream=io.StringIO(newline='');writer=csv.DictWriter(stream,fieldnames=fields,quoting=csv.QUOTE_ALL);writer.writeheader()
        first=9223372036854774000
        tags=','.join('"'*size for size in [24,23,15])
        for i in range(1200):
            writer.writerow(dict(id=str(first+i),title='"'*110,completed='false',createdAt='',priority='urgent',
                dueDate='2031-12-31',completedAt='',project='"'*32,tags=tags,parentId='0',
                dependencies=','.join(str(first+j) for j in range(max(0,i-8),i)),recurrence='yearly',
                recurrenceAnchor='1231',stage='doing',deletedAt='2026-01-01T00:00:00Z' if i>=1000 else '',
                previousCompleted='false',escapeFlags='0',workflowStage='doing'))
        payload=stream.getvalue()
        self.assertLess(len(payload.encode()),2097152)
        # A long legal leading-zero source ID fills the decoded cap without
        # increasing the task text bounds; dense CSV quotes still need escaping.
        padding=2097152-len(payload.encode())
        payload=payload.replace('"'+str(first)+'"','"'+'0'*padding+str(first)+'"',1)
        self.assertEqual(len(payload.encode()),2097152)
        status,headers,body=self.post('/import-preview',dict(payload=payload,format='csv',mode='replace'))
        self.assertEqual(status,200)
        self.assertEqual(int(headers['Content-Length']),len(body))
        self.assertGreater(len(body),4194304);self.assertLess(len(body),8388608)
        preview=Preview(body)
        self.assertEqual(preview.counts,dict(live=1000,trash=200))
        self.assertEqual(preview.fields['payload'],payload)
        self.assertFalse(self.path.exists())

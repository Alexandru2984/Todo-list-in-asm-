"""Independent RFC 5545 byte/field checks for native dated-task snapshots."""
from datetime import datetime
import hashlib
import json
import random
import re
import struct
import unittest
from server import Server
from test_native_import_http import Preview


def calendar(body):
    assert body.endswith(b'\r\n')
    physical=body.split(b'\r\n')[:-1]
    assert all(0<len(line)<=75 for line in physical)
    assert b'\n' not in body.replace(b'\r\n',b'') and b'\r' not in body.replace(b'\r\n',b'')
    lines=[]
    for line in physical:
        # Every physical line is valid UTF-8; folding never splits a code point.
        line.decode('utf-8')
        if line.startswith((b' ',b'\t')):
            assert lines;lines[-1]+=line[1:]
        else:lines.append(line)
    assert lines[0]==b'BEGIN:VCALENDAR' and lines[-1]==b'END:VCALENDAR'
    events=[];event=None
    for line in lines[1:-1]:
        if line==b'BEGIN:VEVENT':assert event is None;event={}
        elif line==b'END:VEVENT':assert event is not None;events.append(event);event=None
        elif event is not None:
            name,value=line.decode().split(':',1);assert name not in event;event[name]=value
            assert name in {'CLASS','TRANSP','STATUS','UID','DTSTAMP','DTSTART;VALUE=DATE','SUMMARY','PRIORITY','DESCRIPTION'}
    assert event is None
    return events


def text(value):
    return re.sub(r'\\([nN,;\\])',lambda m:'\n' if m[1] in 'nN' else m[1],value)


class NativeCalendarExportTests(unittest.TestCase):
    def setUp(self):
        self.server=Server();self.addCleanup(self.server.close)
        self.cookie=self.server.session();self.path=self.server.file(self.cookie)

    def post(self,path,fields):
        status,_,_=self.server.request('POST',path,fields,cookie=self.cookie);self.assertEqual(status,303)

    def get(self,**kw):return self.server.request('GET','/export.ics',cookie=self.cookie,**kw)

    def test_cookie_download_headers_empty_calendar_and_read_only_head(self):
        self.assertEqual(self.server.request('GET','/export.ics')[0],401)
        status,headers,body=self.get();self.assertEqual(status,200);self.assertEqual(calendar(body),[])
        self.assertTrue(headers['Content-Type'].startswith('text/calendar'))
        self.assertIn('asm-dated-tasks.ics',headers['Content-Disposition']);self.assertIn('attachment',headers['Content-Disposition'])
        self.assertIn('no-store',headers['Cache-Control']);self.assertIn('noindex',headers['X-Robots-Tag'])
        self.assertEqual(int(headers['Content-Length']),len(body));self.assertNotIn(self.cookie.split('=')[1].encode(),body)
        status,head,body=self.server.request('HEAD','/export.ics',cookie=self.cookie)
        self.assertEqual(status,200);self.assertEqual(body,b'');self.assertEqual(head['Content-Length'],headers['Content-Length'])
        self.assertFalse(self.path.exists())
        self.assertEqual(self.server.request('POST','/export.ics','',cookie=self.cookie)[0],404)

    def test_dated_live_tasks_only_unicode_text_escaping_and_priority_metadata(self):
        title='Ședință 😀 a,b; \\ quoted " : BEGIN:VEVENT'
        self.post('/add',dict(title=title,due='2031-02-28',priority='urgent',project='A,b; \\ Ș',tags='asm,mobile'))
        self.post('/start-work',dict(id='1'))
        self.post('/add',dict(title='Undated'))
        self.post('/add',dict(title='Done',due='9999-12-31',priority='low'));self.post('/complete',dict(id='3'))
        self.post('/add',dict(title='Trash',due='1970-01-02'));self.post('/delete',dict(id='4'))
        before=self.path.read_bytes();status,_,body=self.get();self.assertEqual(status,200)
        events=calendar(body);self.assertEqual(len(events),2)
        self.assertEqual(text(events[0]['SUMMARY']),title)
        description=text(events[0]['DESCRIPTION'])
        self.assertIn('Task status: In progress',description);self.assertIn('Priority: urgent',description)
        self.assertIn('Project: A,b; \\ Ș',description);self.assertIn('Tags: asm,mobile',description)
        self.assertEqual(events[0]['DTSTART;VALUE=DATE'],'20310228');self.assertEqual(events[0]['PRIORITY'],'1')
        self.assertEqual(events[1]['DTSTART;VALUE=DATE'],'99991231');self.assertEqual(events[1]['PRIORITY'],'9')
        self.assertEqual(text(events[1]['SUMMARY']),'[Done] Done')
        for event in events:
            self.assertEqual(event['TRANSP'],'TRANSPARENT');self.assertEqual(event['CLASS'],'PRIVATE')
            self.assertEqual(event['STATUS'],'CONFIRMED');datetime.strptime(event['DTSTAMP'],'%Y%m%dT%H%M%SZ')
        self.assertEqual(self.path.read_bytes(),before)

    def test_uids_match_independent_sha256_are_stable_and_differ_between_workspaces(self):
        self.post('/add',dict(title='First',due='2031-01-01'))
        uid=calendar(self.get()[2])[0]['UID']
        token=self.cookie.split('=')[1]
        expected=hashlib.sha256(b'ASM TODO calendar UID v1\0'+token.encode()+struct.pack('<Q',1)).hexdigest()+'@asm.micutu.com'
        self.assertEqual(uid,expected);self.assertNotIn(token,uid)
        self.post('/edit',dict(id='1',title='Changed',due='2031-03-02'))
        self.assertEqual(calendar(self.get()[2])[0]['UID'],uid)
        self.server.stop();self.server.start();self.assertEqual(calendar(self.get()[2])[0]['UID'],uid)
        other=self.server.session()
        self.assertEqual(self.server.request('POST','/add',dict(title='Same task ID',due='2031-01-01'),cookie=other)[0],303)
        self.assertNotEqual(calendar(self.server.request('GET','/export.ics',cookie=other)[2])[0]['UID'],uid)

    def test_recurrence_exports_only_real_occurrences_without_extra_rules(self):
        self.post('/add',dict(title='Monthly',due='2031-01-31',repeat='monthly',priority='high'))
        first=calendar(self.get()[2]);self.assertEqual(len(first),1)
        self.post('/complete',dict(id='1'))
        body=self.get()[2];events=calendar(body);self.assertEqual(len(events),2)
        self.assertEqual([event['DTSTART;VALUE=DATE'] for event in events],['20310131','20310228'])
        self.assertEqual([event['PRIORITY'] for event in events],['3','3'])
        self.assertNotIn(b'RRULE',body);self.assertNotIn(b'VALARM',body)
        self.assertIn('Repeats: monthly',text(events[-1]['DESCRIPTION']))

    def test_maximum_calendar_and_random_dates_fit_bounds_and_fold_valid_utf8(self):
        rng=random.Random(5545);dates=['1970-01-02','2000-02-29','2100-03-01','2400-02-29','9999-12-31']
        dates+=[datetime.fromordinal(rng.randrange(datetime(1970,1,2).toordinal(),datetime(9999,12,31).toordinal())).strftime('%Y-%m-%d') for _ in range(995)]
        titles=['\\,;😀'*13+'abc' if i%2 else ';'*110 for i in range(1000)]
        tasks=[dict(id=str(i+1),title=titles[i],completed=False,createdAt=None,dueDate=day,project=';'*32,tags='a\\b,c;d',priority='normal') for i,day in enumerate(dates)]
        source=json.dumps(dict(version=2,tasks=tasks),ensure_ascii=False)
        status,_,body=self.server.request('POST','/import-preview',dict(payload=source,mode='replace'),cookie=self.cookie)
        self.assertEqual(status,200);self.post('/import',Preview(body).fields)
        before=self.path.read_bytes();status,headers,body=self.get();self.assertEqual(status,200)
        self.assertEqual(int(headers['Content-Length']),len(body));self.assertLess(len(body),1048576)
        events=calendar(body);self.assertEqual(len(events),1000);self.assertEqual(len({event['UID'] for event in events}),1000)
        for i,event in enumerate(events):
            self.assertEqual(event['DTSTART;VALUE=DATE'],dates[i].replace('-',''))
            self.assertEqual(text(event['SUMMARY']),titles[i]);self.assertEqual(event['PRIORITY'],'5')
        self.assertEqual(self.path.read_bytes(),before)

    def test_corrupt_storage_fails_closed(self):
        original=b'1|0|1|title\xff\n';self.path.write_bytes(original)
        self.assertEqual(self.get()[0],500);self.assertEqual(self.path.read_bytes(),original)

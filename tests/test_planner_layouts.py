"""Native calendar, board and SVG activity are independently parsed."""
import calendar
from datetime import date, datetime, timedelta, timezone
from html.parser import HTMLParser
import json
import re
import unittest
from urllib.parse import urlencode
import xml.etree.ElementTree as ET
from server import Server
from test_native_views import Rows
from test_planner_storage import snapshot


def epoch(day):return int(datetime.combine(day,datetime.min.time(),timezone.utc).timestamp())


class CalendarCells(HTMLParser):
    def __init__(self,body):
        super().__init__();self.cells=[];self.counts={};self.links=[];self.feed(body.decode())
    def handle_starttag(self,tag,attrs):
        attrs=dict(attrs);kind=attrs.get('class','')
        if kind=='calendar-blank':self.cells.append(None)
        if kind=='calendar-day':
            self.cells.append(attrs.get('data-day','1970-01-01'))
            if 'data-day' in attrs:self.counts[attrs['data-day']]=int(attrs['data-due-count'])
        if tag=='a':self.links.append(attrs.get('href',''))


class PlannerLayoutTests(unittest.TestCase):
    def setUp(self):
        self.server=Server();self.addCleanup(self.server.close)
        self.cookie=self.server.session();self.path=self.server.file(self.cookie)

    def get(self,**fields):
        return self.server.request('GET','/app'+('?' + urlencode(fields) if fields else ''),cookie=self.cookie)

    def post(self,route,fields=None):return self.server.request('POST',route,fields or {},cookie=self.cookie)

    def tasks(self):return json.loads(self.server.request('GET','/export.json',cookie=self.cookie)[2])['tasks']

    def test_calendar_month_grid_leap_centuries_and_native_day_counts(self):
        due=epoch(date(2032,2,29))
        self.path.write_text(snapshot([(1,0,'leap',dict(due=due)),(2,1,'leap done',dict(due=due)),
                                      (3,0,'March',dict(due=epoch(date(2032,3,1)))),(4,0,'undated',{})]))
        for year,month in [(2032,2),(2100,2),(2400,2),(1970,1),(9999,12)]:
            with self.subTest(year=year,month=month):
                status,_,body=self.get(layout='calendar',month=f'{year:04}-{month:02}')
                self.assertEqual(status,200);self.assertNotIn(b'{{',body)
                cells=CalendarCells(body)
                self.assertEqual(len(cells.cells),42)
                assigned=[value for value in cells.cells if value is not None]
                self.assertEqual(len(assigned),calendar.monthrange(year,month)[1])
                self.assertEqual(cells.cells.index(assigned[0]),date(year,month,1).weekday())
                self.assertEqual(assigned[-1],date(year,month,calendar.monthrange(year,month)[1]).isoformat())
                if (year,month)==(2032,2):self.assertEqual(cells.counts['2032-02-29'],2)
        self.assertEqual(Rows(self.get(layout='calendar',month='2032-02')[2]).ids,[2,1])
        self.assertEqual(Rows(self.get(day='2032-03-01')[2]).ids,[3])
        cells=CalendarCells(self.get(layout='calendar',month='2032-02',f='active')[2])
        self.assertEqual(cells.counts['2032-02-29'],1)

    def test_layout_month_and_day_validation_and_gets_never_write(self):
        self.path.write_text(snapshot([(1,0,'read only',{})]));before=self.path.read_bytes()
        for fields in [dict(layout='bad'),dict(month='2031-13'),dict(month='1969-12'),dict(month='10000-01'),
                       dict(month='2031-1'),dict(month='2031-01x'),dict(day='2031-02-29'),dict(day='1970-01-01')]:
            self.assertEqual(self.get(**fields)[0],400)
        for query in ['layout=list&layout=board','month=2031-01&month=2031-02','day=&day=2031-01-01']:
            self.assertEqual(self.server.request('GET','/app?'+query,cookie=self.cookie)[0],400)
        for fields in [dict(layout='calendar',month='2031-01'),dict(layout='board'),dict(day='2031-01-01')]:
            self.assertEqual(self.get(**fields)[0],200)
            self.assertEqual(self.path.read_bytes(),before)

    def test_board_groups_workflow_changes_undo_and_complete_without_losing_context(self):
        self.assertEqual(self.post('/board/add',dict(title='To do'))[0],303)
        self.assertEqual(self.post('/board/add',dict(title='In progress'))[0],303)
        status,headers,_=self.post('/board/start-work',dict(id=2))
        self.assertEqual(status,303);self.assertEqual(headers['Location'],'/app?layout=board')
        self.assertEqual(self.tasks()[1]['stage'],'doing')
        self.assertEqual(self.post('/board/undo')[0],303)
        self.assertEqual(self.tasks()[1]['stage'],'todo')
        self.assertEqual(self.post('/board/redo')[0],303)
        self.assertEqual(self.tasks()[1]['stage'],'doing')
        self.assertEqual(self.post('/board/add',dict(title='Done'))[0],303)
        self.assertEqual(self.post('/board/complete',dict(id=3))[0],303)
        status,_,body=self.get(layout='board')
        self.assertEqual(status,200);self.assertNotIn(b'{{',body)
        columns=re.findall(rb'<li class="board-column"><h3>(.*?)</h3><ul class="task-list">(.*?)</ul></li>',body,re.S)
        self.assertEqual([title for title,_ in columns],[b'To do',b'In progress',b'Done'])
        self.assertEqual([Rows(rows).ids for _,rows in columns],[[1],[2],[3]])
        self.assertIn(b'action="/board/complete"',body)
        self.assertIn(b'action="/board/undo"',body)
        status,_,body=self.get(layout='board',edit=2)
        self.assertEqual(status,200);self.assertIn(b'action="/board/edit"',body)
        self.assertEqual(self.post('/board/to-do',dict(id=3))[0],409)
        self.assertEqual(self.post('/board/reopen',dict(id=3))[0],303)
        self.assertEqual(self.post('/board/to-do',dict(id=3))[0],303)

    def test_board_aliases_are_explicit_and_obey_existing_security_checks(self):
        self.assertEqual(self.post('/board/add',dict(title='one'))[0],303)
        before=self.path.read_bytes()
        for route in ['/board/start-work','/board/to-do','/board/complete','/board/delete']:
            self.assertEqual(self.server.request('GET',route,cookie=self.cookie)[0],405)
            self.assertEqual(self.server.request('POST',route,dict(id=1))[0],401)
            self.assertEqual(self.server.request('POST',route,dict(id=1),cookie=self.cookie,headers={'Origin':'https://evil.example'})[0],403)
        self.assertEqual(self.post('/board/start-work',dict(id=1,title='extra'))[0],400)
        self.assertEqual(self.post('/board/start')[0],404)
        self.assertEqual(self.post('/board/export.json')[0],404)
        self.assertEqual(self.path.read_bytes(),before)

    def test_svg_requires_own_cookie_has_private_policy_and_read_only_calendar_buckets(self):
        now=datetime.now(timezone.utc).date();day=epoch(now)//86400
        self.path.write_text(snapshot([]).replace('#asm=2','#asm=3')+'#undo=0\n'+
            f'M|{day-2}|3\nM|{day-1}|4\nM|{day-30}|9\n')
        before=self.path.read_bytes()
        self.assertEqual(self.server.request('GET','/stats.svg')[0],401)
        status,headers,body=self.server.request('GET','/stats.svg',cookie=self.cookie)
        self.assertEqual(status,200);self.assertTrue(headers['Content-Type'].startswith('image/svg+xml'))
        self.assertIn('no-store',headers['Cache-Control']);self.assertIn('noindex',headers['X-Robots-Tag'])
        self.assertNotIn(self.cookie.split('=')[1].encode(),body)
        svg=ET.fromstring(body);rects=svg.findall('.//{http://www.w3.org/2000/svg}rect')
        self.assertEqual(len(rects),30)
        counts={rect.attrib['data-day']:int(rect.attrib['data-completions']) for rect in rects}
        self.assertEqual(counts[(now-timedelta(days=2)).isoformat()],3)
        self.assertEqual(counts[(now-timedelta(days=1)).isoformat()],4)
        self.assertEqual(sum(counts.values()),7)
        for rect in rects:
            self.assertLessEqual(int(rect.attrib['height']),110)
            self.assertGreaterEqual(int(rect.attrib['y']),20)
        status,_,page=self.get()
        self.assertEqual(status,200)
        self.assertIn(b'data-insight="week">7</strong>',page)
        self.assertIn(b'data-insight="streak">2</strong>',page)
        self.assertEqual(self.path.read_bytes(),before)
        other=self.server.session()
        other_svg=ET.fromstring(self.server.request('GET','/stats.svg',cookie=other)[2])
        self.assertEqual(sum(int(rect.attrib['data-completions']) for rect in other_svg.findall('.//{http://www.w3.org/2000/svg}rect')),0)
        hs,hh,hb=self.server.request('HEAD','/stats.svg',cookie=self.cookie)
        self.assertEqual(hs,200);self.assertEqual(hb,b'');self.assertEqual(int(hh['Content-Length']),len(body))

    def test_native_insights_follow_completion_undo_and_redo(self):
        self.assertEqual(self.post('/add',dict(title='activity'))[0],303)
        self.assertEqual(self.post('/complete',dict(id=1))[0],303)
        self.assertIn(b'data-insight="week">1</strong>',self.get()[2])
        self.assertEqual(self.post('/undo')[0],303)
        self.assertIn(b'data-insight="week">0</strong>',self.get()[2])
        self.assertEqual(self.post('/redo')[0],303)
        self.assertIn(b'data-insight="week">1</strong>',self.get()[2])

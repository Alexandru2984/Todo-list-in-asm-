"""Independent Gregorian oracle checks native recurrence transactions."""
import calendar
from datetime import date, datetime, timedelta, timezone
import json
import random
import unittest
from server import Server
from test_planner_storage import snapshot


def epoch(day):
    return int(datetime.combine(day,datetime.min.time(),timezone.utc).timestamp())


def next_date(due, repeat, anchor, today):
    threshold = max(due,today)
    if repeat in ['daily','weekdays']:
        result = threshold + timedelta(days=1)
        while repeat == 'weekdays' and result.weekday() >= 5: result += timedelta(days=1)
        return result
    if repeat == 'weekly': return due + timedelta(days=((threshold-due).days//7+1)*7)
    year, month = threshold.year, threshold.month
    if repeat == 'yearly': month, day = divmod(anchor,100)
    else: day = anchor
    while True:
        result = date(year,month,min(day,calendar.monthrange(year,month)[1]))
        if result > threshold: return result
        if repeat == 'yearly': year += 1
        else:
            month += 1
            if month == 13: month=1;year+=1


class PlannerRecurrenceTests(unittest.TestCase):
    def setUp(self):
        self.server = Server(); self.addCleanup(self.server.close)
        self.cookie = self.server.session(); self.path = self.server.file(self.cookie)

    def post(self, route, fields):
        return self.server.request('POST',route,fields,cookie=self.cookie)[0]

    def tasks(self):
        return json.loads(self.server.request('GET','/export.json',cookie=self.cookie)[2])['tasks']

    def test_monthly_clips_without_losing_anchor_during_native_form_edits(self):
        self.assertEqual(self.post('/add',{'title':'rent','repeat':'monthly','due':'2031-01-31','priority':'high'}),303)
        self.assertEqual(self.post('/complete',{'id':1}),303)
        task = self.tasks()[-1]
        self.assertEqual((task['dueDate'],task['recurrenceAnchor']),('2031-02-28',31))
        self.assertEqual(task['priority'],'high')
        self.assertEqual(self.post('/edit',{'id':2,'title':'rent edited','repeat':'monthly','due':'2031-02-28'}),303)
        self.assertEqual(self.post('/complete',{'id':2}),303)
        self.assertEqual(self.tasks()[-1]['dueDate'],'2031-03-31')
        before = self.path.read_bytes()
        self.assertEqual(self.post('/complete',{'id':2}),303)
        self.assertEqual(self.path.read_bytes(),before)
        self.assertEqual(len(self.tasks()),3)

    def test_yearly_leap_anchor_returns_on_next_leap_year(self):
        self.assertEqual(self.post('/add',{'title':'leap','repeat':'yearly','due':'2032-02-29'}),303)
        for task_id, expected in enumerate(['2033-02-28','2034-02-28','2035-02-28','2036-02-29'],1):
            self.assertEqual(self.post('/complete',{'id':task_id}),303)
            task = self.tasks()[-1]
            self.assertEqual(task['dueDate'],expected)
            self.assertEqual(task['recurrenceAnchor'],229)

    def test_random_recurrences_match_independent_oracle_and_skip_backlog(self):
        today = datetime.now(timezone.utc).date()
        rng = random.Random(6234)
        names = ['daily','weekdays','weekly','monthly','yearly']
        records = []; expectations = []
        for task_id in range(1,181):
            due = today + timedelta(days=rng.randrange(-1700,1700))
            repeat = rng.choice(names)
            anchor = due.day if repeat == 'monthly' else due.month*100+due.day if repeat == 'yearly' else 0
            records.append((task_id,0,repeat,dict(due=epoch(due),repeat=names.index(repeat)+1,anchor=anchor)))
            expectations.append(next_date(due,repeat,anchor,today).isoformat())
        self.path.write_text(snapshot(records))
        for task_id in range(1,181): self.assertEqual(self.post('/complete',{'id':task_id}),303)
        by_id = {task['id']:task for task in self.tasks()}
        # Snapshot recomputes next ID above the largest source ID, even if its
        # explicit sequence is smaller. New occurrences occupy IDs 181..360.
        for i, expected in enumerate(expectations,181): self.assertEqual(by_id[str(i)]['dueDate'],expected)
        self.assertTrue(all(by_id[str(i)]['completed'] for i in range(1,181)))

    def test_invalid_recurrence_missing_due_and_unknown_values_never_save(self):
        for fields in [{'repeat':'daily'},{'repeat':'yearly','due':''},
                       {'repeat':'hourly','due':'2031-01-01'},
                       {'repeat':'monthly','due':'2031-02-29'}]:
            self.assertEqual(self.post('/add',dict(title='invalid',**fields)),400)
            self.assertFalse(self.path.exists())
        self.assertEqual(self.post('/add','title=x&due=2031-01-01&repeat=daily&repeat=weekly'),400)

    def test_capacity_calendar_and_io_failures_leave_original_completion_unchanged(self):
        self.path.write_text(snapshot([(i,0,'full',{'due':epoch(date(2031,1,1)),'repeat':1}) for i in range(1,1001)]))
        before = self.path.read_bytes()
        self.assertEqual(self.post('/complete',{'id':1}),409)
        self.assertEqual(self.path.read_bytes(),before)
        self.path.write_text(snapshot([(1,0,'end of calendar',{'due':epoch(date(9999,12,31)),'repeat':5,'anchor':1231})]))
        before = self.path.read_bytes()
        self.assertEqual(self.post('/complete',{'id':1}),409)
        self.assertEqual(self.path.read_bytes(),before)
        self.path.write_text(snapshot([(1,0,'write failure',{'due':epoch(date(2031,1,1)),'repeat':1})]))
        before = self.path.read_bytes();self.path.with_suffix('.txt.tmp').mkdir()
        self.assertEqual(self.post('/complete',{'id':1}),507)
        self.assertEqual(self.path.read_bytes(),before)

    def test_changing_due_reanchors_and_clearing_due_removes_repeat(self):
        self.assertEqual(self.post('/add',{'title':'changed','repeat':'monthly','due':'2031-01-31'}),303)
        self.assertEqual(self.post('/edit',{'id':1,'title':'changed','due':'2031-01-15'}),303)
        self.assertEqual(self.tasks()[0]['recurrenceAnchor'],15)
        self.assertEqual(self.post('/edit',{'id':1,'title':'changed','due':''}),303)
        task = self.tasks()[0]
        self.assertIsNone(task['dueDate']);self.assertEqual(task['recurrence'],'none')
        self.assertEqual(task['recurrenceAnchor'],0)

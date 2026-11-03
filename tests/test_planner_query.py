"""Structured native search uses bounded AND predicates and exact metadata."""
from datetime import datetime, timezone
import unittest
import random
from urllib.parse import urlencode
from server import Server
from test_native_views import Rows
from test_planner_storage import snapshot


def epoch(day):return int(datetime.fromisoformat(day).replace(tzinfo=timezone.utc).timestamp())


class PlannerQueryTests(unittest.TestCase):
    def setUp(self):
        self.server=Server();self.addCleanup(self.server.close)
        self.cookie=self.server.session();self.path=self.server.file(self.cookie)
        self.path.write_text(snapshot([
            (1,0,'Plan ședință ASM mobile',dict(priority=2,due=epoch('2031-01-10'),project='My work',tags='asm,mobile')),
            (2,1,'Ship assembly',dict(priority=3,due=epoch('2031-01-20'),project='My Work',tags='asm')),
            (3,0,'Review native security',dict(tags='security')),
            (4,0,'Document ASM security',dict(priority=1,due=epoch('2031-01-05'),project='Personal',tags='asm,security',deps='3')),
            (5,2,'Deleted ASM',dict(deleted=1700000001,project='My work',tags='asm')),
        ]))

    def get(self,query,**fields):
        return self.server.request('GET','/app?'+urlencode(dict(q=query,**fields)),cookie=self.cookie)

    def test_priority_status_dates_projects_tags_and_free_text_are_anded(self):
        cases=[('priority:HIGH',[1]),('status:active',[4,3,1]),('status:done',[2]),
               ('status:trash',[5]),('status:blocked',[4]),('project:"my WORK" #asm',[2,1]),
               ('project:""',[3]),('#asm #security',[4]),('tag:ASM',[4,2,1]),
               ('priority:high status:active #asm before:2031-01-15 after:2031-01-05',[1]),
               ('before:2031-01-10',[4]),('after:2031-01-10',[2]),('on:2031-01-10',[1]),
               ('"ASM mobile"',[1]),('mobile plan',[1]),('șEDINȚĂ #ASM',[1])]
        for query,expected in cases:
            with self.subTest(query=query):
                status,_,body=self.get(query)
                self.assertEqual(status,200);self.assertEqual(Rows(body).ids,expected)
                self.assertEqual(Rows(body).counters,dict(total=4,active=3,done=1))
        self.assertEqual(Rows(self.get('status:trash',f='active')[2]).ids,[])
        self.assertEqual(Rows(self.get('status:active',f='trash')[2]).ids,[])
        self.assertEqual(Rows(self.get('#asm',project='Personal')[2]).ids,[4])

    def test_invalid_operator_values_dates_duplicates_and_bounds_fail_without_writes(self):
        before=self.path.read_bytes()
        queries=['priority:bad','status:bad','priority:','status:','tag:',
                 'before:2031-02-29','after:2031-1-01','on:2031-01-01extra',
                 'priority:high priority:low','status:active status:done',
                 'project:"unterminated','project:"My work"junk',
                 'project:'+('x'*33),'tag:'+('x'*25),' '.join('#'+str(i) for i in range(9)),
                 ' '.join('a' for _ in range(65)),'x'*256]
        for query in queries:
            with self.subTest(query=query):self.assertEqual(self.get(query)[0],400)
        self.assertEqual(self.path.read_bytes(),before)

    def test_unmatched_free_quote_unknown_prefix_and_escaped_project_quote_remain_searchable(self):
        self.path.write_text(snapshot([(1,0,'Literal "<>&😀 owner:me',dict(project='A "quoted" project'))]))
        for query in ['"<>&😀','owner:me','project:"A \\"quoted\\" project"','"Literal" owner:me']:
            self.assertEqual(Rows(self.get(query)[2]).ids,[1],query)
        self.assertEqual(self.get('😀'*63+'abc')[0],200)
        _,_,body=self.get('"<>&😀')
        self.assertIn(b'&#34;&lt;&gt;&amp;',body)
        self.assertNotIn(b'value=""<',body)

    def test_quoted_phrase_requires_contiguous_words(self):
        self.path.write_text(snapshot([(1,0,'red blue green',{}),(2,0,'red green blue',{})]))
        self.assertEqual(Rows(self.get('red blue')[2]).ids,[2,1])
        self.assertEqual(Rows(self.get('"red blue"')[2]).ids,[1])
        self.assertEqual(Rows(self.get('"red green"')[2]).ids,[2])

    def test_bounded_adversarial_query_corpus_never_crashes_or_mutates(self):
        rng=random.Random(2984)
        before=self.path.read_bytes()
        alphabet='abc :#"\\0123ș😀'
        for i in range(180):
            query=''.join(rng.choice(alphabet) for _ in range(rng.randrange(1,120)))
            if i%3==0:query=rng.choice(['priority:','project:','status:','before:','tag:'])+query
            status,_,_=self.get(query)
            self.assertIn(status,[200,400],query)
        self.assertEqual(self.path.read_bytes(),before)

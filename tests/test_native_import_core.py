"""Independent Python JSON/CSV encoders exercise actual NASM import transactions."""
import csv
import io
import json
from pathlib import Path
import random
import subprocess
import tempfile
import unittest

ROOT=Path(__file__).resolve().parents[1]


def task(task_id='1',title='native',**fields):
    return dict(id=str(task_id),title=title,completed=False,createdAt='1970-01-01T00:00:00Z',**fields)


class NativeImportCoreTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.build=tempfile.TemporaryDirectory(prefix='asm-import-harness-')
        cls.addClassCleanup(cls.build.cleanup)
        obj=Path(cls.build.name)/'harness.o';cls.binary=Path(cls.build.name)/'harness'
        subprocess.run(['nasm','-f','elf64','-w+error','tests/import_harness.asm','-o',str(obj)],cwd=ROOT,check=True,capture_output=True)
        objects=[str(path) for path in sorted((ROOT/'build').glob('*.o')) if path.name not in ['main.o','backup-native.o','offsite-native.o']]
        subprocess.run(['ld','-z','noexecstack','-z','separate-code','-o',str(cls.binary),str(obj),*objects],check=True,capture_output=True)

    def setUp(self):
        self.temp=tempfile.TemporaryDirectory(prefix='asm-import-core-test-');self.addCleanup(self.temp.cleanup)
        self.root=Path(self.temp.name);(self.root/'data').mkdir(mode=0o700)
        self.path=self.root/'data'/('todos-'+'a'*32+'.txt')

    def run_import(self,payload,kind='json',mode='replace'):
        if isinstance(payload,dict):payload=json.dumps(payload,ensure_ascii=True).encode()
        elif isinstance(payload,str):payload=payload.encode()
        return subprocess.run([str(self.binary),kind,mode],input=payload,cwd=self.root,capture_output=True,timeout=5)

    def test_json_v1_unicode_surrogate_pairs_null_times_and_large_source_ids(self):
        source=dict(version=1,tasks=[task('9007199254740993','Ședință 😀 "quoted" \\ path')])
        source['tasks'][0]['createdAt']=None
        result=self.run_import(source)
        self.assertEqual(result.returncode,0,result.stderr)
        document=json.loads(result.stdout)
        self.assertEqual(document['tasks'][0]['id'],'1')
        self.assertEqual(document['tasks'][0]['title'],source['tasks'][0]['title'])
        self.assertIsNone(document['tasks'][0]['createdAt'])
        self.assertTrue(self.path.read_text().startswith('#asm=3\n'))

    def test_json_v2_remaps_forward_references_trash_and_underlying_workflow(self):
        source=dict(version=2,tasks=[
            task(10,'child',parentId='20',dependencies=['30'],priority='urgent',dueDate='2031-02-28',recurrence='monthly',recurrenceAnchor=31,tags='asm,mobile'),
            task(20,'parent'),
            dict(task(30,'done prerequisite'),completed=True,stage='done',workflowStage='doing',completedAt='2026-01-01T12:13:14Z'),
        ],trash=[dict(task(40,'trashed'),deletedAt='2026-01-02T00:00:00Z',previousCompleted=True,completedAt='2026-01-01T00:00:00Z')])
        result=self.run_import(source);self.assertEqual(result.returncode,0,result.stderr)
        document=json.loads(result.stdout);rows=document['tasks']
        self.assertEqual(rows[0]['parentId'],'2');self.assertEqual(rows[0]['dependencies'],['3'])
        self.assertEqual(rows[0]['recurrenceAnchor'],31)
        self.assertEqual(rows[2]['workflowStage'],'doing')
        self.assertEqual(document['trash'][0]['id'],'4');self.assertTrue(document['trash'][0]['previousCompleted'])

    def test_csv_quotes_bom_reordered_columns_and_reversible_spreadsheet_prefixes(self):
        columns=['title','id','createdAt','completed','project','tags','escapeFlags','stage','workflowStage']
        stream=io.StringIO(newline='');writer=csv.DictWriter(stream,fieldnames=columns)
        writer.writeheader();writer.writerow(dict(title="'=title, \"quoted\" 😀",id='123',createdAt='',completed='TRUE',project="'=SUM(A1)",tags="'+asm",escapeFlags=7,stage='done',workflowStage='doing'))
        result=self.run_import('\ufeff'+stream.getvalue(),'csv')
        self.assertEqual(result.returncode,0,result.stderr)
        row=json.loads(result.stdout)['tasks'][0]
        self.assertEqual(row['title'],'=title, "quoted" 😀');self.assertEqual(row['project'],'=SUM(A1)')
        self.assertEqual(row['tags'],'+asm');self.assertTrue(row['completed'])
        self.assertEqual(row['workflowStage'],'doing');self.assertIsNone(row['createdAt'])

    def test_merge_fresh_ids_rejects_external_refs_and_capacity_without_overwrite(self):
        self.path.write_text('#next=100\n1|0|0|existing\n')
        source=dict(version=2,tasks=[task(1,'parent'),task(2,'child',parentId='1')])
        result=self.run_import(source,mode='merge');self.assertEqual(result.returncode,0)
        rows=json.loads(result.stdout)['tasks']
        self.assertEqual([row['id'] for row in rows],['1','100','101'])
        self.assertEqual(rows[-1]['parentId'],'100')
        before=self.path.read_bytes()
        self.assertNotEqual(self.run_import(dict(version=2,tasks=[task(2,'external',parentId='1')]),mode='merge').returncode,0)
        self.assertEqual(self.path.read_bytes(),before)
        self.path.write_text(''.join(f'{i}|0|0|full\n' for i in range(1,1001)))
        before=self.path.read_bytes()
        self.assertNotEqual(self.run_import(dict(version=1,tasks=[task()]),mode='merge').returncode,0)
        self.assertEqual(self.path.read_bytes(),before)

    def test_adversarial_json_and_schema_corpus_never_publishes(self):
        self.path.write_text('#next=2\n1|0|0|original\n');before=self.path.read_bytes()
        base=json.dumps(dict(version=1,tasks=[task()]))
        invalid=[b'',b'[]',b'{}',base.encode()+b'\0hidden',base+' trailing',base[:-1],
                 '{"version":1,"version":2,"tasks":[]}', '{"version":01,"tasks":[]}',
                 '{"version":2.0,"tasks":[]}', '{"version":2e0,"tasks":[]}',
                 '{"version":1,"tasks":[],}', '{"version":1,"tasks":[{}]}',
                 '{"version":1,"tasks":['+'['*1000+']'*1000+']}',
                 '{"version":1,"tasks":[],"unknown":{"deep":{}}}',
                 base.replace('native',r'\ud800'),base.replace('native',r'\udc00'),
                 base.replace('native',r'\ud800\u0041'),base.replace('native',r'\u0000'),
                 base.replace('native',r'\uGGGG'),base.replace('native','x'*111),
                 base.replace('native','bad|record'),base.replace('native',r'bad\nrecord'),
                 base.replace('false','"false"'),base.replace('"id": "1"','"id": 1'),
                 base.replace('"id": "1"','"id": "0"'),base.replace('"id": "1"','"id": "9223372036854775807"'),
                 base.replace('1970-01-01T00:00:00Z','2100-02-29T00:00:00Z'),
                 base.replace('1970-01-01T00:00:00Z','2031-01-01T24:00:00Z'),
                 dict(version=2,tasks=[task(1),task(1)]),
                 dict(version=2,tasks=[task(1,parentId='1')]),
                 dict(version=2,tasks=[task(1,dependencies=['2']),task(2,dependencies=['1'])]),
                 dict(version=2,tasks=[task(1,dependencies=['2'],parentId='2'),task(2)]),
                 dict(version=2,tasks=[task(1,tags='asm,ASM')]),
                 dict(version=2,tasks=[task(1,recurrence='daily')]),
                 dict(version=1,tasks=[task(1,priority='high')]),
                 dict(version=2,tasks=[dict(task(1),title='')]),
                 dict(version=2,tasks=[dict(task(1),completedAt='2026-01-01T00:00:00Z')]),
                 dict(version=2,tasks=[dict(task(1),stage='done')]),
                 dict(version=2,tasks=[],trash=[task(1)]),
                 dict(version=2,tasks=[dict(task(1),deletedAt='2026-01-01T00:00:00Z')]),
                ]
        for payload in invalid:
            with self.subTest(payload=str(payload)[:100]):
                result=self.run_import(payload)
                self.assertEqual(result.returncode,1,result.stdout)
                self.assertEqual(self.path.read_bytes(),before)

    def test_csv_malformed_fields_flags_controls_and_headers_fail_closed(self):
        self.path.write_text('#next=2\n1|0|0|original\n');before=self.path.read_bytes()
        invalid=['id,title,completed\n1,native,false\n','id,id,title,completed,createdAt\n1,2,x,false,\n',
                 'id,title,completed,createdAt,unknown\n1,x,false,,x\n',
                 'id,title,completed,createdAt\n1,"unclosed,false,\n',
                 'id,title,completed,createdAt\n1,"x"junk,false,\n',
                 'id,title,completed,createdAt\r1,x,false,\r',
                 'id,title,completed,createdAt\n1,"line\nbreak",false,\n',
                 'id,title,completed,createdAt,escapeFlags\n1,plain,false,,1\n',
                 "id,title,completed,createdAt,escapeFlags\n1,'plain,false,,1\n",
                 "id,title,completed,createdAt,escapeFlags\n1,'=safe,false,,2\n",
                 'id,title,completed,createdAt\n1,x,false,,extra\n',
                 'id,title,completed,createdAt\n1,x,false\n']
        for payload in invalid:
            with self.subTest(payload=payload[:90]):
                self.assertEqual(self.run_import(payload,'csv').returncode,1)
                self.assertEqual(self.path.read_bytes(),before)

    def test_empty_replace_and_io_failure_have_atomic_semantics(self):
        self.path.write_text('#next=100\n1|0|0|original\n')
        before=self.path.read_bytes();self.path.with_suffix('.txt.tmp').mkdir()
        self.assertEqual(self.run_import(dict(version=1,tasks=[task()])).returncode,1)
        self.assertEqual(self.path.read_bytes(),before)
        self.path.with_suffix('.txt.tmp').rmdir()
        result=self.run_import(dict(version=1,tasks=[]));self.assertEqual(result.returncode,0)
        self.assertEqual(json.loads(result.stdout)['tasks'],[])
        self.assertIn('#next=100\n',self.path.read_text());self.assertIn('U|1|0|0|original',self.path.read_text())

    def test_seeded_unicode_and_quote_roundtrips_against_independent_json(self):
        rng=random.Random(6234);alphabet='asm Ședință😀"\\<>&,='
        rows=[task(i,''.join(rng.choice(alphabet) for _ in range(20))) for i in range(1,201)]
        result=self.run_import(dict(version=1,tasks=rows));self.assertEqual(result.returncode,0)
        restored=json.loads(result.stdout)['tasks']
        self.assertEqual([row['title'] for row in restored],[row['title'] for row in rows])

    def test_seeded_mutations_and_truncations_never_crash_or_publish_partial_records(self):
        rng=random.Random(2984)
        source=json.dumps(dict(version=2,tasks=[task(1,'Ședință 😀',priority='high',dueDate='2031-01-01')]),ensure_ascii=True).encode()
        for i in range(180):
            mutated=bytearray(source)
            if i%3==0:mutated=mutated[:rng.randrange(len(mutated))]
            else:
                for _ in range(rng.randrange(1,5)):
                    mutated[rng.randrange(len(mutated))]=rng.choice(b'{}[]:,.0123456789"\\x\x00\xff')
            self.path.write_text('#next=2\n1|0|0|original\n');before=self.path.read_bytes()
            result=self.run_import(bytes(mutated))
            self.assertIn(result.returncode,[0,1])
            if result.returncode:self.assertEqual(self.path.read_bytes(),before)
            else:self.assertIsInstance(json.loads(result.stdout)['tasks'],list)

"""Validate the ASM utility using independent SHA-256 and TAR implementations."""
import hashlib
import os
from pathlib import Path
import random
import resource
import subprocess
import tarfile
import tempfile
import time
import threading
import unittest

BINARY = Path(__file__).resolve().parents[1]/'build/backup'


class NativeBackupTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='asm-native-backup-test-')
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.data = self.root/'data'; self.data.mkdir()
        self.out = self.root/'snapshots'
        self.name = 'todos-'+'a'*32+'.txt'

    def run_backup(self, *args, **kwargs):
        return subprocess.run([str(BINARY), *map(str,args)],capture_output=True,timeout=5,**kwargs)

    def create(self):
        before = set(self.out.glob('*.tar')) if self.out.exists() else set()
        result = self.run_backup(self.data,self.out)
        self.assertEqual(result.returncode,0,result.stderr)
        added = set(self.out.glob('*.tar')) - before
        self.assertEqual(len(added), 1)
        return added.pop()

    def archive(self, members):
        path = self.root/'altered.tar'
        with path.open('wb') as output:
            for name, data, mode, kind in members:
                info = tarfile.TarInfo(name);info.mode = mode;info.size = len(data);info.type = kind
                output.write(info.tobuf(format=tarfile.USTAR_FORMAT))
                output.write(data);output.write(b'\0'*(-len(data)%512))
            output.write(b'\0'*1024)
        return path

    def test_sha256_standard_and_boundary_vectors(self):
        rng = random.Random(6234)
        payloads = [b'',b'abc',b'abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq']
        payloads += [rng.randbytes(size) for size in [1,55,56,63,64,65,119,120,127,128,129,4096,262144,2097152]]
        path = self.root/'vector'
        for data in payloads:
            with self.subTest(length=len(data)):
                path.write_bytes(data)
                result = self.run_backup('--hash',path)
                self.assertEqual(result.returncode,0,result.stderr)
                self.assertEqual(result.stdout.decode().strip(),hashlib.sha256(data).hexdigest())

    def test_roundtrip_tar_sha256_manifest_and_permissions(self):
        contents = b'#next=2\n1|0|1|Native snapshot\n'
        (self.data/self.name).write_bytes(contents)
        (self.data/(self.name+'.tmp')).write_text('incomplete')
        (self.data/(self.name+'.lock')).write_text('')
        archive = self.create()
        self.assertEqual(archive.stat().st_mode & 0o777,0o600)
        self.assertEqual(self.out.stat().st_mode & 0o777,0o700)
        self.assertEqual(self.run_backup('--verify',archive).returncode,0)
        with tarfile.open(archive) as reader:
            self.assertEqual(reader.getnames(),[self.name,'SHA256SUMS'])
            self.assertEqual(subprocess.check_output(['tar','-tf',str(archive)],text=True).splitlines(),[self.name,'SHA256SUMS'])
            self.assertEqual(reader.extractfile(self.name).read(),contents)
            manifest = reader.extractfile('SHA256SUMS').read().decode()
            self.assertEqual(manifest,f'{hashlib.sha256(contents).hexdigest()}  {self.name}\n')
            self.assertTrue(all(item.mode==0o600 for item in reader))

    def test_binary_is_static_with_non_executable_stack(self):
        headers = subprocess.check_output(['readelf','-lW',str(BINARY)],text=True)
        self.assertNotIn('INTERP',headers)
        stack = next(line for line in headers.splitlines() if 'GNU_STACK' in line)
        self.assertIn('RW ',stack)
        self.assertNotIn('RWE',stack)

    def test_planner_size_boundary_survives_archive_and_independent_hash(self):
        contents = b'V2 boundary\n' + b'x'*(2097152-len(b'V2 boundary\n'))
        (self.data/self.name).write_bytes(contents)
        archive = self.create()
        self.assertEqual(self.run_backup('--verify',archive).returncode,0)
        with tarfile.open(archive) as reader:
            self.assertEqual(reader.extractfile(self.name).read(),contents)
            self.assertIn(hashlib.sha256(contents).hexdigest().encode(),reader.extractfile('SHA256SUMS').read())

    def test_empty_archive_and_multiple_snapshots(self):
        first = self.create(); second = self.create()
        self.assertNotEqual(first,second)
        self.assertEqual(self.run_backup('--verify',first).returncode,0)
        with tarfile.open(second) as reader:
            self.assertEqual(reader.getnames(),['SHA256SUMS'])
            self.assertEqual(reader.extractfile('SHA256SUMS').read(),b'')

    def test_source_symlink_hardlink_fifo_and_oversize_fail_without_publication(self):
        outside = self.root/'outside'; outside.write_text('unrelated')
        path = self.data/self.name
        for kind in ['symlink','hardlink','fifo','oversize']:
            with self.subTest(kind=kind):
                if kind=='symlink': path.symlink_to(outside)
                elif kind=='hardlink': os.link(outside,path)
                elif kind=='fifo': os.mkfifo(path)
                else: path.write_bytes(b'x'*2097153)
                result = self.run_backup(self.data,self.out)
                self.assertNotEqual(result.returncode,0)
                self.assertEqual(list(self.out.glob('*.tar')),[])
                self.assertEqual(list(self.out.glob('.snapshot-*')),[])
                self.assertEqual(outside.read_text(),'unrelated')
                path.unlink()
        for mode in ['--hash','--verify']:
            os.mkfifo(path)
            self.assertNotEqual(self.run_backup(mode,path).returncode,0)
            path.unlink()

    def test_verify_detects_payload_manifest_header_and_truncation_damage(self):
        (self.data/self.name).write_bytes(b'original')
        archive = self.create(); original = archive.read_bytes()
        variants = [original[:512]+b'X'+original[513:], original[:100]+b'9'+original[101:],
                    original[:-1], original+b'extra', original[:1024]]
        for data in variants:
            with self.subTest(length=len(data)):
                bad = self.root/'bad.tar';bad.write_bytes(data)
                self.assertNotEqual(self.run_backup('--verify',bad).returncode,0)

    def test_verify_rejects_traversal_symlinks_duplicates_and_unsafe_permissions(self):
        data=b'original'; manifest=f'{hashlib.sha256(data).hexdigest()}  {self.name}\n'.encode()
        for name,mode,kind in [('../outside',0o600,tarfile.REGTYPE),(self.name,0o600,tarfile.SYMTYPE),
                               (self.name,0o4777,tarfile.REGTYPE)]:
            with self.subTest(name=name,mode=mode,kind=kind):
                path=self.archive([(name,data,mode,kind),('SHA256SUMS',manifest,0o600,tarfile.REGTYPE)])
                self.assertNotEqual(self.run_backup('--verify',path).returncode,0)
        path=self.archive([(self.name,data,0o600,tarfile.REGTYPE)]*2+[('SHA256SUMS',manifest*2,0o600,tarfile.REGTYPE)])
        self.assertNotEqual(self.run_backup('--verify',path).returncode,0)
        path=self.archive([(self.name,data,0o600,tarfile.REGTYPE),('SHA256SUMS',manifest,0o600,tarfile.REGTYPE)])
        self.assertEqual(self.run_backup('--verify',path).returncode,0)
        wrong = (b'1' if manifest[:1] != b'1' else b'2') + manifest[1:]
        path=self.archive([(self.name,data,0o600,tarfile.REGTYPE),('SHA256SUMS',wrong,0o600,tarfile.REGTYPE)])
        self.assertNotEqual(self.run_backup('--verify',path).returncode,0)

    def test_retention_only_removes_old_native_namespace_regular_files(self):
        self.out.mkdir()
        old=self.out/'asm-todo-1600000000-0123456789abcdef.tar';old.write_text('old')
        legacy=self.out/'asm-todo-old.tar.gz';legacy.write_text('legacy')
        unrelated=self.out/'unrelated.tar';unrelated.write_text('keep')
        future=self.out/'asm-todo-9223372036854775807-0123456789abcdef.tar';future.write_text('future')
        link=self.out/'asm-todo-1600000000-fedcba9876543210.tar';link.symlink_to(unrelated)
        self.create()
        self.assertFalse(old.exists())
        self.assertTrue(legacy.exists());self.assertTrue(future.exists());self.assertTrue(link.is_symlink())
        self.assertEqual(unrelated.read_text(),'keep')

    def test_verifies_many_members_and_independent_hashes(self):
        records={f'todos-{i:032x}.txt':os.urandom(i*17) for i in range(150)}
        for name,data in records.items(): (self.data/name).write_bytes(data)
        archive=self.create()
        self.assertEqual(self.run_backup('--verify',archive).returncode,0)
        with tarfile.open(archive) as reader:
            for name,data in records.items():
                self.assertEqual(reader.extractfile(name).read(),data)

    def test_hot_backup_keeps_a_complete_immutable_inode_during_replacement(self):
        path = self.data/self.name
        alternatives = [b'A'*131072,b'B'*131072]
        path.write_bytes(alternatives[0])
        stopped = threading.Event()
        def replace():
            index = 0
            while not stopped.is_set():
                temporary = self.data/'replacement.tmp'
                temporary.write_bytes(alternatives[index % 2])
                os.replace(temporary,path)
                index += 1
        worker = threading.Thread(target=replace)
        worker.start()
        try:
            for _ in range(10):
                archive = self.create()
                self.assertEqual(self.run_backup('--verify',archive).returncode,0)
                with tarfile.open(archive) as reader:
                    self.assertIn(reader.extractfile(self.name).read(),alternatives)
        finally:
            stopped.set();worker.join(timeout=5)

    def test_exhausted_write_limit_does_not_publish_or_prune(self):
        self.out.mkdir()
        prior=self.out/'asm-todo-1600000000-0123456789abcdef.tar';prior.write_text('keep on failure')
        (self.data/self.name).write_bytes(b'x'*8192)
        def limit(): resource.setrlimit(resource.RLIMIT_FSIZE,(1024,1024))
        result=self.run_backup(self.data,self.out,preexec_fn=limit)
        self.assertNotEqual(result.returncode,0)
        self.assertEqual(list(self.out.glob('*.tar')),[prior])
        self.assertEqual(prior.read_text(),'keep on failure')

    def test_source_and_destination_symlink_directories_refused(self):
        link=self.root/'link';link.symlink_to(self.data,target_is_directory=True)
        self.assertNotEqual(self.run_backup(link,self.out).returncode,0)
        real=self.root/'real';real.mkdir()
        self.out.symlink_to(real,target_is_directory=True)
        self.assertNotEqual(self.run_backup(self.data,self.out).returncode,0)

"""Native policy and real rclone crypt transport, using disposable local storage."""
import fcntl
import json
import os
from pathlib import Path
import shutil
import subprocess
import tarfile
import tempfile
import time
import unittest

REPO = Path(__file__).resolve().parents[1]
BINARY = REPO / 'build/offsite'
BACKUP = REPO / 'build/backup'
RCLONE = shutil.which('rclone')


@unittest.skipIf(os.getuid() == 0, 'Transport state must have a non-root owner')
class OffsiteTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='asm-offsite-test-')
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.data = self.root/'data'; self.data.mkdir(mode=0o700)
        self.archives = self.root/'archives'
        self.spool = self.root/'spool'; self.spool.mkdir(mode=0o700)
        self.config = self.root/'rclone.conf'
        self.remote = self.root/'encrypted-store'
        self.remote_arg = 'encrypted:asm-todo'
        self.name = 'todos-'+'a'*32+'.txt'
        (self.data/self.name).write_text('#next=2\n1|0|1|Private offsite fixture\n')
        self.create()
        self.config.write_text('[encrypted]\ntype = crypt\nremote = '+str(self.remote)+'\n')
        self.config.chmod(0o600)

    def run_native(self, *args, **kw):
        return subprocess.run([str(BINARY), *map(str,args)],capture_output=True,timeout=20,**kw)

    def create(self):
        result = subprocess.run([str(BACKUP),str(self.data),str(self.archives)],capture_output=True,timeout=5)
        self.assertEqual(result.returncode,0,result.stderr)
        return max(self.archives.glob('*.tar'),key=lambda p:p.stat().st_mtime_ns)

    def stage(self):
        result = self.run_native('--stage',self.archives,self.spool)
        self.assertEqual(result.returncode,0,result.stderr)
        return next(self.spool.glob('*.tar'))

    def crypto_config(self):
        if not RCLONE:self.skipTest('rclone is installed by the native CI job')
        password = subprocess.check_output([RCLONE,'obscure','disposable-fixture-secret'],text=True).strip()
        self.config.write_text('[encrypted]\ntype = crypt\nremote = '+str(self.remote)+
                               '\npassword = '+password+'\nfilename_encryption = standard\n'
                               'directory_name_encryption = true\nno_data_encryption = false\n')
        self.config.chmod(0o600)

    def ship(self, binary=None, **kw):
        return self.run_native('--ship',self.spool,self.config,self.remote_arg,binary or RCLONE,**kw)

    def status(self):
        return self.run_native('--status',self.spool,93600)

    def fake_transport(self, action):
        path = self.root/'transport'
        path.write_text("""#!/usr/bin/python3
import json,os,sys
from pathlib import Path
root=Path(__file__).parent
with (root/'calls').open('a') as log:
    log.write(json.dumps({'args':sys.argv[1:],'override':os.environ.get('RCLONE_CONFIG_ENCRYPTED_NO_DATA_ENCRYPTION')})+'\\n')
source,dest=sys.argv[2:4]
action="""+repr(action)+"""
if action=='fail':sys.exit(23)
wire=root/'wire'
if ':asm-todo/' in dest:
    wire.write_bytes(Path(source).read_bytes())
else:
    payload=bytearray(wire.read_bytes())
    if action=='tamper':payload[512]^=1
    Path(dest).write_bytes(payload);Path(dest).chmod(0o600)
""")
        path.chmod(0o700)
        return path

    def test_latest_verified_archive_is_staged_with_private_permissions(self):
        staged = self.stage()
        self.assertEqual(staged.read_bytes(),next(self.archives.glob('*.tar')).read_bytes())
        self.assertEqual(staged.stat().st_mode & 0o777,0o600)
        self.assertEqual((self.spool/'transport.log').stat().st_mode & 0o777,0o600)
        self.assertEqual((self.spool/'.offsite.lock').stat().st_mode & 0o777,0o600)
        self.stage()  # same immutable archive may be staged again
        self.assertEqual(self.status().returncode,1)
        self.assertFalse((self.spool/'last-success').exists())

    def test_spool_pruning_only_removes_older_native_archives(self):
        first=self.stage()
        old=self.spool/'asm-todo-1600000000-0123456789abcdef.tar'
        old.write_bytes(first.read_bytes());old.chmod(0o600)
        other=self.spool/'keep.txt';other.write_text('keep')
        self.stage()
        self.assertFalse(old.exists());self.assertEqual(other.read_text(),'keep')
        self.assertEqual(len(list(self.archives.glob('*.tar'))),1)

    def test_corrupt_newest_does_not_fall_back_to_an_old_archive(self):
        old=self.stage();before=old.read_bytes()
        path=self.archives/f'asm-todo-{int(time.time())+1}-ffffffffffffffff.tar'
        path.write_bytes(b'corrupt');path.chmod(0o600)
        self.assertNotEqual(self.run_native('--stage',self.archives,self.spool).returncode,0)
        self.assertEqual(old.read_bytes(),before)
        self.assertFalse((self.spool/path.name).exists())

    def test_stale_future_and_malformed_archive_names_cannot_refresh_health(self):
        original=next(self.archives.glob('*.tar'))
        for name in ['asm-todo-1600000000-0123456789abcdef.tar',
                     'asm-todo-9223372036854775807-0123456789abcdef.tar',
                     'asm-todo-1-0123456789abcdef', 'asm-todo-1-0123456789abcdef.tar.extra']:
            with self.subTest(name=name):
                current=original.with_name(name);original.rename(current)
                self.assertNotEqual(self.run_native('--stage',self.archives,self.spool).returncode,0)
                current.rename(original)

    def test_locked_source_or_spool_fails_promptly(self):
        for path in [self.archives/'.backup.lock',self.spool/'.offsite.lock']:
            with path.open('a+') as lock:
                path.chmod(0o600);fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB)
                start=time.monotonic()
                self.assertNotEqual(self.run_native('--stage',self.archives,self.spool).returncode,0)
                self.assertLess(time.monotonic()-start,2)

    def test_unsafe_source_and_destination_inodes_are_refused(self):
        original=next(self.archives.glob('*.tar'));payload=original.read_bytes()
        outside=self.root/'outside';outside.write_bytes(payload);outside.chmod(0o600)
        for kind in ['symlink','hardlink','fifo']:
            original.unlink()
            if kind=='symlink':original.symlink_to(outside)
            elif kind=='hardlink':os.link(outside,original)
            else:os.mkfifo(original,0o600)
            self.assertNotEqual(self.run_native('--stage',self.archives,self.spool).returncode,0)
            original.unlink();original.write_bytes(payload);original.chmod(0o600)
        (self.spool/original.name).symlink_to(outside)
        self.assertNotEqual(self.run_native('--stage',self.archives,self.spool).returncode,0)
        self.assertEqual(outside.read_bytes(),payload)

    def test_symlink_directories_and_public_spool_are_refused(self):
        link=self.root/'link';link.symlink_to(self.spool,target_is_directory=True)
        self.assertNotEqual(self.run_native('--stage',self.archives,link).returncode,0)
        link.unlink();link.symlink_to(self.archives,target_is_directory=True)
        self.assertNotEqual(self.run_native('--stage',link,self.spool).returncode,0)
        self.spool.chmod(0o755)
        self.assertNotEqual(self.run_native('--stage',self.archives,self.spool).returncode,0)

    def test_existing_staged_archive_is_never_silently_overwritten(self):
        archive=self.stage();expected=archive.read_bytes()
        archive.write_bytes(expected[:-1]+b'X')
        self.assertNotEqual(self.run_native('--stage',self.archives,self.spool).returncode,0)
        self.assertEqual(archive.read_bytes(),expected[:-1]+b'X')

    def test_real_crypt_upload_readback_and_native_verification(self):
        self.crypto_config();archive=self.stage();before=archive.read_bytes()
        result=self.ship();self.assertEqual(result.returncode,0,result.stderr)
        self.assertEqual(self.status().returncode,0)
        objects=[path for path in self.remote.rglob('*') if path.is_file()]
        self.assertEqual(len(objects),1)
        self.assertNotIn(archive.name,str(objects[0]))
        self.assertTrue(objects[0].read_bytes().startswith(b'RCLONE\0\0'))
        self.assertNotIn(b'Private offsite fixture',objects[0].read_bytes())
        self.assertEqual(archive.read_bytes(),before)
        self.assertFalse((self.spool/'.restore-check.tar').exists())
        self.assertEqual((self.spool/'last-success').stat().st_mode & 0o777,0o600)
        self.assertEqual(self.ship().returncode,0)
        self.assertEqual(len([p for p in self.remote.rglob('*') if p.is_file()]),1)

    def test_failed_or_corrupt_transport_never_publishes_success(self):
        self.stage()
        for action in ['fail','tamper']:
            with self.subTest(action=action):
                result=self.ship(self.fake_transport(action))
                self.assertNotEqual(result.returncode,0)
                self.assertFalse((self.spool/'last-success').exists())
                self.assertNotIn(b'Private offsite fixture',result.stdout+result.stderr)
                self.assertNotEqual(self.status().returncode,0)

    def test_corrupted_real_encrypted_object_never_advances_success(self):
        self.crypto_config();self.stage();self.assertEqual(self.ship().returncode,0)
        before=(self.spool/'last-success').read_bytes()
        path=next(p for p in self.remote.rglob('*') if p.is_file())
        payload=bytearray(path.read_bytes());payload[-1]^=1;path.write_bytes(payload)
        result=self.ship()
        self.assertNotEqual(result.returncode,0,result.stderr)
        self.assertEqual((self.spool/'last-success').read_bytes(),before)

    def test_transport_failure_preserves_last_good_success_record(self):
        self.stage();transport=self.fake_transport('copy')
        self.assertEqual(self.ship(transport).returncode,0)
        before=(self.spool/'last-success').read_bytes()
        self.assertNotEqual(self.ship(self.fake_transport('tamper')).returncode,0)
        self.assertEqual((self.spool/'last-success').read_bytes(),before)

    def test_environment_cannot_disable_crypt_and_transport_has_no_shell(self):
        self.stage();transport=self.fake_transport('copy')
        result=self.ship(transport,env=dict(os.environ,RCLONE_CONFIG_ENCRYPTED_NO_DATA_ENCRYPTION='true'))
        self.assertEqual(result.returncode,0,result.stderr)
        calls=[json.loads(line) for line in (self.root/'calls').read_text().splitlines()]
        self.assertEqual(len(calls),2)
        for call in calls:
            self.assertIsNone(call['override']);self.assertIn('--immutable',call['args'])
            self.assertIn('--ignore-existing',call['args'])
            self.assertIn('--ask-password=false',call['args'])

    def test_plaintext_disabled_encryption_ambiguous_config_and_unsafe_scope_fail_before_transport(self):
        self.stage();transport=self.fake_transport('copy')
        canonical=self.config.read_text()
        invalid=[canonical.replace('crypt','local'), canonical+'no_data_encryption = true\n',
                 canonical+'NO_DATA_ENCRYPTION = true\n', canonical+'filename_encryption = off\n',
                 canonical+'directory_name_encryption = false\n', canonical+'type = crypt\n',
                 canonical+'\n[encrypted]\ntype = local\n',canonical+'\0no_data_encryption = true\n',
                 canonical+'\n[encrypted] # duplicate\ntype = local\n']
        for text in invalid:
            with self.subTest(config=text[:40]):
                self.config.write_text(text)
                self.assertNotEqual(self.ship(transport).returncode,0)
                self.assertFalse((self.root/'calls').exists())
        self.config.write_text(canonical)
        for remote in ['encrypted:','encrypted:other-app','encrypted:asm-todo/../other',
                       ':crypt:asm-todo','encrypted:asm-todo;echo']:
            self.assertNotEqual(self.run_native('--ship',self.spool,self.config,remote,transport).returncode,0)
        self.assertFalse((self.root/'calls').exists())
        self.config.chmod(0o644)
        self.assertNotEqual(self.ship(transport).returncode,0)

    def test_status_requires_both_archive_and_verification_to_be_fresh(self):
        self.stage();self.assertEqual(self.ship(self.fake_transport('copy')).returncode,0)
        record=self.spool/'last-success';before=record.read_bytes()
        old=b'#asm-offsite=1\nverified=1600000000\narchive='+next(self.spool.glob('*.tar')).name.encode()+b'\n'
        variants=[old,before.replace(b'archive=asm-todo-',b'archive=asm-todo-000'),
                  before.replace(b'verified=',b'verified=999999999999999999999'),
                  before+b'extra\n', before+b'\0extra',before.replace(b'#asm-offsite=1',b'#asm-offsite=2')]
        for payload in variants:
            record.write_bytes(payload)
            self.assertNotEqual(self.status().returncode,0)
        fresh_date=str(int(time.time())).encode()
        record.write_bytes(b'#asm-offsite=1\nverified='+fresh_date+b'\narchive=asm-todo-1600000000-0123456789abcdef.tar\n')
        self.assertNotEqual(self.status().returncode,0)
        record.write_bytes(before);self.assertEqual(self.status().returncode,0)
        record.unlink();record.symlink_to(self.root/'outside')
        self.assertNotEqual(self.status().returncode,0)

    def test_binary_is_static_and_stack_is_non_executable(self):
        headers=subprocess.check_output(['readelf','-lW',str(BINARY)],text=True)
        self.assertNotIn('INTERP',headers)
        self.assertNotIn('RWE',next(line for line in headers.splitlines() if 'GNU_STACK' in line))

    def test_encrypted_v5_restore_keeps_newer_revocation_policy(self):
        self.crypto_config()
        from server import Server,BINARY as SERVER
        from test_key_rotation import Rotation
        server=Server();self.addCleanup(server.close);old=server.session()
        self.assertEqual(server.mutate('/add',dict(title='Offsite V5 fixture',due='2031-01-31',repeat='monthly'),cookie=old)[0],303)
        def rotate(cookie):
            code,_,body=server.request('GET','/rotate-key',cookie=cookie);self.assertEqual(code,200)
            fields=dict(Rotation(body).fields,saved='1')
            code,headers,_=server.request('POST','/rotate-key',fields,cookie=cookie);self.assertEqual(code,303)
            return headers['Set-Cookie'].split(';')[0]
        first=rotate(old)
        for path in self.archives.glob('*.tar'):path.unlink()
        subprocess.run([str(BACKUP),str(server.root/'data'),str(self.archives)],check=True,capture_output=True)
        archive=self.stage();self.assertEqual(self.ship().returncode,0)
        second=rotate(first);server.stop()
        retained=server.root/'retained';(server.root/'data').rename(retained);(server.root/'data').mkdir(mode=0o700)
        recovered=self.root/'recovered.tar'
        subprocess.run([RCLONE,'copyto',self.remote_arg+'/'+archive.name,str(recovered),
                        '--config',str(self.config),'--log-level=ERROR'],check=True,capture_output=True,timeout=20)
        subprocess.run([str(BACKUP),'--verify',str(recovered)],check=True,capture_output=True)
        with tarfile.open(recovered) as reader:
            for member in reader.getmembers():
                if member.name=='SHA256SUMS':continue
                path=server.root/'data'/member.name;path.write_bytes(reader.extractfile(member).read());path.chmod(0o600)
        subprocess.run([str(SERVER),'--preserve-key-policy',str(retained)],cwd=server.root,check=True,capture_output=True)
        subprocess.run([str(SERVER),'--check-storage'],cwd=server.root,check=True,capture_output=True)
        server.start()
        self.assertEqual(server.request('GET','/export.json',cookie=first)[0],410)
        code,_,body=server.request('GET','/export.json',cookie=second);self.assertEqual(code,200)
        self.assertEqual(json.loads(body)['tasks'][0]['title'],'Offsite V5 fixture')

from pathlib import Path
import io
import sys
import tarfile
import tempfile
import unittest
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))
from backup import backup, verify


class BackupTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='asm-backup-test-')
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.data = self.root / 'data'
        self.data.mkdir()
        self.dest = self.root / 'backups'
        self.name = 'todos-' + 'a'*32 + '.txt'

    def test_backup_roundtrip_permissions_and_no_lock_files(self):
        (self.data/self.name).write_bytes(b'#next=2\n1|0|1|keep this task\n')
        (self.data/(self.name+'.lock')).write_text('')
        (self.data/(self.name+'.tmp')).write_text('partial')
        path, count = backup(self.data, self.dest)
        self.assertEqual(count, 1)
        self.assertEqual(verify(path), 1)
        self.assertEqual(path.stat().st_mode & 0o777, 0o600)
        self.assertEqual(self.dest.stat().st_mode & 0o777, 0o700)
        with tarfile.open(path) as archive:
            self.assertEqual(archive.extractfile(self.name).read(), (self.data/self.name).read_bytes())
            self.assertEqual(len(archive.getmembers()), 2)

    def test_symlink_refused_without_creating_success_archive(self):
        outside = self.root/'private'
        outside.write_text('private')
        (self.data/self.name).symlink_to(outside)
        with self.assertRaises(OSError):
            backup(self.data, self.dest)
        self.assertEqual(list(self.dest.iterdir()), [])

    def test_verifier_rejects_traversal_and_modified_data(self):
        (self.data/self.name).write_text('original')
        good, _ = backup(self.data, self.dest)
        with tarfile.open(good) as archive:
            manifest = archive.extractfile('manifest.json').read()
        for name in ['../outside', self.name]:
            with self.subTest(name=name):
                bad = self.root/'bad.tar.gz'
                with tarfile.open(bad, 'w:gz') as archive:
                    for member_name, data in [(name, b'changed'), ('manifest.json', manifest)]:
                        member = tarfile.TarInfo(member_name); member.size = len(data)
                        archive.addfile(member, io.BytesIO(data))
                with self.assertRaises(ValueError):
                    verify(bad)

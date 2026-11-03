#!/usr/bin/env python3
"""Legacy .tar.gz snapshots/verification; production backups use native/backup.asm.
Retained for old archives and rollback compatibility. No external upload.
"""
import argparse
from datetime import datetime, timezone, timedelta
import hashlib
import io
import json
import os
from pathlib import Path
import re
import stat
import tarfile
import tempfile

NAME = re.compile(r'todos-[a-f0-9]{32}\.txt\Z')
MAX_SIZE = 262144
MANIFEST_MAX = 16 * 1024 * 1024


def verify(path):
    # Streaming verification bounds memory independently of total task contents.
    actual = {}
    manifest = None
    with tarfile.open(path, 'r|gz') as archive:
        for member in archive:
            if not member.isfile() or not (NAME.fullmatch(member.name) or member.name == 'manifest.json'):
                raise ValueError('Unsafe archive member')
            if member.name == 'manifest.json':
                if manifest is not None or member.size > MANIFEST_MAX:
                    raise ValueError('Invalid backup manifest')
                manifest = json.loads(archive.extractfile(member).read(MANIFEST_MAX + 1))
            else:
                if member.name in actual or member.size > MAX_SIZE or len(actual) >= 100000:
                    raise ValueError('Invalid or duplicate task member')
                data = archive.extractfile(member).read(MAX_SIZE + 1)
                actual[member.name] = hashlib.sha256(data).hexdigest()
    if manifest is None or manifest['version'] != 1 or manifest['files'] != actual:
        raise ValueError('Backup integrity verification failed')
    return len(actual)


def backup(data_dir, destination, retain_days=14):
    if data_dir.is_symlink() or not data_dir.is_dir():
        raise ValueError('Data directory must be a real directory')
    if destination.is_symlink():
        raise ValueError('Backup directory must not be a symlink')
    destination.mkdir(mode=0o700, parents=True, exist_ok=True)
    destination.chmod(0o700)
    now = datetime.now(timezone.utc)
    name = now.strftime('asm-todo-%Y%m%dT%H%M%S%fZ.tar.gz')
    final = destination / name
    manifest = {'version': 1, 'createdAt': now.isoformat(), 'files': {}}
    temporary = None
    try:
        with tempfile.NamedTemporaryFile(dir=destination, prefix='.snapshot-', delete=False) as handle:
            temporary = Path(handle.name)
            with tarfile.open(fileobj=handle, mode='w:gz') as archive:
                for path in sorted(data_dir.iterdir()):
                    if not NAME.fullmatch(path.name):
                        continue
                    # Each production mutation uses rename, so this fd pins one
                    # complete snapshot even if a task changes during backup.
                    fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW)
                    with os.fdopen(fd, 'rb') as source:
                        metadata = os.fstat(source.fileno())
                        if not stat.S_ISREG(metadata.st_mode) or metadata.st_size > MAX_SIZE:
                            raise ValueError('Invalid task data file')
                        data = source.read(MAX_SIZE + 1)
                    if len(data) > MAX_SIZE:
                        raise ValueError('Task data exceeds backup size limit')
                    manifest['files'][path.name] = hashlib.sha256(data).hexdigest()
                    member = tarfile.TarInfo(path.name)
                    member.mode, member.size, member.mtime = 0o600, len(data), int(now.timestamp())
                    archive.addfile(member, io.BytesIO(data))
                data = json.dumps(manifest, sort_keys=True).encode()
                if len(data) > MANIFEST_MAX:
                    raise ValueError('Backup manifest exceeds size limit')
                member = tarfile.TarInfo('manifest.json')
                member.mode, member.size = 0o600, len(data)
                archive.addfile(member, io.BytesIO(data))
            handle.flush()
            os.fsync(handle.fileno())
        verify(temporary)
        os.replace(temporary, final)
        temporary = None
        directory_fd = os.open(destination, os.O_RDONLY | os.O_DIRECTORY)
        try:
            os.fsync(directory_fd)
        finally:
            os.close(directory_fd)
        cutoff = now - timedelta(days=retain_days)
        for old in destination.glob('asm-todo-*.tar.gz'):
            if old != final and not old.is_symlink() and datetime.fromtimestamp(old.stat().st_mtime, timezone.utc) < cutoff:
                old.unlink()
        return final, len(manifest['files'])
    finally:
        if temporary:
            temporary.unlink(missing_ok=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--data-dir', type=Path, default=Path('/var/lib/asm-todo/data'))
    parser.add_argument('--output-dir', type=Path, default=Path('/var/backups/asm-todo'))
    parser.add_argument('--retain-days', type=int, default=14)
    parser.add_argument('--verify', type=Path)
    args = parser.parse_args()
    if args.verify:
        print(f'Backup verified: {verify(args.verify)} workspace files')
    else:
        if args.retain_days < 1:
            parser.error('--retain-days must be positive')
        path, count = backup(args.data_dir, args.output_dir, args.retain_days)
        print(f'Backup created: {path.name}; {count} workspace files')


if __name__ == '__main__':
    main()

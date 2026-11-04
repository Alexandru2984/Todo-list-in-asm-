#!/usr/bin/env python3
"""Deployment-only credential isolation. Never scheduled; never prints secrets."""
import configparser
import os
from pathlib import Path
import re
import stat
import sys


def isolate(source, destination, alias):
    if not re.fullmatch(r'[a-z0-9][a-z0-9_-]{0,62}',alias):
        raise ValueError('Unsupported remote name')
    source, destination = Path(source), Path(destination)
    if source.is_symlink() or not source.is_file() or source.stat().st_nlink != 1 or stat.S_IMODE(source.stat().st_mode) & 0o077:
        raise ValueError('Source configuration must be private and regular')
    config = configparser.RawConfigParser()
    config.read_string(source.read_text())
    crypt = config[alias]
    if (crypt.get('type') != 'crypt' or not crypt.get('password') or
        crypt.get('no_data_encryption','false') != 'false' or
        crypt.get('filename_encryption','standard') != 'standard' or
        crypt.get('directory_name_encryption','true') != 'true'):
        raise ValueError('An encrypted crypt remote with standard names is required')
    base = crypt['remote'].split(':',1)[0]
    if not re.fullmatch(r'[a-z0-9][a-z0-9_-]{0,62}',base) or config[base].get('type') not in ['drive','s3']:
        raise ValueError('Unsupported crypt dependency')
    backend = config[base]
    if backend.get('service_account_file') or backend.get('env_auth','false') != 'false':
        raise ValueError('External credential files/environment credentials need separate deployment')
    selected = configparser.RawConfigParser()
    selected[base] = dict(backend)
    fields = ['type','remote','password','password2','filename_encryption','directory_name_encryption','no_data_encryption']
    if set(crypt)-set(fields)-{'description'}:
        raise ValueError('Advanced crypt settings need explicit compatibility review')
    selected[alias] = {key:crypt[key] for key in fields if key in crypt}
    if destination.exists() or destination.is_symlink():
        if (destination.is_symlink() or not destination.is_file() or destination.stat().st_nlink != 1 or
            destination.stat().st_uid != destination.parent.stat().st_uid or stat.S_IMODE(destination.stat().st_mode) & 0o077):
            raise ValueError('Existing isolated configuration is unsafe')
        current = configparser.RawConfigParser()
        current.read_string(destination.read_text())
        # Preserve any refreshed OAuth token, but never silently change crypt keys.
        if (set(current.sections()) != {base,alias} or dict(current[alias]) != dict(selected[alias]) or
            current[base].get('type') != backend.get('type')):
            raise ValueError('Existing isolated encryption policy differs; review migration manually')
        return
    owner = destination.parent.stat()
    if not owner.st_uid or stat.S_IMODE(owner.st_mode) & 0o077:
        raise ValueError('Destination must have a private non-root service owner')
    fd = os.open(destination,os.O_WRONLY|os.O_CREAT|os.O_EXCL|os.O_NOFOLLOW,0o600)
    try:
        with os.fdopen(fd,'w') as output:
            os.fchown(output.fileno(),owner.st_uid,owner.st_gid)
            selected.write(output);output.flush();os.fsync(output.fileno())
        directory = os.open(destination.parent,os.O_RDONLY|os.O_DIRECTORY|os.O_NOFOLLOW)
        try:os.fsync(directory)
        finally:os.close(directory)
    except BaseException:
        destination.unlink(missing_ok=True)
        raise


if __name__ == '__main__':
    try:
        if len(sys.argv) != 4:raise ValueError('Expected source, destination and crypt alias')
        isolate(*sys.argv[1:])
    except Exception:
        print('Credential isolation failed; source/target policy or private permissions need review.',file=sys.stderr)
        raise SystemExit(1)
    print('Isolated encrypted transport configuration ready; no credentials printed.')

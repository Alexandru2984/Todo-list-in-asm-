# ASM TODO operations

## Production layout

- `asm-canary.service`: binary `/srv/canary/asm.micutu.com/app/bin/server`;
  working directory `/var/lib/asm-todo`; owner/group `asm-todo`.
- Live records: `/var/lib/asm-todo/data`, mode 0700, files 0600.
- Origin: `127.0.0.1:34624` only; nginx terminates TLS for `asm.micutu.com`.
  Existing Cloudflare routing remains managed outside this repository.
- Nginx templates: `deploy/asm.nginx.conf`, `asm-proxy.conf`, `asm-limits.conf`.
- Backup timer: `asm-backup.timer`, daily around 03:17 UTC, local 14-day retention.
- Native private snapshots: `/var/backups/asm-todo/asm-todo-EPOCH-RANDOM.tar`.
- Backup executable: `/srv/canary/asm.micutu.com/app/bin/backup`, raw NASM + syscalls.
- Older `.tar.gz` snapshots remain intact for compatibility.
- Deployment rollback snapshots: `/var/backups/asm-todo/releases/<UTC timestamp>`.

The pre-migration repository `data/` stays untouched as a private historical
copy. It is not live after migration. Do not start a second writer against it
and expect changes to appear on the public site.

## Release

As repository owner, run `make check`, `npm ci --ignore-scripts`, browser install,
`npm run test:ui`, and `npm audit --audit-level=high`. Review the git diff and
commit each completed stage with the repository owner's identity, no coauthors.

Run `sudo ./deploy/apply.sh`. The script verifies the build is current, backs up
the current binary/config, validates nginx, stops only ASM, copies the quiescent
data, migrates to the dedicated identity, atomically replaces the binary and
runs fresh-workspace lifecycle probes locally and over public HTTPS. It then
installs the native backup binary, creates a verified backup and enables the
backup timer. It pauses the ASM backup job/timer during this switch and restores
it on rollback. It never reloads the
Cloudflare tunnel or restarts unrelated applications. Nginx reload is graceful.
The initial migration can briefly interrupt ASM requests; clients should reload.

Before first deployment, test the **exact** service sandbox with temporary
storage and a spare port. This was performed for this release, including full
CRUD under the syscall allowlist. The app needs read/write/open/close/mkdir,
socket/setsockopt/bind/listen/accept, fork/exit, rt_sigaction/alarm, getrandom,
flock/fsync/rename/time, and process entry syscalls allowed by the unit.

## Health and detection

```sh
systemctl status asm-canary.service asm-backup.timer
curl --fail --max-time 5 http://127.0.0.1:34624/healthz
curl --fail --max-time 10 https://asm.micutu.com/healthz
sudo journalctl -u asm-canary.service -u asm-backup.service --since '1 hour ago'
sudo tail -n 50 /var/log/nginx/asm-canary.access.log
sudo systemctl show asm-canary.service -p MemoryCurrent -p TasksCurrent -p NRestarts
df -h /var/lib/asm-todo /var/backups/asm-todo
df -i /var/lib/asm-todo
```

Configure operator alerts for health failure twice over a minute; service/backup
failure; repeated 5xx; sustained 429s; disk free below 15%; inode free below 10%;
and a backup older than 26 hours. These are recommended rules, not a claim that
notification delivery/on-call is configured. Current MTTD is unmeasured.
No task text, cookie headers or recovery keys belong in alert payloads.

Nginx access logging uses `$uri`, not the original request/query/referrer.
Routine nginx error logging is reduced to critical events because error-log
request contexts cannot be formatted/redacted. Critical events and existing
Cloudflare/old logs can still contain legacy URL keys. Protect log access and
retention; rotate historical logs according to the operator's retention policy.
Do not claim that historical or edge copies of keys have been erased.

## Back up and verify

```sh
sudo systemctl start asm-backup.service
sudo journalctl -u asm-backup.service -n 10 --no-pager
sudo ./bin/backup --verify /var/backups/asm-todo/asm-todo-EPOCH-RANDOM.tar
```

Only complete record snapshots enter archives; lock/tmp files are excluded.
The native verifier checks member types/names, safe permissions, duplicates, size
limits, header checksums and SHA-256 manifests without extracting files. It rejects
links, prefixes, nonzero padding, truncation and trailing payloads. Archives are root-private, mode 0600. Native archives are uncompressed USTAR files readable by standard TAR tools;
`SHA256SUMS` is the manifest. Retention removes only old native archive names after
a new verified archive is published. Old `.tar.gz` archives are not deleted by
the native utility; verify those with `sudo python3 tools/backup.py --verify FILE`
and manage their finite retention deliberately. Local backups do not
protect against VPS loss. Configure encrypted off-host copies and a separate
retention policy before promising disaster recovery. Release snapshots are not
automatically pruned; monitor their size and retain/delete deliberately.

Restore drill: verify the archive, unpack it into an isolated private directory,
compare hashes and start a disposable server against that directory. Never test
a restore by overwriting live data. A temporary archive round trip and invalid
archive rejection are also covered in the automated tests.

## Restore live data (operator decision)

Stop ASM, preserve the current data directory as another private snapshot, verify
the selected backup, restore only verified `todos-*.txt` members (exclude `SHA256SUMS`) into a fresh
0700 `/var/lib/asm-todo/data`, set owner `asm-todo:asm-todo` and file mode 0600,
then start ASM and probe health/a fresh test workspace. Preserve the displaced
data for investigation. A restore rolls back user changes after the snapshot.
Do not run extraction against unverified third-party archives.

## Rollback

`apply.sh` restores the old binary/config automatically if a release check fails.
It preserves the new state directory, and during the initial migration carries
forward record snapshots to the original working directory before restarting the
legacy service. The legacy loader skips the `#next` header, so task records stay
readable. A rollback to the old UI requires legacy URL/key access; the old UI
does not understand the new cookie workflow. Prefer a forward fix where possible.

For a later manual rollback, stop ASM, preserve live state, restore the selected
binary and corresponding unit/nginx files from the release directory, verify
nginx, daemon-reload/start ASM and gracefully reload nginx. Match the unit's
working directory and data ownership. Do not automatically restore an old data
snapshot merely because code is rolled back. Always probe the resulting service.

## Incident response

If keys/tasks may be exposed: restrict this vhost at the proxy, preserve private
logs/state/backups, record timestamps and affected workspace counts, and investigate
the service identity and filesystem. There is no per-session revocation endpoint;
capability rekeying requires a reviewed migration and affected-user recovery plan.
If data is corrupt, do not delete or overwrite it to clear a 500. Investigate and
restore a verified copy. If storage returns 507, check disk, inodes, permissions
and temporary-file paths; reload before retrying an ambiguous write.

For this release, the readiness race, exact syscall sandbox, failed snapshot
writes and legacy/new-format compatibility were checked locally. A real rollout also
exercised automatic rollback, and a verified production backup was restored to
isolated storage and probed successfully. A staffed
incident-response exercise and legal notification assessment
have not been performed. Assess applicable obligations with the operator; the repo
does not establish regulatory scope or a notification deadline.

# ASM TODO operations

## Production layout

- `asm-canary.service`: binary `/srv/canary/asm.micutu.com/app/bin/server`;
  working directory `/var/lib/asm-todo`; owner/group `asm-todo`.
- Live records: `/var/lib/asm-todo/data`, mode 0700, files 0600.
- Origin: `127.0.0.1:34624` only; nginx terminates TLS for `asm.micutu.com`.
  Existing Cloudflare routing remains managed outside this repository.
- Nginx templates: `deploy/asm.nginx.conf`, `asm-proxy.conf`, `asm-limits.conf`.
- Backup timer: `asm-backup.timer`, daily around 03:17 UTC, local 14-day retention.
- Optional encrypted transport: asm-offsite.service after local backup success,
  with native five-minute asm-offsite-health.timer. See [setup/recovery](OFFSITE.md).
- Optional [monitoring](MONITORING.md): minute HTTP/HTTPS checks, five-minute
  capacity checks and metadata-only operator notifications behind explicit opt-in.
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

The native monitoring stage implements exact health/capacity checks and private
backup failure/recovery hooks. External delivery stays gated until explicit
operator activation; see MONITORING.md for the test message and acceptance.
Rate/5xx telemetry, independent host-loss detection and staffed on-call coverage
remain separate work. Monitoring does not enforce filesystem quotas.

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
protect against VPS loss. The optional [native/rclone integration](OFFSITE.md)
replicates the latest verified snapshot into the existing crypt remote, downloads
it and checks exact bytes/native integrity. It requires independent secret escrow
and deliberate remote retention. Release snapshots are not
automatically pruned; monitor their size and retain/delete deliberately.

Restore drill: verify the archive, unpack it into an isolated private directory,
compare hashes and start a disposable server against that directory. Never test
a restore by overwriting live data. A temporary archive round trip and invalid
archive rejection are also covered in the automated tests.

## Restore live data (operator decision)

Stop ASM, preserve the current data directory as another private snapshot, verify
the selected backup, restore only verified `todos-*.txt` members (exclude `SHA256SUMS`) into a fresh
0700 `/var/lib/asm-todo/data`, set owner `asm-todo:asm-todo` and file mode 0600.
Keep the service **and backup job/timer stopped**. Before restarting, run the V5
binary from `/var/lib/asm-todo` with `--preserve-key-policy /private/current-copy/data`,
using the retained trusted current data copy, then `--check-storage`. Both commands
must succeed. The merge requires matching source files, keeps the highest key
epoch, refuses conflicting equal epochs and resets restored V5 request receipts.
It preserves the selected older tasks; it does not reconstruct tasks created
after the archive. Preserve those separately and retain all displaced data for
investigation. See [the full restore contract](STORAGE-V5.md).

Then start ASM, resume the backup timer and probe health/a fresh test workspace.
A restore rolls back user changes after the snapshot. If all newer policy copies
are lost, later key revocations cannot be reconstructed from an old archive.
Never silently restore historical authorization policy and claim keys stay revoked.
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
the service identity and filesystem. A workspace owner can use **Rotate recovery
key**, save its candidate and confirm, invalidating every older key/session for
that workspace. An attacker holding the current key can race this same action;
there is no independent account identity or lost-secret recovery. Preserve newer
key policy when restoring task backups; do not rotate real users as a test.
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

## Planner storage preflight

With the service stopped, validate all workspace files without rewriting them:

```sh
sudo -u asm-todo sh -c 'cd /var/lib/asm-todo && /srv/canary/asm.micutu.com/app/bin/server --check-storage'
```

Rotated snapshots are revision 5; unrotated protected writes remain V4 and
V1/V2/V3 remain readable. Never copy a previous binary over live planner
state without comparing --storage-version. The deployment script preserves a
complete private recovery copy and uses the new native --downgrade converter
before an older reader starts. Conversion retains V1 live fields; metadata,
trash/history remain in that private copy. See [the rollback contract](STORAGE-HISTORY.md).
Native backup retention does not prune these operator-managed release copies.

V4 rollback to reader 3 uses --downgrade-v3 after the same offline preflight/private
copy. It preserves metadata/history/metrics while dropping request receipts.
Older readers use the conservative V1 conversion. Never reuse stale browser
forms after rollback/restore; reload and preserve a draft before retrying.

Any V5 workspace blocks **all** older-reader conversions before any snapshot
rewrite, including `--downgrade-v4`. Use a compatible V5 release or forward fix.
Never remove `#key`/`#keyepoch` to force rollback: this would revive revoked keys.

## Admission capacity and listener pressure

New workspace write attempts reserve one of 1,024 identities across exact data/
lock/tmp names. Existing workspaces continue at capacity. GET/HEAD/import preview
create no per-workspace lock file. See ADMISSION.md for bounds and exceptions.
A 503 may mean admission contention/capacity as well as storage trouble; native
forms retain validated drafts. Do not remove stable lock/gate files while the
service is running. Stop ASM, preserve a private complete copy and investigate
orphan reservations before any deliberate cleanup; no automatic expiry exists.

The listener backs off 100 ms after recoverable accept/fork failures. Track
process/FD/memory pressure and connection errors before changing limits. Only
getdents64/nanosleep were added to the service syscall list for this stage.
Protocol-managed live state, daily archives and release snapshots need separate
budgeting; the admission limit does not configure an OS filesystem quota.

# Native verified off-host backup

The existing gdrive-vps-crypt remote encrypts files and names over the configured
Google Drive backend. ASM uses only its dedicated asm-todo subdirectory. No new
cloud account is provisioned. Archive construction/verification and selection,
staging, comparison, status and health are NASM with raw Linux syscalls. Rclone
is the external encryption/transport executable. Python is deployment/test only.

## Contract

1. Local asm-backup.service success triggers asm-offsite.service through an
   optional systemd drop-in. The existing daily backup timer stays intact.
2. A privileged native stage locks the private archive directory and chooses its
   newest canonical snapshot, requiring age below 26 hours. Complete native
   verification precedes atomic staging into a private service-owned directory.
   A corrupt newest archive fails; it never silently falls back to an old one.
3. Unprivileged native transport rejects plaintext/ambiguous configuration,
   disabled encryption, unsafe inodes and public permissions. It revalidates the
   archive and invokes rclone directly, without shell or inherited RCLONE_* env.
4. --ignore-existing prevents replacing existing objects; --immutable is also
   supplied. The object is downloaded afresh, compared byte-for-byte with the
   staged file and checked by the native TAR/SHA-256 verifier. Upload status,
   size, mtime and directory listing alone never prove success.
5. Only then is last-success atomically written/fsynced. Failure/tampering keeps
   the previous receipt. Diagnostics remain in private transport.log; journal
   status contains no task data, workspace IDs or credentials.

Only the latest snapshot is replicated per run. Historical local archives are
not backfilled. Staging retains one current archive plus temporary readback.
There is no remote sync/delete/purge or automatic remote retention. Remote
history grows with completed copies; budget it and set deliberate retention.
Local native retention stays 14 days. Client flags do not establish provider
WORM. See official [crypt](https://rclone.org/crypt/) and
[copy](https://rclone.org/commands/rclone_copy/) documentation.

## Installation and operations

After local/CI validation:

    sudo ./deploy/install-offsite.sh /home/micu/.config/rclone/rclone.conf
    sudo systemctl start asm-backup.service

The installer creates asm-offsite, installs bin/offsite atomically and preserves
units/binary for rollback. A deployment-only helper copies just the crypt section
and its Drive/S3 dependency to /var/lib/asm-offsite/rclone.conf, mode 0600. Other
remotes are excluded. Reinstall preserves refreshed private OAuth tokens and
refuses silent crypt-key changes. The shared config stays unchanged. No website
restart, credential upload or crypt-key rotation is performed.
Unsupported advanced crypt options are rejected rather than silently changing
path/key behavior. Transport is tested with rclone 1.60.1 and the installed 1.75.0;
it avoids version-specific download flags. Interrupted private staging/readback
cache is collected before allocating another copy, including disk-full recovery.

Transport has no capabilities, NoNewPrivileges, a syscall filter, ProtectHome,
ProtectSystem, 256 MiB/32-task limits and a 45-minute deadline. Only native
ExecStartPre=+ reads private source archives and assigns staged-file ownership.
Transport cannot read live tasks/source archives. OAuth refresh updates only its
isolated config. Provider scope is inherited from the existing token: the remote
prefix is not IAM. Shared-provider/crypt compromise may affect other projects.

The monitoring stage's five-minute timer requires both archive and verification timestamps to be
within 93,600 seconds. It checks a receipt, not the provider. A late/absent record
fails the health unit. Worker failures retry after 15 minutes, limited to three
starts in two hours. External alert delivery/on-call remain unconfigured.

    sudo systemctl status asm-backup.timer asm-offsite.service asm-offsite-health.timer
    sudo journalctl -u asm-offsite.service -u asm-offsite-health.service --since '1 day ago'
    sudo -u asm-offsite /srv/canary/asm.micutu.com/app/bin/offsite --status /var/lib/asm-offsite 93600

Detailed errors are in /var/lib/asm-offsite/transport.log, mode 0600, reset per
invocation. Read privately. Never publish configs/tokens/task data/workspace
filenames. Fresh status proves a past readback, not continuous cloud availability
or immunity to later deletion. After a good local backup, starting
asm-offsite.service manually retries replication without restarting the site.

On corruption: retain local archive/log, stop failing retries, identify the
object privately and inspect an independent download. Do not force-overwrite
history, delete unrelated objects or change shared crypt passwords to clear an
error. Restore verified data in isolation and retain the newest V5 policy.
After credential exposure investigate all projects sharing provider/crypt keys.

## Disaster recovery

Keep an independent secure copy of crypt password, salt and provider recovery
information outside this VPS. Obscured rclone.conf values are recoverable
secrets. If the only decryption config is lost with the VPS, encrypted archives
are unusable. This integration never uploads its own decryption config alongside
data and cannot establish whether independent secret escrow already exists.

Reconstruct the crypt remote on a trusted recovery machine, download a selected
archive into a private directory, then run native backup --verify ARCHIVE.
Only after verification extract exact regular todos-*.txt members into fresh
0700 data/, files 0600, excluding SHA256SUMS. Run server --check-storage and start
a disposable server there. Never replace production data for a restore test.

Live recovery must stop writers and follow [V5 policy preservation](STORAGE-V5.md),
keeping the highest trusted available key epoch. Copies retain captured policy,
not later rotations/writes. The nominal recovery point is the latest completed
daily copy; failure extends it. After urgent compromised-key rotation, request a
fresh backup/replication and verify it. If every newer policy copy is lost,
later revocations cannot be reconstructed. Zero loss and exactly-once writes
across arbitrary restores are not claimed.

## Review and acceptance — 2026-11-04

CISO review: principal risks are credential disclosure, false-positive backup
status and old authorization during restore. Dedicated Unix access, minimal
credential copy, no inherited overrides, no-overwrite transport and downloaded
native checks reduce those risks. Existing provider/VPS trust remains. A stolen
token retains existing provider scope; leaked crypt secrets can expose archives.
No vendor/account is added. Monetary ALE, legal scope and external MTTD are
unknown. A staffed incident tabletop, DPA review and recovery from independently
escrowed secrets are unverified. The operational response walkthrough is above.

- [x] 24 focused offsite/config tests, with real local rclone crypt, failed upload,
  tampered ciphertext, stale health and V5 restore retaining newer revocation.
- [x] Exact systemd transport/health sandbox using a disposable Unix identity.
  Transport could not read source archives; tampering did not advance success.
- [x] Final full suite/CI, actual cloud upload, independent remote restore/hash
  checks and unchanged live task-file proof.

Production acceptance: functional commit d962625 passed both jobs in
[Actions 41817846977](https://github.com/Alexandru2984/Todo-list-in-asm-/actions/runs/41817846977):
222 integration tests and 48 browser cases, with no flaky retries. The actual
service uploaded into the existing crypt namespace, downloaded/compared/verified
the archive and reported success. Starting only asm-backup.service then produced
another fresh verified receipt through OnSuccess, without a manual worker start.

An independent provider download matched the source archive SHA-256; independent
TAR extraction/task-file hashes and isolated native storage validation passed.
Live task-file hashes/count, web binary and web process start time were unchanged.
Transport cannot read live/source directories. Isolated configuration contains
only Drive and crypt, remains private, and preserves refreshed tokens; original
configuration ownership remains correct. Both freshness and backup timers are
enabled; worker/health units succeeded. Source archive history remains local,
and remote history starts with this rollout. Private installation rollback copy:
/var/backups/asm-todo/offsite-releases/20261104T144938Z.

Website releases request offsite dispatch asynchronously when installed. A
dispatch rejection is reported separately and cannot roll back a healthy web
release with a verified local backup. Worker/health failures remain visible.

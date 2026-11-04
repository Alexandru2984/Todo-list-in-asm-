# Native workspace admission and overload handling

GET/HEAD pin immutable snapshot file descriptors and do not create workspace
lock files. POST import-preview is also read-only: confirmation reloads/rechecks
under the stable write lock. Snapshot writers never modify a published inode,
so readers keep a complete old/new snapshot without serializing on LOCK_EX.
Manual maintenance and third-party writers must still run with traffic stopped.

A first write attempt reserves one of 1,024 workspace identities. Admission scans
exact todos-ID.txt, .txt.lock and .txt.tmp names, deduplicates IDs in bounded NASM
memory, and creates the stable lock under data/.admission.lock. Orphan locks/temp
files count as reservations. Concurrent admission uses nonblocking flock; busy/
full admission returns 503 while retaining native add/edit/import drafts.

Existing lock files take the normal fast path, and existing data can recreate a
missing lock even at capacity. Existing workspaces stay usable when new admission
is full/busy. Opens reject symlinks, linked aliases and special inodes. No user
workspace, orphan reservation, gate or stable lock is automatically deleted or
expired. Never unlink a live lock/gate to free capacity: that can split locking
between workers. Reconcile reservations offline with a private recovery copy.

## Resource scope

WORKSPACE_MAX in defs.inc sets the bound; changing it requires a reviewed build.
The application has one snapshot, stable lock and optional temp file per admitted
identity, plus fixed gate files. The existing 2 MiB snapshot/member limit therefore
bounds protocol-managed snapshot data to 2 GiB and temp data to another 2 GiB,
with roughly three namespace entries per identity plus fixed files. Filesystem
block/metadata overhead is additional. Existing operator-restored data above the
limit remains readable/writable; new identities are refused.

This is application admission, not a filesystem/user quota. A compromised Unix
identity or root can bypass the protocol. Native backup retention and private
release snapshots have their own storage requirements and do not fit this live-
state budget. Keep host disk/inode alerts and an operator filesystem budget;
daily archives and operator-managed release copies must also be considered.
No promise of automatic expiry, unlimited users or complete disk-DoS prevention
is made. A malicious client may fill the bounded admission pool; per-IP limits,
revocation/cleanup policy and monitoring remain important.

## Listener overload

accept retries EINTR immediately. Recoverable resource errors sleep 100 ms;
invalid listening descriptor/type/state exits for the existing service restart
policy. A failed fork closes only the accepted connection, sleeps 100 ms and
resumes. The listener does not promise a 503 body on that closed connection.
This bounds retry CPU without claiming a worker pool or benchmarked throughput.

The service allowlist adds only getdents64 for admission and nanosleep for
backoff; existing user/filesystem/network/memory/process restrictions remain.
Runtime probes and fault injection use disposable state/spare loopback ports.
Per-child RLIMIT_NOFILE/NPROC tests verify real EMFILE/EAGAIN pressure, paced
rejection, low retry CPU and recovery after restoring only that child's limits.
Root is exempt from Linux RLIMIT_NPROC, so that specific case is skipped as root;
the normal unprivileged CI runner exercises it.

## Verification

Six native admission cases cover read-only inode growth, full capacity, existing
writers at capacity/under a held global mutex, ID deduplication across file types,
nonregular gates/locks, and source-preserving import rejection. Two resource-fault
cases cover listener pressure/recovery. Full pre-release checks passed 177 native
integration tests and 44 desktop/mobile/no-JavaScript/axe browser cases.

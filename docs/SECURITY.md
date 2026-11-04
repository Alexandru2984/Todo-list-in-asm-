# Security model

Each workspace is an anonymous bearer capability with 128 random bits generated
by Linux getrandom. The browser receives it only in an HttpOnly, Secure,
SameSite=Strict cookie. Normal task URLs and HTML omit the key. Rotated keys use
the stable 128-bit ID plus a fresh 128-bit secret. Native rotation atomically
revokes older keys while preserving tasks; save the candidate before confirming
so a lost response can be recovered. Possession of the active key grants full
access: this is not password/passkey authentication and there is no account
recovery. See [the V5 rotation/restore contract](STORAGE-V5.md).

POST requests require exact URL-encoded fields, reject duplicate fields, check
Origin against Host and reject cross-site/sibling-site Fetch Metadata. Browsers
without Origin/Fetch Metadata still rely on SameSite cookies. Command-line
clients can use cookies directly; Origin is a browser CSRF boundary, not a
replacement for session authentication.

HTTP is limited to one request per connection, 4095 header bytes and 4095 total
bytes for ordinary requests, explicit Content-Length for POST, no transfer coding
and no pipelining. Only exact POST /import-preview and /import may raise the total
envelope to 7 MiB, after cookie/origin validation and acquiring a global native
import lock. Their decoded source is capped at 2 MiB. Nginx independently applies
7m only to these two paths and one shared import connection; ordinary routes stay
at 4k. Duplicate fields, controls, malformed percent escapes and decoded NUL fail.
The response buffer is capped at 8 MiB for escaped previews. A child has an
absolute 15-second lifetime plus socket timeouts. Deployment MUST impose a
process/memory cap and request rate limit; the application does not implement a
worker pool. Native admission now bounds protocol-managed workspace identities;
a filesystem/user quota remains an operator control (see ADMISSION.md).

Storage supports 1000 live tasks, 200 retained trash items, one bounded undo state
and 110 UTF-8 bytes per title. Files and native archive members cap at 2 MiB.
Mutations replay records under a per-workspace lock; GET/HEAD/preview pin
immutable snapshot descriptors without allocating persistent locks. Writes create a full snapshot,
check complete writes/fsync/close, rename atomically and sync the data directory.
Corrupt, oversized or unreadable files return an error and are preserved.
The `#next=N` snapshot header preserves monotonically increasing IDs. Legacy
record-only files remain readable. A failed write before rename preserves the
previous snapshot. A failure after rename or loss of the response can be
ambiguous. Protected V4 requests retain successful operation IDs atomically, so
clients can retry the exact original body/pair. Legacy API writes before V4
activation lack this protection. See [the V4 contract](STORAGE-V4.md).

Imports use native bounded JSON/CSV parsers, strict schemas/types/UTF-8, exact
64-bit IDs, paired surrogate decoding and combined parent/dependency cycle checks.
Every source reference is remapped within the imported document. Preview is
read-only; explicit confirmation reparses under the write lock and commits once.
HTML previews escape the source and task fields. CSV formula protection includes
reversible escapeFlags. Imported documents are private workspace data; action
history, undo snapshots and daily metrics are not imported.

Permanent purge clears the undo snapshot and detaches surviving references. It
does not erase existing native archives or operator-managed release snapshots.
Offline native --check-storage validates all live workspaces without writing or
printing their contents/keys, before deployment changes the binary.

No-follow opens resist symlink redirection. Regular-inode and link-count checks
precede reads/truncation; nonblocking opens also reject FIFO traps. The storage directory must remain
private. Production runs under the dedicated `asm-todo` Unix identity, with private state,
a syscall allowlist, loopback-only networking and process/memory caps. Native
admission limits new reservations to 1,024 identities. An operator filesystem
quota/budget is still needed for compromised-identity writes and retained archives. Assembly code has fixed buffers and no memory-safe runtime;
tests reduce risk but cannot establish the absence of memory corruption. The
static binary is not position-independent; the non-executable stack and syscall
sandbox do not replace memory-safety guarantees.

Production requires TLS, query-free access logging, strict-origin referrers, strict CSP, no shared
caching for workspace responses, no task analytics, and an external backup and
monitoring policy. The app returns explicit security headers even without nginx.
See RUNBOOK.md and RELEASE.md for operational details and verification.

`Cache-Control: no-store, no-transform` prevents Cloudflare's automatic HTML
analytics/JavaScript Detection injection on these responses, so the strict CSP
does not need inline exceptions. This does not disable the edge's network-layer
security, rate limits or challenge rules. Existing WAF rules that explicitly
require JavaScript Detection results must be reviewed by the zone operator.
Cloudflare documents this behavior in its [Web Analytics FAQ](https://developers.cloudflare.com/web-analytics/faq/)
and [JavaScript Detections reference](https://developers.cloudflare.com/cloudflare-challenges/challenge-types/javascript-detections/).

The complete task workflow is now server-rendered in NASM: query validation,
Unicode search, merge sorting, counts, progress, edit/confirmation pages and
JSON/CSV downloads. Normal operation does not depend on JavaScript. Server-side
failed-save pages preserve validated drafts as escaped form values.

Scheduled backups also use a static NASM executable, with SHA-256 per-file
integrity, private USTAR archives, checked writes/fsync/no-replace rename and
14-day retention in its own filename namespace. It refuses symlinks, hardlinks,
FIFOs and unsafe archive members. The process disables core dumps and its systemd
unit has a syscall allowlist, no network and only the read-search capability
needed to read private ASM-owned state. Integrity hashes are not signatures or
encryption. The utility verifies its own strict USTAR profile; legacy compressed
archives use the retained compatibility verifier.

Calendar downloads require the same workspace cookie as JSON/CSV and export no
access key. Task data only enters escaped TEXT values; properties are fixed and
lines are folded on UTF-8 character boundaries. Stable event UIDs use the existing
native SHA-256 implementation over a domain-separated workspace/task tuple.
This is a private attachment, not a public capability URL or calendar feed.

Private HTML forms now carry bounded workspace preconditions/operation IDs.
V4 mutations require both fields; stale/different-body key reuse returns 412,
missing fields return 428, and exact recent replays do not write again.

V5 embeds the current credential hash and key epoch in that same snapshot.
Policy is revalidated under the writer lock before receipt handling; undo/import
cannot roll it back. Revoked keys fail private routes and large-import header
admission with 410. An older archive can revive a key unless the documented
offline merge preserves newer policy. Older-reader conversion refuses V5.

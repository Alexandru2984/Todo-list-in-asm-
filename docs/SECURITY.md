# Security model

Each workspace is an anonymous bearer capability with 128 random bits generated
by Linux getrandom. The browser receives it only in an HttpOnly, Secure,
SameSite=Strict cookie. Normal task URLs and HTML omit the key. Possession of a
legacy or recovery key still grants full access: this is not password/passkey
authentication, and there is no key revocation or account recovery yet.

POST requests require exact URL-encoded fields, reject duplicate fields, check
Origin against Host and reject cross-site/sibling-site Fetch Metadata. Browsers
without Origin/Fetch Metadata still rely on SameSite cookies. Command-line
clients can use cookies directly; Origin is a browser CSRF boundary, not a
replacement for session authentication.

HTTP is limited to one request per connection, 4095 total bytes, explicit
Content-Length for POST, no transfer coding, no pipelining. A child has an
absolute 15-second lifetime plus socket timeouts. Deployment MUST impose a
process/memory cap and request rate limit; the application does not implement a
worker pool or a global on-disk quota.

Storage supports 1000 live tasks per workspace and 110 UTF-8 bytes per title.
Records are replayed under a per-workspace lock; writes create a full snapshot,
check complete writes/fsync/close, rename atomically and sync the data directory.
Corrupt, oversized or unreadable files return an error and are preserved.
The `#next=N` snapshot header preserves monotonically increasing IDs. Legacy
record-only files remain readable. A failed write before rename preserves the
previous snapshot. A failure after rename or loss of the response can be
ambiguous: reload before retrying; request idempotency keys are a future feature.

No-follow opens resist symlink redirection. The storage directory must remain
private. Production runs under the dedicated `asm-todo` Unix identity, with private state,
a syscall allowlist, loopback-only networking and process/memory caps. A global
filesystem quota is still required to bound total anonymous workspace growth. Assembly code has fixed buffers and no memory-safe runtime;
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

# Security and product audit — 2026-11-03

Scope: all tracked Assembly sources, build, smoke tests, CI, the ASM systemd
unit, its nginx vhost and public response headers. No scans or load tests were
performed against production. Exploit checks ran in disposable directories.
No private task contents or credentials are recorded here.

## Baseline findings

| ID | Severity | Evidence / impact | Planned remediation |
|---|---|---|---|
| S01 | High | A POST declaring 999 body bytes but ending early returned 303 and persisted a task in an isolated reproduction. Buffer exhaustion also processes partial requests. | Reject incomplete, oversized and ambiguous HTTP framing before routing. |
| S02 | High | `append_todo` never compacts; loader reads only 256 KiB. At 1000 slots new tasks still append and receive success. Log growth can make subsequent changes disappear from loaded state. | Bounded transactional snapshots, explicit capacity and I/O failures. |
| S03 | High | `flock`, writes and rename errors ignored. Compaction can rename a partially written file over valid data; no fsync. | Fail closed on locks, complete writes, sync and atomic replacement. |
| S04 | High | UID is a bearer capability in query parameters, localStorage, hidden forms and normal nginx request logs. No cookie isolation; any holder can mutate the list. | HttpOnly Secure SameSite cookie; no task tokens in normal URLs/forms; retain explicit legacy migration. |
| S05 | Medium | `copy_uid` accepts the first 32 hex characters of a longer token. Reproduced a write with a valid token followed by `extra`. Field matching also finds `uid=` and `title=` inside other keys. | Exact token and form-field parsing; reject duplicate/invalid fields. |
| S06 | Medium | Content-Length matched at arbitrary byte offsets; duplicate CL and Transfer-Encoding not validated. | Line-based bounded parser; reject unsupported transfer codings and duplicate framing. |
| S07 | Medium | 5-second per-read timeout permits indefinite drip feeding; fork count unlimited in code. Production TasksMax=10 mitigates host impact but makes exhaustion easy. | Absolute child deadline; existing process cap plus proxy limits. |
| S08 | Medium | No CSRF origin checks, CSP allows inline scripts/handlers; no clickjacking header at the backend. Public response contains contradictory referrer headers. | Strict same-origin checks on mutations, external assets, restrictive CSP and consistent headers. |
| S09 | Medium | Storage parser scans beyond bytes read; opens follow symlinks. | Terminate and validate bounded records; no-follow opens; private directories. |
| S10 | Medium | Binary has no explicit GNU_STACK policy; build dependencies omit defs.inc. Server silently switches ports if configured port occupied. | Non-executable stack; accurate incremental build; fail fast on port conflict. |
| S11 | Medium | Smoke tests start the server in the repository, delete a fixed UID and may contact another listener if binding fails. | Ephemeral port and directory per suite; process readiness and cleanup. |
| P01 | Product | Completed items cannot be reopened; edit uses prompt; no search, sort, export, empty-state guidance or error UX. | Accessible workspace with recoverable actions and useful client features. |
| P02 | Product | Root immediately redirects browsers to a capability URL. No crawlable marketing page, canonical, sitemap or social metadata. | Public landing page; private workspace noindex; sitemap and robots. |
| P03 | Quality | Only a shell smoke suite; no real browser tests, protocol adversarial checks, restart durability or failure-path tests. | Python integration/security suite and mobile/desktop browser tests in CI. |

Already present: loopback-only local patch (preserved), 0700 data directory,
0600 data files, per-list locks, title HTML escaping, strict systemd filesystem
sandbox, no capabilities, 64 MiB memory cap, 10-task cap, proxy request limiting,
TLS and Cloudflare edge. These reduce exposure but do not repair application bugs.

## Threat model (ciso-review)

Top three: tampering/data loss through malformed requests or failed writes;
information disclosure through leaked bearer tokens; denial of service through
forks, slow clients and disk consumption. Compromise under the current shared
`micu` OS identity could affect other readable services owned by that identity;
systemd restrictions limit this service's writable paths. A dedicated Unix user
and quota are recommended before broader adoption.

There is one task data file at audit time; this is not a count of real people.
Monetary loss, SLA/MTTD and regulatory scope cannot be inferred from the repo.
No invented ALE or compliance certification. Cloudflare and the VPS operator are
existing trust boundaries; no new third-party runtime service is proposed.

Detection targets: service failures, repeated 5xx, disk headroom, memory/process
limits, backup failures and sustained 429s. Runbook and concrete log/health checks
are delivered with the release. Alert delivery and backup off-host retention
remain operator configuration. No claim of incident-response tabletop testing.

Verdict at baseline: **mitigate before shipping the next release**.

## Verification references

- RFC 9112 framing: https://www.rfc-editor.org/rfc/rfc9112.html#section-6.3
- CSP: https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Content-Security-Policy
- Private-page indexing: https://developers.google.com/search/docs/crawling-indexing/block-indexing

See RELEASE.md for the actual fixes, validation and remaining risks.

## Native planner security review — 2026-11-04

The baseline findings above describe the original application, not the current
release. Strict framing/exact fields and sessions address S01/S04/S05/S06/S08;
checked bounded snapshots and regular-inode validation address S02/S03/S09;
absolute deadlines, proxy/process limits, deterministic builds/binding and
isolated tests address S07/S10/S11. Product and quality work is tracked in the
planner plan and release evidence. The service now uses the dedicated asm-todo
identity rather than the baseline shared user.

The planner expands the attack surface through two document parsers, graph
relationships, history and larger import bodies. Review focused on truncation,
integer/UTF-8/surrogate errors, duplicate/unknown fields, reference confusion,
combined cycles, capacity and output bounds, formula/HTML escaping, atomic import
failure and compatible rollback. Mitigations and exact request/resource bounds
are documented in [IMPORT.md](IMPORT.md) and [SECURITY.md](SECURITY.md). Both the
native gate and isolated nginx independently reject concurrent large import
requests while ordinary CRUD remains available. A read-only native storage
preflight runs before deployment replaces binaries.

Local verification passed 140 native/protocol/proxy/SEO tests. The actual service
sandbox passed the expanded fresh-workspace probe, and independently extracted
native backups preserved planner metadata through a sandboxed restart. Production
and remote CI verification also passed; evidence is recorded in RELEASE.md. These checks
do not establish memory safety or absence of vulnerabilities: the NASM binary
remains non-PIE, bearer-key access has no revocation, aggregate anonymous disk
usage lacks a quota, and off-host encrypted backups/external alerts still require
operator configuration. No production fuzzing or load test was performed.

# Reliability and security delivery plan — 2026-11-04

This plan incorporates the supplied external review. Findings are treated as
hypotheses/priorities until checked, not as proof of an exploit. Existing historical
fixes in AUDIT.md are not reported again as current vulnerabilities. Production
logic stays in NASM; tests/fault injection/benchmarks use disposable state/ports.
Every completed stage receives a separate owner-attributed commit.

## Current work

- [x] Storage V4: monotonic revision, workspace-scoped state precondition, random
  operation IDs, 16 persisted successful receipts, atomic apply/replay and native
  draft-preserving conflict pages. GET leaves V1/V2/V3 files unchanged.
- [x] Compatibility: native V4 validation, verified archive/receipt restoration,
  full preflight, V4-to-V3 downgrade preserving metadata/history, and V1 fallback.
- [x] Abuse/overload: remove persistent read-only lock creation, enforce bounded
  admission for new workspaces, keep stable write locks, and back off on accept/
  fork resource failures. Do not expire/delete user workspaces automatically.
- [x] Release: full native/browser/no-JavaScript/axe checks, actual green CI,
  exact service sandbox, older-reader drill, scoped production rollout and
  fresh-workspace HTTPS/hash/backup verification.

## Review-driven next stages

1. Recovery-key rotation/revocation: delivered by the subsequent native V5 stage;
   see [its completed contract and checks](KEY-ROTATION-PLAN.md) and
   [restore/rollback semantics](STORAGE-V5.md). Cookie-only logout stays separate.
2. Operational resilience: verify the actual trusted proxy/IP chain, real alert
   delivery, off-host encrypted copies and complete-VPS/single-workspace restore.
   Reuse an existing destination if available; do not invent credentials/vendors.
3. Continuous parser fuzzing and instrumented isolated fault/overload tests;
   evaluate a PIE conversion with relocation checks rather than claiming memory
   safety from tests. Keep NASM and independently verify the resulting binary.
4. Benchmarks: 0/100/1000 tasks, 1/8/24 clients, reads/mixed/writes; measure p50/
   p95/p99, throughput, CPU/RSS/I/O/errors and fsync under production restrictions.
   Choose worker-pool/shared-read-lock changes from measurements.
5. Product: separate descriptions/notes, atomic bulk actions, saved views,
   templates, manual order/archive, RO/EN and deliberate timezone semantics.
6. Growth/release: disposable demo, versioned public assets with scoped caching,
   reproducible release artifacts/checksums, changelog/install/security-reporting
   documentation and a privacy policy matching actual retention.
7. Later: separate revocable read-only calendar capability, reminders, PWA/cache;
   offline writes only after explicit sync/conflict semantics. Passkeys/sharing
   need their own authorization model.

The accept loop's unconditional retry after errors and lock-file creation on
GET were confirmed in source. Their exploitation severity depends on deployment
limits; no remote code execution, SQL injection or exploitable overflow is
claimed. Non-PIE/manual buffers, local-only backups and absent external alerts
remain limitations. Revocation was subsequently addressed by the V5 stage.

## CISO review

Top threats: lost/duplicated logical writes (tampering), stale/reused keys or
leaked capabilities (disclosure), anonymous disk/inode/process exhaustion (DoS).
Scope is the private ASM state writable by asm-todo, not unrelated VPS services.
Affected people, monetary ALE, regulatory scope and current MTTD are unknown;
no figures or notification obligations are inferred from a task-file count.

Existing incident-response/backup/rollback instructions are in RUNBOOK.md. The
technical exercise covers two writers, lost reply, restart, corrupt receipt,
pre-rename failure, archive restore and old-reader conversion. This is not a
staffed incident-response tabletop. Detection targets remain 5xx/429/restarts,
space/inodes and delayed backup; external delivery/on-call must be verified.
No new vendor/data processor is introduced by this native change. Existing
Cloudflare/VPS trust boundaries remain. Verdict: mitigate then release after
checks; unresolved operator controls remain explicit, not certified as complete.

The local ciso-review skill's optional advisor scripts are not present in this
installation, so the review is recorded directly rather than fabricating scores.

## Evidence before rollout

The complete existing suite plus initial guard cases passed 166 integration
checks. The expanded focused guard suite passed all 18 cases, including lost
reply/restart, concurrent writers, bounded receipts, maximal escaped HTML,
revision exhaustion, native backup restore and both downgrade targets. Six new
browser cases passed across desktop/mobile, without JavaScript and with light/
dark axe checks. Final full counts and production evidence follow at release.

Abuse/overload stage: six admission cases and two real resource-limit fault cases
passed; full local integration count is now 177 and the complete browser suite
passed 44 cases. GET/HEAD/preview no longer allocate per-workspace lock inodes.
New write admission reserves at most 1,024 identities without expiring user data.
The exact service sandbox and native archive restore passed, and the actual
previous production V3 binary read converted V4 fixtures with metadata intact.

Proxy verification: existing trusted Cloudflare/loopback configuration matches
the published [IPv4](https://www.cloudflare.com/ips-v4/) and
[IPv6](https://www.cloudflare.com/ips-v6/) ranges. A fresh public unauthenticated
probe matched nginx's logged source against the Cloudflare trace source; a
separate spoofed CF-Connecting-IP request received 403. No IP addresses/task data
were recorded here and no shared VPS proxy configuration was changed. This is a
concrete path check, not a claim that external alert delivery is configured.

## Final release evidence

Functional commit 761f3af passed GitHub Actions 41760455940: 177 integration tests
and all 44 browser cases. Both native binaries remain static NASM/raw syscalls;
optional browser JavaScript remains 75 lines. No runtime dependency was added.

The exact systemd sandbox passed native V4/protocol/admission probes and a verified
archive restore. The actual prior production V3 reader successfully read converted
V4 fixture data with recurrence/project/tag/priority metadata preserved.

Production rollout succeeded with private rollback snapshot
/var/backups/asm-todo/releases/20261104T022733Z. Direct and public HTTPS probes
passed V4 replay/different-body rejection plus all existing planner/import/calendar
flows. Public Pixel 5 Chromium with JavaScript disabled passed exact retry,
two-tab conflict, preserved/reviewed draft, monotonic revision, 428 enforcement
and responsive widths. Original task-file hashes and workspace count matched the
private baseline after probe cleanup. The actual backup service completed and
its latest archive passed independent extraction/hash comparison plus native
validation in isolated storage. Service/timer remain active; deployed binary
matches the verified build, with NoNewPrivileges and seccomp active.

The supplied review is incorporated in the next-stage list above. Recovery-key
rotation/revocation was subsequently delivered in [the V5 stage](STORAGE-V5.md).
Off-host destination/alert delivery, filesystem-level quota, continuous fuzzing,
PIE research and benchmarks remain separate work; this release does not claim
those controls or a certified/fully finished 1.0 security posture.

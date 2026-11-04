# Native planner release verification — 2026-11-04

The release is live at https://asm.micutu.com/. Task requests, imports, queries,
calendar/board rendering, SVG statistics, storage maintenance and scheduled
backups run in static x86_64 NASM binaries linked with ld and raw Linux syscalls.
HTML/CSS present the results. Optional browser JavaScript remains 75 lines; no
framework, interpreter or database runtime was added.

## Delivered

- Storage V5 supports native recovery-key rotation/revocation without moving
  workspace data. Save the inactive candidate before confirmation; a lost reply
  can be recovered using that complete key without another mutation. Native
  offline restore retains the highest available key epoch, and every older-reader
  conversion refuses V5 before snapshot rewrites. See STORAGE-V5.md.
- Storage V4 adds monotonic workspace revisions, scoped state preconditions and
  16 atomically persisted successful request receipts. Exact retries do not write
  twice; stale/different-body reuse returns 412 with preserved native drafts.
  V4 clients must supply the write pair (428 otherwise); GET /state.json provides
  the private protocol. V1/V2/V3 reads stay byte-unchanged.
- New native admission reserves up to 1,024 workspace identities; read-only
  GET/HEAD/import-preview allocate no per-workspace locks. Existing writers keep
  working at capacity; no user data/lock reservations are automatically expired.
- Listener resource failures back off 100 ms and recover after pressure clears.
  The service adds only getdents64/nanosleep to its existing syscall restrictions.
- V4-to-V3 rollback preserves task metadata/history/metrics; the native V1 fallback
  and all-file preflight remain available. See STORAGE-V4.md and ADMISSION.md.

- Quick capture accepts one literal title per line, validates/ previews the
  complete batch and appends atomically with fresh IDs/current timestamps and
  one undo step. Empty lines are ignored; UTF-8/title/capacity bounds are enforced.
- Private .ics downloads export dated live tasks as one-day non-blocking calendar
  reminders, with escaped/folded UTF-8 text and stable SHA-256 event identifiers.
  The attachment contains no bearer key and exports existing occurrences only.

- Priorities, strict UTC due dates, Today/Next 7 days/Overdue views and native sorts.
- Daily/weekday/weekly/monthly/yearly recurrence with retained month/leap anchors.
- Projects/tags, subtasks, prerequisites, combined cycle validation and blocked tasks.
- Persistent workspace undo/redo, subtree trash/restore/purge and recent actions.
- Bounded structured AND search with Unicode matching and metadata/date operators.
- Native month calendar, To do/In progress/Done board and private SVG activity with
  7/30-day completion counts and UTC streaks.
- Native JSON v1/v2 and CSV preview/merge/replace import, exact 64-bit ID remapping,
  strict schemas, spreadsheet escaping, metadata/trash round trips and atomic undo.
- Revision 3 storage reads V1/V2 without GET rewrites, validates regular inodes,
  preserves checked atomic snapshots and offers native --check-storage/downgrade.
- Responsive mobile board/forms, 44 px completion controls, empty-chart guidance,
  light/dark themes and complete essential workflows without JavaScript.
- Public descriptions/FAQ reflect the shipped features. Public CSS/JS are crawlable;
  private application routes remain excluded. See [SEO policy](SEO.md).

## Security and boundaries

The original audit fixes remain active: strict request framing/exact fields,
HttpOnly Secure SameSite capability sessions, origin checks, escaped output,
strict CSP, bounded child lifetimes, loopback binding and checked synced storage.
The dedicated asm-todo service runs with no capabilities, NoNewPrivileges,
seccomp syscall filtering, read-only filesystem restrictions and a non-executable
stack. The binary remains non-PIE and is not a memory-safe runtime.

Ordinary requests and every header block cap at 4095 bytes. Only the two exact,
authenticated import POST paths admit a 7 MiB envelope with a 2 MiB decoded cap.
Nginx and a regular-file native flock independently serialize large imports.
Ordinary CRUD remains available while an import slot is occupied. The response
cap is 8 MiB for escaped previews; normal full-workspace rendering stays below
4 MiB. Storage/native archive members cap at 2 MiB. Service limits are 256 MiB
memory, a 160 MiB high watermark and 32 tasks; the proxy permits 24 connections.
See [the import contract](IMPORT.md) and [security model](SECURITY.md).

## Verification

- **198 local integration tests passed**: key rotation/revocation/restore,
  protocol, storage/revisions, recurrence,
  metadata/relationships, history, query/layout/statistics, exports/imports, native
  backup/legacy archive compatibility, deployment probes, real isolated nginx
  policy and public crawler resources. JavaScript syntax and patch checks passed.
- **48 browser tests passed** on desktop and Pixel 5 emulation, including key
  preparation/download, revoked-session recovery and native
  no-JavaScript workflows, import preview/merge/replace/undo, layout checks at
  320/390/768/1440 px and automated axe WCAG A/AA checks in light/dark themes.
  Automated axe results are not an accessibility certification.
- Boundary/adversarial cases include 1,200 live/trash records, exact 2 MiB decoded
  sources, form encoding near 6 MiB, escaped previews above 4 MiB, malformed
  JSON/CSV, overflow, Unicode/surrogates, formula text, source-reference isolation,
  combined cycles, capacity/write failures and concurrent import rejection.
- Development dependency audit reported zero known vulnerabilities.
- Actual GitHub Actions [run 41760455940](https://github.com/Alexandru2984/Todo-list-in-asm-/actions/runs/41760455940)
  passed both security-and-storage (**177 tests**) and browser-and-accessibility
  (**44 tests**) for functional release commit **761f3af**. Earlier per-stage
  commits also have successful runs. The original dark-theme CI contrast failure
  was repaired without disabling axe checks.
- V5 functional commit **3066086** passed both jobs in
  [run 41810661682](https://github.com/Alexandru2984/Todo-list-in-asm-/actions/runs/41810661682):
  **198 native tests**, **47 browser cases on first attempt and one existing
  desktop conflict case on retry**. All four new rotation browser cases passed
  first attempt. The follow-up harness waits explicitly for edit/commit/conflict
  transitions and fails CI on any flaky retry; see current main workflow results.
  The original timeout did not reproduce in 12 local desktop repeats. After
  strengthening synchronization/assertions, both conflict flows passed 16 local
  desktop/mobile executions with CI retry-failure enforcement enabled.
- The exact production service sandbox passed a fresh-workspace rehearsal on a
  spare loopback port. NoNewPrivileges and seccomp were active. An independently
  extracted native archive retained planner metadata/workflow state through a
  sandboxed restore/restart. An isolated V3-to-V1 drill also ran the actual prior
  production binary over converted fixtures.

## Production verification

- V5 rollout succeeded with private rollback snapshot
  `/var/backups/asm-todo/releases/20261104T095738Z`. Both direct and public HTTPS
  probes passed key preparation/download, atomic rotation, revoked-key rejection,
  exact lost-response recovery without a second revision, and all prior planner
  workflows. Only each probe's fresh stable workspace ID was removed.
- Public Pixel 5 Chromium with JavaScript disabled passed saving the candidate
  before confirmation, secure rotated cookie, revocation in another browser,
  forgetting that inactive session, full 64-character recovery, private HTML and
  responsive widths 320/390/768/1440. No existing user's key was rotated.
- V5 post-release verification confirmed unchanged original task-file SHA-256
  hashes/workspace count, an actual successful backup service run, native archive
  verification, independent extraction/hash comparison and isolated native
  validation. The deployed binary matches the tested build; service/timer remain
  active, NoNewPrivileges/seccomp enabled, with zero service restarts recorded.
- An exact-unit rehearsal additionally retained a second rotation's policy over
  a first-rotation archive, then rejected its revoked key after sandbox restart.
  All three old-reader downgrade modes refused V5 without modifying snapshots.
  The actual previous V4 production reader also accepted an unchanged V4 fixture.
- deploy/apply.sh created a private binary/config/data rollback snapshot at
  /var/backups/asm-todo/releases/20261104T022733Z, stopped ASM traffic, validated
  existing storage without rewriting tasks, atomically installed the binaries,
  then passed direct and public HTTPS fresh-workspace probes.
- Those probes covered native CRUD, structured search, recurrence/anchors,
  board/calendar, private SVG, large import preview/confirmation/undo, trash/purge,
  quick capture/undo, private .ics snapshots, download correctness, session/CSP/noindex/no-transform policy and absence of
  unexpected edge script injection. Every probe removed only its own fresh UID.
- Public HTTPS Chromium with JavaScript disabled additionally passed the mobile
  planner/board/calendar workflow, completion statistics and responsive widths
  from 320 to 1440 px. The productivity increment additionally passed public
  mobile capture/atomic undo/redo, date editing and the actual calendar download.
  V4 additionally passed an exact retry, two-tab conflict, preserved/reviewed draft,
  monotonic revision and missing-precondition rejection on public mobile Chromium
  without JavaScript. Temporary workspaces were removed after inspection.
- Original production task-file SHA-256 hashes and workspace count matched the
  private pre-release baseline after all probe cleanup. No existing workspace
  was used for test mutations.
- The actual asm-backup.service completed successfully under its sandbox. The
  latest native production archive passed native verification, independent TAR
  extraction/hash comparison and native storage validation in isolated storage.
- asm-canary.service is active as asm-todo; the deployed binary matches the tested
  build, with NoNewPrivileges and seccomp active. asm-backup.timer is enabled and
  active. Nginx syntax validation passed and only the ASM vhost/snippet/limits
  were updated before graceful reload; tunnel settings and unrelated services
  were not changed.
- Rollback compares reader revisions before restoring an older binary. Cross-
  revision rollback first preserves planner state and converts with the new
  native binary (V3 conversion retains planner metadata/history). A failed conversion restores the compatible copy; a failed
  recovery copy leaves the service stopped. See [storage history](STORAGE-HISTORY.md).
- Each completed stage uses the existing repository owner's commit identity,
  without assistant credits or coauthor trailers.

## Remaining limits

Anonymous bearer keys are not accounts. Rotation revokes every older key for one
workspace; there is no independent device-session management or account recovery.
Native admission bounds protocol-managed reservations to 1,024 workspaces; no
OS filesystem/user quota or automatic expiry is configured. The optional
[encrypted off-host pipeline](OFFSITE.md) now implements verified replication;
independent secret escrow, remote retention and external alert delivery remain
operator responsibilities. Local archives alone do not protect against VPS loss. Purge does not erase retained
archives or operator-managed release/recovery snapshots.

Protected V4 requests have a bounded 16-receipt retry window, committed with task
state. Reuse the exact original body/pair after a lost response. Restoring an older
archive alone also restores its receipt window; the documented V5 policy merge
clears restored receipts and advances revision. No indefinite/cross-restore exactly-once
guarantee is claimed. Legacy clients before V4 activation lack these protections. Unicode matching uses the documented
simple folds rather than full normalization/collation, and dates use UTC. The
native parser/crypto implementations have independent format/hash oracles and
adversarial tests, without formal memory-safety or security certification. Backup
SHA-256 provides integrity, not encryption or authentication. Offline queues,
passkeys, sharing, localization and bulk selection remain roadmap proposals.

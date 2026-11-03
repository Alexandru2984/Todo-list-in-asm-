# Native planner release verification — 2026-11-04

The release is live at https://asm.micutu.com/. Task requests, imports, queries,
calendar/board rendering, SVG statistics, storage maintenance and scheduled
backups run in static x86_64 NASM binaries linked with ld and raw Linux syscalls.
HTML/CSS present the results. Optional browser JavaScript remains 75 lines; no
framework, interpreter or database runtime was added.

## Delivered

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

- **151 local integration tests passed**: protocol, storage/revisions, recurrence,
  metadata/relationships, history, query/layout/statistics, exports/imports, native
  backup/legacy archive compatibility, deployment probes, real isolated nginx
  policy and public crawler resources. JavaScript syntax and patch checks passed.
- **38 browser tests passed** on desktop and Pixel 5 emulation, including native
  no-JavaScript workflows, import preview/merge/replace/undo, layout checks at
  320/390/768/1440 px and automated axe WCAG A/AA checks in light/dark themes.
  Automated axe results are not an accessibility certification.
- Boundary/adversarial cases include 1,200 live/trash records, exact 2 MiB decoded
  sources, form encoding near 6 MiB, escaped previews above 4 MiB, malformed
  JSON/CSV, overflow, Unicode/surrogates, formula text, source-reference isolation,
  combined cycles, capacity/write failures and concurrent import rejection.
- Development dependency audit reported zero known vulnerabilities.
- Actual GitHub Actions [run 41740662580](https://github.com/Alexandru2984/Todo-list-in-asm-/actions/runs/41740662580)
  passed both security-and-storage (**151 tests**) and browser-and-accessibility
  (**38 tests**) for functional release commit **9b50cee**. Earlier per-stage
  commits also have successful runs. The original dark-theme CI contrast failure
  was repaired without disabling axe checks.
- The exact production service sandbox passed a fresh-workspace rehearsal on a
  spare loopback port. NoNewPrivileges and seccomp were active. An independently
  extracted native archive retained planner metadata/workflow state through a
  sandboxed restore/restart. An isolated V3-to-V1 drill also ran the actual prior
  production binary over converted fixtures.

## Production verification

- deploy/apply.sh created a private binary/config/data rollback snapshot at
  /var/backups/asm-todo/releases/20261103T234023Z, stopped ASM traffic, validated
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
  Temporary workspaces were removed after inspection.
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
  native binary. A failed conversion restores the compatible copy; a failed
  recovery copy leaves the service stopped. See [storage history](STORAGE-HISTORY.md).
- Each completed stage uses the existing repository owner's commit identity,
  without assistant credits or coauthor trailers.

## Remaining limits

Anonymous bearer keys are not accounts and have no server-side revocation or
account recovery. Aggregate anonymous disk growth has no global quota. Off-host
encrypted backups and external alert delivery remain operator configuration;
local archives do not protect against VPS loss. Purge does not erase retained
archives or operator-managed release/recovery snapshots.

There is no request idempotency key: a lost response or failure after rename can
be ambiguous, so reload before retrying. Unicode matching uses the documented
simple folds rather than full normalization/collation, and dates use UTC. The
native parser/crypto implementations have independent format/hash oracles and
adversarial tests, without formal memory-safety or security certification. Backup
SHA-256 provides integrity, not encryption or authentication. Offline queues,
passkeys, sharing, localization and bulk selection remain roadmap proposals.

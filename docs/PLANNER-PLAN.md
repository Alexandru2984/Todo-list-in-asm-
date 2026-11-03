# Native planner implementation plan — 2026-11-03

All production task, import, query, calendar, statistics and backup logic stays in
x86_64 NASM with raw Linux syscalls. HTML/CSS present server results; essential
flows must remain usable with JavaScript disabled. Existing private user files
are never test fixtures. Each completed stage receives a separate owner-attributed
commit without assistant/coauthor credits.

## Delivery stages and acceptance

- [x] CI: inspect actual GitHub failures with gh, repair the root cause, push a
  concrete tested fix and observe a successful remote run. Keep axe checks active.
- [x] V2 storage: read legacy records unchanged, version new snapshots, preserve
  native backup compatibility, add a native downgrade command and test rollback.
- [x] Priorities/dates: low/normal/high/urgent, strict ISO dates, Today/Upcoming/
  Overdue views, priority/due sorts, completion timestamps and native forms.
- [x] Recurrence: daily/weekdays/weekly/monthly/yearly, calendar arithmetic,
  clipped month/year dates with a retained anchor, no duplicate next occurrence
  on repeated completion; capacity failures must leave the original unchanged.
- [x] Projects/tags: bounded UTF-8 values, editable on native forms, exact folded
  filtering and preserved JSON/CSV exports. No separate runtime/database.
- [x] Subtasks/dependencies: parent links plus up to eight prerequisite IDs,
  combined cycle detection, blocked-task view, completion checks, useful native
  property forms. No dangling references after permanent purge.
- [x] Undo/trash/activity: soft delete/restore, latest 200 trash items, one atomic
  workspace-wide undo/redo snapshot (also covers bulk/recurrence/import), last 20
  activity events. Permanent purge clears undo content for the purged action.
- [x] Import: native bounded JSON v1/v2 and CSV parsers, validated preview,
  merge/replace confirmation, reference remapping, atomic apply and undo.
- [x] Search: structured AND operators for priority/status/due/project/tag and
  free text; strict operator/date validation; reuse the native Unicode matcher.
- [x] Calendar/board/insights: native month navigation/day counts, native workflow
  movement, a private SVG chart with UTC daily completion buckets and streaks.
- [x] Release: local protocol/storage/migration/backup tests, browser/mobile/
  no-JavaScript/axe tests, remote GitHub Actions green, sandboxed production
  rollout, fresh-workspace HTTPS probes and a verified isolated restore drill.

## Storage contract

A task's original first 128 bytes remain recognizable to existing modules while
its in-memory stride grows to 512 bytes. Metadata includes priority, due date,
completion time, parent, recurrence/anchor, project, tags, up to eight dependency
IDs, workflow stage, deletion time and previous completion state. There are at
most 1000 live tasks and 200 retained trash entries.

New snapshots use an explicit revision 3 header, V2 current-task records, a bounded previous
workspace snapshot, activity records and UTC metric buckets. A file remains the
atomic transaction boundary: checked full writes, fsync, rename and directory
fsync under a stable per-workspace flock. Legacy V1 files remain readable and are
not rewritten by GET requests. Mutation writes revision 3; corrupt files fail closed.

A native `--downgrade` maintenance command validates all files before writing V1
live records. Deployment rollback preserves the V2 state first and invokes the
new binary's converter before returning to the older binary. Converter failures
must not start an incompatible older reader over partially converted data.

Storage/backup/request/render caps must be updated together and remain explicit.
Import payloads have an independent decoded-size cap, strict duplicate-field
checks and a single global proxy import slot. Ordinary requests retain their
small limit; large import bodies do not relax header validation. Resource caps
are adjusted only with bounded-buffer accounting and sandbox checks.

## Feature semantics

Dates and charts use UTC, matching the existing native calendar. Recurrence
creates the next active task when a task is completed and skips missed dates;
monthly/yearly anchors survive short months and leap years. Completing an already
done task is idempotent. Dependencies and unfinished children block completion.

Undo/redo swaps the last whole-workspace state, retains monotonic IDs and commits
atomically. Permanent purge removes relevant references and clears undo; backup
retention still applies. Legacy completed tasks have no invented completion time.

JSON V2 preserves new metadata and trash separately while keeping live `tasks`
compatible in meaning with V1. CSV includes reversible spreadsheet-escape flags.
Import is explicitly confirmed after preview and is independently revalidated
under the write lock. Merge assigns/remaps new IDs; replace is reversible by undo.

## Security review and remaining limits

Primary risks are malformed import data, reference cycles, silent migration loss,
and resource exhaustion. Mitigations are strict bounded parsers, one transaction
per file, capacity checks, graph validation, parser adversarial cases, independent
format oracles and verified downgrade/backup drills. No new vendor is introduced.

Existing IR/backup runbooks remain applicable. Off-host copies, global disk quotas
and external alert delivery remain operator work; no monetary/regulatory impact
or compliance guarantee is inferred from this repository.

## Verified checkpoints

- CI contrast fix: GitHub Actions run 41716185000 passed both jobs.
- V2 foundation: protocol/storage/view/export suite passed; native backup suite
  passed including the 2 MiB boundary; all 16 desktop/mobile/no-JavaScript/axe
  browser cases passed. Offline downgrade and corruption preflight use isolated
  workspaces. Production rollout remains the final delivery stage.

- Priority/date stage: 78 native/protocol tests passed. Existing 16 browser cases
  passed; the corrected planner and expanded axe cases passed on desktop/mobile.
  155 independent Gregorian dates matched native parsing, including leap-century
  boundaries. JSON V2/extended CSV preserve metadata and bounded trash.

- Recurrence stage: 84 native/protocol tests passed; native planner and expanded
  axe browser cases passed on desktop/mobile. Independent recurrence oracles
  covered 180 mixed schedules, clipped month/leap anchors and atomic failures.

- Projects/tag stage: 89 native/protocol tests passed, plus desktop/mobile native
  planner and axe cases. Folded exact filtering, canonical tag bounds, preserved
  links and worst-case escaped rendering have independent assertions.

- Relationship stage: 96 native/protocol tests passed; six focused browser cases
  passed across desktop/mobile, including no-JavaScript prerequisites and axe.
  Mixed cycles, atomic rejection, subtree deletion, large IDs and worst-case
  graph/escaped rendering are covered.

- History/trash stage: 106 native/protocol tests passed; eight focused browser
  cases passed on desktop/mobile. Verified native archive restoration preserves
  metadata and undo; V3 downgrade also passed an isolated drill using the actual
  previous production binary. Reader revision comparison covers rollback across
  V1/V2/V3, including an unsuccessful service-start attempt.

- Structured search stage: 111 native/protocol tests passed, including 180 seeded
  adversarial queries; native planner and axe cases passed on desktop/mobile.
  AND predicates, phrases, Unicode, trash, bounded parsing and read-only failure
  behavior are verified. Search permits 255 UTF-8 bytes and paths up to 2047
  bytes within the unchanged 4095-byte ordinary request envelope.

- Calendar/board/insights stage: 117 native/protocol tests passed. All previous
  browser cases passed, and the corrected calendar workflow plus four new
  layout-specific light/dark axe cases passed on desktop/mobile. Native month
  grids, day counts, workflow/undo redirects, chart privacy and UTC buckets have
  independent parsers/oracles. Large imports and final production release remain.

- Import stage: 140 native/protocol/proxy/SEO checks passed. JSON/CSV round trips,
  malformed/duplicate fields, UTF-8/surrogates, formula escaping, graph references,
  capacity, atomic failures and adversarial inputs are covered. Exact 2 MiB decoded
  sources, 1,200 records and previews exceeding 4 MiB passed. Large requests have
  a 7 MiB wire envelope, unchanged 4095-byte headers, a single global import slot
  in nginx and the native service, and an 8 MiB response buffer. Ordinary requests
  keep their 4095-byte envelope. The prior full browser run passed all 32 cases.

- Final release: GitHub Actions 41737981261 passed both jobs with 140 integration
  tests and 32 browser cases; local final runs matched. Exact systemd sandbox,
  native V3 backup/restore and actual older-reader downgrade drills passed.
  Production direct/HTTPS probes and a public mobile browser without JavaScript
  passed. Existing task-file hashes/count matched the private baseline, and the
  actual scheduled backup service/archive passed independent restore validation.
  The deployed binary matches the tested build; timer and service are active.
  Full evidence and remaining operator limits are recorded in RELEASE.md.

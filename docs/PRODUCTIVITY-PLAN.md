# Next product iteration — 2026-11-04

Keep task/storage/import/calendar/backup logic in NASM x86_64 and raw Linux
syscalls. HTML/CSS present native results; essential flows work without JavaScript.
Each completed stage has an owner-attributed commit without coauthor credits.
Tests use disposable storage and spare ports, never existing production sessions.

## Current delivery

- [x] Quick capture: one literal title per LF/CRLF line; ignore blank lines and
  trim outer ASCII spaces/tabs. Validate the complete batch, preview, then append
  atomically with fresh IDs, current creation timestamps and one undo step.
  Preserve existing tasks; do not offer replace for this capture format.
- [ ] Calendar download: private authenticated .ics attachment containing due
  tasks as all-day, non-blocking VEVENTs. Escape text, fold UTF-8 content lines,
  keep UIDs stable without disclosing the access key, omit trash/undated tasks.
  Export existing occurrences only; no automatic sync or extra recurring events.
- [ ] Release: local native/protocol/backup checks, desktop/mobile no-JavaScript
  and axe checks, actual green GitHub Actions, isolated service sandbox rehearsal,
  scoped production deploy and fresh-workspace HTTPS/backup verification.

No storage revision, runtime framework, third-party service or additional
JavaScript is required for these two features. Existing request/source/capacity
and service resource limits remain in effect.

## Proposed follow-up order

1. Multi-tab conflict detection and persisted idempotency: stale forms must not
   overwrite newer edits; retries of one action must not duplicate tasks/imports.
   Design a bounded persistent revision/replay contract before implementation.
2. Bulk selection/actions: complete, move project, set priority/date and trash a
   selected set in one transaction/undo. Reuse graph checks; reject the entire
   set if a prerequisite/capacity rule fails. Keyboard/mobile access is essential.
3. Saved views: named validated search/filter/layout settings with native links.
   Include read-only GET behavior, limits and backup/import compatibility.
4. Reusable project/checklist templates: preview before materializing fresh IDs,
   remap internal references and apply one undoable transaction.
5. Manual ordering: native move-up/down controls with persisted bounded ranks;
   optional drag behavior must preserve the keyboard/no-JavaScript path.
6. Romanian/English UI and deliberate date/timezone preferences, with the UTC
   storage contract kept explicit and independently tested.
7. Safe growth: aggregate disk budget, bounded workers and benchmarks; off-host
   encrypted archives/alert delivery need an operator-selected destination.
8. Public interactive demo with disposable sample tasks and a native Architecture
   page for discovery. No private content or access keys in the sitemap/analytics.

Passkeys, sharing and offline write queues need a separate authorization/conflict
model. They are future candidates, not features delivered by this iteration.

## Evidence

Quick capture: 145 integration tests passed, including five new boundary,
validation, Unicode, capacity and atomic-failure cases. Four focused browser
cases passed on desktop/mobile, including no-JavaScript undo/redo and light/dark
axe checks. Final remote CI and deployment remain pending until both features
are complete.

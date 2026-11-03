# Product roadmap

## Release 1 — foundation and usable product

Delivered on 2026-11-03. See [release verification](RELEASE.md) for checks and limits.

1. Strict bounded HTTP parsing, absolute deadlines and predictable binding.
2. Transactional, synced storage with explicit capacity and disk errors.
3. Anonymous server-generated sessions; preserve legacy task lists through migration.
4. Responsive workspace: create/edit/complete/reopen/delete, search, filters,
   sorting, progress, theme, keyboard shortcuts, confirmations and JSON/CSV export.
5. Public landing page with clear privacy/recovery guidance, metadata, social
   previews, robots, sitemap and a noindex private workspace.
6. Isolated protocol/storage tests; desktop/mobile browser checks; least-privilege CI.
7. Scoped production deployment with backup, health checks and rollback instructions.

## Release 2 — ASM first

Delivered: native JSON/CSV export and UTC dates; server-side search, filters,
merge sorting, statistics, progress, editing and confirmations; task duplication;
complete no-JavaScript workspace; native NASM backup/SHA-256 utility and timer.
HTML/CSS present the result. Browser JavaScript is optional convenience only.
Python/Playwright remain development or legacy verification tools.

All subsequent task/storage/backup features should follow the same NASM-first
constraint; no framework or interpreter backend should be introduced.

## Release 3 — native planner

Implemented under the [delivery plan](PLANNER-PLAN.md): priorities/due dates,
UTC date views, daily/weekday/weekly/monthly/yearly recurrence with anchors,
projects/tags, subtasks/prerequisites, structured search, workspace undo/redo,
recoverable trash, native calendar/board, private SVG activity and JSON/CSV
preview/merge/replace import. Storage revision 3 reads V1/V2 and provides a
native offline preflight/downgrade path. See [features](PLANNER-FEATURES.md) and
[release verification](RELEASE.md) for release status and checks.

## Next — additional organization

- Manual drag ordering with equivalent keyboard controls; the native board and
  calendar already work through normal HTML links/forms.
- Bulk selection and archive; duplication and one-step workspace undo already ship.
- Installable offline PWA: queue writes and resolve conflicts explicitly.
- Romanian/English localization and user-selected timezone/date formats.

## Next — accounts and scale

- Optional passkey accounts, recovery and multiple devices, session revocation.
- Explicit sharing roles, expiring invitations and audit trail.
- Global filesystem quota, off-host encrypted backups and additional restore drills.
  The dedicated Unix identity and local restore drills are already delivered.
- Bounded worker model, benchmarked limits, resource telemetry and abuse controls.
- Data retention/deletion controls, accessibility audit and privacy policy review.

## Discovery and growth

- Search Console ownership and sitemap submission by the domain owner.
- Helpful public content about the Assembly implementation, static demo and FAQ.
- Measure activation and return usage only after defining a privacy-conscious
  analytics design; never send task text or capability tokens to analytics.
- Browser performance/accessibility budgets and real user feedback before adding
  dependencies, trackers, monetization or collaboration complexity.

No ranking, traffic or adoption guarantees. Items under Next and Discovery are
proposals, not claims of delivered behavior.

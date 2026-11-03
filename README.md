# ASM TODO

A focused task workspace with an **x86_64 Assembly backend**, raw Linux syscalls,
and a responsive HTML/CSS/JavaScript interface. No libc or web runtime framework.

[Live site](https://asm.micutu.com/) · [Audit](docs/AUDIT.md) ·
[Security model](docs/SECURITY.md) · [Roadmap](docs/ROADMAP.md) ·
[Operations](docs/RUNBOOK.md)

## What works

- Add, edit, duplicate, complete, reopen, delete and clear completed tasks.
- Priorities, UTC due dates, Today / Next 7 days / Overdue views, six sort
  orders, search, All/Active/Done filters and progress indicators,
  computed on the server in ASM. The complete task workflow works without JavaScript.
- Native daily/weekday/weekly/monthly/yearly recurrence creates the next task
  atomically on completion and retains month/leap-day anchors.
- Native projects and tags with exact Unicode-aware filters, editable properties
  and spreadsheet-safe metadata exports.
- Native subtasks and up to eight prerequisites, combined cycle checks, blocked
  task view and server-enforced completion rules.
- Native workspace undo/redo, recoverable trash and a bounded recent-changes log.
- Native structured AND search for priority/status/dates/projects/tags, quoted
  phrases and exact metadata matching.
- Optional JavaScript adds light/dark themes, keyboard shortcuts (`N` and `/`),
  immediate input feedback and a desktop focus timer. It does not select, sort,
  count, edit or export tasks.
- JSON and spreadsheet-safe CSV exports generated in ASM, with native UTC
  calendar formatting; explicit recovery-key download.
- Responsive layouts checked from 320 to 1440 px; accessible native dialogs,
  keyboard controls, status announcements and reduced-motion preferences.
- Public landing page, canonical/social metadata, a share preview, robots and
  sitemap. Private workspace responses send `noindex` and never enter the sitemap.
- Anonymous 128-bit sessions generated on the server, in HttpOnly Secure
  SameSite cookies. Legacy URLs/localStorage keys migrate to the new session.
- Strict bounded HTTP parser, complete-write handling, per-list locks, atomic
  synced snapshots, capacity checks and explicit storage errors.

Each browser session is an anonymous capability, not a password-protected
account. Anyone with a recovery key can access that workspace. Save the key
privately before clearing cookies. Exports of tasks do not contain the key.

## Build and run

Linux x86_64, NASM, binutils/ld and make are required.

```sh
make                 # build/server + build/backup; never overwrites the production binary
make run             # local data/ and 127.0.0.1:34624
./build/server 8080   # choose a port; conflicts fail instead of scanning
```

Use a TLS reverse proxy for normal deployment: session cookies are Secure.
Chromium accepts loopback as a trustworthy development context. The live
service uses `bin/server` and `/var/lib/asm-todo/data`, under a dedicated OS user.
The repository's old `data/` directory is not live storage after migration.

For a disposable preview, without any real user data:

```sh
python3 tools/preview.py   # prints its temporary loopback URL; Ctrl-C to stop
```

## Verification and CI

```sh
make check                         # Python protocol/storage/security/backup tests
npm ci --ignore-scripts             # development-only browser tools
npx playwright install chromium --only-shell
npm run test:ui                     # Chromium desktop + Pixel 5 emulation, axe checks
npm audit --audit-level=high
```

Every test server uses a new temporary directory, random sessions and a selected
loopback port. Tests never delete a production UID or bind the live port.
The compatibility entry point `tests/smoke.sh` runs the isolated Python suite.
GitHub Actions has separate security/storage and browser/accessibility jobs,
read-only repository permissions, pinned action SHAs, timeouts and failure reports.
No deploy or secrets are available to the workflow.

Automated axe checks cover WCAG A/AA rules that the tool can assess. They are not
a certification or a substitute for manual assistive-technology testing.

## Native backup

The scheduled job runs `bin/backup`, compiled from NASM with `ld` alone. It pins
complete task snapshots by fd, generates an uncompressed USTAR archive plus a
SHA-256 manifest, verifies it, then publishes with no-replace atomic rename and
fsync. Private native archives have 14-day retention. No Python, Node, shell,
`tar` or `sha256sum` process is used by the backup executable.

```sh
./build/backup /path/to/data /path/to/private-backups
./build/backup --verify /path/to/private-backups/asm-todo-EPOCH-RANDOM.tar
```

Python remains for development checks and old `.tar.gz` archive compatibility;
Playwright remains a development-only browser test tool. See [project rules](AGENTS.md).

## Architecture

| File | Purpose |
|---|---|
| `src/main.asm` | Loopback socket, bounded child lifetime, fork-per-connection lifecycle |
| `src/http.asm` | Bounded HTTP line, header and body validation |
| `src/router.asm` | Routing, sessions, same-origin checks, forms, escaping and rendering |
| `src/view.asm` | Native query parser, Unicode search, bounded merge sort and statistics |
| `src/template.asm` | Native HTML interpolation and edit/confirmation forms |
| `src/export.asm` | Native JSON/CSV serialization and formula protection |
| `native/backup.asm` | Native TAR snapshots, verification, atomic publication and retention |
| `native/sha256.asm` | Native SHA-256 integrity implementation |
| `src/storage.asm` | Per-workspace locking, legacy replay and durable full snapshots |
| `src/utils.asm` | Complete writes, strict decimal parsing, UTF-8 validation and strings |
| `web/` | Assets embedded into the binary at build time; no separate asset server |
| `deploy/` | Reviewed systemd/nginx configurations and deployment procedure |
| `tools/backup.py` | Legacy .tar.gz compatibility/rollback tool; no scheduled use |

Versioned snapshots preserve legacy V1 reads and write explicit V2 metadata
on mutation. Monotonic IDs survive deletion. Native trash retains up to 200 items, with restoration, permanent purge,
workspace-wide undo/redo and bounded activity in the
[revision 3 extension](docs/STORAGE-HISTORY.md). The native
offline downgrade command supports rollback to older binaries. See the
[storage contract](docs/STORAGE-V2.md).

Limits: 1,000 tasks per workspace, 110 **UTF-8 bytes** per title, 4,095 request
bytes, one HTTP request per connection. There is no runtime TLS, account recovery,
server-side session revocation, offline queue or collaboration layer.

The [native planner delivery plan](docs/PLANNER-PLAN.md) tracks recurrence,
projects, dependencies, undo/trash, import, structured search, calendar and insights.
The broader roadmap also proposes passkeys, sharing and scale. Unchecked stages
are not released features.

## License

[MIT](LICENSE)

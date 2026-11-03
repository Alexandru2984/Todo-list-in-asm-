# ASM-first release verification — 2026-11-03

The live application and scheduled backup logic are native x86_64 NASM programs,
linked with `ld` and raw Linux syscalls. No interpreter or runtime framework
serves task requests or performs scheduled backups.

## Delivered in this release

- `src/export.asm`: authenticated JSON/CSV downloads, proper escaping, spreadsheet
  formula neutralization (including Unicode whitespace), native UTC dates and
  complete exports independent of the currently filtered view.
- `src/view.asm`: strict query parsing, ASCII/Latin-1/Romanian case-insensitive
  Unicode search, four deterministic sort orders, stable O(n log n) merge sort,
  counters, filtered row selection and rounded completion percentage.
- `src/template.asm`: server-rendered counts, filters, progress, search state,
  editing and explicit confirmation pages. GET confirmation pages never mutate
  tasks. Failed-save forms preserve validated drafts as escaped values.
- Task duplication creates a fresh active task and respects capacity/isolation.
- The complete workspace works with JavaScript disabled. HTML/CSS present the
  native result. JavaScript was reduced from 288 to 75 lines for optional theme,
  input feedback, shortcuts, countdown and one-time legacy browser-key migration.
- `native/backup.asm` and `native/sha256.asm`: private USTAR archives, SHA-256
  manifests, no-follow regular-file reads, strict archive verification, checked
  writes/fsync/no-replace publication, duplicate rejection and 14-day retention.
  Core dumps are disabled; no external tar/hash process or interpreter is invoked.
- The backup timer runs the native binary under a syscall allowlist, no network
  and only the read-search capability required for private ASM-owned source data.
- Existing data format, cookie sessions, CSRF checks, strict CSP, loopback binding,
  SEO boundaries and prior storage/protocol protections remain in effect.
- AGENTS.md records the NASM-first constraint and attribution rules for future work.

## Validation

- **64 integration checks passed**: 31 protocol/storage/security, 7 native export,
  10 native view/duplicate, 12 native backup, 3 legacy archive compatibility and
  1 deployment-proxy check.
- Native UTC formatting matched an independent calendar on 255 timestamps.
  SHA-256 matched independent hashes on 16 standard/boundary vectors. Native TAR
  output was read independently by GNU tar and Python's tar reader.
- Native backups reject damaged payloads/manifests/headers, duplicate members,
  traversal, unsafe modes, links, FIFOs, oversized files, truncation and trailing
  payloads. Interrupted writes neither publish an archive nor prune old backups. Hot-backup
  tests also verified pinned immutable inodes while the source file was atomically
  replaced repeatedly.
- **16 browser checks passed**, desktop and Pixel 5 emulation, including complete
  no-JavaScript workflows and automated axe WCAG A/AA checks. Layout checks cover
  320/390/768/1440 px. Relevant export/no-JavaScript cases were rechecked after a
  tablet settings-layout correction. No manual WCAG certification is claimed.
- Exact backup service sandbox passed isolated verification with private source
  files owned by `asm-todo`; both binaries have non-executable stacks and no ELF
  interpreter. Build warnings and JavaScript syntax checks passed.

## Production verification

The release is live at https://asm.micutu.com/.

- Localhost and public HTTPS probes passed native search, server counts, JSON/CSV
  exports, session/private-page policy and the full task lifecycle.
- Public HTTPS Chromium with **JavaScript disabled** passed create/search/edit,
  duplicate, server-rendered progress/filtering, full JSON export from a filtered
  view and clear-completed confirmation. Only fresh probe workspaces were used.
- Original production task-file hashes matched the pre-release baseline. Probe
  records were removed. No original workspace was used for test mutations.
- The actual scheduled native backup service completed successfully. Its archive
  passed native verification, independent extraction/hash comparison, then a
  restore drill under the exact isolated ASM service sandbox and dedicated user.
- `asm-canary.service` remains active as `asm-todo`; `asm-backup.timer` remains
  enabled. Nginx passed validation; unrelated services/tunnel configuration were
  not changed. Private binary/config/data rollback snapshots were retained.
- Commits use the existing repository owner's identity, without coauthor trailers
  or assistant credits. GitHub Actions is configured; remote execution requires
  pushing the local commits and has not been claimed as completed.

## Remaining limits

- Anonymous bearer keys are not accounts; no key revocation or account recovery.
- No global disk quota/expiry for anonymous workspaces, or off-host backup/alert
  delivery policy. Local backups do not protect against VPS loss.
- New archives are uncompressed. Retention applies only to the native .tar name
  namespace; old .tar.gz archives/verification and rollback compatibility remain.
- Search/collation implement specified simple folding, not full locale-aware
  Unicode normalization/collation. Dates are rendered in UTC.
- Native parsing/crypto code has adversarial tests and independent format/hash
  oracles, but no formal verification, external security certification or PIE
  code-address randomization. Hashes provide integrity, not encryption/signatures.
- No request idempotency key: after an interrupted connection, reload before retry.
- Priorities, due dates, tags, import, offline mode, passkeys and sharing remain
  roadmap work, to be implemented under the same NASM-first rule.

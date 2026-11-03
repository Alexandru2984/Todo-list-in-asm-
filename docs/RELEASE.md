# Release verification — 2026-11-03

## Delivered

- Strict bounded framing and exact fields; reject truncated/ambiguous requests.
- Full checked/synced atomic snapshots; enforce capacity, preserve corrupt data,
  reject symlinks, retain monotonic IDs and serialize concurrent mutations.
- Server-generated anonymous cookie sessions; same-origin POST checks, migration,
  explicit recovery download and no tokens in normal task URLs/forms.
- Responsive workspace, public landing page, search/filter/sort, progress,
  edit/reopen/confirmations, JSON/CSV exports, theme, keyboard controls and focus timer.
- Static assets embedded at build time; restrictive CSP, consistent privacy
  headers, noindex workspace, canonical/social metadata, robots and sitemap.
- Isolated Python security/storage/backup tests and Chromium desktop/mobile tests,
  automated axe checks; pinned, read-only, time-bounded GitHub Actions workflow.
- Versioned dedicated-user systemd sandbox, nginx limits/private access logging,
  deployment/rollback tools and verified private daily local backup procedure.

## Validation before deployment

- 31 protocol/storage/security checks, including the absolute 15-second child
  deadline, 40 concurrent writes, 1000-slot capacity, maximum escaped render,
  restart persistence, failed writes, corrupt files, symlink refusal and the
  maximum representable task-ID boundary.
- Three backup round-trip/integrity/path-safety checks.
- Proxy-normalized lowercase response headers covered by a deployment-probe
  regression check. A real rollout automatically reverted on the original
  validator failure; the existing service remained available.
- 14 Chromium browser checks across desktop and Pixel 5 emulation. Layout overflow
  checked at 320, 390, 768 and 1440 px. Automated WCAG A/AA checks passed for public
  page and workspace in light/dark themes. No claim of manual WCAG certification.
- `npm audit`: zero reported vulnerabilities in the locked development dependencies.
- Full fresh-workspace lifecycle passed under the exact proposed service sandbox,
  dedicated identity and syscall allowlist, using isolated state/a spare port.
- Existing production listener and original data remained untouched during tests.

## Production verification

The release is live at https://asm.micutu.com/.

- Localhost and public HTTPS probes passed session creation, private-page policy
  and the full create/complete/reopen/edit/delete lifecycle on fresh probe lists.
- Public Chromium checks passed mobile/desktop task actions, the final mobile
  heading/input sizes, and zero JavaScript/CSP errors. Cloudflare's automatic
  analytics/challenge script injection is suppressed using `no-transform`;
  the app's own external script remains allowed by the restrictive CSP.
- Original task-file hashes matched the pre-deployment snapshot byte-for-byte.
  Probe lists were removed; no original workspace was used for testing.
- The service runs as `asm-todo`, with no effective Linux capabilities, seccomp
  active, NoNewPrivileges, 32-task/96-MiB caps and a loopback-only listener.
- Daily backup timer is enabled. The backup service completed successfully;
  SHA-256 verification and an isolated restore/server lifecycle drill passed.
- Nginx configuration passed validation and was gracefully reloaded. Cloudflare
  tunnel configuration and unrelated services were not changed.
- Commits use the repository owner's existing name/email with no coauthor lines.
  GitHub Actions has not run remotely because these commits have not been pushed.

See RUNBOOK.md for live paths, rollback snapshots and remaining operator work.

## Remaining work and limits

- Anonymous bearer keys are not account authentication; no revocation, multi-device
  session management or account recovery. Key holders have complete list access.
- No global disk quota/retention limit for anonymous workspaces. Proxy rate limits
  and process caps reduce abuse; they do not solve distributed resource exhaustion.
- Daily backups are local to this VPS; off-host encryption/restore policy and
  alert routing remain operator configuration. Release backups need manual retention.
- Static Assembly code has no memory-safe runtime, fuzzing coverage or PIE/ASLR for
  code addresses. Automated adversarial tests are not a proof of security.
- Historical/Cloudflare logs may contain legacy keys. Critical nginx errors can
  retain request contexts; normal new URLs never carry keys.
- No idempotency keys: a connection failure after commit can leave an ambiguous
  result. The UI preserves drafts and tells users to reload before retrying.
- CI configuration is committed; a remote GitHub run requires pushing the commits.
- Priorities, dates, tags, import, offline mode, passkeys and collaboration remain
  roadmap items. No claims of traffic growth, SEO rankings or compliance certification.

# Native recovery-key rotation — 2026-11-04

## Contract

- Keep the canonical 128-bit workspace ID and existing private snapshot/lock.
  Rotated credentials are 64 lowercase hex characters: the stable 32-character
  ID plus a fresh 128-bit random secret. Legacy 32-character keys remain usable
  until rotation. IDs alone never authorize a rotated workspace.
- Storage V5 adds the current credential hash and a monotonic key epoch to the
  same atomic snapshot as tasks, history, revision and receipts. No aliases,
  per-rotation files, tombstones or extra workspace slots accumulate.
- Prepare a new candidate through authenticated GET, save/download it before
  confirmation, then submit the saved-key acknowledgement and V4 write pair.
  The candidate is inactive before commit; no candidate is persisted on GET.
- Serialize rotation with existing writers and check authorization again under
  that lock. Publish policy and state together using checked fsync/rename.
  Older keys fail on data reads/writes, recovery/restore and import admission.
- If the response is lost, the pre-saved new key restores access. Repeating a
  rotation request that supplies the already-active new key may sign in with
  that key without changing any state; the old key alone cannot retrieve it.
- Rotation is not undoable; task undo remains available. Neither undo, purge nor
  JSON/CSV import can replace authentication policy. Existing task metadata is
  preserved. Calendar identifiers keep the stable workspace identity.

## Restore and rollback

Historical snapshots can predate key revocation. Provide a native offline policy
merge using a retained current data copy, preserving the highest available key
epoch and refusing ambiguous equal-epoch/different-key branches. Reset request
receipts/advance revision when applying restored policy. Require matching source
records; never silently revive keys from an old task archive.

Old binaries cannot enforce V5 revocation. Offline downgrade to V1/V3/V4 must
preflight all files and refuse any V5 workspace without writing anything. Failed
cross-version deployment rollback retains the compatible release/private copy.
A full restore that discards every newer policy copy cannot preserve later
revocations; operator documentation must say so explicitly.

## Acceptance

- [x] Native 32/64-character session handling and V5 authenticated snapshots.
- [x] Native preparation/download/confirmation, atomic rotation and lost-reply login.
- [x] Native offline policy-preserving restore; safe downgrade refusal.
- [x] Isolated tests: stale/concurrent writers, replay, failure, backup/restore,
  both key lengths, revoked endpoints, large-import header gate and no key leaks.
- [x] Desktop/mobile/no-JavaScript/light-dark axe checks, green actual CI,
  exact sandbox rehearsal, scoped deployment and fresh-workspace HTTPS probes.

## Threat review

Top risks are reviving a revoked key, splitting policy/data transactions and
locking out an owner after response loss. One policy-bearing atomic snapshot,
pre-saved candidates, lock-bound revalidation and downgrade refusal address
these. A bearer who already possesses the current key has the same authority as
the owner and may race to rotate it; no password/passkey identity is invented.
Requests authorized before the rotation commit may finish; past downloads cannot
be recalled. Archives remain private data with separate retention requirements.
No new vendor/runtime/JavaScript or formal security certification is introduced.

## Review and verification evidence

The six-question CISO review was applied to this boundary change. Principal
STRIDE risks are credential spoofing/disclosure, policy tampering during restore
and owner lockout/denial of service. One compromised active bearer exposes its
workspace; a compromised service identity can expose all service-owned task
files. Monetary impact/ALE and regulatory scope are not established by this
repository and are not fabricated. No vendor or subprocessors were added.
Current external alert delivery and MTTD remain unconfigured/unmeasured; the
runbook defines signals and response actions without claiming staffed coverage.
The isolated response-loss, archive-policy rollback and failed-write exercises
test technical recovery; a staffed incident tabletop has not been performed.
No new compliance claim or notification deadline is introduced.

- Local suite: 198 integration tests and 48 desktop/mobile browser cases passed;
  four new browser cases cover native downloads, no-JavaScript recovery and axe
  checks in both themes. Dependency audit: zero known vulnerabilities.
- Exact production service unit rehearsed with private disposable storage and a
  spare port, NoNewPrivileges/seccomp active, 256 MiB / 32-task limits. Observed
  MemoryPeak was 3,899,392 bytes for this rehearsal, not a load benchmark.
- Native backup verified/extracted independently; a subsequent second rotation
  was retained by merging newer policy over the older archive. The new key
  loaded the restored planner; the former key returned 410 after sandbox restart.
  All three unsafe downgrade modes refused V5 without changing task snapshots.
- Functional commit 3066086 passed GitHub Actions 41810661682; one existing
  desktop conflict test needed a retry. Subsequent test changes explicitly wait
  for the pinned old edit form, the other tab's committed redirect and the 412
  response. CI now rejects tests that pass only on retry rather than hiding them.
- Scoped rollout passed direct/public HTTPS rotation and lost-response probes.
  Public Pixel 5 Chromium without JavaScript passed candidate download before
  confirmation, revocation of another browser and full-key restore. Original
  production task-file hashes/count matched the private pre-release baseline.
  The real backup service completed; its archive passed independent extraction,
  hash comparison and native storage validation. See RELEASE.md for details.

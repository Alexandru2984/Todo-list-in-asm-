# Recovery-key rotation and storage V5

The backend, key generation/validation, confirmation pages and offline policy
merge are x86_64 NASM with raw Linux syscalls. No browser JavaScript is needed.
V1–V4 files remain readable and are not upgraded by reads. Normal protected
writes to an unrotated workspace still produce V4; explicit rotation produces V5.

## Credentials and confirmation

A legacy recovery key is 32 lowercase hex characters (128 random bits). A
rotated key is 64: the stable 32-character workspace ID followed by a fresh
128-bit getrandom secret. The ID alone stops authorizing a rotated workspace.
Each further rotation replaces the secret without moving task data, creating
aliases or consuming another admission slot. The active key remains a bearer
credential with full workspace authority, not an account or second factor.

Open **Rotate recovery key** under workspace tools. GET `/rotate-key` validates
access and generates an inactive candidate, without modifying storage. Save it
using the native POST `/rotation-key` download or copy the complete value, check
the saved-key acknowledgement, then confirm POST `/rotate-key`. The confirmation
requires the normal `_state` / `_request` pair and existing origin checks.
Candidates must be exactly 64 lowercase hex characters scoped to this workspace.
API clients must use a cryptographically secure random 128-bit suffix; hex format
validation alone does not prove entropy. Use the native prepared candidate rather
than choosing a memorable secret.

The server revalidates the credential under the same exclusive lock used by task
writers. It commits the new policy, revision, request receipt and rotation event
in one checked snapshot. Tasks, trash, task undo/redo, metrics and calendar IDs
survive. Rotation cannot be undone. Every earlier credential then receives 410
on private reads/writes, restore, recovery and large-import header admission.
Requests that already opened an authorized snapshot may finish; prior downloads
cannot be recalled. Public pages/assets and forgetting the local cookie remain
available. Invalid restore never clears an unrelated existing browser cookie.

Save the candidate **before** confirmation. If the response or new cookie is
lost, restore from home with that complete new key. Repeating the original
confirmation with the already-active candidate signs in without changing state,
even after its mutation receipt expires. This requires the complete active
credential in the request; an old key cannot retrieve the new secret. A stale
workspace precondition preserves the candidate for review (412); an uncertain
save (507) asks the user to retain both keys and retry that same candidate.
If all valid copies of the active secret are lost, no account recovery exists.

## Snapshot policy

V5 starts with these canonical lines, followed by existing V4 guards/history:

```text
#asm=5
#next=N
#key=64_lowercase_hex_hash
#keyepoch=positive_monotonic_integer
#revision=positive_monotonic_integer
#generation=32_lowercase_hex
```

`#key` is lowercase SHA-256 of the ASCII bytes
`ASM TODO active key v1`, a NUL byte, and the exact complete recovery key.
Comparison examines all 64 hash characters. The new secret is not persisted in
plaintext, URLs, ordinary HTML, exports, calendar feeds or receipt records.
The preparation page and explicit recovery/download responses necessarily show
it and are private/no-store/noindex. Archives and filenames still identify the
stable workspace and contain confidential task data; protect them accordingly.
This fast hash is suitable for randomly generated 128-bit secrets, not passwords.

The key epoch increments once per successful rotation. Import and task undo
cannot replace policy. The loader checks policy before accepting a mutation
receipt, so an old session cannot replay around revocation. Missing, duplicate,
malformed or out-of-order policy headers fail closed. Restore/recovery/import
admission use a bounded canonical header check; task routes also validate the
complete snapshot and graph. A valid header is not a certificate that trailing
task records are intact. No memory-safety or independent cryptographic audit is
claimed. Session rotation follows the general principle of invalidating old
credentials described by the [OWASP session guidance](https://cheatsheetseries.owasp.org/cheatsheets/Session_Management_Cheat_Sheet.html).

## Restore without reviving revoked keys

An old task archive contains old authorization policy. Stop HTTP and backup
writers and retain a private, trusted copy of the current data directory before
restoring. Verify the archive with the native backup verifier, extract only its
verified task members into fresh private `data/`, then run the **V5 binary** from
the restored working directory:

```sh
/path/to/v5/server --preserve-key-policy /private/retained-current/data
/path/to/v5/server --check-storage
```

The first command requires a matching retained file for every restored workspace.
It preflights every target/source pair before writing any target. The highest
available key epoch wins; equal positive epochs with different hashes are an
ambiguous branch and fail closed. Restored task data/history stay as selected,
while V5 targets receive a revision above both available revisions, a fresh
generation and no old request receipts. Both-legacy pairs need no policy change.
Source snapshots are not modified. The retained source must be trusted and
separately verified: the merge reads its authorization header, not every task.

Directory maintenance locks exclude other maintenance commands, not running HTTP
writers. Keep the service and backup job stopped throughout. Multi-workspace
publication is not one filesystem transaction; after interruption rerun the
merge and check successfully before serving any restored data. Retain private
pre-restore and restored copies until recovery is validated. Workspaces created
after the archive are absent from it and must be retained/restored separately.

If every newer policy copy is lost, revocations newer than the recovered archive
cannot be reconstructed. Do not promise that a historical full-VPS restore will
keep them. Replicate current policy/data securely off-host and define retention;
this release does not configure an off-host destination or encryption provider.

## Safe rollback

`--storage-version` reports reader 5. `--downgrade`, `--downgrade-v3` and the new
`--downgrade-v4` preflight all files and refuse **any V5 workspace before rewriting
any snapshot**. A V4 rollback check is a no-op on V1–V4. Erasing policy to make an
older reader start would reactivate revoked credentials and is not supported.
Once any workspace rotates, use a V5-compatible binary or a forward fix. The
deployment rollback preserves a private copy and retains the compatible release
if conversion fails; operators must inspect that failure instead of forcing an
older binary over V5 data.

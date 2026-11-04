# Storage V4: workspace consistency and request replay

The native HTTP renderer adds a hidden _state/_request pair to every private POST
form, including board actions, history, failed-save drafts and import previews.
No JavaScript is required. _state is SHA-256 of the fixed workspace identity, a
NUL delimiter and SHA-256 of the exact snapshot bytes. _request is a fresh 128-bit
random operation ID. The state is scoped to the workspace, so identical empty
workspaces cannot accidentally share a precondition.

## Transaction

After cookie/origin/schema validation, the server acquires the existing workspace
lock and loads/validates the complete snapshot. It checks recent successful
operation IDs before checking state. An exact retry returns the same 303 redirect
without changing the file, even after restart or undo. A reused ID with different
route/body, or a stale state, returns 412 and performs no mutation.

The fingerprint is SHA-256 of the exact raw route, a NUL delimiter and SHA-256
of the exact encoded request body, captured before destructive form parsing.
The receipt binds the entire submitted pair/body, not just the operation ID.
Equivalent fields with different encodings/order are not the same request.

Successful mutations atomically persist the task/history state, an incremented
workspace revision, a fresh generation and up to 16 successful receipts. Success
without task changes also consumes the operation ID, preserving undo/metrics.
Failed writes do not publish a receipt independently of task state. A lost
response can therefore be retried with the original pair/body. Receipt eviction
still leaves the old state stale, so an expired request is rejected, not reapplied.
The random generation also changes on each V4 save, independently of undo state.

Add/edit conflicts preserve the escaped draft and properties. The user can open
the current workspace and explicitly resubmit the reviewed draft using a fresh
pair. Import conflicts preserve the source and show an updated preview; confirmation
is revalidated again. GET requests never migrate or rewrite task snapshots.

## Protocol and migration

Authenticated GET /state.json returns private no-store/noindex JSON containing
revision (a decimal string), state and operationId. Programmatic clients send
these as _state/_request URL-encoded fields. Once a workspace is V4, task mutations
without both fields return 428. Native forms supply them automatically. Legacy
V1/V2/V3 clients remain readable and can mutate until a protected write activates
V4; clients must adopt the protocol to continue writing after activation.
Public session creation/recovery and browser logout are outside task transactions.

Versioned files begin with #asm=4, the existing #next header, exactly one positive
#revision and exactly one #generation of 32 lowercase hex characters. R records
hold operation ID (32 hex characters) and request fingerprint (64), oldest first.
Duplicates, missing/invalid generation/revision, overflow and more than 16 receipts
fail closed. Current/history task metadata remains the V3 representation.

```
#asm=4
#next=2
#revision=1
#generation=00000000000000000000000000000001
R|00000000000000000000000000000002|0000000000000000000000000000000000000000000000000000000000000003
```

The existing checked write/fsync/rename/directory-fsync transaction, 2 MiB member
cap and native backup utility cover these small additional records. All writes
of an existing V4 file advance the revision; undo does not rewind it. GETs of
legacy files stay byte-unchanged. Offline --check-storage validates V4 too.

Deployment compares --storage-version (now 4). Rollback to reader 3 preserves a
complete private copy and invokes --downgrade-v3, retaining task metadata, history,
metrics and monotonic IDs while dropping V4 request state. Older targets use
--downgrade to V1. Both converters validate all workspaces before rewriting any;
V3 downgrade leaves existing V1/V2/V3 files unchanged. Failed conversion restores
the private compatible copy rather than starting an incompatible reader.

## Bounds and limits

Receipts contain hashes/IDs, never task text. They are not authentication tokens.
The bounded 16-receipt replay window belongs to the persisted snapshot; restoring
an older archive also restores its revision/receipts and cannot preserve later
acknowledgements. No cross-restore or indefinite exactly-once guarantee is claimed.
Cookie possession and Origin checks remain the authorization/CSRF boundary.

The renderer inserts pairs in place, moving bytes backwards rather than allocating
another response-sized buffer. Every insertion and form count is bounded by the
existing 8 MiB response buffer and 8192 form positions. Task/source text is escaped
before this pass, and GET forms receive no extra query fields. Tests independently
parse maximal HTML to verify every native POST form is protected exactly once.

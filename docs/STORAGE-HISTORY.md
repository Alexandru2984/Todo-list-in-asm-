# Native history and trash (storage revision 3)

Revision 3 reads existing V1/V2 workspaces and leaves them byte-unchanged on GET.
Mutations now write `#asm=3`, the same current base/A metadata records, followed
by bounded history. The public JSON download schema remains version 2.

```
#asm=3
#next=100
1|0|1700000000|Example
A|1|0|0|0|0|0||||0|0|0|0
#undo=1
E|1700000000|1|1
M|19675|1
N|19674|1
U|2|0|1700000000|Previous state
V|2|0|0|0|0|0||||0|0|0|0
```

`#undo` is 0 unavailable, 1 undo available or 2 redo available. U/V records are
previous base/metadata records, with exactly the same scalar, text, capacity and
combined graph validation as current records. Each side has at most 1000 live
and 200 trash entries. IDs never rewind when swapping states. An empty previous
workspace is valid; malformed/duplicate history, missing metadata, dangling refs
and cycles fail without overwriting the file.

E contains UTC epoch, numeric operation and affected task ID (zero for bulk).
Operations 1..12 are add, edit, complete, reopen, trash, clear, restore, purge,
import, workflow, undo and redo. Only the latest 20 events persist, without task
titles or workspace capability keys. Undo preserves this action history.

M/N are current/previous UTC-day completion counts in 90 bounded day/count
buckets. Each ring slot is day modulo 90 and stores its explicit day to prevent
stale/future values from being confused. Counts cap at one billion per day.
Completions increment once; repeated completion is idempotent. Undo/redo also
swap these buckets. Reopen/trash do not erase a historical completion.

One stable file lock and checked write/fsync/rename/directory-fsync cover current
state, previous state, activity and metrics. A failed write never publishes only
half a recurrence or undo. The existing 2 MiB storage/native-backup member cap
covers both task arrays. The 256 MiB service envelope includes the extra 0.6 MiB
undo array per active worker. The response buffer is now 8 MiB for escaped import
previews; ordinary rendering stays below 4 MiB. Large import reception is globally
serialized and keeps the ordinary request/header limits intact.

## Trash semantics and privacy

Delete/clear retains at most 200 trash entries and includes descendants. Restore
checks live capacity, restores the selected trashed subtree and detaches its root
when its parent stays in trash. A completed live parent must be reopened before
restoring an active child. Prerequisites in trash keep dependents blocked.

Purge removes the selected trash subtree (or all trash), detaches surviving
references and clears the complete undo snapshot. Removed titles therefore do
not remain in an undo record. Numeric activity IDs may remain. Native daily
backup retention still applies; private deployment/recovery snapshots are
operator-managed and can also contain copies. Purge does not claim to erase
those archives. Permanent removal is explicitly confirmed in native HTML forms.

## Compatible rollback

`--storage-version` reports 3. Deployment compares the previous and new reader
revisions. Equal revisions retain planner state directly. Different revisions
preserve a private complete recovery copy and use the new native `--downgrade`
converter to write V1 live snapshots before installing an older binary. Metadata,
trash, history and metrics remain in the private recovery copy. This conversion
is deliberately conservative; even a previous V2 reader can read the V1 result.

The rollback guard is armed **before** attempting to start the new service,
covering a process that briefly accepts writes before systemd reports failure.
Conversion failure restores the private copy and retains the compatible release;
a failed recovery copy leaves the service stopped. Tests cover malformed-file
preflight and restored undo/metadata from a verified native TAR archive. An
isolated manual drill also ran the converted V3 fixture through the actual
previous production binary, without using production task files.

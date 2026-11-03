# Native planner storage V2

The HTTP runtime and offline converter are the same statically linked NASM
binary. No new database, interpreter or runtime is required.

Each private workspace is one atomic snapshot under a stable per-workspace flock.
The initial V2 codec accepts the following newline-terminated records:

```
#asm=2
#next=100
1|0|1700000000|Example
A|1|0|0|0|0|0||||0|0|0|0
```

The `A` fields are ID, priority, due epoch, completion epoch, parent ID, recurrence,
project, tags, comma-separated prerequisite IDs, workflow stage, deletion epoch,
previous status and recurrence anchor. Each task requires exactly one metadata
record after its base record. IDs cannot be duplicated. Unknown records, missing
metadata, malformed UTF-8, invalid scalar bounds and reference cycles fail closed.
Later delivery stages can extend this explicit version with bounded state records.

The in-memory task stride is 512 bytes, retaining the original 128-byte prefix.
There are at most 1,000 live tasks and 200 trash entries, eight prerequisites per
task, 110 UTF-8 bytes per title, 32 per project and 64 per tag string. Files and
native backup members are capped at 2 MiB. Due dates are UTC midnight. Completion
times are captured on new completions; legacy completion times stay unknown.

Legacy V1 replay files remain readable. A GET never migrates or rewrites data.
The next successful mutation writes V2 atomically. Native deletion retains a
bounded trash entry and includes descendants; oldest trash beyond 200 entries is
removed and references are detached. Trash restoration, undo and activity now use the backward-compatible
[revision 3 extension](STORAGE-HISTORY.md).

Every opened data/temporary inode must be regular and have at most one link.
Checks precede reads or truncation; O_NOFOLLOW and O_NONBLOCK prevent symlink and
FIFO attacks. Temporary writes, fsync, rename and directory fsync remain checked.
The service allowlist adds only fstat and ftruncate for these checks. The response
buffer grows to 4 MiB as planner metadata becomes visible. The service memory
ceiling is 256 MiB (160 MiB high watermark): 24 simultaneous workers may each
touch a 2 MiB source buffer, a 0.6 MiB task array and a 4 MiB response buffer, plus
process overhead. The ordinary HTTP request cap remains 4 KiB. Worst-case escaped
metadata rendering has a dedicated capacity test; the cap is not a request limit.


## Offline downgrade

Stop the HTTP service and preserve a private complete copy of `data/` first.
From the service working directory, run the new binary as the data owner:

```
/srv/canary/asm.micutu.com/app/bin/server --downgrade
```

The converter validates every exact workspace filename in a first directory pass,
then rewrites V2 files into V1 live-task snapshots in a second pass. V1 files and
unrelated names remain byte-unchanged. Monotonic IDs, titles, statuses and creation
times survive. Planner metadata and trash do not fit V1 and remain in the private
V2 recovery copy. Maintenance must run offline; per-file locks and the directory
maintenance lock do not replace stopping traffic.

`deploy/apply.sh` compares previous/new reader revisions using
`--storage-version`. On rollback to V1, it preserves V2 data and invokes this
converter before installing the previous binary. A failed conversion restores the
V2 recovery copy and keeps the compatible V2 release. If copying that recovery
state fails, the service stays stopped for manual recovery. A filesystem failure
mid-conversion can require recovery; this is why the private copy is mandatory.

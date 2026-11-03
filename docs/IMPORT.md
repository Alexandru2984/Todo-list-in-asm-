# Native import contract

Production parsing, preview rendering, ID remapping, graph validation and atomic
application run in x86_64 NASM with raw Linux syscalls. HTML forms submit the
source; the optional JavaScript theme helper does not parse or apply data.

## Accepted documents

JSON versions 1 and 2 use a required version and tasks array. Version 2 can
include trash. exportedAt is optional but validated when supplied. Fields and
primitive types are allowlisted; duplicate or unknown members fail. IDs are
positive exact signed-64-bit decimal strings; source INT64_MAX is excluded so a
subsequent ID is representable. Numbers reject overflow, floats and leading
zeros. Strings validate UTF-8, JSON escapes and paired UTF-16 surrogates; NUL is
rejected. Unknown createdAt remains null on export.

CSV requires id,title,completed,createdAt, in any column order. Known metadata
columns are optional, up to the complete 18-column export. Unknown/duplicate
headers fail. The lexer accepts an optional BOM, LF or CRLF, quoted fields and
doubled quotes. Field validation rejects controls in task text. escapeFlags
reverses exactly one exporter-added formula-protection apostrophe, after checking
that the remainder could be a formula. Legacy CSV lacks that evidence and keeps
its apostrophes. JSON/CSV preserve workflowStage separately from visible done
status so reopen retains the underlying workflow choice.

## Transaction and references

Preview parses and validates the entire source without saving. At most 20 items
are sampled; the original source is HTML-escaped into a readonly confirmation
form. The confirmation is not trusted: the native handler reparses it and reloads
the current workspace under its stable write lock.

Merge copies the current live/trash records and adds imported records. Replace
starts with only the imported records. Both assign fresh monotonic IDs and map
parents/dependencies only through source IDs in this document. Missing references,
self-links, duplicates and combined parent/dependency cycles fail. Completed
parents cannot gain active children or unfinished prerequisites. Capacity is
checked before save: 1,000 live tasks and 200 trash items; merge never silently
prunes existing trash. Empty merge is a no-op; empty replace is undoable clear.

One checked write/fsync/rename/directory-fsync publishes the entire import and
previous workspace snapshot. Failure before rename preserves the old snapshot;
after rename or a lost response the result can be ambiguous, so reload before
retrying. No idempotency key is claimed. Capacity/storage errors return an escaped
confirmation page retaining the source. Imported action history, undo states and
daily metrics are intentionally outside the portable task schema.

## Resource and request boundaries

Decoded source is at most 2 MiB. Form encoding can expand bytes by three, so the
request envelope is 7 MiB minus one byte. Header parsing still caps at 4095 bytes.
Only exact POST /import-preview and /import qualify, after cookie and same-origin
checks. The native regular-file flock in data/.import.lock permits one importer;
failed admission returns 503 before receiving a large body. Symlinks, hardlinks
and FIFO gate files fail closed. Normal CRUD remains available. Keep the shared
lock inode in place while workers are running.

Nginx independently limits these exact locations to 7m, leaves ordinary requests
at 4k and shares a one-connection import zone across addresses. Request buffering
stays on. The native 8 MiB response cap covers worst-case escaped source previews;
normal full-workspace rendering stays below 4 MiB. Service memory/process limits,
15-second child lifetime, socket timeouts and proxy rates remain active.

## Evidence

The local suite includes JSON/CSV round trips, exact 64-bit IDs, unknown dates,
formula escaping, metadata/trash/workflow state, reordered fields, Unicode and
surrogates, truncation/mutation fuzzing, graph cycles and reference isolation,
atomic save failures, merge/replace/undo and no-JavaScript browser confirmation.
Boundary cases include 1,200 total records, quote-all CSV, a 2 MiB source whose
form encoding approaches 6 MiB, and a valid escaped preview exceeding 4 MiB.
Isolated nginx tests check the exact large-body exception and import concurrency
without binding production ports or changing the live proxy.

## Explicit line capture

format=lines is used only by the **Add several tasks** form. It is never guessed
from JSON/CSV input and permits merge only. One nonblank LF/CRLF line creates one
literal title with a fresh ID/current UTC timestamp and default task properties.
Outer ASCII spaces/tabs are trimmed; embedded controls and bare CR fail. It
shares the same bounded preview/confirmation, validation, atomic save and undo
transaction. Blank-only source is rejected instead of clearing any task state.

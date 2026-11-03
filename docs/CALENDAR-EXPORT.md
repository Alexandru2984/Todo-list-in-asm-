# Native calendar download

GET /export.ics (and HEAD) requires the existing HttpOnly workspace cookie and
returns a private text/calendar attachment, asm-dated-tasks.ics. It sends
noindex/no-store and contains no recovery key or authenticated workspace URL.
The handler uses the same checked storage reader and never rewrites task files.

The NASM serializer exports all live tasks with a due date, independent of the
current view. Each becomes a one-day VEVENT with DATE DTSTART, CLASS:PRIVATE and
TRANSP:TRANSPARENT. These are all-day reminders that do not block availability.
Completed tasks have [Done] before the title and retain their completion status
in the description. Undated tasks and trash are omitted. Priority, workflow,
project, tags and recurrence choice are described in escaped text.

This is a snapshot download, not a subscription, sync protocol or complete backup.
Only actual stored occurrences are exported; no RRULE or alarms generate extra
future tasks. Use JSON/CSV for a complete portable task backup. External calendar
applications can handle repeated imports differently; automatic deduplication or
synchronization with a particular vendor is not claimed.

## Encoding and privacy

The implementation follows [RFC 5545](https://www.rfc-editor.org/rfc/rfc5545.html),
including CRLF content lines, TEXT escaping of backslash/comma/semicolon/newline
and folding at 75 octets without splitting UTF-8 characters. A DATE event without
DTEND/DURATION lasts one day (section 3.6.1), allowing the upper due-date boundary
9999-12-31 without constructing an invalid five-digit following year.

UID is lowercase SHA-256 of a domain-separated fixed-length workspace/task tuple,
followed by @asm.micutu.com. It is stable across reads, title/date edits and
backup restores, differs between workspaces, and never includes the bearer key.
The existing independently tested native SHA-256 module is reused; the hash is
an opaque event identifier and is not used for authentication or encryption.

At most 1,000 events are emitted. Field bounds keep the logical line scratch
under 512 bytes and each escaped/folded event below 1 KiB, within the existing
8 MiB response cap. No storage version or syscall/service permissions change.

Independent Python checks cover CRLF/physical-line limits, UTF-8 folding,
escaping, date boundaries/random Gregorian dates, priority/status metadata,
privacy/HEAD, SHA-256 UID oracles/stability/isolation, recurrence snapshots,
corrupt storage and worst-case 1,000-task output. Browser checks exercise the
actual no-JavaScript download on desktop/mobile and responsive settings layout.

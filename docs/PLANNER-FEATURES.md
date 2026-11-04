# Native planner features

All essential controls submit normal HTML forms. Filtering, sorting, date
validation and exports run in the NASM binary with JavaScript disabled.

## Priority and dates

Use **Priority & due date** below the new-task field, or **Edit** in a task's
menu. Priority is normal, low, high or urgent; priority sort orders urgent, high,
normal, low, then newest ID for ties. Due-date sort puts the earliest date first,
leaves undated tasks last and breaks ties by newest ID.

Dates use strict Gregorian YYYY-MM-DD and UTC. The earliest assignable due date
is 1970-01-02 because zero represents no due date; the latest is 9999-12-31.
Invalid dates, duplicate fields and stripped control characters fail without a
write. Clearing the date removes it (and clears any associated recurrence).
An edit containing only ID/title preserves the existing priority and date.

**Today** shows active tasks due on today's UTC date. **Next 7 days** shows active
tasks due tomorrow through seven days from today, inclusively. **Overdue** shows
active tasks whose due date is before today. Completed tasks remain available in
Completed and exports. New completions record UTC timestamps; legacy completed
tasks retain unknown completion times. Repeating completion is idempotent.

## Portable exports

JSON now has `version: 2`, `exportedAt`, a live `tasks` array and a separate `trash`
array. Each task retains the V1 ID/title/completed/createdAt fields and adds
priority, dueDate, completedAt, project, tags, parentId, dependencies, recurrence,
recurrenceAnchor, stage, workflowStage, deletedAt and previousCompleted. The stage
field describes the visible todo/doing/done state; workflowStage preserves the
underlying todo/doing choice when a completed task is reopened. IDs remain strings to
avoid JavaScript's 53-bit integer limit. Unknown optional dates are JSON null;
projects and tags are bounded strings. Tags are editable in native task details.

CSV keeps the original first four columns and adds the metadata columns plus
`escapeFlags`. It includes retained trash, distinguished by deletedAt. Dependency
IDs use a quoted comma-separated field; missing parent is zero. When a title,
project or tag string could execute as a spreadsheet formula, export prefixes an
apostrophe. Bits 1, 2 and 4 of escapeFlags identify exactly which of these fields
received that added apostrophe. The native importer removes exactly one added
prefix without corrupting an original leading apostrophe. workflowStage is the
last CSV column and preserves the underlying workflow state. CSV does not
contain the workspace capability key. Treat all exports as private task data.

## Recurrence

Choose daily, weekdays (Monday to Friday), weekly, monthly or yearly in the native
Repeat field. A repeating task requires a due date. Completing it marks the
original done and creates one fresh active occurrence in the same atomic file
commit. Repeating the completion request creates no duplicate. The new date is
strictly after both today and the original due date, skipping missed backlog.

Monthly series retain their original day anchor: January 31 becomes February 28
(or 29), then March 31. Yearly February 29 series return to the 29th in leap years.
Saving a title-only edit, or submitting an unchanged form, retains that anchor.
Changing the due date explicitly resets it. New occurrences preserve priority,
project, tags and prerequisites but begin outside the original parent and workflow
stage. A full workspace, exhausted IDs, an unrepresentable next date or a failed
write leaves the original completion unchanged. Existing completed legacy tasks
stay idempotent and do not receive invented timestamps or new occurrences.

## Projects and tags

Task details and Edit include a project (up to 32 UTF-8 bytes) and tags. Tags use
commas, trim surrounding ASCII spaces and retain their spelling. There are at
most eight tags, 24 bytes each and 64 input bytes total. Empty tags, trailing
commas and case-insensitive duplicates are rejected. Clear the field to remove
all tags. Title-only edits preserve these fields; duplication and recurrence
carry them into the new task.

Open **Filter by project & tag** to match one exact project and/or one exact tag.
Matching folds ASCII, Latin-1 and Romanian case like native title search. A tag
filter for `asm` does not match `assembly`. Filters combine with date/status,
free-text search and sort, and remain present in native navigation links. Global
workspace counters continue to include all live tasks. Names are escaped in
HTML and encoded in URLs; exports retain the original UTF-8 text.

## Subtasks and prerequisites

Every row displays its task ID. **Add subtask** in an active task's menu prefills
the new task's parent. Task details/Edit can set a parent ID (zero removes it) and
up to eight comma-separated prerequisite IDs. IDs remain exact 64-bit decimals.
Self-links, missing tasks, duplicate prerequisites and cycles fail without a write.
The graph check includes both parent-to-child and task-to-prerequisite edges, so
mixed cycles cannot leave the workspace impossible to complete.

A task is blocked while any prerequisite is not completed, or any live child is
active. The **Blocked** view lists these tasks; completion buttons explain the
state, and the server independently refuses direct blocked completion requests.
Deleting a prerequisite keeps its dependent blocked until the prerequisite is
restored or the relationship is removed. Deleting a parent trashes its subtree.
Permanent retention pruning detaches references to removed IDs.

Reopen a completed parent before adding an active child or reopening its subtask.
A completed task cannot acquire unfinished prerequisites. Duplication retains
parent/prerequisite links and still validates them; recurring next occurrences
start outside the original parent, while retaining prerequisite IDs.

## Undo, trash and recent changes

**Undo last change** reverses one entire workspace change; **Redo last change**
reapplies it. Recurrence, bulk clear, deletion and restoration are single changes.
IDs stay monotonic and a new change replaces the redo branch. State survives a
server restart and a verified native archive restore. Recent changes lists the
last 20 numeric actions with UTC timestamps.

**Trash** contains up to 200 retained items. Restore brings back the selected
subtree after a capacity check. Restoring a child while its parent remains in
trash makes that child a root task. Permanent removal requires confirmation,
detaches references and clears undo. Empty trash applies to every trash item.
Server backups and private release snapshots may still retain copies. See the
[history storage contract](STORAGE-HISTORY.md) for the exact retention boundary.

## Structured search

Search accepts up to 255 UTF-8 bytes. Plain terms combine with AND, in any order;
double quotes keep a contiguous phrase together. Exact native metadata predicates
are `priority:normal|low|high|urgent`, `status:active|done|blocked|trash`,
`project:"My work"`, `tag:asm` or `#asm`, and `before:YYYY-MM-DD`,
`after:YYYY-MM-DD`, `on:YYYY-MM-DD`. Before/after are exclusive and require an
assigned due date. An empty quoted project matches unassigned tasks. Metadata
predicates also combine with the normal project/tag/status/date controls.

There is one predicate per scalar field, up to eight tag predicates and 64 free
terms. Duplicate scalar predicates, invalid dates/values, overlong metadata and
unclosed operator quotes fail. Quoted values can escape quotes/backslashes.
An unmatched quote in ordinary free text remains literal; an unknown prefix is
literal searchable text. Quote a phrase to search a known operator name literally.
Status trash includes retained trash when the outer view is All or Trash; an
incompatible outer status view yields no matches. Counters remain global.

## Calendar, board and activity

Choose List, Board or Calendar above the filters. Calendar uses a native
Monday-first six-week grid with Gregorian month navigation from 1970 through
9999. Counts follow the current task filters and include completed tasks when
those filters include them. Selecting a day opens its due tasks in List. The
month selector resets a selected day so another month can be explored. Global
workspace counters stay global. January 1, 1970 has no assignable due date because
zero is the existing no-date sentinel.

Board groups active tasks into To do/In progress, plus a Done column. The native
menu can Start work or Move to To do. Complete/Reopen retain their prerequisite,
parent and recurrence rules. Board mutation aliases are explicitly allowlisted
and preserve the board after redirects; unknown paths, extra fields, cross-origin
requests and missing sessions receive the usual validation. Changes to workflow
stage support undo/redo. Mobile stacks columns without horizontal scrolling.

Your momentum shows completions in the last 7/30 UTC days and a current streak
ending today or yesterday, bounded to 90 recorded days. The private SVG plots the
last 30 days, using only bounded numeric counts and generated dates. Every SVG
request requires its own workspace cookie, sends no-store/noindex and discloses
no task titles or access key. GET/calendar/chart requests never rewrite data.
Legacy completed tasks do not invent activity; new completion actions increment
one bucket. Undo/redo swaps the activity buckets with the task snapshot.

## Import

Open **Import tasks**, paste a native JSON/CSV export, select Merge or Replace,
then preview and explicitly confirm. This works without JavaScript. Preview
validates the entire document and shows at most 20 sample entries; it never writes
workspace data. Confirmation reparses the source and validates capacity and links
against the current workspace while holding its write lock. Both operations use
one atomic snapshot and can be undone as one change.

Merge preserves existing tasks and assigns fresh monotonically increasing IDs to
all imported live/trash records. Replace replaces both live tasks and trash, also
with fresh IDs; an empty replacement clears both. Parents/dependencies are
remapped only within the imported document: a missing source reference cannot
attach to an unrelated existing task. Imports preserve task metadata and retained
trash, but do not import another workspace's action history, undo or daily metrics.

Limits are 2 MiB of decoded source, 1,000 live tasks, 200 retained trash entries
and the normal field/relationship bounds. JSON v1/v2 and CSV v1/extended exports
are supported. Unknown or duplicate fields, invalid encodings, numeric overflow,
cycles and dangling links fail without a write. Unknown creation dates remain
unknown. CSV supports BOM, LF/CRLF, reordered columns and quoted/doubled quotes.
Legacy CSV without escapeFlags retains leading apostrophes because the original
value cannot be recovered unambiguously. See [the import contract](IMPORT.md).

## Quick capture

**Add several tasks**, below the new-task field, accepts one title per line.
It trims outer ASCII spaces/tabs, ignores empty lines and accepts LF or CRLF
(with an optional initial UTF-8 BOM). Punctuation, bullets and duplicate titles
remain literal. Interior controls, bare CR, invalid UTF-8 and titles longer than
110 UTF-8 bytes reject the whole batch.

Preview validates every title and shows the first 20. Confirmation validates
again under the write lock, assigns fresh IDs/current UTC creation times and
appends all tasks as one atomic, undoable change. Existing tasks are preserved.
The normal 1,000-live-task capacity and 2 MiB decoded-source limit apply. Quick
capture never replaces the workspace; new tasks begin active with normal priority.

## Calendar download

In **Workspace & backups**, choose **Calendar (.ics)** to download every live
scheduled task as an all-day reminder. Completed tasks are marked [Done]; tasks
without a due date and trash are omitted. Titles, priority, workflow, projects,
tags and recurrence choice remain readable in the calendar entry. The download
uses the workspace cookie and does not contain your recovery key.

It is a snapshot: later edits are not synchronized and no extra future recurring
occurrences are generated. Keep JSON/CSV for a complete task backup. See the
[calendar export contract](CALENDAR-EXPORT.md) for encoding/privacy and limits.

## Multiple tabs and safe retries

Forms remember the workspace state they were rendered from. If another tab saves
first, a stale write is rejected with **Workspace changed** and its draft/source
is preserved. Review the current workspace before explicitly applying the draft.
A recent exact retry of a successful change returns the original redirect without
adding another task/import or replaying undo. Revisions and the last 16 successful
request receipts persist across restart and native backups; undo never rewinds
the workspace revision. See [the V4 contract](STORAGE-V4.md) for client/restore
bounds. Admission capacity can delay new workspaces while existing ones stay usable.

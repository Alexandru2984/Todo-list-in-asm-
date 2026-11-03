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
recurrenceAnchor, stage, deletedAt and previousCompleted. IDs remain strings to
avoid JavaScript's 53-bit integer limit. Unknown optional dates are JSON null;
projects and tags are bounded strings. Tags are editable in native task details.

CSV keeps the original first four columns and adds the metadata columns plus
`escapeFlags`. It includes retained trash, distinguished by deletedAt. Dependency
IDs use a quoted comma-separated field; missing parent is zero. When a title,
project or tag string could execute as a spreadsheet formula, export prefixes an
apostrophe. Bits 1, 2 and 4 of escapeFlags identify exactly which of these fields
received that added apostrophe. A future native importer can therefore remove
one added prefix without corrupting an original leading apostrophe. CSV does not
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

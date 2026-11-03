# Public discovery policy

The public landing page describes the native planner features that ship with
this release: priorities/dates, recurrence, projects/tags, calendar/board,
subtasks/prerequisites, undo/trash and JSON/CSV import/export. Canonical URL,
Open Graph/Twitter preview, sitemap, mobile layout and a no-JavaScript FAQ remain
available without starting a workspace.

The former Disallow: /app also matched /app.css and /app.js. Specific Allow rules
now permit those public rendering resources, while application/export/recovery,
import, board, statistics and health routes remain disallowed. Google's robots
rules use the most specific matching path; see its
[official specification](https://developers.google.com/crawling/docs/robots-txt/robots-txt-spec).
A regression test extracts the landing page's actual stylesheet/script URLs and
checks their crawler access alongside the private routes.

Robots rules are crawler guidance, not authorization. Private endpoints continue
to require the workspace cookie and return noindex/no-store headers. Task pages
and task content never enter the public sitemap. Ownership verification and
Search Console submission remain domain-owner operations; no traffic or ranking
guarantee is implied.

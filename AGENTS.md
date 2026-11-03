# Project rules

- Keep production task logic and scheduled backup logic in x86_64 NASM with raw
  Linux syscalls. Do not introduce a C, Python, Node, React or framework backend.
- HTML/CSS are the browser presentation. JavaScript may provide optional theme,
  input feedback, shortcuts, countdown and legacy browser-key migration. Search,
  sort, counts, progress, editing, confirmations and exports must work without it.
- Python/Playwright are development and independent verification tools. The old
  Python archive utility remains only for legacy .tar.gz compatibility/rollback.
- Tests must use temporary storage, fresh sessions and spare loopback ports.
  Never run a destructive test against an existing workspace or production data.
- Build into build/. Deploy binaries atomically, preserve private rollback
  snapshots, and verify native backups before publishing or pruning them.
- Commit each completed stage with the repository owner's existing identity.
  Do not add assistant attribution, contributor credits or coauthor trailers.

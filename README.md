# ASM TODO Server

A multi-user TODO list web application written entirely in **x86_64 Assembly** for Linux — no libc, no frameworks, just NASM and raw syscalls. It ships a forking HTTP server, a dark-mode web UI, and crash-safe per-user file persistence.

![CI](https://github.com/Alexandru2984/Todo-list-in-asm-/actions/workflows/ci.yml/badge.svg)

## Features

- **Built from scratch:** pure NASM + Linux syscalls; the binary links with `ld` alone.
- **Concurrent HTTP server:** `fork()` per connection — one slow client can't stall the rest. Children are auto-reaped via `SIGCHLD` ignore.
- **Real request parsing:** reads until headers complete and the `Content-Length` body has fully arrived, so split-packet POSTs work; responses are delivered through a partial-write-safe loop.
- **Proper HTTP responses:** `Content-Length` on every response, `405 Method Not Allowed` for wrong methods, and security headers (`X-Content-Type-Options: nosniff`, `Referrer-Policy: no-referrer`, `Cache-Control: no-store`).
- **Multi-user:** each browser gets a random 32-hex-char uid (generated client-side, validated server-side) with its own task file.
- **CRUD + extras:** add, complete, edit (✎), delete, and clear-done — with timestamps, task counter, and All/Active/Done filters.
- **Crash-safe persistence:** operations append to `data/todos-{uid}.txt`, then the log is compacted by writing a temp file and `rename()`-ing it over the original. Concurrent children serialize via `flock` on a per-user lock file.
- **Hardened:** HTML-escaped output (XSS), URL decoding with CR/LF/`|` stripping (storage-format injection), strict hex uid validation (path traversal), `atoi` overflow guard, receive/send socket timeouts, title length caps.

## Requirements

- Linux x86_64
- [NASM](https://nasm.us/), `ld` (binutils), `make`
- `curl` and `netcat` for the smoke tests

## Getting started

```bash
make            # build → bin/server
make run        # build + start
./bin/server 8080   # optional: choose the start port
```

The server prints the port it listens on (default `34624`; if busy, it scans upward). Open `http://localhost:<port>` — the UI assigns your uid automatically and keeps it in `localStorage`.

## Testing

```bash
make && ./tests/smoke.sh
```

Twenty end-to-end checks over real HTTP: routing, header correctness, CRUD with on-disk assertions, XSS/injection/traversal hardening, split-packet POST delivery, and parallel-write integrity. The same suite runs in GitHub Actions on every push.

## Architecture

| File | Role |
|---|---|
| `src/main.asm` | entry point, signals, sockets, fork-per-connection accept loop, request reading |
| `src/router.asm` | routing, form parsing, URL decoding, HTML escaping/rendering, HTTP responses |
| `src/storage.asm` | task array, append-log persistence, compaction, per-user `flock` |
| `src/utils.asm` | `strlen`, `itoa`, `atoi`, `strncmp`, `write_all`, … |
| `src/defs.inc` | syscall numbers, constants, macros |

### Storage format

One record per line in `data/todos-{uid}.txt`:

```
id|status|timestamp|title        # status: 0=active, 1=done
```

Mutations append a superseding record (crash-safe), then the file is rewritten compacted via temp-file + atomic `rename()`. On load, records replay in order, so the last write for an id wins.

## Limitations (by design, it's assembly)

- The uid in the URL is the only access control — treat it as a capability token, don't host anything sensitive.
- Max 1000 tasks per user, titles capped at 110 characters, requests at 4 KB.
- HTTP/1.0-style `Connection: close` on every request; no TLS (put it behind a reverse proxy if exposed).

## License

[MIT](LICENSE)

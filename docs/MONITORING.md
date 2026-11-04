# Native operational monitoring and private operator notifications

New health acceptance and capacity accounting are x86_64 NASM with raw Linux
syscalls. Curl handles HTTP/TLS transport. Notifications reuse the existing host
relay and its encrypted Telegram/Resend credentials; no application framework,
new provider account or new notification backend is introduced.

## Checks

- asm-http-health.service: loopback /healthz approximately every minute.
- asm-public-health.service: public HTTPS /healthz approximately every minute,
  including DNS/TLS/proxy routing from this VPS.
- asm-capacity-health.service: data, local-archive and offsite-staging filesystems
  approximately every five minutes. Require at least 1 GiB available, 15% free
  blocks and 10% free inodes. Available blocks exclude reserved blocks.
- asm-offsite-health.service: native archive/readback receipt freshness every five
  minutes, with the existing 26-hour limit on both timestamps.
- Failure/recovery hooks for local backup, offsite worker and freshness checks.
  Restarting services trigger failure handlers according to systemd's state and
  retry semantics; a transient retry is not promised to page immediately.

Timers include small randomized delay/accuracy windows. HTTP transport retries
one failed GET, uses normal certificate verification, disables curlrc and drops
inherited proxy/credential environment. Only an exact healthy body plus final
HTTP 200 is accepted. The native reader holds at most 21 bytes; oversized output
terminates the producer and is never copied into diagnostic messages. Redirects,
HTML challenges, wrong/truncated bodies and TLS failure do not pass as healthy.

Filesystem checks pin directories with O_PATH and read fstatfs counters without
opening task contents. They tolerate the monitor's intentionally read-only mount
namespace. These are capacity checks, not a quota or proof that another process
can write. Unit sandboxes use DynamicUser, no capabilities, read-only filesystem,
resource limits and syscall filtering. No automatic cleanup, task mutations or
website restart is performed by probes.

## Notification privacy and authorization

The installer prepares units and local checks but never creates the delivery
opt-in marker /etc/asm-ops/alerts-enabled. Without it, notification units are
skipped before credentials/delivery start. Existing explicit opt-in persists
across installation. Live messaging requires explicit operator authorization.

asm-alert@ and asm-resolved@ use a dedicated asm-alert identity and private state,
separate from the web server and rclone worker. Systemd decrypts the existing
provider credentials for each authorized notification; secrets are not committed,
placed in argv, or copied to a new plaintext configuration file.

The common host configuration currently permits log forwarding for other
projects. ASM forces ALERT_INCLUDE_LOGS=false, zero log lines and a 1 KiB body
limit using an ExecStart env prefix, which wins over EnvironmentFile values.
Messages contain only operational host/time/unit state. They never include task
text, recovery keys, request headers, archive member names or private transport
logs. The existing relay retains its legacy swift-vapor label; the subject/unit
identifies ASM. Other projects and their alert policy are not changed.

A shared delivery lock serializes incident/recovery updates. The existing relay
throttles repeated failures per check for 24 hours, sends one recovery after an
accepted incident, then clears that incident. Healthy repeats send no message.
Delivery failure does not mark an incident as delivered. Provider acceptance is
not proof that the operator read the message; ambiguous network retries can
produce duplicates. No exactly-once notification guarantee is claimed.

Recovery units also require an active incident marker, avoiding credential
loading on every healthy timer tick. The explicit test uses separate state so
its marker does not leave production incident recovery permanently active.

## Install and inspect

After native/CI and isolated sandbox verification:

    sudo ./deploy/install-monitoring.sh
    sudo systemctl status asm-http-health.timer asm-public-health.timer asm-capacity-health.timer asm-offsite-health.timer
    sudo journalctl -u asm-http-health.service -u asm-public-health.service -u asm-capacity-health.service --since '1 hour ago'

The installer snapshots prior files/timer state privately and restores them on
failure. It preserves the existing backup/offsite chain and never activates the
website service. Native checks can be run manually with build/probe --http URL,
--health-file FILE or --space DIRECTORY MIN_BYTES MIN_SPACE_PERCENT MIN_INODE_PERCENT.
A zero inode threshold explicitly disables unavailable inode accounting checks.

After authorization, the operator may create the root-private opt-in marker and
start asm-notify-test.service once. The exact static test subject is:

    ASM TODO monitoring test

Its body (plus the relay's host/time metadata) is:

    ASM TODO monitoring test: health and backup checks are installed. This message contains no workspace data, recovery keys or private logs.

Remove the opt-in marker to gate future notifications; stop already-running
notification units separately if necessary. This cannot recall an in-flight
provider request. Local probes/timers remain useful without external delivery.
Do not inject production failures to test a pager: use isolated mock units and
loopback-only provider endpoints.

## Response and limits

For a loopback failure, inspect the ASM process/unit and port. If only public
health fails, inspect TLS/DNS/nginx/tunnel routing. For capacity, inspect free
space/inodes and growth before deleting anything. For backup/freshness failure,
retain local archives, inspect the private transport log and follow OFFSITE.md.
Never forward private diagnostics to notifications or delete data to clear a 500.

These checks run on the VPS: complete host power/network loss cannot be reported
by the dead host. A truly independent external uptime monitor remains separate
operator work. Filesystem quotas, remote retention, independent backup-secret
escrow, rate/5xx telemetry and compromise detection are not implemented here.

## Review and acceptance

The CISO review addresses log/credential disclosure, silent false-positive health
and notification floods. Strict native acceptance, minimal metadata, forced log
exclusion, separate role/state and duplicate/recovery handling mitigate these.
Existing provider credentials retain their existing scope. Monetary ALE, legal
scope, external delivery latency and staffed on-call coverage are unknown; no
financial/compliance figures or guarantees are inferred from workspace counts.

Response exercises use temporary storage, spare ports and synthetic failures.
A staffed incident tabletop and independent host-loss detection are unverified.
Primary references: [curl options](https://curl.se/docs/manpage.html),
[systemd failure hooks](https://www.freedesktop.org/software/systemd/man/latest/systemd.unit.html),
[timer semantics](https://www.freedesktop.org/software/systemd/man/latest/systemd.timer.html).

- Native suite includes exact status/body, malformed/oversized/chunked responses,
  proxy/curlrc quarantine, self-signed TLS rejection, unsafe inodes and independent
  statvfs capacity oracles, plus actual notification environment precedence.
- Sandbox acceptance covers actual encrypted dummy credentials, loopback-only
  fake delivery, log privacy, throttling, recovery and failed-provider handling.
- Live checks and live notification activation evidence follow deployment.

Local acceptance: 237 integration tests passed, including 15 new native probe and
notification-policy cases. An exact systemd rehearsal passed DynamicUser probes,
capacity checks and the actual shared relay using encrypted dummy credentials.
An adversarial include-logs=true configuration did not leak synthetic journal
secrets into payloads. Duplicate incidents were throttled; one recovery cleared
state; healthy repeats stayed quiet; rejected provider delivery created no success
marker. Egress was restricted to a loopback fake provider throughout. Production
credentials/recipients were not used, and the shared relay file remained unchanged.

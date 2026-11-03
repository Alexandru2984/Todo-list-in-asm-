#!/usr/bin/env bash
# Scoped ASM deployment. Run only after make check and browser checks pass.
set -Eeuo pipefail
if [[ $EUID -ne 0 ]]; then echo 'Run with sudo.' >&2; exit 1; fi
REPO_DIR=$(cd -- "$(dirname -- "$0")/.." && pwd)
cd -- "$REPO_DIR"
exec 9>/run/asm-todo-deploy.lock
flock -n 9 || { echo 'Another ASM deployment is running.' >&2; exit 1; }
make -q all || { echo 'Build is stale. Run make as the repository owner first.' >&2; exit 1; }
[[ -x build/server && -x build/backup ]]
LIVE_WORKDIR=$(systemctl show asm-canary.service --property=WorkingDirectory --value)
case "$LIVE_WORKDIR" in "$REPO_DIR"|/var/lib/asm-todo) ;; *) echo 'Unexpected live storage directory.' >&2; exit 1;; esac
[[ -d "$LIVE_WORKDIR/data" && ! -L "$LIVE_WORKDIR/data" ]]
STAMP=$(date -u +%Y%m%dT%H%M%SZ)
BACKUP_DIR="/var/backups/asm-todo/releases/$STAMP"
install -d -m 0700 "$BACKUP_DIR"
cp -a /etc/systemd/system/asm-canary.service "$BACKUP_DIR/asm-canary.service"
cp -a /etc/nginx/sites-available/asm.micutu.com-canary "$BACKUP_DIR/asm.nginx.conf"
cp -a /etc/nginx/conf.d/asm-rate-limit.conf "$BACKUP_DIR/asm-limits.conf"
if [[ -f /etc/nginx/snippets/asm-proxy.conf ]]; then cp -a /etc/nginx/snippets/asm-proxy.conf "$BACKUP_DIR/asm-proxy.conf"; fi
cp -a bin/server "$BACKUP_DIR/server"
# Old releases do not implement this read-only command. A successful exact
# response identifies a compatible planner rollback target; otherwise conversion is needed.
PREVIOUS_STORAGE_VERSION=1
PREVIOUS_STORAGE_VERSION=$(bin/server --storage-version 2>/dev/null || true)
case "$PREVIOUS_STORAGE_VERSION" in 2|3) ;; *) PREVIOUS_STORAGE_VERSION=1;; esac
NEW_STORAGE_VERSION=$(build/server --storage-version)
case "$NEW_STORAGE_VERSION" in 2|3) ;; *) echo 'Unsupported storage revision.' >&2; exit 1;; esac
printf '%s\n' "$PREVIOUS_STORAGE_VERSION" > "$BACKUP_DIR/previous-storage-version"
if [[ -f bin/backup ]]; then cp -a bin/backup "$BACKUP_DIR/backup"; fi
cp -a /etc/systemd/system/asm-backup.service "$BACKUP_DIR/asm-backup.service"
printf '%s\n' "$LIVE_WORKDIR" > "$BACKUP_DIR/previous-working-directory"
git rev-parse HEAD > "$BACKUP_DIR/revision"
sha256sum build/server > "$BACKUP_DIR/new-binary.sha256"
STOPPED=0
TIMER_STOPPED=0
START_ATTEMPTED=0
PREVIOUS_UID=$(stat -c %u "$LIVE_WORKDIR/data")
PREVIOUS_GID=$(stat -c %g "$LIVE_WORKDIR/data")
SUCCESS=0
rollback() {
    local exit_code=$?
    if [[ $SUCCESS == 0 ]]; then
        echo "Deployment failed; restoring ASM service/configuration from $BACKUP_DIR" >&2
        if [[ $STOPPED == 1 ]]; then systemctl stop asm-canary.service || true; fi
        # Never place the older binary over incompatible planner files. Preserve the entire planner state
        # first; the native offline converter preflights every workspace. If a
        # conversion fails, restore that copy and retain the compatible planner service/binaries.
        if [[ $START_ATTEMPTED == 1 && $PREVIOUS_STORAGE_VERSION != "$NEW_STORAGE_VERSION" ]]; then
            if ! cp -a /var/lib/asm-todo/data "$BACKUP_DIR/failed-release-planner-data"; then
                echo 'Cannot preserve planner state; retaining the compatible planner release.' >&2
                systemctl start asm-canary.service || true
                if [[ $TIMER_STOPPED == 1 ]]; then systemctl start asm-backup.timer || true; fi
                exit "$exit_code"
            fi
            if ! (cd /var/lib/asm-todo && runuser -u asm-todo -- "$REPO_DIR/bin/server" --downgrade); then
                if ! mv /var/lib/asm-todo/data "$BACKUP_DIR/partial-downgrade-data" || ! cp -a "$BACKUP_DIR/failed-release-planner-data" /var/lib/asm-todo/data; then
                    echo "Cannot restore planner state. Service remains stopped; private recovery copy: $BACKUP_DIR/failed-release-planner-data" >&2
                    exit "$exit_code"
                fi
                echo 'Native downgrade failed; restored planner data and retained the compatible planner release.' >&2
                systemctl start asm-canary.service || true
                if [[ $TIMER_STOPPED == 1 ]]; then systemctl start asm-backup.timer || true; fi
                exit "$exit_code"
            fi
        fi
        # Preserve live changes made during the brief initial directory migration.
        if [[ $START_ATTEMPTED == 1 && "$LIVE_WORKDIR" != /var/lib/asm-todo ]]; then
            cp -a /var/lib/asm-todo/data "$BACKUP_DIR/failed-release-data"
            mv -- "$LIVE_WORKDIR/data" "$BACKUP_DIR/original-data-at-rollback"
            cp -a /var/lib/asm-todo/data "$LIVE_WORKDIR/data"
            chown -R "$PREVIOUS_UID:$PREVIOUS_GID" "$LIVE_WORKDIR/data"
        fi
        cp -a "$BACKUP_DIR/asm-backup.service" /etc/systemd/system/asm-backup.service
        if [[ -f "$BACKUP_DIR/backup" ]]; then
            install -m 0755 "$BACKUP_DIR/backup" bin/backup.rollback
            mv -f -- bin/backup.rollback bin/backup
        fi
        cp -a "$BACKUP_DIR/asm-canary.service" /etc/systemd/system/asm-canary.service
        cp -a "$BACKUP_DIR/asm.nginx.conf" /etc/nginx/sites-available/asm.micutu.com-canary
        cp -a "$BACKUP_DIR/asm-limits.conf" /etc/nginx/conf.d/asm-rate-limit.conf
        if [[ -f "$BACKUP_DIR/asm-proxy.conf" ]]; then cp -a "$BACKUP_DIR/asm-proxy.conf" /etc/nginx/snippets/asm-proxy.conf; else rm -f /etc/nginx/snippets/asm-proxy.conf; fi
        if [[ $STOPPED == 1 ]]; then
            install -m 0755 "$BACKUP_DIR/server" bin/server.rollback
            mv -f -- bin/server.rollback bin/server
            systemctl daemon-reload
            systemctl start asm-canary.service || true
        fi
        if [[ $TIMER_STOPPED == 1 ]]; then systemctl start asm-backup.timer || true; fi
        if nginx -t; then systemctl reload nginx; fi
    fi
    exit "$exit_code"
}
trap rollback EXIT
if ! getent passwd asm-todo >/dev/null; then
    useradd --system --user-group --no-create-home --home-dir /var/lib/asm-todo --shell /usr/sbin/nologin asm-todo
fi
install -m 0644 deploy/asm-limits.conf /etc/nginx/conf.d/asm-rate-limit.conf
install -m 0644 deploy/asm-proxy.conf /etc/nginx/snippets/asm-proxy.conf
install -m 0644 deploy/asm.nginx.conf /etc/nginx/sites-available/asm.micutu.com-canary
nginx -t
systemctl stop asm-backup.timer asm-backup.service
TIMER_STOPPED=1
systemctl stop asm-canary.service
STOPPED=1
cp -a "$LIVE_WORKDIR/data" "$BACKUP_DIR/data"
# Validate every existing workspace while traffic is stopped, before replacing
# binaries or changing ownership. The native command never rewrites a file.
(cd "$LIVE_WORKDIR" && "$REPO_DIR/build/server" --check-storage)
install -d -m 0700 -o asm-todo -g asm-todo /var/lib/asm-todo
if [[ "$LIVE_WORKDIR" != /var/lib/asm-todo ]]; then
    if [[ -e /var/lib/asm-todo/data ]]; then mv -- /var/lib/asm-todo/data "$BACKUP_DIR/previous-state-data"; fi
    cp -a "$BACKUP_DIR/data" /var/lib/asm-todo/data
fi
chown -R asm-todo:asm-todo /var/lib/asm-todo/data
chmod 0700 /var/lib/asm-todo/data
install -m 0755 build/server bin/server.new
mv -f -- bin/server.new bin/server
install -m 0755 build/backup bin/backup.new
mv -f -- bin/backup.new bin/backup
install -m 0644 deploy/asm-canary.service /etc/systemd/system/asm-canary.service
systemctl daemon-reload
START_ATTEMPTED=1
systemctl start asm-canary.service
# Probe the new backend before nginx switches to the new policy.
python3 tools/deployment_probe.py --base http://127.0.0.1:34624 --cleanup-data-dir /var/lib/asm-todo/data
systemctl reload nginx
# Verify actual TLS origin traffic through the newly loaded vhost.
python3 tools/deployment_probe.py --base https://asm.micutu.com --cleanup-data-dir /var/lib/asm-todo/data
install -d -m 0700 /var/backups/asm-todo
./bin/backup /var/lib/asm-todo/data /var/backups/asm-todo
install -m 0644 deploy/asm-backup.service /etc/systemd/system/asm-backup.service
install -m 0644 deploy/asm-backup.timer /etc/systemd/system/asm-backup.timer
systemctl daemon-reload
systemctl enable --now asm-backup.timer
SUCCESS=1
printf 'ASM release deployed. Rollback snapshot: %s\n' "$BACKUP_DIR"

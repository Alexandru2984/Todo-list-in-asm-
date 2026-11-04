#!/usr/bin/env bash
# Install read-only checks. External delivery stays behind the operator's opt-in.
set -Eeuo pipefail
[[ $EUID == 0 ]] || { echo 'Run with sudo.' >&2; exit 1; }
REPO_DIR=$(cd -- "$(dirname -- "$0")/.." && pwd)
cd -- "$REPO_DIR"
exec 9>/run/asm-monitoring-install.lock
flock -n 9 || { echo 'Another ASM monitoring installation is running.' >&2; exit 1; }
make -q all || { echo 'Build is stale.' >&2; exit 1; }
[[ -x /usr/bin/curl && -x build/probe && -x bin/offsite ]]
[[ -x /usr/local/libexec/swift-vapor/alert-notify.sh && -f /etc/swift-vapor/alerts.env ]]
[[ -f /etc/credstore.encrypted/swift-vapor-smtp-pass && -f /etc/credstore.encrypted/swift-vapor-telegram ]]
units=(asm-http-health.service asm-http-health.timer asm-public-health.service asm-public-health.timer asm-capacity-health.service asm-capacity-health.timer asm-alert@.service asm-resolved@.service asm-notify-test.service asm-offsite-health.timer)
timers=(asm-http-health.timer asm-public-health.timer asm-capacity-health.timer asm-offsite-health.timer)
watched=(asm-backup.service asm-offsite.service asm-offsite-health.service)
STAMP=$(date -u +%Y%m%dT%H%M%SZ)
ROLLBACK_DIR="/var/backups/asm-todo/monitoring-releases/$STAMP"
install -d -m 0700 "$ROLLBACK_DIR"
files=("$REPO_DIR/bin/probe")
for unit in "${units[@]}"; do files+=("/etc/systemd/system/$unit"); done
for unit in "${watched[@]}"; do files+=("/etc/systemd/system/$unit.d/monitoring.conf"); done
for i in "${!files[@]}"; do
    if [[ -e ${files[$i]} ]]; then cp -a "${files[$i]}" "$ROLLBACK_DIR/$i"; fi
done
previous_timers=()
for timer in "${timers[@]}"; do
    if systemctl is-enabled --quiet "$timer" 2>/dev/null; then previous_timers+=("$timer"); fi
done
SUCCESS=0
rollback() {
    local exit_code=$?
    if [[ $SUCCESS == 0 ]]; then
        systemctl stop "${timers[@]}" 2>/dev/null || true
        for timer in "${timers[@]}"; do systemctl disable "$timer" 2>/dev/null || true; done
        for i in "${!files[@]}"; do
            if [[ -e $ROLLBACK_DIR/$i ]]; then cp -a "$ROLLBACK_DIR/$i" "${files[$i]}"; else rm -f -- "${files[$i]}"; fi
        done
        systemctl daemon-reload
        if (( ${#previous_timers[@]} )); then systemctl enable --now "${previous_timers[@]}"; fi
        echo "Monitoring installation failed; previous files/timers restored. Private rollback copy: $ROLLBACK_DIR" >&2
    fi
    exit "$exit_code"
}
trap rollback EXIT
systemctl stop "${timers[@]}" 2>/dev/null || true
if ! getent passwd asm-alert >/dev/null; then
    useradd --system --user-group --no-create-home --home-dir /var/lib/asm-alerts --shell /usr/sbin/nologin asm-alert
fi
install -d -m 0700 -o root -g root /etc/asm-ops
install -d -m 0700 -o asm-alert -g asm-alert /var/lib/asm-alerts
install -m 0755 build/probe bin/probe.new
mv -f -- bin/probe.new bin/probe
for unit in "${units[@]}"; do install -m 0644 "deploy/$unit" "/etc/systemd/system/$unit"; done
for unit in "${watched[@]}"; do
    install -d -m 0755 "/etc/systemd/system/$unit.d"
    install -m 0644 deploy/asm-backup-monitoring.conf "/etc/systemd/system/$unit.d/monitoring.conf"
done
systemctl daemon-reload
systemd-analyze verify /etc/systemd/system/asm-http-health.service /etc/systemd/system/asm-public-health.service /etc/systemd/system/asm-capacity-health.service /etc/systemd/system/asm-alert@.service /etc/systemd/system/asm-resolved@.service /etc/systemd/system/asm-notify-test.service
systemctl enable --now "${timers[@]}"
SUCCESS=1
if [[ -f /etc/asm-ops/alerts-enabled ]]; then
    echo 'Existing operator opt-in retained; external delivery is enabled.'
else
    echo 'Read-only checks installed; external notifications remain gated until explicit operator opt-in.'
fi
echo "Monitoring rollback copy: $ROLLBACK_DIR"

#!/usr/bin/env bash
# Deployment only. The scheduled backup/verification policy is native NASM.
set -Eeuo pipefail
[[ $EUID == 0 ]] || { echo 'Run with sudo.' >&2; exit 1; }
REPO_DIR=$(cd -- "$(dirname -- "$0")/.." && pwd)
cd -- "$REPO_DIR"
exec 9>/run/asm-offsite-install.lock
flock -n 9 || { echo 'Another offsite installation is running.' >&2; exit 1; }
make -q all || { echo 'Build is stale.' >&2; exit 1; }
[[ -x /usr/bin/rclone && -x build/offsite && -x bin/backup ]]
SOURCE_CONFIG=${1:-/home/micu/.config/rclone/rclone.conf}
STAMP=$(date -u +%Y%m%dT%H%M%SZ)
ROLLBACK_DIR="/var/backups/asm-todo/offsite-releases/$STAMP"
install -d -m 0700 "$ROLLBACK_DIR"
files=(/etc/systemd/system/asm-offsite.service /etc/systemd/system/asm-offsite-health.service /etc/systemd/system/asm-offsite-health.timer /etc/systemd/system/asm-backup.service.d/offsite.conf "$REPO_DIR/bin/offsite")
for i in "${!files[@]}"; do
    if [[ -e ${files[$i]} ]]; then cp -a "${files[$i]}" "$ROLLBACK_DIR/$i"; fi
done
TIMER_ENABLED=0
if systemctl is-enabled --quiet asm-offsite-health.timer 2>/dev/null; then TIMER_ENABLED=1; fi
SUCCESS=0
rollback() {
    local exit_code=$?
    if [[ $SUCCESS == 0 ]]; then
        systemctl stop asm-offsite-health.timer asm-offsite.service 2>/dev/null || true
        for i in "${!files[@]}"; do
            if [[ -e $ROLLBACK_DIR/$i ]]; then cp -a "$ROLLBACK_DIR/$i" "${files[$i]}"; else rm -f -- "${files[$i]}"; fi
        done
        systemctl daemon-reload
        if [[ $TIMER_ENABLED == 1 ]]; then systemctl enable --now asm-offsite-health.timer; else systemctl disable asm-offsite-health.timer 2>/dev/null || true; fi
        echo "Offsite installation failed; units/binary restored. Private state retained at /var/lib/asm-offsite; rollback copy: $ROLLBACK_DIR" >&2
    fi
    exit "$exit_code"
}
trap rollback EXIT
systemctl stop asm-offsite-health.timer asm-offsite-health.service asm-offsite.service 2>/dev/null || true
if ! getent passwd asm-offsite >/dev/null; then
    useradd --system --user-group --no-create-home --home-dir /var/lib/asm-offsite --shell /usr/sbin/nologin asm-offsite
fi
install -d -m 0700 -o asm-offsite -g asm-offsite /var/lib/asm-offsite
python3 tools/offsite_config.py "$SOURCE_CONFIG" /var/lib/asm-offsite/rclone.conf gdrive-vps-crypt
install -m 0755 build/offsite bin/offsite.new
mv -f -- bin/offsite.new bin/offsite
install -m 0644 deploy/asm-offsite.service /etc/systemd/system/asm-offsite.service
install -m 0644 deploy/asm-offsite-health.service /etc/systemd/system/asm-offsite-health.service
install -m 0644 deploy/asm-offsite-health.timer /etc/systemd/system/asm-offsite-health.timer
install -d -m 0755 /etc/systemd/system/asm-backup.service.d
install -m 0644 deploy/asm-backup-offsite.conf /etc/systemd/system/asm-backup.service.d/offsite.conf
systemctl daemon-reload
systemd-analyze verify /etc/systemd/system/asm-offsite.service /etc/systemd/system/asm-offsite-health.service /etc/systemd/system/asm-offsite-health.timer
systemctl enable --now asm-offsite-health.timer
SUCCESS=1
echo "Offsite services installed. Start asm-backup.service for a fresh archive and asynchronous replication. Rollback copy: $ROLLBACK_DIR"

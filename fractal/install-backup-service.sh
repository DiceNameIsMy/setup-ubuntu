#!/usr/bin/env bash
# Renders immich-backup.service for this checkout's path and installs it,
# together with immich-backup.timer, as systemd --user units. Run as your
# normal user (no sudo) - the backup script needs no root or local Docker
# access, only SSH to rpi4.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UNIT_DIR="$HOME/.config/systemd/user"
SERVICE_NAME="immich-backup.service"
TIMER_NAME="immich-backup.timer"

if [[ $EUID -eq 0 ]]; then
  echo "Run this as your normal user, not root/sudo (it installs a --user unit)." >&2
  exit 1
fi

if [[ ! -f "$SCRIPT_DIR/$SERVICE_NAME" || ! -f "$SCRIPT_DIR/$TIMER_NAME" ]]; then
  echo "Expected $SERVICE_NAME and $TIMER_NAME next to this script in $SCRIPT_DIR." >&2
  exit 1
fi

if [[ ! -x "$SCRIPT_DIR/backup.sh" ]]; then
  echo "Warning: $SCRIPT_DIR/backup.sh is not executable; chmod +x it first." >&2
fi

mkdir -p "$UNIT_DIR"

sed "s|__IMMICH_WORKDIR__|$SCRIPT_DIR|g" "$SCRIPT_DIR/$SERVICE_NAME" >"$UNIT_DIR/$SERVICE_NAME"
cp "$SCRIPT_DIR/$TIMER_NAME" "$UNIT_DIR/$TIMER_NAME"

systemctl --user daemon-reload
systemctl --user enable --now "$TIMER_NAME"

echo "Installed and enabled $TIMER_NAME (workdir: $SCRIPT_DIR)."
echo "Check status with: systemctl --user status $TIMER_NAME"
echo "Check schedule with: systemctl --user list-timers $TIMER_NAME"
echo
echo "For the timer to fire even when not logged into a graphical session,"
echo "enable lingering: loginctl enable-linger $USER"

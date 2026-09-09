#!/usr/bin/env bash
# Renders immich.service for the current (or given) user and installs it as
# a systemd unit. Run with sudo; the compose stack itself still runs as the
# target user (docker group membership required), not as root.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE="$SCRIPT_DIR/immich.service"
UNIT_NAME="immich.service"
DEST="/etc/systemd/system/$UNIT_NAME"

if [[ $EUID -ne 0 ]]; then
  echo "Run this with sudo (needs to write to /etc/systemd/system)." >&2
  exit 1
fi

TARGET_USER="${1:-${SUDO_USER:-$(id -un)}}"

if ! id "$TARGET_USER" &>/dev/null; then
  echo "User '$TARGET_USER' does not exist." >&2
  exit 1
fi

if ! id -nG "$TARGET_USER" | grep -qw docker; then
  echo "Warning: '$TARGET_USER' is not in the 'docker' group." >&2
  echo "  Run: usermod -aG docker $TARGET_USER (then re-login) before starting the service." >&2
fi

if ! command -v tailscale &>/dev/null; then
  echo "Warning: 'tailscale' not found on PATH; the unit's tailscale serve steps will fail." >&2
elif ! tailscale status &>/dev/null; then
  echo "Warning: tailscale is installed but not logged in/running (tailscale status failed)." >&2
fi

if [[ ! -f "$TEMPLATE" ]]; then
  echo "Template not found: $TEMPLATE" >&2
  exit 1
fi

sed \
  -e "s|__IMMICH_WORKDIR__|$SCRIPT_DIR|g" \
  -e "s|__IMMICH_USER__|$TARGET_USER|g" \
  "$TEMPLATE" > "$DEST"

echo "Installed $DEST for user '$TARGET_USER', workdir '$SCRIPT_DIR'."

systemctl daemon-reload
systemctl enable --now "$UNIT_NAME"

echo "Enabled and started. Check status with: systemctl status $UNIT_NAME"
echo "Tailscale serve mapping:"
tailscale serve status 2>&1 || true

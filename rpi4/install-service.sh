#!/usr/bin/env bash
# Renders immich.service for the current (or given) user and installs it as
# a systemd unit. Run with sudo; the compose stack itself still runs as the
# target user (docker group membership required), not as root.
#
# Requires the UUIDs of the SSD (Postgres data, must be a real POSIX
# filesystem like ext4 -- Postgres needs its data dir owned exactly by its
# own internal uid) and the HDD (shared storage: Immich library + other
# stuff like Obsidian sync, whatever filesystem it already is) so it can
# pin /etc/fstab entries to stable /mnt mount points, instead of the
# USB-order-dependent /media/nur/<label> automount paths.
# Find them with: lsblk -no UUID /dev/sdX
set -euo pipefail

SSD_MOUNT="/mnt/ssd"
HDD_MOUNT="/mnt/Axagon"

usage() {
  cat >&2 <<EOF
Usage: sudo $0 --ssd-uuid=<UUID> --hdd-uuid=<UUID> [TARGET_USER]

  --ssd-uuid   UUID of the drive holding the Postgres DB (mounted at $SSD_MOUNT)
  --hdd-uuid   UUID of the drive holding shared storage incl. the photo/video
               library (mounted at $HDD_MOUNT)
  TARGET_USER  defaults to \$SUDO_USER, or the current user

Find UUIDs with: lsblk -no UUID /dev/sda /dev/sdb
EOF
  exit 1
}

SSD_UUID=""
HDD_UUID=""
POSITIONAL=()
for arg in "$@"; do
  case "$arg" in
    --ssd-uuid=*) SSD_UUID="${arg#*=}" ;;
    --hdd-uuid=*) HDD_UUID="${arg#*=}" ;;
    -h|--help) usage ;;
    *) POSITIONAL+=("$arg") ;;
  esac
done

if [[ -z "$SSD_UUID" || -z "$HDD_UUID" ]]; then
  echo "Both --ssd-uuid and --hdd-uuid are required." >&2
  usage
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE="$SCRIPT_DIR/immich.service"
UNIT_NAME="immich.service"
DEST="/etc/systemd/system/$UNIT_NAME"

if [[ $EUID -ne 0 ]]; then
  echo "Run this with sudo (needs to write to /etc/fstab and /etc/systemd/system)." >&2
  exit 1
fi

TARGET_USER="${POSITIONAL[0]:-${SUDO_USER:-$(id -un)}}"

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

# Pin each drive to a stable mount point by UUID (rather than relying on
# whatever /media/nur/<label> path the desktop automounter assigns) and
# make sure it's actually mounted before we point Immich's storage at it.
ensure_mount() {
  local uuid="$1" mountpoint="$2" fstype="$3" options="$4"
  mkdir -p "$mountpoint"
  if ! grep -qs "^UUID=$uuid[[:space:]]" /etc/fstab; then
    echo "UUID=$uuid $mountpoint $fstype $options 0 0" >> /etc/fstab
    systemctl daemon-reload
  fi
  if ! mountpoint -q "$mountpoint"; then
    mount "$mountpoint"
  fi
  if ! mountpoint -q "$mountpoint"; then
    echo "Failed to mount UUID=$uuid at $mountpoint. Is the drive connected?" >&2
    exit 1
  fi
}

TARGET_UID="$(id -u "$TARGET_USER")"
TARGET_GID="$(id -g "$TARGET_USER")"

ensure_mount "$SSD_UUID" "$SSD_MOUNT" auto "nofail,x-systemd.device-timeout=10"
ensure_mount "$HDD_UUID" "$HDD_MOUNT" auto "uid=$TARGET_UID,gid=$TARGET_GID,nofail,x-systemd.device-timeout=10"

# Postgres requires its data directory be owned exactly by its own internal
# uid (999 in the immich-postgres image); that only works on a real POSIX
# filesystem, not NTFS/exFAT where ownership is a single fixed mount option
# applied to everything.
SSD_FSTYPE="$(findmnt -no FSTYPE "$SSD_MOUNT")"
if [[ "$SSD_FSTYPE" != ext4 && "$SSD_FSTYPE" != ext3 && "$SSD_FSTYPE" != xfs && "$SSD_FSTYPE" != btrfs ]]; then
  echo "Warning: $SSD_MOUNT is $SSD_FSTYPE, not a native Linux filesystem." >&2
  echo "  Postgres needs real per-file ownership for its data dir; reformat this drive (e.g. mkfs.ext4)." >&2
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

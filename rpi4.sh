#!/bin/bash
set -e

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() {
  cat >&2 <<EOF
Usage: $0 --ssd-uuid=<UUID> --hdd-uuid=<UUID>

  --ssd-uuid  UUID of the drive for Immich's Postgres DB (lsblk -no UUID /dev/sdX)
  --hdd-uuid  UUID of the drive for Immich's photo/video library

Passed through to rpi4/install-service.sh, which mounts them by UUID at
stable paths instead of relying on /media/nur/<label> automount paths.
EOF
  exit 1
}

ssd_uuid=""
hdd_uuid=""
for arg in "$@"; do
  case "$arg" in
    --ssd-uuid=*) ssd_uuid="${arg#*=}" ;;
    --hdd-uuid=*) hdd_uuid="${arg#*=}" ;;
    -h|--help) usage ;;
    *) usage ;;
  esac
done
[[ -n "$ssd_uuid" && -n "$hdd_uuid" ]] || usage

_have() {
  command -v "$1" >/dev/null 2>&1
}

sudo apt update -y && sudo apt full-upgrade -y
sudo rpi-eeprom-update -a

# Reboot


if ! _have docker; then
    curl -fsSL https://get.docker.com -o get-docker.sh
    sudo sh get-docker.sh
    sudo usermod -aG docker $USER
fi

if ! _have tailscale; then
    curl -fsSL https://tailscale.com/install.sh | sh
    sudo tailscale up
fi
# always re-apply: harmless if already set, but must not be skipped just
# because tailscale was already installed by a prior run
sudo tailscale set --operator="$USER"

# Immich (server + redis + db; ML runs remotely on fractal, see rpi4/.env)
sudo "$script_dir/rpi4/install-service.sh" "--ssd-uuid=$ssd_uuid" "--hdd-uuid=$hdd_uuid" "$USER"

# Add key and repo for syncthing
sudo mkdir -p /etc/apt/keyrings
sudo curl -L -o /etc/apt/keyrings/syncthing-archive-keyring.gpg \
  https://syncthing.net/release-key.gpg

echo "deb [signed-by=/etc/apt/keyrings/syncthing-archive-keyring.gpg] \
https://apt.syncthing.net/ syncthing stable-v2" | \
  sudo tee /etc/apt/sources.list.d/syncthing.list

# Install
sudo apt update
sudo apt install -y syncthing

# Obsidian's synced folder lives on the HDD (mounted at /mnt/Axagon by
# install-service.sh above); don't let syncthing start until it's there.
sudo mkdir -p "/etc/systemd/system/syncthing@$(whoami).service.d"
sudo cp "$script_dir/rpi4/syncthing-mount.conf" "/etc/systemd/system/syncthing@$(whoami).service.d/mount.conf"
sudo systemctl daemon-reload

sudo systemctl enable syncthing@$(whoami).service
sudo systemctl start syncthing@$(whoami).service
sudo systemctl status syncthing@$(whoami).service

# Expose a port on current device to configure syncthing via UI.
ssh -L 8385:127.0.0.1:8384 nur@rpi

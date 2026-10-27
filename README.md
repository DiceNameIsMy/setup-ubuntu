# setup-ubuntu

Scripts to provision a fresh Ubuntu desktop: base packages, zsh + oh-my-zsh,
apt repos (Brave, VS Code, Docker, NVIDIA container toolkit, GitHub CLI),
GNOME desktop config, and dev tooling (uv, Codex, Tailscale, Obsidian,
whisrs).

## Usage

```sh
./setup.sh
```

Idempotent — safe to re-run.

## Immich updates

Both Immich stacks keep `IMMICH_VERSION=v3` in their `.env` files. Their
startup services pull images before starting Compose, with a ten-minute
pull timeout and fallback to cached images if the registry is unavailable.

The `install-service.sh` scripts also install and enable a weekly restart
service and timer for their host. Every Sunday between 04:00 and 04:30 local
time, the timer restarts the main service, whose startup step pulls images.
Missed runs are caught up when the timer next starts. An intentionally
stopped stack is left alone. The Pi's main service retains its storage
mount guards. Restarting briefly takes the stack and its Tailscale endpoint
offline, including while images are pulled; a failed pull uses cached images.

Inspect schedules with `systemctl list-timers 'immich*-update.timer'` and
logs with `journalctl -u immich-update.service` on the Pi or
`journalctl -u immich-ml-update.service` on fractal. Reinstall the service
units to apply repository changes to a host; updating these files alone
does not change installed services. PostgreSQL and Valkey retain their
explicit image pins. Automatic updates do not take a backup; keep the
separate backup timer enabled and review release notes for required
Compose changes.

Run a single step instead of the whole thing by naming its function
(works for anything defined in `setup.sh` or `desktop.sh`, since the
latter is sourced by the former):

```sh
./setup.sh install_apt_packages
./setup.sh install_codex
./setup.sh configure_desktop
./setup.sh list          # show every available function
```

## Browser tooling for Codex

```sh
./setup.sh install_browser_skills
# From the target project directory:
bash ~/.agents/skills/browser-use/setup.sh
```

The desktop setup installs Codex using the official standalone installer and
copies the browser-use skill into `~/.agents/skills/browser-use`. Browser setup
registers Codex by default. It preserves support for explicitly selecting other
existing clients, but provisioning no longer installs Claude Code, its skills,
or its statusline. Existing Claude installations are not uninstalled.

Browser profiles resolve relative to the project directory. Exclude
`.codex/browser-profile` and `.playwright-mcp/` from Git. Desktop browser setup
uses a visible browser. The shared source remains in `claude/browser-use/` for
compatibility; this directory name does not install Claude.

## Raspberry Pi: Codex and headless operation

The full `rpi4.sh` setup also runs these targeted tasks, which can be run
separately without changing disks, mounts, Immich, or Syncthing:

```sh
bash rpi4/setup-codex.sh
bash rpi4/configure-headless.sh
```

Run as the normal Pi user, not root. Codex setup installs the CLI and browser
skill, installs system Chromium for ARM64, and registers Playwright in headless
mode. It prompts for device authentication if necessary, enables user lingering,
and installs `codex-remote.service` to start remote control on boot without a
desktop login. Finally it prints a short-lived phone pairing code. Use
`--no-pair` when rerunning setup without generating a code. This does not install
an automatic-update timer.

Headless configuration disables Bluetooth (and hciuart when present), changes
the boot target to `multi-user.target`, and stops/disables the display manager.
It ends the graphical session immediately. Ethernet, Wi-Fi settings, SSH,
Tailscale, Docker, and storage services are left intact. No reboot is required.
To restore the Pi desktop: `sudo systemctl set-default graphical.target` then
`sudo systemctl enable --now lightdm.service`. To restore Bluetooth:
`sudo systemctl enable --now bluetooth.service` (and hciuart if previously used).

Verify:

```sh
systemctl --user status codex-remote.service
codex mcp get playwright
systemctl get-default
systemctl is-active lightdm.service bluetooth.service
```

## Host setup and backups

Keep this checkout at a stable path: installed systemd units refer to it.
Track source `.service` and `.timer` files; installers render host-specific
copies. Keep credentials in ignored `.env` files.

On the Pi, copy `rpi4/.env.example` to `rpi4/.env`, set a strong database
password, and confirm storage paths. Identify the SSD and HDD UUIDs with
`lsblk -f`, then provision the Pi:

```sh
./rpi4.sh --ssd-uuid=<SSD_UUID> --hdd-uuid=<HDD_UUID>
```

This upgrades packages, installs services, and configures mounts. The script
ends with an SSH tunnel for Syncthing; close it when finished. Ensure the
library and database directories exist on the mounted drives before startup.
After Docker group membership changes, log out and back in. To reinstall only
Immich units and mount configuration:

```sh
sudo ./rpi4/install-service.sh --ssd-uuid=<SSD_UUID> --hdd-uuid=<HDD_UUID> "$USER"
```

On fractal, run desktop setup, confirm Docker GPU support and Tailscale login,
and copy `fractal/.env.example` to `fractal/.env`. Then install the ML service:

```sh
sudo ./fractal/install-service.sh "$USER"
```

Configure the fractal ML endpoint in Immich Administration > Settings.
`rpi4/run.sh` is a compatibility shortcut for `sudo systemctl start immich.service`.

For backups, review the non-secret host and path settings in
`fractal/backup.env`. The normal user needs passwordless SSH to the Pi,
permission to read its library and run Docker there, and local write access to
`BACKUP_ROOT`. Install `rsync`, `gzip`, and `libnotify-bin`, then run:

```sh
./fractal/backup.sh
./fractal/install-backup-service.sh
systemctl --user list-timers immich-backup.timer
journalctl --user -u immich-backup.service
```

The timer runs monthly. Enable `loginctl enable-linger "$USER"` if it should
run while logged out. This is a mirror of the remote Immich library plus a
fresh database dump, not a backup of all `/data`; deleted remote files are
removed from the mirror on the next successful sync.

Verify a completed backup with:

```sh
./fractal/verify-restore.sh
```

Open `http://localhost:2284` and inspect albums and photos. The check uses a
unique Compose project, a temporary database volume, and a read-only backup
library. ML is disabled during verification. Uploads and other actions that
write to the library are expected to fail. Press Enter to remove the temporary
stack and volume. If cleanup fails, the script preserves its temporary
configuration and reports its location. Keep the image versions in
`fractal/verify-compose.yml` aligned with `rpi4/docker-compose.yml`.

## Repository checks

Desktop and Pi setup install ShellCheck and ripgrep; Docker Compose is installed
with Docker. On existing hosts, install the new check dependencies with
`sudo apt install shellcheck ripgrep`. Then run:

```sh
./scripts/check.sh
```

This checks Bash syntax, runs ShellCheck, and validates all three Compose
configurations using dummy environment values. It does not start containers
or execute provisioning scripts. `.shellcheckrc` disables SC2016 because the
setup scripts intentionally write literal variable references into shell config
files; other ShellCheck checks remain enabled.

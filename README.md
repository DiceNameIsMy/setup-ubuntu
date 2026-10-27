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

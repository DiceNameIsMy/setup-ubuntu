# setup-ubuntu

Scripts to provision a fresh Ubuntu desktop: base packages, zsh + oh-my-zsh,
apt repos (Brave, VS Code, Docker, NVIDIA container toolkit, GitHub CLI),
GNOME desktop config, and dev tooling (uv, Claude Code, Tailscale, Obsidian,
whisrs).

Also clones and installs a Claude Code statusline
([DiceNameIsMy/statusline](https://github.com/DiceNameIsMy/statusline)) showing
token usage, model, effort level, and git branch.

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
./setup.sh configure_desktop
./setup.sh list          # show every available function
```

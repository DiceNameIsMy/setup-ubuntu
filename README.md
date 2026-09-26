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

## Browser tooling for Claude Code and Codex

Install the shared browser-use skill for both clients:

```sh
./setup.sh install_browser_skills
```

This copies the skill to `~/.claude/skills/browser-use` and
`~/.agents/skills/browser-use` (Codex's
[user skill directory](https://developers.openai.com/codex/skills)). The full
setup also installs both copies. Codex itself must already be installed.
The existing `install_claude_browser_skill` task remains available, alongside
`install_codex_browser_skill`.

From your target project's root, install the browser and register Playwright MCP
with all installed clients:

```sh
bash ~/.agents/skills/browser-use/setup.sh
```

Use `BROWSER_CLIENT=claude`, `codex`, or `both` to select clients explicitly.
Registration is user-wide; restart the clients afterward. Each uses a separate
persistent profile in the project (`.claude/browser-profile` or
`.codex/browser-profile`) so both can run simultaneously. Exclude these profiles
and `.playwright-mcp/` from version control.

Verify with `claude mcp list` and/or `codex mcp list`, then navigate and take a
snapshot in a new session. Codex registration uses its documented
[MCP CLI](https://developers.openai.com/codex/mcp).

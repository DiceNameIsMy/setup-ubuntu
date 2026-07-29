#!/bin/bash
# Idempotent setup for the Playwright MCP browser-automation server.
# Safe to re-run. Registers the server ONCE at user scope (available in every
# project, no per-project restart needed), but points it at a profile dir
# given as a RELATIVE path. The playwright-mcp subprocess inherits its cwd
# from whichever project directory the Claude Code session was launched in,
# so the relative path resolves to a different, isolated profile directory
# per project automatically — one global registration, per-project sessions.
set -euo pipefail

NODE_VERSION=20
PROJECT_DIR="${PROJECT_DIR:-$PWD}"
PROFILE_REL="${BROWSER_PROFILE_REL:-.claude/browser-profile}"

# nvm refuses to activate ANY Node version -- including its own auto-use
# triggered just by sourcing nvm.sh -- while ~/.npmrc has a `prefix` or
# `globalconfig` setting. This repo's own configure_npm_global_prefix (in
# packages.sh) sets exactly that (npm config set prefix "$HOME/.local", so
# `npm i -g` doesn't need sudo), so every machine provisioned by this repo
# hits it. Hide the file for the nvm/npm calls below -- which would otherwise
# also honor that prefix and install @playwright/mcp into ~/.local instead of
# the nvm Node tree -- rather than deleting the setting, which is there
# deliberately for the system npm's global installs (e.g. @immich/cli).
# Self-heals if a previous run crashed mid-hide.
NPMRC="$HOME/.npmrc"
NPMRC_HIDDEN_PATH="$HOME/.npmrc.browser-use-skill-bak"
if [ -f "$NPMRC_HIDDEN_PATH" ] && [ ! -f "$NPMRC" ]; then
  mv "$NPMRC_HIDDEN_PATH" "$NPMRC"
fi
NPMRC_HIDDEN=0
if [ -f "$NPMRC" ] && grep -qE '^(prefix|globalconfig) *=' "$NPMRC"; then
  mv "$NPMRC" "$NPMRC_HIDDEN_PATH"
  NPMRC_HIDDEN=1
fi
_restore_npmrc() {
  if [ "$NPMRC_HIDDEN" = 1 ] && [ -f "$NPMRC_HIDDEN_PATH" ]; then
    mv "$NPMRC_HIDDEN_PATH" "$NPMRC"
  fi
}
trap _restore_npmrc EXIT

# 1. nvm + Node 20 (system Node is frequently < 20; @playwright/mcp refuses to start below it)
if [ ! -s "$HOME/.nvm/nvm.sh" ]; then
  curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh | bash
fi

# The nvm installer appends a plain `\. "$NVM_DIR/nvm.sh"` (no args) to the
# shell rc file(s), which defaults to auto-running `nvm use default` on every
# new shell. Once a default alias exists (below), that trips the same
# ~/.npmrc prefix/globalconfig check as above -- but on *every terminal
# opened from now on*, not just this script -- because sourcing happens
# before this script's own hide/restore window exists. `--no-use` skips the
# auto-switch; costless here since interactive shells use the system
# node/npm and this skill only ever invokes nvm's node by absolute path.
_ensure_nvm_no_use() {
  local rc="$1"
  [ -f "$rc" ] || return 0
  grep -Fq '$NVM_DIR/nvm.sh" --no-use' "$rc" && return 0
  grep -Fq '$NVM_DIR/nvm.sh"  # This loads nvm' "$rc" || return 0
  sed -i 's|\$NVM_DIR/nvm\.sh"  # This loads nvm|$NVM_DIR/nvm.sh" --no-use  # This loads nvm|' "$rc"
}
_ensure_nvm_no_use "$HOME/.bashrc"
_ensure_nvm_no_use "$HOME/.zshrc"

export NVM_DIR="$HOME/.nvm"
# shellcheck source=/dev/null
. "$NVM_DIR/nvm.sh"
# `nvm which` resolves an already-installed version purely locally; `nvm
# install` hits the network to look up the latest patch release even when a
# matching version is already installed. Try the cheap path first — this is
# most of the difference between a multi-second and a sub-second re-run.
NODE_BIN="$(nvm which "$NODE_VERSION" 2>/dev/null || true)"
if [ -z "$NODE_BIN" ]; then
  nvm install "$NODE_VERSION" >/dev/null
  nvm alias default "$NODE_VERSION" >/dev/null
  NODE_BIN="$(nvm which "$NODE_VERSION")"
fi
NODE_DIR="$(dirname "$NODE_BIN")"
echo "Node: $NODE_BIN ($("$NODE_BIN" --version))"

# 2. @playwright/mcp installed globally under Node 20 (npx re-execs via PATH and picks up
#    the system Node otherwise — see Gotchas in SKILL.md). A filesystem check is enough and
#    skips spawning npm (whose own startup cost dwarfs the check itself).
[ -e "$NODE_DIR/../lib/node_modules/@playwright/mcp" ] || \
  "$NODE_DIR/npm" install -g @playwright/mcp@latest
echo "playwright-mcp: $NODE_DIR/playwright-mcp"

# 3. Chromium binary (the MCP server defaults to the "chrome-for-testing" channel, a
#    separate download from Playwright's own bundled Chromium)
"$NODE_DIR/node" "$NODE_DIR/playwright-mcp" install-browser chrome-for-testing

# npmrc no longer needed hidden -- nothing past this point touches npm.
_restore_npmrc
trap - EXIT
NPMRC_HIDDEN=0

# 4. Per-project profile dir for THIS project, created now so it exists even before
#    the server's first launch here.
mkdir -p "$PROJECT_DIR/$PROFILE_REL"
echo "Profile dir (this project): $PROJECT_DIR/$PROFILE_REL"

# 5. Register the server once, at user scope, with a RELATIVE --user-data-dir.
#    Re-registering is harmless (claude mcp add overwrites); skip if already present
#    and correctly pointed at a relative path to avoid needless churn.
CURRENT_ARGS="$(claude mcp get playwright 2>/dev/null | grep '^  Args:' || true)"
if echo "$CURRENT_ARGS" | grep -q -- "--user-data-dir=$PROFILE_REL\$"; then
  echo "playwright already registered at user scope with relative profile dir; skipping re-add."
else
  claude mcp remove playwright -s user >/dev/null 2>&1 || true
  claude mcp add playwright -s user -- "$NODE_BIN" "$NODE_DIR/playwright-mcp" \
    --browser=chromium "--user-data-dir=$PROFILE_REL"
  echo "Registered playwright MCP server at user scope (relative profile: $PROFILE_REL)."
fi

echo
echo "Done. If this is the first time the playwright server was registered in this"
echo "Claude Code installation, restart Claude Code (or reconnect MCP servers) once"
echo "to load the tools. After that, running this skill in any other project needs"
echo "no further setup or restart — each project gets its own isolated browser profile"
echo "at <project>/$PROFILE_REL automatically."
echo "Verify with: claude mcp list"

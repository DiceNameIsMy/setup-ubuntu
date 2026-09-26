#!/bin/bash
# Idempotent setup for the Playwright MCP browser-automation server.
# Shared by Claude Code and Codex. Relative profiles resolve against the MCP
# subprocess's working directory, with separate defaults for each client.
set -euo pipefail

NODE_VERSION=20
PROJECT_DIR="${PROJECT_DIR:-$PWD}"
BROWSER_CLIENT="${BROWSER_CLIENT:-auto}"
CLIENTS=()
case "$BROWSER_CLIENT" in
  auto)
    for client in claude codex; do
      if command -v "$client" >/dev/null 2>&1; then CLIENTS+=("$client"); fi
    done
    ;;
  claude|codex) CLIENTS=("$BROWSER_CLIENT") ;;
  both) CLIENTS=(claude codex) ;;
  *) echo "BROWSER_CLIENT must be auto, claude, codex, or both" >&2; exit 1 ;;
esac
if [ "${#CLIENTS[@]}" -eq 0 ]; then
  echo "Install Claude Code or Codex before running browser setup." >&2
  exit 1
fi
for client in "${CLIENTS[@]}"; do
  command -v "$client" >/dev/null 2>&1 || {
    echo "Required client is not installed: $client" >&2; exit 1;
  }
done
if [[ "${BROWSER_PROFILE_REL:-}" = /* ]]; then
  echo "BROWSER_PROFILE_REL must be relative to the project directory." >&2
  exit 1
fi

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

# 4. Register at user scope for each installed (or explicitly selected) client.
# Keep Claude's existing profile; Codex gets its own to avoid browser locks when
# both clients are running in the same project.
for client in "${CLIENTS[@]}"; do
  PROFILE_REL="${BROWSER_PROFILE_REL:-.$client/browser-profile}"
  mkdir -p "$PROJECT_DIR/$PROFILE_REL"
  echo "$client profile (this project): $PROJECT_DIR/$PROFILE_REL"

  if [ "$client" = claude ]; then
    CURRENT="$(claude mcp get playwright 2>/dev/null || true)"
    if ! { grep -Fqx "  Command: $NODE_BIN" <<< "$CURRENT" &&
           grep -Fqx "  Args: $NODE_DIR/playwright-mcp --browser=chromium --user-data-dir=$PROFILE_REL" <<< "$CURRENT" &&
           grep -q 'Scope: User' <<< "$CURRENT"; }; then
      claude mcp remove playwright -s user >/dev/null 2>&1 || true
      claude mcp add playwright -s user -- "$NODE_BIN" "$NODE_DIR/playwright-mcp" \
        --browser=chromium "--user-data-dir=$PROFILE_REL"
    fi
  else
    # Codex add replaces the named entry, retaining unrelated config settings.
    codex mcp add playwright -- "$NODE_BIN" "$NODE_DIR/playwright-mcp" \
      --browser=chromium "--user-data-dir=$PROFILE_REL"
  fi
  echo "Registered playwright for $client. Verify with: $client mcp list"
done

echo
echo "Done. Restart each configured client (or reconnect MCP servers) to load changes."
echo "Profiles resolve relative to the MCP server's working directory at launch."

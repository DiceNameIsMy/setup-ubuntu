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

# 1. nvm + Node 20 (system Node is frequently < 20; @playwright/mcp refuses to start below it)
if [ ! -s "$HOME/.nvm/nvm.sh" ]; then
  curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh | bash
fi
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

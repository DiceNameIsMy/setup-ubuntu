#!/usr/bin/env bash
# Targeted Pi setup: safe to run without reprovisioning storage or Immich.
set -euo pipefail
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$script_dir/codex.sh"

install_codex
install_browser_skills
# Use Debian's ARM64 Chromium; Chrome for Testing has no Linux ARM64 build.
sudo apt-get install -y chromium
BROWSER_CLIENT=codex BROWSER_HEADLESS=1 BROWSER_EXECUTABLE_PATH=/usr/bin/chromium \
  bash "$HOME/.agents/skills/browser-use/setup.sh"
enable_codex_remote_control
if [[ "${1:-}" != --no-pair ]]; then
  codex remote-control pair
fi

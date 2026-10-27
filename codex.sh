#!/usr/bin/env bash
# Shared Codex installation and optional remote access. Sourced by setup.sh
# and rpi4/setup-codex.sh.
codex_setup_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

install_codex() {
  export PATH="$HOME/.local/bin:$PATH"
  if ! command -v codex >/dev/null 2>&1; then
    curl -fsSL https://chatgpt.com/codex/install.sh | sh
  fi
}

install_browser_skills() {
  install_codex_browser_skill
}

install_codex_browser_skill() {
  mkdir -p "$HOME/.agents/skills/browser-use"
  cp "$codex_setup_dir/claude/browser-use/SKILL.md" "$codex_setup_dir/claude/browser-use/setup.sh" \
    "$HOME/.agents/skills/browser-use/"
}

enable_codex_remote_control() {
  local codex_bin
  codex_bin="$(command -v codex)"
  if ! "$codex_bin" login status; then
    "$codex_bin" login --device-auth
  fi
  mkdir -p "$HOME/.config/systemd/user"
  cat > "$HOME/.config/systemd/user/codex-remote.service" <<EOF
[Unit]
Description=Codex remote control

[Service]
Type=oneshot
RemainAfterExit=yes
Environment="PATH=$HOME/.local/bin:/usr/local/bin:/usr/bin:/bin"
ExecStart="$codex_bin" remote-control start
ExecStop="$codex_bin" remote-control stop
TimeoutStartSec=120

[Install]
WantedBy=default.target
EOF
  sudo loginctl enable-linger "$(id -un)"
  systemctl --user daemon-reload
  systemctl --user enable --now codex-remote.service
}

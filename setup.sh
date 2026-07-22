#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$script_dir/zsh.sh"
source "$script_dir/repos.sh"
source "$script_dir/packages.sh"
source "$script_dir/desktop.sh"

_log() {
  printf '\n[%s] %s\n' "$(date +'%H:%M:%S')" "$*"
}

_require_sudo() {
  # `sudo -v` doesn't honor NOPASSWD sudoers rules under sudo-rs (the Rust
  # rewrite, default on newer Ubuntu) when there's no tty -- it still forces
  # an interactive auth prompt. Running a real no-op command does the same
  # credential-priming job and works under both classic sudo and sudo-rs.
  sudo true
}

_have() {
  command -v "$1" >/dev/null 2>&1
}

_append_if_missing() {
  local line="$1"
  local file="$2"
  grep -Fqx "$line" "$file" 2>/dev/null || echo "$line" >> "$file"
}

_clone_or_update() {
  local repo="$1"
  local dir="$2"

  if [[ -d "$dir/.git" ]]; then
    git -C "$dir" pull --ff-only
  elif [[ -e "$dir" ]]; then
    _log "Skipping $dir because it exists but is not a git repo"
  else
    git clone "$repo" "$dir"
  fi
}

_have_nvidia_gpu() {
  lspci -nn 2>/dev/null | grep -qi nvidia
}

setup_git() {
  # already configured -- nothing to do, and don't re-prompt on every re-run
  if git config --global user.name >/dev/null 2>&1 && git config --global user.email >/dev/null 2>&1; then
    return
  fi

  local name="" email="" input
  # if `gh auth login` has already been run, use it as a source of defaults
  if _have gh && gh auth status >/dev/null 2>&1; then
    name="$(gh api user --jq '.name // empty' 2>/dev/null || true)"
    email="$(gh api user --jq '.email // empty' 2>/dev/null || true)"
  fi

  read -r -p "Your name${name:+ [$name]}: " input
  name="${input:-$name}"
  read -r -p "Your email${email:+ [$email]}: " input
  email="${input:-$email}"

  [[ -n "$name" ]] && git config --global user.name "$name"
  [[ -n "$email" ]] && git config --global user.email "$email"
}

print_followups() {
  echo "Manual follow-ups:"
  echo "  - Restart session or run: exec zsh"
  echo "  - Re-login to apply docker group membership"
  echo "  - Log out and back in so newly installed GNOME extensions activate"
  echo "  - Next: install gaze (curl -fsSL https://gaze.gundulabs.com/install.sh | sh)"
  echo "  - Run: gh auth login (can generate and upload an SSH key for you)"
}

_list_tasks() {
  # functions prefixed with `_` are internal helpers, not standalone steps
  declare -F | awk '{print $3}' | grep -v '^main$' | grep -v '^_' | sort
}

main() {
  _require_sudo

  _log "Base packages"
  install_base_packages
  configure_npm_global_prefix

  _append_if_missing 'export PATH="$HOME/.local/bin:$PATH"' "$HOME/.bashrc"

  _log "Grant ownership to the /data folder"
  grant_data_ownership

  _log "Zsh"
  set_default_shell_zsh
  install_oh_my_zsh
  configure_zsh_plugins

  _log "Repositories"
  setup_brave_repo
  setup_vscode_repo
  setup_github_cli_repo
  setup_docker_repo
  setup_nvidia_container_toolkit_repo

  _log "APT refresh"
  sudo apt update

  _log "Install packages"
  install_apt_packages
  init_wine_prefix

  _log "uv"
  install_uv

  _log "Claude Code"
  install_claude_code

  _log "Tailscale"
  install_tailscale

  _log "Obsidian"
  install_obsidian

  _log "Docker group"
  configure_docker_group

  _log "NVIDIA container toolkit"
  configure_nvidia_docker

  _log "Desktop"
  configure_desktop

  _log "Upgrade and clean up packages"
  upgrade_apt_packages

  setup_git

  _log "Done"
  print_followups
}

if [[ "${1:-}" == "list" ]]; then
  _list_tasks
elif [[ "${1:-}" ]] && declare -F "$1" >/dev/null; then
  "$@"
else
  main "$@"
fi

#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$script_dir/desktop.sh"

log() {
  printf '\n[%s] %s\n' "$(date +'%H:%M:%S')" "$*"
}

require_sudo() {
  # `sudo -v` doesn't honor NOPASSWD sudoers rules under sudo-rs (the Rust
  # rewrite, default on newer Ubuntu) when there's no tty -- it still forces
  # an interactive auth prompt. Running a real no-op command does the same
  # credential-priming job and works under both classic sudo and sudo-rs.
  sudo true
}

have() {
  command -v "$1" >/dev/null 2>&1
}

append_if_missing() {
  local line="$1"
  local file="$2"
  grep -Fqx "$line" "$file" 2>/dev/null || echo "$line" >> "$file"
}

clone_or_update() {
  local repo="$1"
  local dir="$2"

  if [[ -d "$dir/.git" ]]; then
    git -C "$dir" pull --ff-only
  elif [[ -e "$dir" ]]; then
    log "Skipping $dir because it exists but is not a git repo"
  else
    git clone "$repo" "$dir"
  fi
}

set_default_shell_zsh() {
  local zsh_path
  zsh_path="$(command -v zsh)"
  # only run chsh (which needs a password) if zsh isn't already the default
  if [[ "$(getent passwd "$USER" | cut -d: -f7)" != "$zsh_path" ]]; then
    chsh -s "$zsh_path"
    log "Default shell changed to zsh; relogin required"
  fi
}

install_oh_my_zsh() {
  if [[ ! -d "$HOME/.oh-my-zsh" ]]; then
    # non-interactive install: leave the shell switch to set_default_shell_zsh
    # and don't let it overwrite the .zshrc we configure afterward
    RUNZSH=no CHSH=no KEEP_ZSHRC=yes sh -c \
      "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
  fi
}

configure_zsh_plugins() {
  local z_custom zshrc
  z_custom="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"
  zshrc="$HOME/.zshrc"

  clone_or_update https://github.com/rupa/z.git "$z_custom/plugins/z"
  clone_or_update https://github.com/zsh-users/zsh-autosuggestions "$z_custom/plugins/zsh-autosuggestions"
  clone_or_update https://github.com/zsh-users/zsh-syntax-highlighting "$z_custom/plugins/zsh-syntax-highlighting"

  if [[ ! -f "$zshrc" ]]; then
    cp "$HOME/.oh-my-zsh/templates/zshrc.zsh-template" "$zshrc"
  fi

  # make sure a custom or stripped-down .zshrc still ends up with the env var,
  # theme, and plugins we need, without duplicating anything already there
  grep -q '^export ZSH=' "$zshrc" || sed -i '1i export ZSH="$HOME/.oh-my-zsh"' "$zshrc"

  if grep -q '^ZSH_THEME=' "$zshrc"; then
    sed -i 's/^ZSH_THEME=.*/ZSH_THEME="robbyrussell"/' "$zshrc"
  else
    sed -i '/^export ZSH=/a ZSH_THEME="robbyrussell"' "$zshrc"
  fi

  # drop any existing plugins list (however it's formatted) so ours replaces it cleanly
  grep -q '^plugins=(' "$zshrc" && sed -i '/^plugins=(/,/)/d' "$zshrc"
  cat >> "$zshrc" <<'EOF'

plugins=(
  git
  z
  zsh-autosuggestions
  zsh-syntax-highlighting
)
EOF

  append_if_missing 'source $ZSH/oh-my-zsh.sh' "$zshrc"
  append_if_missing '. "$HOME/.local/bin/env"' "$zshrc"
}

fetch_apt_keyring() {
  local key_url="$1" keyring_path="$2"
  sudo install -d -m 0755 "$(dirname "$keyring_path")"
  # skip re-fetching a key that's already trusted locally
  if [[ ! -f "$keyring_path" ]]; then
    curl -fsSL "$key_url" | sudo gpg --dearmor -o "$keyring_path"
  fi
}

setup_brave_repo() {
  sudo rm -f /etc/apt/sources.list.d/brave-browser-release.list
  fetch_apt_keyring https://brave-browser-apt-release.s3.brave.com/brave-browser-archive-keyring.gpg \
    /etc/apt/keyrings/brave-browser-archive-keyring.gpg

  sudo tee /etc/apt/sources.list.d/brave-browser-release.sources >/dev/null <<EOF
Types: deb
URIs: https://brave-browser-apt-release.s3.brave.com
Suites: stable
Components: main
Architectures: amd64 arm64
Signed-By: /etc/apt/keyrings/brave-browser-archive-keyring.gpg
EOF
}

setup_vscode_repo() {
  fetch_apt_keyring https://packages.microsoft.com/keys/microsoft.asc /etc/apt/keyrings/packages.microsoft.gpg

  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/packages.microsoft.gpg] https://packages.microsoft.com/repos/code stable main" \
    | sudo tee /etc/apt/sources.list.d/vscode.list > /dev/null
}

setup_docker_repo() {
  fetch_apt_keyring https://download.docker.com/linux/ubuntu/gpg /etc/apt/keyrings/docker.gpg

  # target whatever Ubuntu release this machine actually runs, not a hardcoded one
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$UBUNTU_CODENAME") stable" \
    | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
}

have_nvidia_gpu() {
  lspci -nn 2>/dev/null | grep -qi nvidia
}

setup_nvidia_container_toolkit_repo() {
  have_nvidia_gpu || return

  fetch_apt_keyring https://nvidia.github.io/libnvidia-container/gpgkey \
    /etc/apt/keyrings/nvidia-container-toolkit.gpg

  curl -fsSL https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list \
    | sed 's#deb https://#deb [signed-by=/etc/apt/keyrings/nvidia-container-toolkit.gpg] https://#' \
    | sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list > /dev/null
}

configure_nvidia_docker() {
  have_nvidia_gpu || return

  sudo apt install -y nvidia-container-toolkit
  sudo nvidia-ctk runtime configure --runtime=docker
  sudo systemctl restart docker
}

setup_git() {
  local configure_git=n
  read -r -p "Would you like to configure git with an SSH key? [y/n]:" configure_git
  if [[ "$configure_git" != "y" ]]; then
    return
  fi

  local name="" email=""
  read -r -p "Your name: " name
  read -r -p "Your email: " email

  ssh-keygen -t ed25519 -C "$email"
  log "An ssh key has been generated."

  git config --global user.name "$name"
  git config --global user.email "$email"
}

install_base_packages() {
  sudo dpkg --add-architecture i386
  sudo apt update
  sudo apt install -y \
    ubuntu-drivers-common ca-certificates curl wget \
    gnupg gnupg2 software-properties-common apt-transport-https \
    git jq zsh python3 npm nodejs libturbojpeg0 \
    gnome-shell-extension-manager gnome-browser-connector
  sudo snap install telegram-desktop
}

grant_data_ownership() {
  if [[ -d /data ]]; then
    sudo chown -R "$USER:$USER" /data
  fi
}

install_apt_packages() {
  sudo apt install -y \
    brave-browser code \
    wine64 wine32 winbind wine64-preloader \
    docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin \
    ddcutil qbittorrent

  npm i -g @immich/cli
}

init_wine_prefix() {
  have wine || return
  [[ -d "$HOME/.wine" ]] && return

  # skip the Mono/Gecko installer popups; nothing here needs .NET or embedded HTML
  WINEDLLOVERRIDES="mscoree=;mshtml=" wineboot --init >/dev/null 2>&1
}

install_uv() {
  have uv || curl -LsSf https://astral.sh/uv/install.sh | sh
}

install_claude_code() {
  if ! have claude && ! have claude-code; then
    curl -fsSL https://claude.ai/install.sh | bash
  fi
}

install_tailscale() {
  if ! have tailscale; then
    curl -fsSL https://tailscale.com/install.sh | sh
    sudo tailscale set --operator="$USER"
  fi
}

install_obsidian() {
  snap install obsidian --classic
}

configure_docker_group() {
  getent group docker >/dev/null || sudo groupadd docker
  # only add the user (and flag the relogin requirement) if not already a member
  if ! id -nG "$USER" | grep -qw docker; then
    sudo usermod -aG docker "$USER"
    log "Added $USER to docker group; relogin required"
  fi
}

print_followups() {
  echo "Manual follow-ups:"
  echo "  - Restart session or run: exec zsh"
  echo "  - Re-login to apply docker group membership"
  echo "  - Log out and back in so newly installed GNOME extensions activate"
  echo "  - Next: install gaze (curl -fsSL https://gaze.gundulabs.com/install.sh | sh)"
}

main() {
  require_sudo

  log "Base packages"
  install_base_packages

  append_if_missing 'export PATH="$HOME/.local/bin:$PATH"' "$HOME/.bashrc"

  log "Grant ownership to the /data folder"
  grant_data_ownership

  log "Zsh"
  set_default_shell_zsh
  install_oh_my_zsh
  configure_zsh_plugins

  log "Repositories"
  setup_brave_repo
  setup_vscode_repo
  setup_docker_repo
  setup_nvidia_container_toolkit_repo

  log "APT refresh"
  sudo apt update

  log "Install packages"
  install_apt_packages
  init_wine_prefix

  log "uv"
  install_uv

  log "Claude Code"
  install_claude_code

  log "Tailscale"
  install_tailscale

  log "Obsidian"
  install_obsidian

  log "Docker group"
  configure_docker_group

  log "NVIDIA container toolkit"
  configure_nvidia_docker

  log "Desktop"
  configure_desktop

  setup_git

  log "Done"
  print_followups
}

main "$@"


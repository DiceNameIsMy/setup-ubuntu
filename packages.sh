#!/usr/bin/env bash
# Package installation beyond the OS base image: apt packages, snaps, wine,
# uv, Claude Code, Tailscale, Obsidian, whisrs, and docker group/runtime wiring.
# Sourced from setup.sh; relies on _log()/_have()/_have_nvidia_gpu() from there.
set -euo pipefail

upgrade_apt_packages() {
  sudo apt upgrade -y
  sudo apt autoremove -y
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

configure_npm_global_prefix() {
  # apt's npm defaults its global prefix to root-owned /usr, so `npm i -g`
  # needs sudo -- point it at ~/.local instead, which is already on PATH
  npm config set prefix "$HOME/.local"
}

install_apt_packages() {
  sudo apt install -y \
    brave-browser code gh \
    wine64 wine32 winbind wine64-preloader \
    docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin \
    ddcutil qbittorrent

  npm i -g @immich/cli
}

init_wine_prefix() {
  _have wine || return
  [[ -d "$HOME/.wine" ]] && return

  # skip the Mono/Gecko installer popups; nothing here needs .NET or embedded HTML
  WINEDLLOVERRIDES="mscoree=;mshtml=" wineboot --init >/dev/null 2>&1
}

install_uv() {
  _have uv || curl -LsSf https://astral.sh/uv/install.sh | sh
}

install_claude_code() {
  if ! _have claude && ! _have claude-code; then
    curl -fsSL https://claude.ai/install.sh | bash
  fi
}

install_tailscale() {
  if ! _have tailscale; then
    curl -fsSL https://tailscale.com/install.sh | sh
    sudo tailscale set --operator="$USER"
  fi
}

install_obsidian() {
  snap install obsidian --classic
}

install_whisrs() {
  if ! _have whisrs; then
    WHISRS_MINIMAL=1 curl -sSL https://y0sif.github.io/whisrs/install.sh | bash
  fi

  mkdir -p "$HOME/.config/whisrs"
  # only seed the template and run onboarding on first install -- don't
  # clobber an already-configured backend/API key on re-runs
  if [[ ! -f "$HOME/.config/whisrs/config.toml" ]]; then
    cp "$script_dir/whisrs-config.toml" "$HOME/.config/whisrs/config.toml"
    whisrs setup
  fi
}

configure_docker_group() {
  getent group docker >/dev/null || sudo groupadd docker
  # only add the user (and flag the relogin requirement) if not already a member
  if ! id -nG "$USER" | grep -qw docker; then
    sudo usermod -aG docker "$USER"
    _log "Added $USER to docker group; relogin required"
  fi
}

configure_nvidia_docker() {
  _have_nvidia_gpu || return 0

  sudo apt install -y nvidia-container-toolkit
  sudo nvidia-ctk runtime configure --runtime=docker
  sudo systemctl restart docker
}

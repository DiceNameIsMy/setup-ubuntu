#!/usr/bin/env bash
# apt repository setup: keyrings + sources.list.d entries for Brave, VS Code,
# GitHub CLI, Docker, and (conditionally) the NVIDIA container toolkit.
# Sourced from setup.sh; relies on _have_nvidia_gpu() from there.
set -euo pipefail

_fetch_apt_keyring() {
  local key_url="$1" keyring_path="$2"
  sudo install -d -m 0755 "$(dirname "$keyring_path")"
  # skip re-fetching a key that's already trusted locally
  if [[ ! -f "$keyring_path" ]]; then
    curl -fsSL "$key_url" | sudo gpg --dearmor -o "$keyring_path"
  fi
}

setup_brave_repo() {
  sudo rm -f /etc/apt/sources.list.d/brave-browser-release.list
  _fetch_apt_keyring https://brave-browser-apt-release.s3.brave.com/brave-browser-archive-keyring.gpg \
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
  _fetch_apt_keyring https://packages.microsoft.com/keys/microsoft.asc /etc/apt/keyrings/packages.microsoft.gpg

  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/packages.microsoft.gpg] https://packages.microsoft.com/repos/code stable main" \
    | sudo tee /etc/apt/sources.list.d/vscode.list > /dev/null
}

setup_github_cli_repo() {
  local keyring_path=/etc/apt/keyrings/githubcli-archive-keyring.gpg
  sudo install -d -m 0755 /etc/apt/keyrings
  # the upstream key is already in binary keyring format, so unlike the other
  # repos here it's written straight through rather than piped through gpg --dearmor
  if [[ ! -f "$keyring_path" ]]; then
    curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | sudo tee "$keyring_path" > /dev/null
    sudo chmod go+r "$keyring_path"
  fi

  echo "deb [arch=$(dpkg --print-architecture) signed-by=$keyring_path] https://cli.github.com/packages stable main" \
    | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null
}

setup_docker_repo() {
  _fetch_apt_keyring https://download.docker.com/linux/ubuntu/gpg /etc/apt/keyrings/docker.gpg

  # target whatever Ubuntu release this machine actually runs, not a hardcoded one
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$UBUNTU_CODENAME") stable" \
    | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
}

setup_nvidia_container_toolkit_repo() {
  _have_nvidia_gpu || return

  _fetch_apt_keyring https://nvidia.github.io/libnvidia-container/gpgkey \
    /etc/apt/keyrings/nvidia-container-toolkit.gpg

  curl -fsSL https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list \
    | sed 's#deb https://#deb [signed-by=/etc/apt/keyrings/nvidia-container-toolkit.gpg] https://#' \
    | sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list > /dev/null
}

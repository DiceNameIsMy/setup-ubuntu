#!/usr/bin/env bash
# zsh setup: default shell, oh-my-zsh install, plugins.
# Sourced from setup.sh; relies on _log()/_clone_or_update()/_append_if_missing() from there.
set -euo pipefail

set_default_shell_zsh() {
  local zsh_path
  zsh_path="$(command -v zsh)"
  # only run chsh (which needs a password) if zsh isn't already the default
  if [[ "$(getent passwd "$USER" | cut -d: -f7)" != "$zsh_path" ]]; then
    chsh -s "$zsh_path"
    _log "Default shell changed to zsh; relogin required"
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

  # z ships as a built-in oh-my-zsh plugin (the zsh-z rewrite) -- don't clone rupa/z
  # into custom/plugins/z, it lacks a z.plugin.zsh entry file and shadows the working one
  _clone_or_update https://github.com/zsh-users/zsh-autosuggestions "$z_custom/plugins/zsh-autosuggestions"
  _clone_or_update https://github.com/zsh-users/zsh-syntax-highlighting "$z_custom/plugins/zsh-syntax-highlighting"

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
  # also drop any existing oh-my-zsh source line so it always ends up after the
  # plugins array below -- oh-my-zsh reads $plugins at source time, so if the
  # array comes after (as it does in the stock template), every plugin silently
  # fails to load
  sed -i '\#^source \$ZSH/oh-my-zsh\.sh$#d' "$zshrc"
  # the deletions above leave trailing blank lines behind; collapse them so
  # repeated runs don't pile up more blank lines before each re-append
  printf '%s\n' "$(cat "$zshrc")" > "$zshrc"
  cat >> "$zshrc" <<'EOF'

plugins=(
  git
  z
  zsh-autosuggestions
  zsh-syntax-highlighting
)

source $ZSH/oh-my-zsh.sh
EOF

  _append_if_missing '. "$HOME/.local/bin/env"' "$zshrc"
}

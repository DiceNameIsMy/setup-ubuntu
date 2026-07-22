#!/usr/bin/env bash
# GNOME desktop configuration: extensions, extension settings, keyboard layouts.
# Sourced from setup.sh; relies on _log() from there.
set -euo pipefail

_gnome_shell_major_version() {
  gnome-shell --version | grep -oP '(?<=GNOME Shell )\d+'
}

_install_gnome_extension() {
  # Returns 0 if the extension is already visible to the running shell
  # (safe to enable now), 1 if it was just installed but won't be
  # recognized until the next login, 2 if there's no build for this
  # shell version.
  local uuid="$1"
  gnome-extensions list 2>/dev/null | grep -qx "$uuid" && return 0

  local shell_version info download_path tmp_zip
  shell_version="$(_gnome_shell_major_version)"
  info="$(curl -fsSL "https://extensions.gnome.org/extension-info/?uuid=${uuid}&shell_version=${shell_version}")"
  download_path="$(jq -r '.download_url // empty' <<<"$info")"
  if [[ -z "$download_path" ]]; then
    _log "No build of $uuid for GNOME Shell $shell_version; skipping"
    return 2
  fi

  tmp_zip="$(mktemp --suffix=.shell-extension.zip)"
  curl -fsSL "https://extensions.gnome.org${download_path}" -o "$tmp_zip"
  gnome-extensions install --force "$tmp_zip"
  rm -f "$tmp_zip"
  return 1
}

configure_dash_to_dock() {
  # position/opacity/sizing preferences; deliberately excludes
  # preferred-monitor(-by-connector), which is tied to this machine's
  # specific monitor setup and wouldn't make sense elsewhere
  dconf load /org/gnome/shell/extensions/dash-to-dock/ <<'EOF'
[/]
background-opacity=0.80
dash-max-icon-size=48
dock-position='BOTTOM'
height-fraction=0.90
intellihide=false
intellihide-mode='FOCUS_APPLICATION_WINDOWS'
show-trash=false
EOF
}

configure_gsnap() {
  dconf load /org/gnome/shell/extensions/gsnap/ <<'EOF'
[/]
show-icon=false
show-tabs=false
use-modifier=true
EOF
}

configure_brightness_ddcutil() {
  # sleep-multiplier is tuned way above the 1.0 default because these
  # monitors' DDC/CI is unreliable at normal polling speed
  dconf load /org/gnome/shell/extensions/display-brightness-ddcutil/ <<'EOF'
[/]
ddcutil-sleep-multiplier=56.0
hide-system-indicator=false
only-all-slider=true
show-all-slider=true
show-osd=true
show-value-label=true
step-change-keyboard=10.0
EOF
}

configure_gnome_extensions() {
  local uuid rc needs_relogin=false
  for uuid in \
    display-brightness-ddcutil@themightydeity.github.com \
    dash-to-dock@micxgx.gmail.com \
    gSnap@micahosborne
  do
    rc=0
    _install_gnome_extension "$uuid" || rc=$?
    if [[ "$rc" -eq 0 ]]; then
      gnome-extensions enable "$uuid"
    elif [[ "$rc" -eq 1 ]]; then
      needs_relogin=true
    fi
  done

  configure_dash_to_dock
  configure_gsnap
  configure_brightness_ddcutil

  if [[ "$needs_relogin" == true ]]; then
    _log "New GNOME extensions installed; relogin required, then re-run setup.sh to enable them"
  fi
}

configure_keyboard_layout() {
  gsettings set org.gnome.desktop.input-sources sources \
    "[('xkb', 'us'), ('xkb', 'cz+qwerty'), ('xkb', 'ru')]"
  gsettings set org.gnome.desktop.input-sources xkb-options "['grp_led:scroll']"
}

configure_appearance() {
  gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark'
  gsettings set org.gnome.desktop.interface gtk-theme 'Yaru-olive-dark'
  gsettings set org.gnome.desktop.interface icon-theme 'Yaru-olive-dark'
}

configure_desktop() {
  configure_gnome_extensions
  configure_keyboard_layout
  configure_appearance
}

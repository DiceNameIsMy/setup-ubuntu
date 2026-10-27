#!/usr/bin/env bash
# Apply only the requested headless/radio changes; keep network/storage intact.
set -euo pipefail
for unit in bluetooth.service hciuart.service; do
  if [[ "$(systemctl show "$unit" -p LoadState --value)" != not-found ]]; then
    sudo systemctl disable --now "$unit"
  fi
done
sudo systemctl set-default multi-user.target
# Stop just the display manager, not the target or the user's other services.
display_manager="display-manager.service"
if [[ "$(systemctl show "$display_manager" -p LoadState --value)" = not-found ]] &&
   [[ "$(systemctl show lightdm.service -p LoadState --value)" != not-found ]]; then
  display_manager="lightdm.service"
fi
if [[ "$(systemctl show "$display_manager" -p LoadState --value)" != not-found ]]; then
  display_manager="$(systemctl show "$display_manager" -p Id --value)"
  sudo systemctl stop "$display_manager"
  sudo systemctl disable "$display_manager"
fi

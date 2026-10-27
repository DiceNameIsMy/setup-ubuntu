#!/usr/bin/env bash
# Compatibility entry point: systemd owns startup and the Tailscale endpoint.
set -euo pipefail
sudo systemctl start immich.service

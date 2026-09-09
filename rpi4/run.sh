#!/bin/bash

set -e

docker compose up -d

# tailscale is installed on windows. To call it .exe must be added.
tailscale serve --bg 127.0.0.1:2283

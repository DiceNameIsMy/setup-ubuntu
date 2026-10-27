#!/usr/bin/env bash
# Static checks only: never starts containers or runs provisioning scripts.
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT"
mapfile -t scripts < <(rg --files --hidden -g '*.sh' -g '!.git')
for script in "${scripts[@]}"; do
  bash -n "$script"
done
echo "Bash syntax passed."
if ! command -v shellcheck >/dev/null; then
  echo "ShellCheck is required; install it with: sudo apt install shellcheck" >&2
  exit 1
fi
shellcheck -x "${scripts[@]}"
TMP_CHECK=$(mktemp -d)
trap 'rm -rf "$TMP_CHECK"' EXIT
for host in rpi4 fractal; do
  cp "$host/.env.example" "$TMP_CHECK/.env"
  if [[ -f "$host/hwaccel.ml.yml" ]]; then
    cp "$host/hwaccel.ml.yml" "$TMP_CHECK/hwaccel.ml.yml"
  fi
  docker compose --project-directory "$TMP_CHECK" \
    --env-file "$TMP_CHECK/.env" -f "$ROOT/$host/docker-compose.yml" config --quiet
done
cp rpi4/.env.example "$TMP_CHECK/.env"
docker compose --project-directory "$TMP_CHECK" --env-file "$TMP_CHECK/.env" \
  -f "$ROOT/fractal/verify-compose.yml" config --quiet
echo "ShellCheck and Compose validation passed."

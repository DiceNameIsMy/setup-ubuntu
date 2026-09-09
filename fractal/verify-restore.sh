#!/usr/bin/env bash
# Spins up a throwaway Immich stack (server + redis + a fresh postgres)
# from the current backup so you can eyeball it in the browser, then tears
# everything temporary back down on your say-so. The real backup.env-scoped
# library and db dump are never modified (library is mounted read-only).
#
# Reuses fractal's already-running immich-machine-learning container (it's
# stateless) instead of starting a second one, since both compose files
# declare `name: immich` and land on the same Docker network.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=backup.env
source "$SCRIPT_DIR/backup.env"

LIBRARY_DIR="$BACKUP_ROOT/library"
DB_DUMP="$BACKUP_ROOT/db/immich-db.sql.gz"
VERIFY_DIR="$BACKUP_ROOT/verify"
COMPOSE_SRC="$SCRIPT_DIR/../rpi4/docker-compose.yml"

if [[ ! -d "$LIBRARY_DIR" || ! -f "$DB_DUMP" ]]; then
  echo "No backup found at $BACKUP_ROOT (run ./backup.sh first)." >&2
  exit 1
fi

compose() {
  docker compose --project-directory "$VERIFY_DIR" \
    -f "$VERIFY_DIR/docker-compose.yml" --env-file "$VERIFY_DIR/.env" "$@"
}

cleanup() {
  echo "Tearing down the verify stack..."
  compose down || true
  rm -rf "$VERIFY_DIR"
  echo "Done. $LIBRARY_DIR and $BACKUP_ROOT/db were not modified."
}
trap cleanup EXIT

mkdir -p "$VERIFY_DIR"
sed 's|${UPLOAD_LOCATION}:/data|${UPLOAD_LOCATION}:/data:ro|' \
  "$COMPOSE_SRC" >"$VERIFY_DIR/docker-compose.yml"

cat >"$VERIFY_DIR/.env" <<EOF
UPLOAD_LOCATION=$LIBRARY_DIR
DB_DATA_LOCATION=$VERIFY_DIR/db-data
DB_PASSWORD=verify
DB_USERNAME=$REMOTE_DB_USER
DB_DATABASE_NAME=immich
IMMICH_VERSION=v3
TZ=Europe/Prague
IMMICH_MACHINE_LEARNING_URL=http://immich_machine_learning:3003
EOF

echo "Starting temporary database..."
compose up -d database

echo -n "Waiting for database to be ready"
for _ in $(seq 1 30); do
  if docker exec immich_postgres pg_isready -U "$REMOTE_DB_USER" &>/dev/null; then
    echo " ready."
    break
  fi
  echo -n "."
  sleep 2
done

echo "Restoring DB dump into the temporary database..."
gunzip -c "$DB_DUMP" | docker exec -i immich_postgres psql -U "$REMOTE_DB_USER"

echo "Starting the rest of the stack..."
compose up -d

cat <<EOF

Immich verify stack is up: http://localhost:2283
Log in with your normal account and check albums/photos/search.

EOF
read -r -p "Press Enter (or any key + Enter) to tear it all down... " _

# cleanup() runs automatically via the EXIT trap.

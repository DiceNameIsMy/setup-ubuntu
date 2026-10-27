#!/usr/bin/env bash
# Spins up a throwaway Immich stack (server + redis + a fresh postgres)
# from the current backup so you can eyeball it in the browser, then tears
# everything temporary back down on your say-so. The real backup.env-scoped
# library and db dump are never modified (library is mounted read-only).
#
# Uses an isolated Compose project, a temporary database volume, and port 2284.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/backup.env"

LIBRARY_DIR="$BACKUP_ROOT/library"
DB_DUMP="$BACKUP_ROOT/db/immich-db.sql.gz"
COMPOSE_SRC="$SCRIPT_DIR/verify-compose.yml"

if [[ ! -d "$LIBRARY_DIR" || ! -f "$DB_DUMP" ]]; then
  echo "No backup found at $BACKUP_ROOT (run ./backup.sh first)." >&2
  exit 1
fi

VERIFY_DIR=$(mktemp -d "${TMPDIR:-/tmp}/immich-verify.XXXXXX")
PROJECT_NAME="immich-verify-$(basename "$VERIFY_DIR" | tr '[:upper:]' '[:lower:]')"
RESTORE_ADMIN="verify_admin_${RANDOM}_${RANDOM}"

compose() {
  docker compose -p "$PROJECT_NAME" --project-directory "$SCRIPT_DIR" \
    -f "$COMPOSE_SRC" --env-file "$VERIFY_DIR/.env" "$@"
}

cleanup() {
  echo "Tearing down the verify stack..."
  if ! compose down --volumes; then
    echo "Cleanup failed; temporary configuration remains at $VERIFY_DIR." >&2
    return 1
  fi
  rm -rf "$VERIFY_DIR"
  echo "Done. $LIBRARY_DIR and $BACKUP_ROOT/db were not modified."
}
trap cleanup EXIT

cat >"$VERIFY_DIR/.env" <<EOF
UPLOAD_LOCATION=$LIBRARY_DIR
DB_PASSWORD=verify
DB_USERNAME=$REMOTE_DB_USER
RESTORE_ADMIN=$RESTORE_ADMIN
DB_DATABASE_NAME=immich
IMMICH_VERSION=v3
TZ=Europe/Prague
IMMICH_MACHINE_LEARNING_ENABLED=false
EOF

echo "Starting temporary database..."
compose up -d database

echo -n "Waiting for database to be ready"
ready=false
for _ in {1..30}; do
  if compose exec -T database pg_isready -U "$RESTORE_ADMIN" &>/dev/null; then
    echo " ready."
    ready=true
    break
  fi
  echo -n "."
  sleep 2
done

if [[ "$ready" != true ]]; then
  echo "Temporary database did not become ready." >&2
  exit 1
fi

echo "Restoring DB dump into the temporary database..."
gunzip -c "$DB_DUMP" | compose exec -T database psql -d template1 -v ON_ERROR_STOP=1 -U "$RESTORE_ADMIN"

# The dump restores the production role password; use a temporary password here.
compose exec -T database psql -d template1 -v ON_ERROR_STOP=1 \
  -U "$RESTORE_ADMIN" -v restore_user="$REMOTE_DB_USER" <<'SQL'
ALTER ROLE :"restore_user" WITH PASSWORD 'verify';
SQL

echo "Starting the rest of the stack..."
compose up -d

cat <<EOF

Immich verify stack is up: http://localhost:2284
Log in with your normal account and check albums/photos/search.

EOF
read -r -p "Press Enter (or any key + Enter) to tear it all down... " _

# cleanup() runs automatically via the EXIT trap.

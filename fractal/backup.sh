#!/usr/bin/env bash
# Pulls rpi4's Immich library + a fresh DB dump into a single local mirror
# on fractal (see backup.env for the source/destination config).
#
# Safe to interrupt and rerun: rsync resumes an in-progress transfer rather
# than restarting it, the DB dump is written via a temp file + atomic
# rename, and a flock prevents two runs from overlapping.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=backup.env
source "$SCRIPT_DIR/backup.env"

LIBRARY_DIR="$BACKUP_ROOT/library"
DB_DIR="$BACKUP_ROOT/db"
DB_DUMP="$DB_DIR/immich-db.sql.gz"
LOG_FILE="$BACKUP_ROOT/backup.log"
LAST_SYNC_FILE="$BACKUP_ROOT/last-sync.txt"
LOCK_FILE="$BACKUP_ROOT/backup.lock"
SSH_OPTS=(-o BatchMode=yes -o ConnectTimeout=10)

mkdir -p "$LIBRARY_DIR" "$DB_DIR"

exec 200>"$LOCK_FILE"
if ! flock -n 200; then
  echo "$(date -Is) another backup run is already in progress, exiting" >>"$LOG_FILE"
  exit 0
fi

exec > >(tee -a "$LOG_FILE") 2>&1
echo "===== $(date -Is) backup starting ====="

notify() {
  notify-send "$@" || true
}

on_error() {
  local exit_code=$?
  echo "===== $(date -Is) backup FAILED (exit $exit_code) ====="
  notify -u critical "Immich backup failed" "$(tail -n 20 "$LOG_FILE")"
  exit "$exit_code"
}
trap on_error ERR

notify "Immich backup starting" "Syncing library from $REMOTE_HOST"

rsync -a --delete --partial -e "ssh ${SSH_OPTS[*]}" \
  "$REMOTE_HOST:$REMOTE_UPLOAD_LOCATION/" "$LIBRARY_DIR/"

ssh "${SSH_OPTS[@]}" "$REMOTE_HOST" \
  "docker exec $REMOTE_DB_CONTAINER pg_dumpall --clean --if-exists -U $REMOTE_DB_USER" \
  | gzip >"$DB_DUMP.tmp"
mv "$DB_DUMP.tmp" "$DB_DUMP"

FILE_COUNT=$(find "$LIBRARY_DIR" -type f | wc -l)
TOTAL_SIZE=$(du -sh "$LIBRARY_DIR" | cut -f1)
echo "$(date -Is) OK files=$FILE_COUNT size=$TOTAL_SIZE" >"$LAST_SYNC_FILE"

echo "===== $(date -Is) backup completed OK ====="
notify "Immich backup completed" "$FILE_COUNT files, $TOTAL_SIZE"

#!/bin/sh
set -eu
umask 077

script_dir="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
backup_dir="${MERCADITO_BACKUP_DIR:-$script_dir/backups}"
mkdir -p "$backup_dir"
timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
temporary="$backup_dir/.marketplace_um-$timestamp.dump.tmp"
destination="$backup_dir/marketplace_um-$timestamp.dump"

cleanup() { rm -f "$temporary"; }
trap cleanup EXIT HUP INT TERM

docker compose --project-directory "$script_dir" exec -T postgres \
  pg_dump --username postgres --dbname marketplace_um --format=custom \
  --compress=6 --no-owner --no-privileges > "$temporary"

docker compose --project-directory "$script_dir" exec -T postgres \
  pg_restore --list < "$temporary" > /dev/null

test -s "$temporary"
mv "$temporary" "$destination"
trap - EXIT HUP INT TERM
echo "$destination"

#!/bin/sh
set -eu
umask 077

script_dir="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
backup_dir="${MERCADITO_BACKUP_DIR:-$script_dir/backups}"
mkdir -p "$backup_dir"
timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
temporary="$backup_dir/.marketplace_um-$timestamp.dump.tmp"
destination="$backup_dir/marketplace_um-$timestamp.dump"
retention_days="${MERCADITO_BACKUP_RETENTION_DAYS:-14}"

case "$retention_days" in
  ''|*[!0-9]*) echo 'MERCADITO_BACKUP_RETENTION_DAYS debe ser un entero positivo.' >&2; exit 2 ;;
esac
if [ "$retention_days" -lt 1 ] || [ "$retention_days" -gt 3650 ]; then
  echo 'MERCADITO_BACKUP_RETENTION_DAYS debe estar entre 1 y 3650.' >&2
  exit 2
fi

cleanup() { rm -f "$temporary"; }
trap cleanup EXIT HUP INT TERM

docker compose --project-directory "$script_dir" exec -T postgres \
  pg_dump --username postgres --dbname marketplace_um --format=custom \
  --compress=6 --no-owner > "$temporary"

docker compose --project-directory "$script_dir" exec -T postgres \
  pg_restore --list < "$temporary" > /dev/null

test -s "$temporary"
mv "$temporary" "$destination"
trap - EXIT HUP INT TERM

# Sólo elimina dumps creados por este script, dentro del directorio validado.
# El respaldo recién creado ya fue verificado antes de aplicar retención.
find "$backup_dir" -maxdepth 1 -type f -name 'marketplace_um-*.dump' \
  -mtime "+$retention_days" -delete

if [ -n "${MERCADITO_BACKUP_MIRROR_DIR:-}" ]; then
  mirror_dir="$MERCADITO_BACKUP_MIRROR_DIR"
  mkdir -p "$mirror_dir"
  chmod 700 "$mirror_dir"
  cp "$destination" "$mirror_dir/"
  chmod 600 "$mirror_dir/$(basename "$destination")"
fi

echo "$destination"

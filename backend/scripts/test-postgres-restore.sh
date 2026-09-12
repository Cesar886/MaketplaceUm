#!/usr/bin/env bash
set -euo pipefail
umask 077

backend_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
dump_path="${1:-}"
if [[ -z "$dump_path" || ! -s "$dump_path" ]]; then
  echo 'Uso: test-postgres-restore.sh RUTA_DUMP' >&2
  exit 2
fi

secrets_dir="$backend_dir/infra/postgres/secrets"
for secret in postgres_app_password postgres_migrator_password; do
  if [[ ! -s "$secrets_dir/$secret" ]]; then
    echo "Falta el secreto $secrets_dir/$secret" >&2
    exit 1
  fi
done

database="marketplace_restore_test_$(date -u +%Y%m%d%H%M%S)_$$"
if [[ ! "$database" =~ ^[a-z0-9_]+$ ]]; then
  echo 'Nombre temporal inválido.' >&2
  exit 1
fi

cleanup() {
  docker exec marketplace-um-postgres-1 dropdb \
    --username postgres --if-exists --force "$database" >/dev/null 2>&1 || true
}
trap cleanup EXIT HUP INT TERM

docker exec marketplace-um-postgres-1 createdb \
  --username postgres --owner marketplace_migrator "$database"
docker exec marketplace-um-postgres-1 psql --username postgres --dbname "$database" \
  --set ON_ERROR_STOP=1 --command 'GRANT CONNECT ON DATABASE '"$database"' TO marketplace_app' \
  >/dev/null

migrator_password="$(tr -d '\r\n' < "$secrets_dir/postgres_migrator_password")"
PGPASSWORD="$migrator_password" pg_restore \
  --host 127.0.0.1 --username marketplace_migrator --dbname "$database" \
  --exit-on-error --no-owner "$dump_path"
unset migrator_password

app_password="$(tr -d '\r\n' < "$secrets_dir/postgres_app_password")"
verification="$(PGPASSWORD="$app_password" psql \
  --host 127.0.0.1 --username marketplace_app --dbname "$database" \
  --no-align --tuples-only --field-separator='|' --command \
  "SELECT (SELECT count(*) FROM sellers),
          (SELECT count(*) FROM products),
          (SELECT count(*) FROM messages),
          has_table_privilege(current_user, 'schema_migrations', 'SELECT'),
          has_table_privilege(current_user, 'schema_migrations', 'INSERT,UPDATE,DELETE')")"
unset app_password

IFS='|' read -r sellers products messages can_read_history can_write_history <<< "$verification"
if [[ ! "$sellers" =~ ^[0-9]+$ || ! "$products" =~ ^[0-9]+$ || ! "$messages" =~ ^[0-9]+$ ]]; then
  echo "Conteos restaurados inválidos: $verification" >&2
  exit 1
fi
if [[ "$can_read_history" != t || "$can_write_history" != f ]]; then
  echo "Privilegios restaurados inválidos: $verification" >&2
  exit 1
fi

printf 'Restauración verificada: sellers=%s products=%s messages=%s; historial protegido.\n' \
  "$sellers" "$products" "$messages"

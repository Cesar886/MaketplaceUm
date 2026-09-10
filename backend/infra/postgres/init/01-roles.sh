#!/bin/sh
set -eu

app_password="$(tr -d '\r\n' < /run/secrets/postgres_app_password)"
migrator_password="$(tr -d '\r\n' < /run/secrets/postgres_migrator_password)"

if [ "${#app_password}" -lt 32 ] || [ "${#migrator_password}" -lt 32 ]; then
  echo 'Las contraseñas app/migrator deben tener al menos 32 caracteres.' >&2
  exit 1
fi

psql --set ON_ERROR_STOP=1 \
  --username "$POSTGRES_USER" \
  --dbname "$POSTGRES_DB" \
  --set=app_password="$app_password" \
  --set=migrator_password="$migrator_password" <<'SQL'
SELECT format(
  'CREATE ROLE marketplace_migrator LOGIN PASSWORD %L NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION CONNECTION LIMIT 3',
  :'migrator_password'
) WHERE NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'marketplace_migrator') \gexec

SELECT format(
  'CREATE ROLE marketplace_app LOGIN PASSWORD %L NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION CONNECTION LIMIT 60',
  :'app_password'
) WHERE NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'marketplace_app') \gexec

REVOKE ALL ON DATABASE marketplace_um FROM PUBLIC;
GRANT CONNECT ON DATABASE marketplace_um TO marketplace_migrator, marketplace_app;
ALTER DATABASE marketplace_um OWNER TO marketplace_migrator;

REVOKE CREATE ON SCHEMA public FROM PUBLIC;
ALTER SCHEMA public OWNER TO marketplace_migrator;
GRANT USAGE ON SCHEMA public TO marketplace_app;

ALTER ROLE marketplace_migrator SET search_path = public, pg_catalog;
ALTER ROLE marketplace_app SET search_path = public, pg_catalog;
ALTER ROLE marketplace_app SET statement_timeout = '15s';
ALTER ROLE marketplace_app SET lock_timeout = '5s';
ALTER ROLE marketplace_app SET idle_in_transaction_session_timeout = '15s';

ALTER DEFAULT PRIVILEGES FOR ROLE marketplace_migrator IN SCHEMA public
  GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO marketplace_app;
ALTER DEFAULT PRIVILEGES FOR ROLE marketplace_migrator IN SCHEMA public
  GRANT USAGE, SELECT, UPDATE ON SEQUENCES TO marketplace_app;
SQL

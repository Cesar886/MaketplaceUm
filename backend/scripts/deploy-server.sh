#!/usr/bin/env bash
set -euo pipefail
umask 077

backend_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$backend_dir"

if [[ ! -f .env.migrator ]]; then
  echo 'Falta backend/.env.migrator (chmod 600) con DATABASE_URL del rol marketplace_migrator.' >&2
  exit 1
fi

npm install --omit=dev
npm run db:backup

set -a
# Archivo local del servidor, protegido por rsync y gitignore. Sólo contiene
# variables para este comando; PM2 continúa leyendo .env con el rol limitado.
source ./.env.migrator
set +a
NODE_ENV=production PG_RUN_MIGRATIONS=true npm run db:migrate
unset DATABASE_URL

pm2 restart ecosystem.config.js --update-env
pm2 save

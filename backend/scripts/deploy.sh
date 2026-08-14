#!/bin/bash
# Despliega el backend al servidor de producción vía rsync.
#
# Por qué existe: el 2026-08-04 un rsync manual sin exclusiones sobrescribió
# mercadito_um.db / .db-shm / .db-wal de producción con la copia local de
# desarrollo, borrando cuentas creadas directamente en el servidor (ver
# incidente documentado — confirmado por md5sum idéntico entre el .db local
# y el que quedó en el servidor tras el rsync). El .gitignore ya excluye
# estos archivos de git, pero rsync no usa .gitignore — necesita sus propias
# exclusiones explícitas.
#
# El mismo patrón volvió a pasar el 2026-08-05 con backend/.env: como está en
# .gitignore, nunca existe en el checkout local, así que --delete lo borraba
# del servidor en cada deploy (dejando SMTP_HOST/USER/PASS vacíos y el envío
# de códigos de verificación muerto). --exclude '.env' es la corrección.
set -euo pipefail

HOST="root@157.245.247.45"
REMOTE_DIR="/root/mercaditoUmBack/"
LOCAL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/"

rsync -avz --delete \
  --exclude '.env' \
  --exclude 'mercadito_um.db' \
  --exclude 'mercadito_um.db-shm' \
  --exclude 'mercadito_um.db-wal' \
  --exclude '*.bak' \
  --exclude 'node_modules' \
  --exclude 'uploads' \
  --exclude 'logs' \
  --exclude 'backups' \
  --exclude '*.test.js' \
  --exclude 'testUtils.js' \
  "$LOCAL_DIR" "$HOST:$REMOTE_DIR"

echo "Sincronizado. Recuerda correr 'npm install' en el servidor si cambiaron dependencias, luego 'pm2 restart mercadito-backend'."

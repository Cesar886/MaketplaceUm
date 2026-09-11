#!/usr/bin/env bash
set -euo pipefail

if [[ "${EUID}" -ne 0 ]]; then
  echo 'Este instalador debe ejecutarse como root.' >&2
  exit 1
fi

backend_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
install -m 0644 "$backend_dir/infra/postgres/systemd/marketplace-postgres-backup.service" \
  /etc/systemd/system/marketplace-postgres-backup.service
install -m 0644 "$backend_dir/infra/postgres/systemd/marketplace-postgres-backup.timer" \
  /etc/systemd/system/marketplace-postgres-backup.timer
systemctl daemon-reload
systemctl enable --now marketplace-postgres-backup.timer
systemctl list-timers marketplace-postgres-backup.timer --no-pager

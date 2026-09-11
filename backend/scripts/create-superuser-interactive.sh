#!/usr/bin/env bash
set -euo pipefail

if [[ ! -t 0 || ! -t 1 ]]; then
  echo 'Ejecuta este comando desde una terminal SSH interactiva.' >&2
  exit 1
fi

backend_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$backend_dir"

read -r -p 'Nuevo usuario administrativo: ' admin_create_user
read -r -s -p 'Contraseña larga y única (14-72 bytes): ' admin_create_password
printf '\n'
read -r -s -p 'Repite la contraseña: ' admin_create_password_confirmation
printf '\n'

cleanup() {
  unset admin_create_user admin_create_password admin_create_password_confirmation
  unset ADMIN_CREATE_USERNAME ADMIN_CREATE_PASSWORD
}
trap cleanup EXIT HUP INT TERM

if [[ "$admin_create_password" != "$admin_create_password_confirmation" ]]; then
  echo 'Las contraseñas no coinciden; no se creó ninguna cuenta.' >&2
  exit 1
fi

export ADMIN_CREATE_USERNAME="$admin_create_user"
export ADMIN_CREATE_PASSWORD="$admin_create_password"
unset admin_create_password_confirmation
npm run admin:create

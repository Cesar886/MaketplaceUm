#!/usr/bin/env bash

# Este archivo se carga desde deploy.sh. DATA_PATHS sigue siendo la única
# fuente de verdad: la misma lista alimenta los filtros de rsync y este guard.

deploy_path_is_protected() {
  local candidate="${1#./}"
  local pattern basename directory
  candidate="${candidate%/}"
  basename="${candidate##*/}"

  for pattern in "${DATA_PATHS[@]}"; do
    pattern="${pattern#./}"

    # Patrones con ruta completa (por ejemplo infra/.../*_password).
    if [[ "$candidate" == $pattern ]]; then
      return 0
    fi

    # Los patrones de rsync sin slash aplican al basename en cualquier nivel.
    if [[ "$pattern" != */* && "$basename" == $pattern ]]; then
      return 0
    fi

    # Una entrada "directorio/" protege ese componente en cualquier nivel.
    if [[ "$pattern" == */ && "$pattern" != */'*'* ]]; then
      directory="${pattern%/}"
      if [[ "/$candidate/" == *"/$directory/"* ]]; then
        return 0
      fi
    fi
  done
  return 1
}

deploy_find_protected_changes() {
  local output="$1"
  local line change candidate

  while IFS= read -r line; do
    # deploy.sh fuerza el formato `%i|%n`: ignoramos banners, estadísticas y
    # cualquier otra línea que no sea una entrada itemizada de rsync.
    [[ "$line" == *'|'* ]] || continue
    change="${line%%|*}"
    candidate="${line#*|}"
    if [[ "$change" != \*deleting* && "${#change}" -ne 11 ]]; then
      continue
    fi
    if deploy_path_is_protected "$candidate"; then
      printf '%s|%s\n' "$change" "$candidate"
    fi
  done <<< "$output"
}

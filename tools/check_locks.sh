#!/usr/bin/env bash
# Comprueba que los archivos BLOQUEADOS (LOCKED.md) no han cambiado sin permiso del usuario.
# Uso: tools/check_locks.sh            -> falla si alguno cambió
#      tools/check_locks.sh --update   -> SOLO con permiso expreso del usuario: anota el estado actual como aprobado
set -euo pipefail
cd "$(dirname "$0")/.."
FILES="lua/ge/extensions/earthRaid/startclock.lua lua/ge/extensions/earthRaid/loader.lua lua/ge/extensions/earthRaid/vhud.lua"
SUMS=tools/locks.sha256
if [ "${1:-}" = "--update" ]; then sha256sum $FILES > "$SUMS"; echo "bloqueos actualizados"; exit 0; fi
sha256sum -c "$SUMS" || { echo "ARCHIVO BLOQUEADO MODIFICADO: pide permiso al usuario (LOCKED.md) y verifica con OBS antes de --update"; exit 1; }
# Cámara del semáforo = la del juego (verificada el 28-nov con OBS contra Utah SS1)
S=lua/ge/extensions/earthRaid/startclock.lua
grep -q "f = f:normalized() \* -1" "$S" && grep -q "^M.FOV = 25" "$S" && grep -q "^M.DIST_M = 1.0" "$S" && grep -q "^M.SHIFT = 1 / 3" "$S" \
  || { echo "startclock.lua: la cámara ya no es la del juego"; exit 1; }
echo "bloqueos OK"

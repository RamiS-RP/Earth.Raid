#!/usr/bin/env sh
# Empaqueta el mod para BeamNG.drive: earth_raid.zip con las carpetas del mod EN LA RAÍZ del zip
# (lua/, ui/, art/, scripts/, settings/, earthRaid/). BeamNG no carga un zip con una carpeta dentro
# (p. ej. earth_raid/lua/...): el mod aparece en la lista pero no hace nada.
set -e
cd "$(dirname "$0")/.."
OUT="${1:-earth_raid.zip}"
rm -f "$OUT"
zip -r -q "$OUT" art earthRaid lua mod_info scripts settings ui beamngEarth_addon.json LICENSE -x '*.DS_Store' -x 'earthRaid/events/*'
echo "$OUT listo: cópialo tal cual (sin descomprimir) a <carpeta de usuario de BeamNG>/current/mods/"

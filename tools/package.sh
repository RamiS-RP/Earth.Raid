#!/usr/bin/env sh
# Empaqueta el mod para BeamNG.drive: raid-earth.zip con la raíz del mod (sin docs/ ni tools/).
set -e
cd "$(dirname "$0")/.."
rm -f raid-earth.zip
zip -r raid-earth.zip art earthRaid lua scripts settings ui beamngEarth_addon.json -x '*.DS_Store'
echo "raid-earth.zip listo: cópialo a <carpeta de usuario de BeamNG>/mods/"

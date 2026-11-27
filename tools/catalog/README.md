# Catálogo de Earth.Raid

El juego lee los eventos de:

1. `/earthRaid/index.json` (los que trae el mod).
2. Paquetes: cualquier carpeta con su `index.json` y `events/` dentro de `/earthRaid/packs/<paquete>/` (en el mod) o de
   `<carpeta de usuario>/settings/earthRaid/packs/<paquete>/`. Si dos paquetes traen el mismo `id`, gana el último
   (los del jugador pisan a los del mod).
3. Importación (menú → ⤓ Importar): `<carpeta de usuario>/settings/earthRaid/import/`. Una subcarpeta por evento con
   uno o varios archivos de ruta (KMZ, KML, GPX, GeoJSON u OSM XML), su logo (`logo.png`/`.jpg`) y, si se quiere,
   `event.json` con la ficha (`name`, `short`, `dates` "AAAA-MM-DD/AAAA-MM-DD", `country`, `city`, `region`,
   `championship`, `organizer`, `type`, `surface`, `link`, `source`, `description`); un archivo suelto también vale.
   `importer.lua` reconoce los nombres de los mapas de organizadores ("Special Stage - SS 2/5 …", "Liaison Route",
   "TC", "Flying Finish", "Stop Control", "Radio", "Jump", "Sand Bag"…) y los de una ruta propia (cada línea es un
   tramo; "Enlace", "Liaison" o "A -> B" = enlace; "Asistencia"/"Service" = parque). Lo convierte a un paquete en
   `settings/earthRaid/packs/imported/` solo cuando algo cambia.

## Construir un paquete

```
python build_catalog.py sources.json salida/ --name raid-earth-es
```

`sources.json` lista cada evento con sus datos (nombre, fechas, país, campeonato…) y el trazado: `file` (un KMZ, KML o
GPX local) o `url` (se descarga una vez, con caché en `.cache/`, respetando `robots.txt`). Copia `salida/` a una de
las carpetas de paquetes.

## De dónde salen los datos

- **Trazados**: solo los que el organizador publica para descargar (KMZ/KML/GPX del recorrido o del roadbook), o
  los que haga el propio jugador. No hay una fuente abierta con los tramos de todos los rallies.
- **rally-maps.com**: no tiene API ni exportación, y sus condiciones de uso no están publicadas; no se raspa.
  Si se quiere usar, hay que pedir permiso a su responsable.
- **El juego no descarga nada**: la Lua del juego solo tiene HTTP sin cifrar, así que los paquetes se distribuyen
  como archivos (con el mod o copiándolos a la carpeta de usuario).

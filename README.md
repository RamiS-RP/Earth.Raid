# Earth.Raid (Raid.Earth)

Rallies, raids y el Dakar de verdad en **BeamNG.drive**, sobre el mundo real de **BeamNG.Earth**: los mismos tramos, con sus controles horarios, sus enlaces y su señalización según el reglamento de la FIA, y un copiloto que canta las notas.

> Proyecto en desarrollo (alfa). Se buscan probadores y colaboradores: mira [Colaborar](#colaborar).

*English summary [below](#english).*

## Qué hace

- **Catálogo de eventos** cerca de donde estás, con radio configurable y filtros por país, tipo, categoría, superficie y estado (en curso, próximos, celebrados).
- **Tramo suelto o rally completo**: enlaces entre tramos con su tiempo asignado, controles horarios (TC) con tarjeta de tiempos, penalizaciones por retraso, asistencia y resultados.
- **Montaje estándar en todos los tramos**, el mismo en los dos sentidos (el tramo inverso usa los mismos objetos):
  - **TC y STOP:** aviso amarillo, cartel rojo y puesto de control a 150 m de la línea, con carpas a cada lado en doble sentido, mesa, silla, reloj LED para fichar, luz de noche y generador.
  - **Salida y meta:** carteles de los dos sentidos a ambos lados de los sensores, semáforo con reloj y cuenta atrás, líneas pintadas con spray de borde a borde y fin de zona.
  - **Zonas de seguridad:** aviso de meta lanzada a 100 m, tablillas 3-2-1, radio y médico.
  - **Ambiente:** vallas publicitarias, público y sonido.
  - **Regla fija:** nada en la calzada salvo conos en el eje.
- **Copiloto**: notas visuales y de voz con los copilotos del juego. Las curvas se vuelven a medir sobre la carretera real mientras conduces. Se puede ajustar la antelación, el tamaño y la opacidad, o activar notas prudentes.
- **Pantalla de rally**: cronómetro y progreso, notas, cuentarrevoluciones, fuerzas g, cuentakilómetros, volante y pedales, y sin minimapa.
- **Importar rutas** desde el menú (⤓ Importar):
  - **Formatos:** KMZ, KML, GPX, GeoJSON y OSM XML, con su logo, un enlace a la fuente y la ficha del evento.
  - **Reconocimiento automático:** tramos, pasadas, enlaces, controles, meta lanzada, STOP, radios, saltos y chicanes, por los nombres que usan los mapas de los organizadores.

## Requisitos

- BeamNG.drive 0.40 o posterior.
- BeamNG.Earth, con su nivel cargado. Raid.Earth usa su API de complementos: posición real, GPS, teletransporte y lugares.

## Instalar

1. Descarga el repositorio o ejecuta `tools/package.sh` para crear `raid-earth.zip`.
2. Cópialo a `<carpeta de usuario de BeamNG>/mods/` (o descomprímelo en `mods/unpacked/earth_raid/`).
3. Entra en BeamNG.Earth. **Ctrl+Mayús+G** abre el menú de Raid.Earth.

## Añadir un rally

Menú → **⤓ Importar** → **Abrir la carpeta**. Crea una carpeta por evento dentro de `settings/earthRaid/import/`:

```
settings/earthRaid/import/rally-islas-canarias/
  50RICv2.kmz              ← uno o varios archivos de ruta (KMZ, KML, GPX, GeoJSON, OSM)
  Sunday_Test_-_Ingenio.kmz
  logo.png                 ← opcional
  event.json               ← opcional: la ficha (también se edita desde el menú)
```

`event.json`:

```json
{
  "name": "Rally Islas Canarias – Rally of Spain",
  "dates": "2027-05-06/2027-05-09",
  "country": "es",
  "championship": "WRC",
  "organizer": "CD Todo Sport",
  "surface": "asphalt",
  "link": "https://rallyislascanarias.com/"
}
```

Lo que no rellenes se deduce del archivo: el nombre, los tramos y sus pasadas, los enlaces y el parque de asistencia. Para una ruta propia basta con dibujar las líneas en Google My Maps y exportar el KML. Cada línea es un tramo; las que se llaman «Enlace…» o «A -> B» son enlaces, y un punto llamado «Asistencia» marca el parque.

**Sobre los datos:** los recorridos pertenecen a sus organizadores. Importa solo lo que tengas derecho a usar (archivos publicados por el organizador para descargar, o rutas propias). Las carreteras, edificios y lugares que se ven en el juego vienen de BeamNG.Earth (OpenStreetMap, Overture, etc.) con sus licencias.

## Estructura

| Carpeta | Contenido |
|---|---|
| `lua/ge/extensions/earthRaid/` | La lógica: `main` (menú, catálogo, importación), `stage` (fases del tramo), `rally` (rally completo), `dressing` (montaje de objetos), `props` (objetos del juego), `pacenotes` (notas), `importer` (formatos de mapas), `startclock` (reloj LED), `settings`… |
| `ui/` | El menú (Vue) y la app del HUD. |
| `settings/ui_apps/layouts/` | La pantalla de rally. |
| `earthRaid/` | El catálogo que trae el mod (vacío: cada jugador importa sus rutas). |
| `art/sound/earthRaid/` | Sonidos de ambiente (sintéticos, se pueden cambiar). |
| `tools/catalog/` | Scripts para construir paquetes de eventos fuera del juego. |
| `docs/` | Normas del montaje y plan de trabajo. |

## Hoja de ruta

- **Búsqueda automática de rallies de todo el mundo** con la información pública disponible: calendarios, recorridos publicados por los organizadores y datos abiertos. Es la parte en la que más ayuda hace falta.
- **Mapas de rallies (rally-maps.com):** solo con el permiso de su responsable, que se pedirá antes de nada.
- **Más eventos:** raids y el Dakar, con navegación por roadbook.
- **Juego en línea:** cortes de carretera persistentes en BeamMP.Earth.
- **Más contenido:** voz en español y grabaciones reales de público.

## Licencia

Código bajo licencia [MIT](LICENSE). Los recorridos, logos y datos de cada rally pertenecen a sus organizadores y no se incluyen en el repositorio.

## Colaborar

Las incidencias y las propuestas son bienvenidas en *Issues*. Para enviar código:

1. Abre una incidencia contando qué quieres cambiar.
2. Sigue las [normas del montaje](docs/normas.md): son las que mantienen todos los tramos con la misma calidad.
3. Prueba en el juego. Revisa el registro (`beamng.log`) buscando avisos de `earthRaid`.

## English

**Raid.Earth** brings real rallies, raids and the Dakar to BeamNG.drive on top of the real-world map of BeamNG.Earth.

- **Stages and timing:** real stages with time controls, road sections, flying finish and STOP.
- **Signage:** FIA-style signage, the same layout in both directions of a stage.
- **Co-driver:** pacenotes measured on the real road.
- **Rally HUD:** a dedicated screen layout for stages.
- **Route importer:** KMZ, KML, GPX, GeoJSON and OSM, with a logo, a source link and event details.

Install it as a BeamNG mod (see above) and open it with **Ctrl+Shift+G** inside BeamNG.Earth. Contributors are welcome, especially for the worldwide automatic rally discovery from public data.

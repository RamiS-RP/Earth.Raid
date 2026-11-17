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

**Desde BeamNG.Earth (recomendado):** menú de pausa → BeamNG.Earth → **Add-ons** → *Add from GitHub* → `RamiroRP/earth.raid` → **Add**. Se instala el `earth_raid.zip` de la última release.

**Versiones:** la **estable** (rama `main`, release normal) es la que instala Add-ons y la que se recomienda a los jugadores. La **beta** (rama `beta`, *pre-release* `vX.Y.Z-beta.N`) es para desarrolladores y probadores: descárgala a mano desde Releases.

**Rallies incluidos:** 43 Rally Sierra Morena 2026, Rally Islas Canarias, Rally de Ourense y Rallye Cristian López 2026 (en `earthRaid/packs/`). Puedes añadir más desde el menú (⤓ Importar).

**A mano:**
1. Descarga `earth_raid.zip` de [Releases](https://github.com/RamiroRP/earth.raid/releases) (o créalo con `tools/package.sh`).
2. Cópialo **tal cual, sin descomprimir**, a `<carpeta de usuario de BeamNG>/current/mods/`.
   - El zip debe tener `lua/`, `ui/`, `scripts/`… en su raíz. Un zip con una carpeta dentro (p. ej. `raid-earth/lua/…`, el que da *Code → Download ZIP* de GitHub) **no funciona**: el mod sale en la lista pero no aparece el menú.
3. Entra en BeamNG.Earth. Raid.Earth tiene su propia pestaña en el menú de pausa (**Esc** → **Raid.Earth**), junto a BeamNG.Earth y BeamMP. Si quieres un atajo, asígnalo en Opciones → Controles → «Raid.Earth: open the events menu».
4. Ten **una sola copia**: si instalaste desde Add-ons (`earth_raid-1.zip`) y además a mano (`earth_raid.zip`), borra una. Dos copias a la vez se pisan.

## Mods recomendados (para una mejor experiencia)

No son obligatorios, pero con ellos el rally se vive mucho mejor. **Paso a paso:**

1. Entra en cada enlace de la tabla (es la web oficial de BeamNG).
2. Pulsa **Download** (Descargar). Se descarga un archivo `.zip`.
3. Copia ese `.zip` **tal cual, sin descomprimir**, a tu carpeta de mods: `Documentos\BeamNG.drive\<versión>\mods`
   (o abre el juego → menú principal → **Mods** → **Abrir carpeta de mods**).
4. Abre el juego. **Raid.Earth activa solo** los mods recomendados que encuentre descargados (si no quieres, apágalo en Raid.Earth → Ajustes → «Activar solos los mods recomendados descargados»).
5. Para comprobarlo: Raid.Earth → Ajustes → **Mods recomendados**: cada uno dice *activado*, *descargado* o *no instalado*.

| Mod | Para qué sirve |
|---|---|
| [Racing Line Mod](https://www.beamng.com/resources/racing-line-mod.39806/) | Dibuja la trazada ideal **dentro del tramo** (de la salida a la meta), en lugar de la línea azul del GPS. Fuera del tramo (hacia el control horario y hacia la salida) siempre se usa la línea azul del GPS del juego. Se puede apagar en Ajustes; si no lo tienes, verás la línea azul. |
| [Hands on the Wheel](https://www.beamng.com/threads/hands-on-the-wheel-driver-immersion-mod-beta-0-5-0.111759/) | Pone las manos del piloto en el volante (vista interior más real). |
| [EnvyFFB](https://www.beamng.com/resources/envyffb-drift-force-feedback.40147/) | Force feedback del volante más realista (si juegas con volante). |
| [Realistic Headlights & Fogs V2](https://www.beamng.com/resources/realistic-headlights-fogs-v2.38672/) | Faros y antinieblas realistas: imprescindible en tramos de noche. |
| [Smoke Dust FX](https://www.beamng.com/resources/smoke-dust-fx.39628/) | Humo y polvo realistas, sobre todo en tramos de tierra. |

**Idioma:** Raid.Earth usa el idioma del juego (por ahora español o inglés).

**Superficies:** cada tramo lleva su superficie FIA: asfalto, tierra (grava), nieve o mixto. Al importar una ruta, elígela en el formulario o déjala en *Automática* (se lee de los nombres: «tierra», «grava», «nieve»...). En pistas y caminos de tierra que el juego no tiene como carretera, el propio trazado del tramo cuenta como calzada, así que no se pone nada encima.

**Copiloto en español:** cada release trae también `earth_raid_voice_es.zip` (voz generada con Piper a partir de `tools/voicepack/es.json`). Cópialo a `mods/` como el otro y elige el copiloto en Ajustes. Para otros idiomas o voces: traduce `es.json` y ejecuta `tools/voicepack/make_voicepack.py` (Piper, voces de Windows o espeak-ng); cualquier voicepack con el formato del juego aparece en Ajustes → Copiloto.

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

Install it from BeamNG.Earth → Add-ons → Add from GitHub → `RamiroRP/earth.raid`, or copy `earth_raid.zip` from Releases (unzipped NO: as is) into `mods/`, and open it from its own tab in the pause menu (**Esc → Raid.Earth**). Contributors are welcome, especially for the worldwide automatic rally discovery from public data.

### Recommended mods (for a better experience)

They are optional, but rallying feels much better with them. **Step by step:**

1. Open each link in the table (it is BeamNG's official website).
2. Click **Download**. You get a `.zip` file.
3. Copy that `.zip` **as it is, without unzipping it**, into your mods folder: `Documents\BeamNG.drive\<version>\mods`
   (or start the game → main menu → **Mods** → **Open mods folder**).
4. Start the game. **Raid.Earth turns on by itself** the recommended mods it finds downloaded (to stop that, switch off Raid.Earth → Settings → "Turn on downloaded recommended mods automatically").
5. To check: Raid.Earth → Settings → **Recommended mods**: each one says *enabled*, *downloaded* or *not installed*.

| Mod | What it does |
|---|---|
| [Racing Line Mod](https://www.beamng.com/resources/racing-line-mod.39806/) | Draws the ideal racing line **inside the stage** (from the start to the finish) instead of the blue GPS line. Outside the stage (to the time control and to the start line) the game's blue GPS line is always used. It can be switched off in Settings; without the mod you get the blue line. |
| [Hands on the Wheel](https://www.beamng.com/threads/hands-on-the-wheel-driver-immersion-mod-beta-0-5-0.111759/) | Puts the driver's hands on the steering wheel (a more real cockpit view). |
| [EnvyFFB](https://www.beamng.com/resources/envyffb-drift-force-feedback.40147/) | More realistic steering-wheel force feedback (if you play with a wheel). |
| [Realistic Headlights & Fogs V2](https://www.beamng.com/resources/realistic-headlights-fogs-v2.38672/) | Realistic headlights and fog lights: a must for night stages. |
| [Smoke Dust FX](https://www.beamng.com/resources/smoke-dust-fx.39628/) | Realistic smoke and dust, above all on gravel stages. |

**Language:** Raid.Earth follows the game's language (Spanish or English for now).

**Surfaces:** every stage is labelled with its FIA surface: tarmac, gravel, snow or mixed. When you import a route, pick it in the form or leave it on *Automatic* (it is read from the names: "tierra", "gravel", "snow"...). On gravel tracks and paths the game has no road for, the stage line itself counts as the road, so nothing is placed on it.

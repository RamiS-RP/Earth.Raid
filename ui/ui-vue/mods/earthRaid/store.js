// El estado del menú y las llamadas a Lua (lua/ge/extensions/earthRaid/main.lua). Lua publica el modelo entero con
// guihooks.trigger('EarthRaidState', model) tras cada cambio; la página pide acciones con bngApi.engineLua.
import { ref } from "vue"

export const state = ref(null)

export function engineLua(script, cb) {
  if (window.bngApi && window.bngApi.engineLua) (cb ? window.bngApi.engineLua(script, cb) : window.bngApi.engineLua(script))
}

// call("uiSelect", "id") -> earthRaid_main.uiSelect("id")
export function call(fn, ...args) {
  const a = args.map(v => (typeof v === "string" ? JSON.stringify(v) : String(v))).join(", ")
  engineLua(`if earthRaid_main then earthRaid_main.${fn}(${a}) end`)
}

export function typing(on) { engineLua(`if setCEFTyping then setCEFTyping(${on ? "true" : "false"}) end`) }
export function onState(model) { state.value = model }

export function list(v) {
  if (Array.isArray(v)) return v
  if (v && typeof v === "object") return Object.values(v)
  return []
}

const TEXT = {
  es: {
    title: "Raid.Earth", filtered: "(Filtrado)", close: "Cerrar", back: "Volver", search: "Buscar rally, tramo o lugar",
    near: "En tu zona", live: "En curso", upcoming: "Próximos", past: "Celebrados", none: "No hay rallies que coincidan.",
    noneHint: "El catálogo crece añadiendo el KMZ o GPX de cada prueba.", all: "Todos",
    country: "País", type: "Tipo", surface: "Superficie", status: "Estado",
    rally: "Rally", raid: "Raid", dakar: "Rally raid", asphalt: "Asfalto", gravel: "Tierra", snow: "Nieve", mixed: "Mixto",
    official: "Fuente oficial", openRally: "Abrir rally", challenge: "Tipo de desafío", championship: "Campeonato",
    organizer: "Organizador", dates: "Fechas", place: "Lugar", stagesInfo: "Tramos", here: "Estás en la zona",
    away: "a {d}", summary: "Resumen del rally", rules: "Normas", settings: "Ajustes", ratings: "Calificaciones",
    stageDist: "Distancia de los tramos especiales: {d}", liaisonDist: "Distancia de los enlaces: {d}",
    totalDist: "Distancia total: {d}", start: "Iniciar", gps: "GPS a la salida", tp: "Teletransporte",
    cancel: "Cancelar tramo", running: "En marcha", startIn: "salida a {d}",
    copilot: "Copiloto", visualNotes: "Notas de ruta visuales", voice: "Voz del copiloto",
    falseStart: "Sanciones de salida en falso", recoveryPenalty: "Penalización al recuperar (+5 s)",
    closures: "Cortar las calles del tramo", ambience: "Ambiente (público, vallas, asistencia)",
    noTraffic: "Sin tráfico en el tramo", regionalTraffic: "Tráfico con coches de la zona", parkCars: "Coches de rally en los boxes", performance: "Rendimiento", perf_auto: "Auto", perf_low: "Bajo", perf_medium: "Medio", perf_high: "Alto", perfHelp: "Cuántos conos, carteles y coches tienen física a la vez. Bajo: ninguno (todo estático), para equipos justos. Auto: según la calidad elegida en BeamNG.Earth.", arrows: "Flechas en las curvas", cautions: "Carteles de peligro",
    import: "Importar", importTitle: "Importar una ruta", openFolder: "Abrir la carpeta", importAll: "Volver a importar todo",
    importHelp1: "Copia la ruta en la carpeta de importación ({dir}): una carpeta por evento, con uno o varios archivos de ruta (KMZ, KML, GPX, GeoJSON u OSM), su logo (PNG/JPG) y, si quieres, event.json con sus datos. Un archivo suelto también vale.",
    recModsHelp: "Opcionales, pero el rally se vive mucho mejor con ellos. Descárgalos de beamng.com (botón Descargar) y Raid.Earth los activa solo.", rec_racingline: "dibuja la trazada ideal en el tramo (sustituye a la línea azul del GPS)", rec_hotw: "pone las manos del piloto en el volante", rec_envyffb: "force feedback del volante más realista", rec_headlights: "faros y antinieblas realistas para los tramos de noche", rec_smokedust: "humo y polvo realistas en tierra", recActive: "activado", recInactive: "descargado (se activará)", recMissing: "no instalado", recDownload: "Descargar", recModsAuto: "Activar solos los mods recomendados descargados", vpPartial: "incompleto: lo que falta lo dice la voz por defecto", rallyRunning: "Rally en marcha", restartFromTc: "Reiniciar desde el último TC", restartRally: "Reiniciar el rally desde el principio", abandonRally: "Abandonar el rally", restartStage: "Reiniciar tramo", abandonStage: "Abandonar tramo", newEvent: "Nuevo evento", surfAuto: "Automática (por los nombres)", pauseEvents: "Eventos", pauseOpen: "Abrir Raid.Earth", pauseIdle: "Ningún tramo en marcha. Elige un evento para empezar.", pauseImport: "Sube la ruta de un rally (.kmz, .kml, .gpx, .geojson), su imagen y una descripción: se convierte en tramos con la señalización FIA.", pauseMore: "Más ajustes (copiloto, notas, enlaces) en el menú completo.", settings: "Ajustes", upRoute: "Ruta (.kmz, .kml, .gpx…)", upLogo: "Imagen del evento", upGo: "Subir e importar", upSending: "Enviando…", upDone: "importado", importHelp2: "Se reconocen los tramos, enlaces, controles, meta lanzada, STOP, radios, saltos y chicanes por sus nombres (como los mapas de los organizadores). Rellena o corrige la ficha y guarda.",
    importNone: "No hay nada en la carpeta de importación todavía.", noLogo: "sin logo", stagesShort: "tramos",
    imp_new: "Importado", imp_ok: "Al día", imp_error: "Error", saveImport: "Guardar ficha e importar", reimport: "Reimportar",
    seeEvent: "Ver el evento", autoFilled: "Lo que no rellenes se deduce del archivo (nombre, tramos, pasadas, enlaces, parque de asistencia).",
    m_name: "Nombre", m_short: "Nombre corto", m_dates: "Fechas", m_country: "País", m_city: "Ciudad", m_region: "Región",
    m_championship: "Campeonato", m_organizer: "Organizador", m_type: "Tipo", m_surface: "Superficie", m_link: "Enlace (fuente)",
    m_source: "Origen de los datos", m_description: "Descripción",
    ph_name: "Rally de ...", ph_short: "Rally ...", ph_dates: "2027-05-06/2027-05-09", ph_country: "es", ph_city: "", ph_region: "",
    ph_championship: "WRC, ERC, CERA, Dakar...", ph_organizer: "", ph_link: "https://...", ph_source: "KMZ del organizador",
    rally: "Rally", raid: "Raid / Dakar", hillclimb: "Subida", custom: "Ruta propia", mixed: "Mixto",
    raceHud: "Pantalla de rally (sin minimapa)", racingLine: "Línea de carrera (mod Racing Line) en vez de la línea azul del GPS", recMods: "Mods recomendados", installed: "instalado ✓", recRacing: "dibuja la línea de carrera ideal con la velocidad de paso; Raid.Earth la usa en el tramo.", recHotw: "añade un piloto al coche.", sounds: "Sonido de ambiente (público, generadores)", notesSafe: "Notas prudentes (un grado más cerradas)",
    notesLead: "Antelación de las notas", notesSize: "Tamaño de las notas", notesAlpha: "Opacidad de las notas",
    early: "pronto", normal: "normal", late: "tarde",
    on: "Activado", off: "Desactivado", tries: "Intentos", best: "Mejor tiempo", last: "Últimos intentos",
    time: "Tiempo", penalty: "Penalización", split: "Parcial", vehicle: "Vehículo", noRuns: "Aún no has corrido este tramo.",
    pickStage: "Elige un tramo", selected: "Seleccionado", source: "Fuente", stageSummary: "Resumen del tramo", voiceReal: "Voz real", screenLines: "Pantalla y líneas", modeGroup: "Modo de juego", hardcore: "Modo hardcore", hardcoreNote: "Sin reparar ni restablecer el coche, sin línea azul ni línea de carrera, sin notas en pantalla ni minimapa: solo la voz del copiloto y el HUD mínimo. Recreando la máxima realidad.", penalties: "Sanciones", distance: "Distancia", roadLbl: "Carretera", preNote: "El vehículo y la hora del día se pueden cambiar desde Conducción libre antes de iniciar.", map: "Mapa", mapHelp: "Tramos en rojo (el elegido en naranja), enlaces en azul. Pulsa un tramo del mapa para elegirlo.",
    rule1: "Ve a la salida siguiendo el GPS. Al llegar, coloca el morro en la línea verde y detente.",
    rule3: "Cuenta atrás de 10 s con el reloj de salida. Arrancar antes: salida en falso, +10 s.",
    rule4: "Recuperar el coche (R) en el tramo añade 5 segundos.",
    rule5: "Meta lanzada: cruza la meta y detente en el control STOP, 150 m más allá.",
    rule6: "Durante el tramo no hay tráfico y las calles que salen del recorrido están cortadas.",
    rule2: "Tienes 1 minuto para colocarte con el morro a menos de 1 m de la línea, sin pasarla. Si no estás colocado al acabar: +10 s y el minuto vuelve a empezar. Colocado, Mayús+E sale ya.",
    km: "km", category: "Categoría", nearBy: "Cerca", radius: "Radio", onlyNear: "Solo cerca", reload: "Volver a leer el catálogo",
    custom: "Ruta propia", dirNormal: "Sentido normal", dirReverse: "Tramo inverso", service: "Asistencia (final)", noneHint2: "⤓ Importar: tus rutas (KMZ, KML, GPX, GeoJSON, OSM) con su logo y su ficha, desde {dir}. Paquetes de eventos: {packs}.",
    modeStage: "Tramo suelto", modeRally: "Rally completo", startRally: "Iniciar rally completo", startFrom: "Empezar desde",
    fromStart: "el principio", itinerary: "Itinerario", liaison: "enlace", rallyDist: "Rally completo: {d} ({s} cronometrados + {l} de enlaces)",
    skipLiaison: "Saltar enlace (al control, a tu hora)", abandon: "Abandonar rally", rallyRunning: "Rally en marcha: {l}",
    rallyBest: "Mejor rally completo", liaisonKmh: "Media de los enlaces", gpsOnly: "sin trazado: GPS",
    ruleR1: "Sales de la asistencia (TC0) a tu hora. Cada enlace tiene una hora prevista para fichar en el siguiente control (TC).",
    ruleR2: "Para fichar, detente en el punto del TC. Fuera de tu minuto: 10 s por minuto de adelanto o retraso. Si llegas pronto puedes esperar o pulsar Mayús+E para adelantar el reloj.",
    ruleR3: "Fichado el TC, sales del tramo en el siguiente minuto entero (al menos 35 s después). En los enlaces hay tráfico; en los tramos, no.",
    ruleR4: "Tu tiempo total es la suma de los tramos y las penalizaciones. Un enlace largo se puede saltar desde este menú (teletransporte, sin penalización).",
  },
  en: {
    title: "Raid.Earth", filtered: "(Filtered)", close: "Close", back: "Back", search: "Search rally, stage or place",
    near: "In your area", live: "Live", upcoming: "Upcoming", past: "Past", none: "No rallies match.",
    noneHint: "The catalogue grows by adding each event's KMZ or GPX.", all: "All",
    country: "Country", type: "Type", surface: "Surface", status: "Status",
    rally: "Rally", raid: "Raid", dakar: "Rally raid", asphalt: "Tarmac", gravel: "Gravel", snow: "Snow", mixed: "Mixed",
    official: "Official source", openRally: "Open rally", challenge: "Challenge type", championship: "Championship",
    organizer: "Organizer", dates: "Dates", place: "Location", stagesInfo: "Stages", here: "You are in the area",
    away: "{d} away", summary: "Rally summary", rules: "Rules", settings: "Settings", ratings: "Ratings",
    stageDist: "Special stage distance: {d}", liaisonDist: "Road section distance: {d}", totalDist: "Total distance: {d}",
    start: "Start", gps: "GPS to start", tp: "Teleport", cancel: "Cancel stage", running: "Running", startIn: "start {d} away",
    copilot: "Co-driver", visualNotes: "Visual pacenotes", voice: "Co-driver voice",
    falseStart: "False start penalties", recoveryPenalty: "Recovery penalty (+5 s)",
    closures: "Close the stage side roads", ambience: "Ambience (spectators, fences, service)",
    noTraffic: "No traffic on the stage", regionalTraffic: "Traffic with cars from the region", parkCars: "Rally cars in the service bays", performance: "Performance", perf_auto: "Auto", perf_low: "Low", perf_medium: "Medium", perf_high: "High", perfHelp: "How many cones, signs and cars have physics at once. Low: none (all static), for modest PCs. Auto: follows the quality chosen in BeamNG.Earth.", arrows: "Corner arrows", cautions: "Caution boards",
    import: "Import", importTitle: "Import a route", openFolder: "Open the folder", importAll: "Re-import everything",
    importHelp1: "Copy the route into the import folder ({dir}): one folder per event, with one or more route files (KMZ, KML, GPX, GeoJSON or OSM), its logo (PNG/JPG) and, optionally, event.json with its details. A single loose file works too.",
    recModsHelp: "Optional, but rallying feels much better with them. Download them from beamng.com (Download button) and Raid.Earth turns them on by itself.", rec_racingline: "draws the ideal racing line on the stage (replaces the blue GPS line)", rec_hotw: "puts the driver's hands on the wheel", rec_envyffb: "more realistic steering-wheel force feedback", rec_headlights: "realistic headlights and fog lights for night stages", rec_smokedust: "realistic smoke and dust on gravel", recActive: "enabled", recInactive: "downloaded (will be enabled)", recMissing: "not installed", recDownload: "Download", recModsAuto: "Turn on downloaded recommended mods automatically", vpPartial: "incomplete: the default voice says what is missing", rallyRunning: "Rally in progress", restartFromTc: "Restart from the last time control", restartRally: "Restart the rally from the start", abandonRally: "Retire from the rally", restartStage: "Restart stage", abandonStage: "Retire from the stage", newEvent: "New event", surfAuto: "Automatic (from the names)", pauseEvents: "Events", pauseOpen: "Open Raid.Earth", pauseIdle: "No stage running. Pick an event to start.", pauseImport: "Upload a rally route (.kmz, .kml, .gpx, .geojson), its image and a description: it becomes stages with FIA signage.", pauseMore: "More settings (co-driver, notes, road sections) in the full menu.", settings: "Settings", upRoute: "Route (.kmz, .kml, .gpx…)", upLogo: "Event image", upGo: "Upload and import", upSending: "Sending…", upDone: "imported", importHelp2: "Stages, road sections, controls, flying finish, STOP, radios, jumps and chicanes are recognised by their names (as in organisers' maps). Fill in or fix the details and save.",
    importNone: "Nothing in the import folder yet.", noLogo: "no logo", stagesShort: "stages",
    imp_new: "Imported", imp_ok: "Up to date", imp_error: "Error", saveImport: "Save details and import", reimport: "Re-import",
    seeEvent: "See the event", autoFilled: "Whatever you leave empty is taken from the file (name, stages, runs, road sections, service park).",
    m_name: "Name", m_short: "Short name", m_dates: "Dates", m_country: "Country", m_city: "City", m_region: "Region",
    m_championship: "Championship", m_organizer: "Organiser", m_type: "Type", m_surface: "Surface", m_link: "Link (source)",
    m_source: "Data source", m_description: "Description",
    ph_name: "Rally ...", ph_short: "Rally ...", ph_dates: "2027-05-06/2027-05-09", ph_country: "es", ph_city: "", ph_region: "",
    ph_championship: "WRC, ERC, Dakar...", ph_organizer: "", ph_link: "https://...", ph_source: "Organiser's KMZ",
    rally: "Rally", raid: "Raid / Dakar", hillclimb: "Hill climb", custom: "Own route", mixed: "Mixed",
    raceHud: "Rally screen (no minimap)", racingLine: "Racing line (Racing Line mod) instead of the blue GPS line", recMods: "Recommended mods", installed: "installed ✓", recRacing: "draws the ideal racing line with corner speeds; Raid.Earth uses it on stages.", recHotw: "adds a driver to the car.", sounds: "Ambient sound (crowd, generators)", notesSafe: "Safe pacenotes (one grade tighter)",
    notesLead: "Pacenote timing", notesSize: "Pacenote size", notesAlpha: "Pacenote opacity",
    early: "early", normal: "normal", late: "late",
    on: "On", off: "Off", tries: "Attempts", best: "Best time", last: "Last attempts",
    time: "Time", penalty: "Penalty", split: "Split", vehicle: "Vehicle", noRuns: "You have not driven this stage yet.",
    pickStage: "Pick a stage", selected: "Selected", source: "Source", stageSummary: "Stage summary", voiceReal: "Real voice", screenLines: "Screen and lines", modeGroup: "Game mode", hardcore: "Hardcore mode", hardcoreNote: "No repairing or resetting the car, no blue line or racing line, no on-screen notes or minimap: only the co-driver's voice and the minimum HUD. As real as it gets.", penalties: "Penalties", distance: "Distance", roadLbl: "Road", preNote: "The vehicle and the time of day can be changed from Freeroam before starting.", map: "Map", mapHelp: "Stages in red (the chosen one in orange), road sections in blue. Click a stage on the map to pick it.",
    rule1: "Follow the GPS to the start. Put the nose on the green line and stop.",
    rule3: "10 s countdown on the start clock. Moving early: false start, +10 s.",
    rule4: "Recovering the car (R) on a stage adds 5 seconds.",
    rule5: "Flying finish: cross the line and stop at the STOP control, 150 m further.",
    rule6: "No traffic on the stage, and the side roads are closed.",
    rule2: "You have 1 minute to stage with the nose less than 1 m before the line, not past it. Not staged in time: +10 s and the minute starts again. Staged, Shift+E starts now.",
    km: "km", category: "Category", nearBy: "Near", radius: "Radius", onlyNear: "Only near", reload: "Reload the catalogue",
    custom: "Own route", dirNormal: "Normal direction", dirReverse: "Reverse stage", service: "Service park (finish)", noneHint2: "⤓ Import: your routes (KMZ, KML, GPX, GeoJSON, OSM) with their logo and details, from {dir}. Event packs: {packs}.",
    modeStage: "Single stage", modeRally: "Full rally", startRally: "Start full rally", startFrom: "Start from",
    fromStart: "the beginning", itinerary: "Itinerary", liaison: "road section", rallyDist: "Full rally: {d} ({s} timed + {l} road sections)",
    skipLiaison: "Skip road section (to the control, on time)", abandon: "Retire from rally", rallyRunning: "Rally running: {l}",
    rallyBest: "Best full rally", liaisonKmh: "Road section average", gpsOnly: "no track: GPS",
    ruleR1: "You leave the service park (TC0) at your time. Each road section has a due time at the next time control (TC).",
    ruleR2: "Stop at the TC point to check in. Outside your minute: 10 s per minute early or late. Early, you can wait or press Shift+E to advance the clock.",
    ruleR3: "After the TC you start the stage at the next whole minute (at least 35 s later). Road sections have traffic; stages do not.",
    ruleR4: "Your total is stage times plus penalties. A long road section can be skipped from this menu (teleport, no penalty).",
  },
}

export function t(key, vars) {
  const lang = state.value && state.value.lang === "es" ? "es" : "en"
  const s = TEXT[lang][key] || TEXT.en[key] || key
  return s.replace(/\{(\w+)\}/g, (_, k) => (vars && vars[k] != null ? String(vars[k]) : ""))
}

export function dist(m) {
  if (m == null) return ""
  const mi = state.value && state.value.units === "mi"
  if (mi) return (m / 1609.344).toFixed(1) + " mi"
  return m < 1000 ? Math.round(m / 10) * 10 + " m" : (m / 1000).toFixed(1) + " km"
}
export const km = v => (v == null ? "" : Number(v).toFixed(2).replace(".", ",") + " km")
export function clock(sec) {
  if (sec == null) return "—"
  const m = Math.floor(sec / 60)
  const r = (sec - m * 60).toFixed(1).padStart(4, "0")
  return m + ":" + r
}
export const flag = cc => (cc ? `/earthRaid/flags/${String(cc).toLowerCase()}.png` : "")
const MONTHS = { es: ["ene", "feb", "mar", "abr", "may", "jun", "jul", "ago", "sep", "oct", "nov", "dic"],
  en: ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"] }
export function dates(s) {
  const m = /^(\d+)-(\d+)-(\d+)\/(\d+)-(\d+)-(\d+)$/.exec(s || "")
  if (!m) return s || ""
  const lang = state.value && state.value.lang === "es" ? "es" : "en"
  const mo = MONTHS[lang]
  if (m[2] === m[5]) return `${+m[3]}–${+m[6]} ${mo[+m[2] - 1]} ${m[1]}`
  return `${+m[3]} ${mo[+m[2] - 1]} – ${+m[6]} ${mo[+m[5] - 1]} ${m[4]}`
}

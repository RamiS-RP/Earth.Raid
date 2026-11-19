-- Raid.Earth: punto de entrada (extensión "earthRaid_main").
-- Funciona sobre la API de BeamNG.Earth (beamngEarth_api v1): propone los eventos del catálogo cercanos, publica el
-- menú (catálogo, ficha del rally, ajustes, clasificaciones) y arranca los tramos (stage.lua).
local M = {}
local TAG = 'earthRaid'
M.VERSION = '0.8.2'
M.NEEDS = { 'pose', 'gps', 'teleport', 'notify', 'events', 'options' }
M.INDEX = '/earthRaid/index.json'
-- Más paquetes de eventos: carpetas con su index.json (mismo formato) dentro del mod o en la carpeta del jugador, y
-- rutas propias en KML. Los paquetes del jugador pisan a los del mod con el mismo id.
M.PACK_DIRS = { '/earthRaid/packs/', '/settings/earthRaid/packs/', '/settings/earthRaid/packs/imported/' }
M.IMPORT_DIR = '/settings/earthRaid/import/'
M.SERVICE_TELEPORT_M = 2000 -- rally completo: más lejos que esto de la asistencia, se empieza allí
M.CHECK_S = 5              -- cada cuánto se mira la zona
M.LEAVE_FACTOR = 1.5       -- un evento descartado o ya propuesto se olvida al alejarse a radio x esto
M.TELEPORT_OVER_M = 60000  -- más lejos que esto de la salida: accept() teletransporta en vez de poner el GPS

local catalog = require('earthRaid/catalog')
local clean = require('earthRaid/clean')
local dressing = require('earthRaid/dressing')
local loader = require('earthRaid/loader')
local servicepark = require('earthRaid/servicepark')
local props = require('earthRaid/props')
local geo = require('earthRaid/geo')
local stage = require('earthRaid/stage')
local rally = require('earthRaid/rally')
local importer = require('earthRaid/importer')
M.HUD_APP = 'EarthRaidHud'

local S = { index = nil, earth = false, reason = 'not checked', timer = 0, opts = {},
  proposal = nil,          -- { event, stage, stageM, boxM } lo que se ofrece ahora
  seen = {},               -- id -> true: ya propuesto en esta visita a la zona
  loaded = {} }            -- id -> el evento completo (tramos con su trazado)

local function api() return rawget(_G, 'beamngEarth_api') end

local function spanish()
  local ok, l = pcall(function() return Lua:getSelectedLanguage() end)
  return ok and type(l) == 'string' and l:sub(1, 2):lower() == 'es'
end

local function km(m)
  if S.opts.units == 'mi' then return ('%.1f mi'):format(m / 1609.344) end
  return ('%.1f km'):format(m / 1000)
end

function M.checkEarth()
  local a = api()
  if not a then return false, 'BeamNG.Earth is not installed' end
  local ok, major = pcall(a.version)
  if not ok or major ~= 1 then return false, 'BeamNG.Earth modding API v1 is required' end
  for _, n in ipairs(M.NEEDS) do
    if not a.has(n) then return false, 'BeamNG.Earth is too old (API feature "' .. n .. '" missing)' end
  end
  return true
end

local function readOptions()
  local a = api()
  if not (a and a.addonOptions) then return end
  for _, id in ipairs({ 'earth-raid', 'raid-earth', 'earth_raid' }) do
    local ok, o = pcall(a.addonOptions, id)
    if ok and type(o) == 'table' and next(o) ~= nil then S.opts = o return end
  end
end

local function refresh()
  local ok, why = M.checkEarth()
  S.earth, S.reason = ok, why or 'ok'
  if ok then readOptions() end
end

local settings = require('earthRaid/settings')
local guide = require('earthRaid/guide')
local function radiusM() return (tonumber(settings.get().radiusKm) or tonumber(S.opts.searchKm) or 50) * 1000 end

-- Un paquete: su index.json; cada evento recuerda su carpeta (para su archivo y su logo) y de qué paquete viene
local function addPack(byId, order, base, pack)
  local data = jsonReadFile(base .. 'index.json')
  if type(data) ~= 'table' or type(data.events) ~= 'table' then return 0 end
  for _, e in ipairs(data.events) do
    if type(e) == 'table' and e.id and e.file then
      e._base, e._pack = base, data.name or pack or base
      if not byId[e.id] then order[#order + 1] = e.id end
      byId[e.id] = e
    end
  end
  return #data.events
end

-- ---- importación: la carpeta M.IMPORT_DIR ------------------------------------------------------------------------------
-- Cada subcarpeta es un evento (uno o varios archivos de ruta, su logo y event.json con los datos); cada archivo de ruta
-- suelto en la carpeta también (con su logo y sus datos al lado: nombre.png, nombre.event.json). Se convierte a un
-- paquete en M.IMPORTED_DIR (solo cuando cambia algo) y el catálogo lo lee como los demás.
M.IMPORTED_DIR = '/settings/earthRaid/packs/imported/'
M.ROUTE_EXT = { kml = true, kmz = true, gpx = true, geojson = true, json = true, osm = true }
M.LOGO_EXT = { png = true, jpg = true, jpeg = true, svg = true, webp = true }
S.imports = {}

local function ext(f) return (tostring(f):match('%.([%w]+)$') or ''):lower() end
local function baseName(f) return (tostring(f):match('([^/]+)$') or f) end
local function stem(f) return (baseName(f):gsub('%.[%w]+$', '')) end

-- el texto de un archivo de ruta (un KMZ se abre con el lector de zip del juego: su primer .kml)
local function routeText(f)
  if ext(f) == 'kmz' then
    local zip = ZipArchive and ZipArchive()
    if not (zip and zip:openArchiveName(f, 'r')) then return nil, 'KMZ: no se pudo abrir' end
    local text
    for idx, name in pairs(zip:getFileList() or {}) do
      if type(name) == 'string' and name:lower():match('%.kml$') then text = zip:readFileEntryByIdx(idx) break end
    end
    zip:close()
    if not text then return nil, 'KMZ sin KML dentro' end
    return text
  end
  return readFile(f)
end

local function readRoute(f)
  local text, err = routeText(f)
  if not text then return nil, err end
  local e = ext(f)
  if e == 'kml' or e == 'kmz' then return importer.readKml(text) end
  if e == 'gpx' then return importer.readGpx(text) end
  if e == 'osm' then return importer.readOsm(text) end
  if e == 'geojson' or e == 'json' then return importer.readGeojson(text, jsonDecode) end
  return nil, 'formato no reconocido'
end

-- las fuentes de la carpeta de importación: { key, dir, files = {...}, logo, metaFile, sig }
local function scanImports()
  local out = {}
  local root = M.IMPORT_DIR
  local okD, dirs = pcall(function() return FS:findFiles(root, '*', 0, false, true) end)
  local function sigOf(files)
    local parts = {}
    for _, f in ipairs(files) do
      local ok, st = pcall(function() return FS:stat(f) end)
      parts[#parts + 1] = baseName(f) .. ':' .. tostring(ok and type(st) == 'table' and st.filesize or '?') .. ':' ..
        tostring(ok and type(st) == 'table' and st.modtime or '?')
    end
    table.sort(parts)
    return table.concat(parts, '|')
  end
  for _, d in ipairs(okD and dirs or {}) do
    if FS:directoryExists(d) then
      local src = { key = baseName(d:gsub('/$', '')), dir = d:gsub('/?$', '/'), files = {} }
      local all = FS:findFiles(src.dir, '*', 0, false, false) or {}
      for _, f in ipairs(all) do
        local e = ext(f)
        if baseName(f):lower() == 'event.json' then src.metaFile = f
        elseif M.ROUTE_EXT[e] then src.files[#src.files + 1] = f
        elseif M.LOGO_EXT[e] and not src.logo then src.logo = f end
      end
      table.sort(src.files)
      src.metaFile = src.metaFile or (src.dir .. 'event.json')
      if #src.files > 0 then
        local sigFiles = {}
        for _, f in ipairs(src.files) do sigFiles[#sigFiles + 1] = f end
        if FS:fileExists(src.metaFile) then sigFiles[#sigFiles + 1] = src.metaFile end
        if src.logo then sigFiles[#sigFiles + 1] = src.logo end
        src.sig = sigOf(sigFiles)
        out[#out + 1] = src
      end
    end
  end
  local loose = FS:findFiles(root, '*', 0, false, false) or {}
  for _, f in ipairs(loose) do
    local e = ext(f)
    if M.ROUTE_EXT[e] and not baseName(f):lower():match('%.event%.json$') then
      local st = stem(f)
      local src = { key = st, dir = root, files = { f }, metaFile = root .. st .. '.event.json' }
      for le in pairs(M.LOGO_EXT) do if FS:fileExists(root .. st .. '.' .. le) then src.logo = root .. st .. '.' .. le end end
      local sigFiles = { f }
      if FS:fileExists(src.metaFile) then sigFiles[#sigFiles + 1] = src.metaFile end
      if src.logo then sigFiles[#sigFiles + 1] = src.logo end
      src.sig = sigOf(sigFiles)
      out[#out + 1] = src
    end
  end
  table.sort(out, function(a, b) return a.key < b.key end)
  return out
end

-- Convierte una fuente en paquete (si cambió o force). Devuelve el informe para el menú.
local function importOne(src, force)
  local id = 'imp-' .. importer.slug(src.key)
  local packDir = M.IMPORTED_DIR .. id .. '/'
  local info = { key = src.key, id = id, dir = src.dir, files = {}, logo = src.logo, metaFile = src.metaFile }
  for _, f in ipairs(src.files) do info.files[#info.files + 1] = baseName(f) end
  local meta = FS:fileExists(src.metaFile) and jsonReadFile(src.metaFile) or nil
  info.meta = type(meta) == 'table' and meta or {}
  local old = jsonReadFile(packDir .. 'index.json')
  if not force and type(old) == 'table' and old.importSig == src.sig and old.events and old.events[1] then
    info.status, info.event = 'ok', old.events[1]
    info.report = old.report
    return info
  end
  local sources = {}
  for _, f in ipairs(src.files) do
    local okR, r, err = pcall(readRoute, f)
    if okR and r then sources[#sources + 1] = r
    else
      info.status, info.error = 'error', baseName(f) .. ': ' .. tostring(okR and err or r)
      return info
    end
  end
  local okB, ev, entry, report = pcall(importer.build, sources, id, info.meta)
  if not okB or not ev then
    info.status, info.error = 'error', tostring(okB and entry or ev)
    return info
  end
  -- lo que no dice el jugador, deducido del archivo
  local guess = importer.guessMeta(ev, entry)
  entry.short = entry.short or guess.short
  entry.type = info.meta.type or guess.type
  entry.championship = entry.championship or guess.championship
  if src.logo then
    -- el logo se copia junto al paquete (el menú lo carga de ahí)
    local data = readFile(src.logo)
    if data then
      local lname = 'logo.' .. ext(src.logo)
      if writeFile(packDir .. lname, data) then entry.logo = lname end
    end
  end
  entry.file = 'events/' .. id .. '.json'
  ev.logo, ev.short, ev.championship = entry.logo, entry.short, entry.championship
  jsonWriteFile(packDir .. entry.file, ev, false)
  jsonWriteFile(packDir .. 'index.json', { format = 1, name = 'import', importSig = src.sig, importKey = src.key,
    report = report, events = { entry } }, true)
  info.status, info.event, info.report = 'new', entry, report
  log('I', TAG, ('import %s: %d stages, %d liaisons, %d points'):format(src.key, report.stages or 0, report.liaisons or 0,
    report.eventPoints or 0))
  return info
end

function M.importAll(force)
  local list = {}
  local okS, srcs = pcall(scanImports)
  if not okS then log('W', TAG, 'import scan: ' .. tostring(srcs)) srcs = {} end
  for _, src in ipairs(srcs) do
    local ok, info = pcall(importOne, src, force)
    if ok then list[#list + 1] = info else list[#list + 1] = { key = src.key, status = 'error', error = tostring(info) } end
  end
  S.imports = list
  return list
end

-- Tramos retirados provisionalmente (earthRaid/disabled.json: evento -> tramo -> motivo), además de los `disabled` del
-- propio archivo del evento: valen aunque el paquete importado se regenere
local function isDisabled(evId, st)
  if st.disabled then return true end
  S.disabledMap = S.disabledMap or jsonReadFile('/earthRaid/disabled.json') or {}
  local m = S.disabledMap[evId]
  return type(m) == 'table' and m[st.id] ~= nil
end

function M.loadIndex()
  S.disabledMap = nil
  local byId, order = {}, {}
  S.loaded = {}
  addPack(byId, order, '/earthRaid/', 'base')
  for _, dir in ipairs(M.PACK_DIRS) do
    local ok, files = pcall(function() return FS:findFiles(dir, 'index.json', 1, false, false) end)
    table.sort(ok and files or {})
    for _, f in ipairs(ok and files or {}) do
      local base = f:gsub('index%.json$', '')
      addPack(byId, order, base, base:match('([^/]+)/$'))
    end
  end
  pcall(M.importAll, false)
  local imported = #(S.imports or {})
  local events = {}
  for _, id in ipairs(order) do events[#events + 1] = byId[id] end
  -- tramos retirados del paquete (disabled): también fuera de las fichas y los recuentos, no solo del rally
  for _, ev in ipairs(events) do
    local kept, dropped, km, n = {}, false, 0, 0
    for _, st in ipairs(type(ev.stages) == 'table' and ev.stages or {}) do
      if isDisabled(ev.id, st) then dropped = true
      else kept[#kept + 1] = st if st.kind == 'ss' then km, n = km + (tonumber(st.km) or 0) * math.max(1, type(st.runs) == 'table' and #st.runs or 1), n + 1 end end
    end
    if dropped then ev.stages, ev.stageCount, ev.stageKm = kept, n, math.floor(km * 10 + 0.5) / 10 end
  end
  S.index = { events = events }
  log('I', TAG, ('catalogue: %d event(s), %d imported'):format(#events, imported))
  return #events
end

-- El evento completo (con los trazados), leído una vez
-- todos los eventos del índice (para la auditoría)
function M.events()
  if not S.index then M.loadIndex() end
  return S.index and S.index.events or {}
end
function M.event(id)
  if S.loaded[id] then return S.loaded[id] end
  for _, e in ipairs(S.index and S.index.events or {}) do
    if e.id == id then
      local data = jsonReadFile((e._base or '/earthRaid/') .. e.file)
      if type(data) == 'table' then
        -- la carpeta del paquete y el logo de la entrada del catálogo (para la pantalla de carga)
        data._base = data._base or e._base or '/earthRaid/'
        data.logo = data.logo or e.logo
        data.description = data.description or e.description
        -- tramos retirados del paquete (disabled: superespeciales sobre explanadas que el mapa no tiene como
        -- carretera; no cumplen la norma de las líneas en la calzada)
        if type(data.stages) == 'table' then
          local keep = {}
          for _, st in ipairs(data.stages) do if not isDisabled(id, st) then keep[#keep + 1] = st end end
          data.stages = keep
        end
        S.loaded[id] = data
      end
      return S.loaded[id]
    end
  end
end

-- Los eventos cerca de un punto (para probar sin el mundo): catalog.nearby
function M.nearby(lat, lon, radiusKm)
  if not S.index then M.loadIndex() end
  return catalog.nearby(S.index, lat, lon, (tonumber(radiusKm) or radiusM() / 1000) * 1000)
end

local function proposalText(p)
  local e, st = p.event, p.stage
  if spanish() then
    local t = ('Raid.Earth: %s en esta zona (%d tramos, %s cronometrados).'):format(e.name, e.stageCount or 0, km((e.stageKm or 0) * 1000))
    if st then t = t .. (' Tramo más cercano: %s (%s), salida a %s.'):format(st.title, km(st.km * 1000), km(p.stageM)) end
    return t .. ' Esc → Raid.Earth para verlo.'
  end
  local t = ('Raid.Earth: %s is in this area (%d stages, %s timed).'):format(e.name, e.stageCount or 0, km((e.stageKm or 0) * 1000))
  if st then t = t .. (' Nearest stage: %s (%s), start %s away.'):format(st.title, km(st.km * 1000), km(p.stageM)) end
  return t .. ' Esc → Raid.Earth to see it.'
end

-- Un mensaje en pantalla con categoría propia (otro mensaje del juego no lo pisa) y el tiempo pedido
function M.toast(text, seconds)
  local ok = pcall(function() guihooks.trigger('Message', { ttl = seconds or 8, msg = text, category = 'earthRaid', icon = 'flag' }) end)
  if not ok then local a = api() if a and a.notify then pcall(a.notify, text, seconds or 8) end end
end

local function publish()
  local p = S.proposal
  guihooks.trigger('EarthRaidProposal', p and { id = p.event.id, name = p.event.name, type = p.event.type,
    surface = p.event.surface, stageCount = p.event.stageCount, stageKm = p.event.stageKm, boxM = p.boxM,
    stage = p.stage and { id = p.stage.id, title = p.stage.title, km = p.stage.km, distM = p.stageM } or nil,
    stages = p.event.stages, text = proposalText(p) } or {})
end

local function propose(p)
  S.proposal = p
  S.seen[p.event.id] = true
  local text = proposalText(p)
  log('I', TAG, 'proposal: ' .. text)
  M.toast(text, 20)
  publish()
  M.publishState()
end

-- Mira la zona del jugador: propone el evento más cercano que aún no se haya ofrecido. force: olvida lo ya ofrecido.
function M.check(force)
  local a = api()
  if not (S.earth and a and a.ready and a.ready()) then return nil end
  if S.opts.propose == 'off' and not force then return nil end
  if not S.index then M.loadIndex() end
  local lat, lon = a.position()
  if not lat then return nil end
  if force then S.seen = {} end
  local r = radiusM()
  -- lo ya visto se olvida al salir de la zona
  for id in pairs(S.seen) do
    for _, e in ipairs(S.index.events) do
      if e.id == id and catalog.distToBox(lat, lon, e.bbox) > r * M.LEAVE_FACTOR then
        S.seen[id] = nil
        if S.proposal and S.proposal.event.id == id then S.proposal = nil publish() end
      end
    end
  end
  local list = catalog.nearby(S.index, lat, lon, r)
  for _, p in ipairs(list) do
    if not S.seen[p.event.id] then propose(p) return p end
  end
  -- la propuesta en pie sigue al día (el tramo más cercano cambia al moverse)
  if S.proposal then
    for _, p in ipairs(list) do
      if p.event.id == S.proposal.event.id then S.proposal = p end
    end
  end
  return nil
end

-- Aceptar: el GPS a la salida del tramo (stageId, o el más cercano); teletransporte si está muy lejos o mode == 'teleport'
function M.accept(stageId, mode)
  local p, a = S.proposal, api()
  if not (p and a) then return false, 'nothing proposed' end
  local st = p.stage
  if stageId then
    for _, s in ipairs(p.event.stages or {}) do if s.id == stageId then st = s end end
  end
  if not st then return false, 'no stage' end
  local lat, lon = a.position()
  local d = lat and catalog.dist(lat, lon, st.start[1], st.start[2]) or 0
  local label = p.event.name .. ' - ' .. st.title
  S.target = { eventId = p.event.id, stageId = st.id }
  if mode == 'teleport' or (mode ~= 'gps' and d > M.TELEPORT_OVER_M) then
    return a.teleport(st.start[1], st.start[2], label)
  end
  local ok, err = a.gpsSet(st.start[1], st.start[2], label)
  if ok then M.toast((spanish() and 'GPS a la salida de ' or 'GPS set to the start of ') .. st.title, 6) end
  return ok, err
end

function M.dismiss()
  if not S.proposal then return end
  S.proposal = nil
  publish()
end

function M.status()
  return { version = M.VERSION, earth = S.earth, reason = S.reason, events = S.index and #S.index.events or 0,
    proposal = S.proposal and S.proposal.event.id or nil, stage = S.proposal and S.proposal.stage and S.proposal.stage.id or nil,
    target = S.target }
end

-- ---- el menú (ui/ui-vue/mods/earthRaid): Lua publica el modelo entero con 'EarthRaidState' -------------------------

M.OUTLINE_PTS = 140        -- puntos por tramo en el dibujo del menú
M.NATIVE_VISUAL = 'RallyVisualPacenotes'
M.NOTES_TOP = '70px'
local U = { open = false, q = '', sel = nil, filters = { country = '', type = '', category = '', surface = '', status = '', near = '' } }

-- categorías de un evento: los campeonatos de su "championship" ("ERC · S-CER" -> ERC, S-CER)
local function categories(ev)
  local out = {}
  for raw in tostring(ev.championship or ''):gsub('·', ','):gmatch('[^,/;]+') do
    local c = raw:gsub('^%s+', ''):gsub('%s+$', '')
    if c ~= '' then out[#out + 1] = c end
  end
  return out
end

local function outline(path)
  local n = #path
  if n <= M.OUTLINE_PTS then return path end
  local out, step = {}, (n - 1) / (M.OUTLINE_PTS - 1)
  for i = 0, M.OUTLINE_PTS - 1 do out[#out + 1] = path[math.floor(i * step + 0.5) + 1] end
  return out
end

local function lower(s) return tostring(s or ''):lower() end

local function matches(ev, q)
  if q == '' then return true end
  for _, f in ipairs({ ev.name, ev.short, ev.city, ev.region, ev.country, ev.countryName, ev.championship, ev.organizer }) do
    if lower(f):find(q, 1, true) then return true end
  end
  for _, s in ipairs(ev.stages or {}) do
    if lower(s.title):find(q, 1, true) then return true end
  end
  return false
end

-- 'live' (en curso), 'upcoming' (próximo), 'past' (celebrado), según sus fechas
local function statusOf(ev)
  local a, b = tostring(ev.dates or ''):match('(%d+%-%d+%-%d+)/(%d+%-%d+%-%d+)')
  if not a then return 'past' end
  local today = os.date('%Y-%m-%d')
  if today < a then return 'upcoming' end
  if today > b then return 'past' end
  return 'live'
end

local function eventCard(ev, lat, lon)
  local d = lat and type(ev.bbox) == 'table' and catalog.distToBox(lat, lon, ev.bbox) or nil
  return { id = ev.id, name = ev.name, short = ev.short, type = ev.type or 'rally', surface = ev.surface,
    surfacePct = ev.surfacePct, dates = ev.dates, country = ev.country and tostring(ev.country):lower() or nil,
    city = ev.city, region = ev.region, championship = ev.championship, categories = categories(ev),
    organizer = ev.organizer, logo = ev.logo and ((ev._base or '/earthRaid/') .. ev.logo) or nil,
    description = ev.description, stageCount = ev.stageCount, stageKm = ev.stageKmOfficial or ev.stageKm,
    totalKm = ev.totalKmOfficial, boxM = d, near = d ~= nil and d <= radiusM(), status = statusOf(ev),
    stages = ev.stages, source = ev.source, link = ev.link, pack = ev._pack, custom = ev._pack == 'import' and (ev.type == 'custom' or not ev.dates) }
end

-- Mods recomendados para una mejor experiencia (README). Si el jugador los tiene descargados pero desactivados, se
-- activan al cargar Raid.Earth (petición del usuario, 17-nov), salvo que lo apague en Ajustes (recModsAuto).
M.RECOMMENDED = {
  { id = 'racingline', name = 'Racing Line Mod', match = { 'racingline', 'racing_line' },
    url = 'https://www.beamng.com/resources/racing-line-mod.39806/' },
  { id = 'hotw', name = 'Hands on the Wheel', match = { 'hotw', 'handsonthewheel', 'hands_on_the_wheel' },
    url = 'https://www.beamng.com/threads/hands-on-the-wheel-driver-immersion-mod-beta-0-5-0.111759/' },
  { id = 'envyffb', name = 'EnvyFFB', match = { 'envyffb' },
    url = 'https://www.beamng.com/resources/envyffb-drift-force-feedback.40147/' },
  { id = 'headlights', name = 'Realistic Headlights & Fogs V2', match = { 'realisticheadlights', 'realistic_headlights' },
    url = 'https://www.beamng.com/resources/realistic-headlights-fogs-v2.38672/' },
  { id = 'smokedust', name = 'Smoke Dust FX', match = { 'smokedustfx', 'smoke_dust', 'smokedust' },
    url = 'https://www.beamng.com/resources/smoke-dust-fx.39628/' },
}

local function modsDb()
  local ok, db = pcall(function() return core_modmanager.getMods() end)
  return ok and type(db) == 'table' and db or {}
end

-- estado de cada recomendado: installed (descargado), active, modname
function M.recommendedState()
  local db = modsDb()
  local out = {}
  for _, r in ipairs(M.RECOMMENDED) do
    local e = { id = r.id, name = r.name, url = r.url, installed = false, active = false }
    for name, m in pairs(db) do
      local n = (tostring(name) .. ' ' .. tostring(m.fullpath or '')):lower():gsub('[%s%-%.]', '')
      for _, pat in ipairs(r.match) do
        if n:find(pat, 1, true) then
          e.installed = true
          e.modname = e.modname or name
          if m.active then e.active = true e.modname = name end
        end
      end
    end
    out[#out + 1] = e
  end
  return out
end

-- activa los recomendados que están descargados y desactivados
function M.enableRecommended()
  local done = {}
  for _, e in ipairs(M.recommendedState()) do
    if e.installed and not e.active and e.modname then
      local ok = pcall(core_modmanager.activateMod, e.modname)
      if ok then done[#done + 1] = e.name end
    end
  end
  if #done > 0 then
    log('I', TAG, 'recommended mods enabled: ' .. table.concat(done, ', '))
    M.toast((spanish() and 'Raid.Earth activó los mods recomendados: ' or 'Raid.Earth enabled the recommended mods: ')
      .. table.concat(done, ', '), 8)
  end
  return done
end

function M.hasHotw()
  for _, e in ipairs(M.recommendedState()) do if e.id == 'hotw' then return e.active end end
  return false
end

local function buildModel()
  if not S.index then M.loadIndex() end
  local a = api()
  local lat, lon
  if S.earth and a and a.ready and a.ready() then lat, lon = a.position() end
  local st = stage.state()
  local rs = rally.state()
  local m = { earth = S.earth, reason = S.reason, version = M.VERSION, lang = spanish() and 'es' or 'en',
    units = S.opts.units == 'mi' and 'mi' or 'km', q = U.q, filters = U.filters, radiusKm = radiusM() / 1000,
    stageActive = st and { eventId = st.eventId, stageId = st.stageId, phase = st.phase, title = st.title } or nil,
    rallyActive = rally.active() and (function() local R = rally.state() return { eventId = R.ev and R.ev.id, name = R.ev and R.ev.name, idx = R.idx } end)() or nil,
    rallyActive = rs and { eventId = rs.ev.id, phase = rs.phase, idx = rs.idx, count = #rs.it.items,
      label = rs.it.items[rs.idx] and rs.it.items[rs.idx].label or nil } or nil,
    pos = lat and { lat = lat, lon = lon } or nil, proposalId = S.proposal and S.proposal.event.id or nil,
    target = S.target, events = {}, total = #S.index.events,
    facets = { country = {}, type = {}, category = {}, surface = {}, status = {} },
    settings = settings.get(), voicepacks = settings.voicepacks(), today = os.date('%Y-%m-%d'),
    racingLineMod = guide.racingLineAvailable(), hotwMod = M.hasHotw(), recMods = M.recommendedState(),
    importDir = M.IMPORT_DIR, packDirs = M.PACK_DIRS, imports = U.importOpen and M.importsModel() or nil,
    importOpen = U.importOpen or false, pre = S.pre and { kind = S.pre.kind, eventId = S.pre.eventId, stageId = S.pre.stageId, reverse = S.pre.reverse } or nil }
  local q = lower(U.q)
  local seen = { country = {}, type = {}, category = {}, surface = {}, status = {} }
  local f = U.filters
  local function inCats(card, c)
    for _, x in ipairs(card.categories) do if x == c then return true end end
    return false
  end
  for _, ev in ipairs(S.index.events) do
    local card = eventCard(ev, lat, lon)
    for k in pairs(seen) do
      local vals = k == 'category' and card.categories or { card[k] }
      for _, v in ipairs(vals) do
        if v and not seen[k][v] then seen[k][v] = true table.insert(m.facets[k], v) end
      end
    end
    local pass = matches(ev, q) and (f.country == '' or card.country == f.country) and (f.type == '' or card.type == f.type)
      and (f.category == '' or inCats(card, f.category))
      and (f.surface == '' or card.surface == f.surface) and (f.status == '' or card.status == f.status)
      and (f.near == '' or card.near)
    if pass then m.events[#m.events + 1] = card end
  end
  for k in pairs(m.facets) do table.sort(m.facets[k]) end
  -- cerca de ti primero, del más cercano al más lejano; luego en curso, próximos (por fecha) y el resto
  local rank = { live = 1, upcoming = 2, past = 3 }
  table.sort(m.events, function(x, y)
    if x.near ~= y.near then return x.near end
    if x.near and y.near and x.boxM ~= y.boxM then return x.boxM < y.boxM end
    if rank[x.status] ~= rank[y.status] then return rank[x.status] < rank[y.status] end
    if x.dates ~= y.dates then return tostring(x.dates) > tostring(y.dates) end
    return x.name < y.name
  end)
  local full = U.sel and M.event(U.sel)
  if full then
    local card
    for _, ev in ipairs(S.index.events) do if ev.id == full.id then card = eventCard(ev, lat, lon) end end
    local sel = card or { id = full.id, name = full.name }
    sel.bbox, sel.points, sel.stages, sel.liaisonKm, sel.liaisonCount = full.bbox, full.points or {}, {}, 0, #(full.liaisons or {})
    for _, l in ipairs(full.liaisons or {}) do sel.liaisonKm = sel.liaisonKm + (l.lengthM or 0) / 1000 end
    local results = stage.results()
    local n = 0
    for _, s in ipairs(full.stages or {}) do if s.kind == 'ss' then n = n + 1 end end
    for _, s in ipairs(full.stages or {}) do
      local r = results[full.id .. '/' .. s.id] or {}
      local cp = s.path and clean.stage(s) or {}
      sel.stages[#sel.stages + 1] = { id = s.id, kind = s.kind, title = s.title, runs = s.runs or {}, road = s.road,
        surface = s.surface or full.surface, best = r.best, tries = r.runs or 0, attempts = r.attempts or {},
        km = clean.length(cp) / 1000, hazards = s.hazards or {}, start = s.start, finish = s.finish,
        distM = lat and catalog.dist(lat, lon, s.start[1], s.start[2]) or nil, outline = outline(cp),
        hasReverse = M.hasReverse(full, s) }
    end
    sel.ssCount = n
    -- los enlaces, para el mapa de la ficha (línea azul discontinua)
    sel.liaisons = {}
    for _, l in ipairs(full.liaisons or {}) do
      if type(l.path) == 'table' and #l.path >= 2 then sel.liaisons[#sel.liaisons + 1] = { name = l.name, outline = outline(l.path) } end
    end
    -- el rally completo: el orden de paso y lo que se tarda (para elegir desde qué tramo empezar)
    local okI, it = pcall(rally.itinerary, full, nil, rally.LIAISON_AVG_KMH)
    if okI and it then
      sel.itinerary = {}
      local lkm, stkm = 0, 0
      for _, item in ipairs(it.items) do
        lkm = lkm + item.liaison.lengthM / 1000
        if item.stage then stkm = stkm + (item.stage.lengthM or 0) / 1000 end
        sel.itinerary[#sel.itinerary + 1] = { label = item.label, run = item.run, final = item.final,
          stageId = item.stage and item.stage.id, title = item.stage and item.stage.title or item.name,
          liaisonKm = item.liaison.lengthM / 1000, minutes = item.liaison.minutes, real = item.liaison.real }
      end
      sel.rallyKm, sel.rallyStageKm, sel.rallyLiaisonKm = lkm + stkm, stkm, lkm
      sel.hasService = it.startName ~= nil
    end
    local rr = results[full.id .. '/rally']
    sel.rallyBest = rr and rr.best or nil
    sel.rallyRuns = rr and rr.runs or 0
    m.sel = sel
  end
  return m
end

function M.publishState()
  if not (U.open or U.peek) then return end
  local ok, model = pcall(buildModel)
  if ok then guihooks.trigger('EarthRaidState', model) else log('W', TAG, 'model: ' .. tostring(model)) end
end

-- el coche quieto (la pantalla de inicio) / suelto
local function freezeCar(on)
  local v = getPlayerVehicle and getPlayerVehicle(0) or be:getPlayerVehicle(0)
  if v then pcall(function() v:queueLuaCommand('controller.setFreeze(' .. (on and 1 or 0) .. ')') end) end
end
local function navigate(route)
  local r = rawget(_G, 'ui_router')
  if r and r.navigate then return pcall(r.navigate, route) end
  return pcall(function() guihooks.trigger('ChangeState', { state = route }) end)
end

function M.uiOpen()
  refresh()
  U.open = true
  if S.proposal and not U.sel then U.sel = S.proposal.event.id end
  navigate('earthRaid')
  M.publishState()
end
function M.toggleMenu() if U.open then M.uiClose() else M.uiOpen() end end
function M.uiClose() U.open = false navigate('play') end
function M.uiState() U.open = true M.publishState() end
-- el idioma del juego para la interfaz ('es' o 'en')
function M.uiLang() return spanish() and 'es' or 'en' end
-- ¿tramo o rally en marcha? (el menú de pausa abre entonces la pestaña de Raid.Earth)
function M.uiIsActive() return (stage.state() ~= nil) or rally.active() or loader.active() end
-- el estado para la pestaña del menú de pausa (sin abrir el menú)
function M.uiPeek() refresh() U.peek = true M.publishState() end
function M.uiSearch(q) U.q = type(q) == 'string' and q:sub(1, 60) or '' M.publishState() end
function M.uiFilter(key, value)
  if U.filters[key] ~= nil then U.filters[key] = type(value) == 'string' and value or '' end
  M.publishState()
end
function M.uiSelect(id) U.sel = type(id) == 'string' and id or nil M.publishState() end
function M.uiBack() U.sel = nil M.publishState() end
function M.uiSetSetting(key, value)
  settings.set(key, value)
  if key == 'radiusKm' then S.seen = {} end
  M.publishState()
end
-- ---- importar (menú) ----
-- lo que el menú muestra de cada fuente de la carpeta de importación
function M.importsModel()
  local out = {}
  for _, i in ipairs(S.imports or {}) do
    local ev = i.event or {}
    out[#out + 1] = { key = i.key, id = i.id, status = i.status, error = i.error, files = i.files, hasLogo = i.logo ~= nil,
      logo = ev.logo and (M.IMPORTED_DIR .. i.id .. '/' .. ev.logo) or nil, meta = i.meta or {},
      name = ev.name, stageCount = ev.stageCount, stageKm = ev.stageKm, liaisonKm = ev.liaisonKm,
      stages = ev.stages, warnings = i.report and i.report.warnings or {} }
  end
  return out
end
function M.uiImportOpen(on)
  U.importOpen = on ~= false
  if U.importOpen then pcall(M.importAll, false) end
  M.publishState()
end
-- vuelve a convertir una fuente (key) o todas (nil), y relee el catálogo
function M.uiImportRun(key)
  if key and key ~= '' then
    for _, src in ipairs(scanImports()) do if src.key == key then pcall(importOne, src, true) end end
  else
    pcall(M.importAll, true)
  end
  M.loadIndex()
  M.toast((spanish() and 'Importado. Catálogo: ' or 'Imported. Catalogue: ') .. #S.index.events .. (spanish() and ' eventos' or ' events'), 5)
  M.publishState()
end
-- guarda la ficha de una fuente (json con name, short, dates, country, city, region, championship, organizer, type,
-- surface, link, description) en su event.json y la vuelve a convertir
M.META_KEYS = { 'name', 'short', 'dates', 'country', 'city', 'region', 'championship', 'organizer', 'type', 'surface',
  'link', 'description', 'source' }
function M.uiImportMeta(key, json)
  local ok, data = pcall(jsonDecode, json)
  if not ok or type(data) ~= 'table' then return end
  for _, src in ipairs(scanImports()) do
    if src.key == key then
      local meta = {}
      for _, k in ipairs(M.META_KEYS) do
        local v = data[k]
        if type(v) == 'string' then v = v:sub(1, 400):gsub('^%s+', ''):gsub('%s+$', '') end
        if v ~= nil and v ~= '' then meta[k] = v end
      end
      if meta.country then meta.country = tostring(meta.country):lower():sub(1, 2) end
      jsonWriteFile(src.metaFile, meta, true)
    end
  end
  M.uiImportRun(key)
end
-- ---- subir un evento desde el menú ----------------------------------------------------------------------------------
-- La página lee los archivos (ruta y logo) y los manda en trozos base64; aquí se validan (nombre, tipo, tamaño) y se
-- escriben solo dentro de M.IMPORT_DIR/<clave>/. Luego se guarda la ficha y se convierte como cualquier importación.
M.UPLOAD_MAX = 25 * 1024 * 1024
M.UPLOAD_CHUNK_MAX = 96 * 1024
local uploads = {}

local B64 = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
local B64I = {}
for i = 1, 64 do B64I[B64:byte(i)] = i - 1 end
local function b64decode(str)
  str = str:gsub('[^%w%+/]', '')
  local out, n = {}, #str
  local byte, char, floor = string.byte, string.char, math.floor
  for i = 1, n, 4 do
    local a, b, c, d = B64I[byte(str, i)], B64I[byte(str, i + 1) or 0], B64I[byte(str, i + 2) or 0], B64I[byte(str, i + 3) or 0]
    if not (a and b) then break end
    local v = a * 262144 + b * 4096 + (c or 0) * 64 + (d or 0)
    local b1, b2, b3 = floor(v / 65536), floor(v / 256) % 256, v % 256
    if c and d then out[#out + 1] = char(b1, b2, b3)
    elseif c then out[#out + 1] = char(b1, b2)
    else out[#out + 1] = char(b1) end
  end
  return table.concat(out)
end
M._b64decode = b64decode

local function slug(name)
  local s = tostring(name or ''):lower()
  local map = { ['á'] = 'a', ['é'] = 'e', ['í'] = 'i', ['ó'] = 'o', ['ú'] = 'u', ['ü'] = 'u', ['ñ'] = 'n', ['ç'] = 'c',
    ['à'] = 'a', ['è'] = 'e', ['ò'] = 'o', ['â'] = 'a', ['ê'] = 'e', ['ô'] = 'o', ['ã'] = 'a', ['õ'] = 'o' }
  for k, v in pairs(map) do s = s:gsub(k, v) end
  s = s:gsub('[^a-z0-9]+', '-'):gsub('^%-+', ''):gsub('%-+$', '')
  return s:sub(1, 40)
end

local function uploadEvent(data) guihooks.trigger('EarthRaidUpload', data) end

-- empieza: una carpeta nueva para el evento (nombre único)
function M.uiUploadNew(name)
  local base = slug(name)
  if base == '' then base = 'evento' end
  local key, n = base, 1
  while FS:directoryExists(M.IMPORT_DIR .. key) do n = n + 1 key = base .. '-' .. n end
  uploads = {}
  uploadEvent({ phase = 'key', key = key })
end

local function uploadName(file)
  local b = baseName(tostring(file or '')):gsub('[^%w%-_%. ]', '_')
  local e = ext(b)
  if M.LOGO_EXT[e] and e ~= 'svg' then return 'logo.' .. e, 'logo' end
  if M.ROUTE_EXT[e] and e ~= 'json' and b:lower() ~= 'event.json' then return b:sub(1, 80), 'route' end
  return nil
end

function M.uiUpload(key, file, idx, total, b64)
  key, idx, total = tostring(key or ''), tonumber(idx) or 0, tonumber(total) or 0
  local name = uploadName(file)
  local fail = function(why) uploads[key .. '/' .. tostring(file)] = nil uploadEvent({ phase = 'error', key = key, file = file, error = why }) end
  if not key:match('^[a-z0-9%-]+$') or #key > 48 then return fail('clave') end
  if not name then return fail(spanish() and 'tipo de archivo no admitido' or 'file type not supported') end
  if type(b64) ~= 'string' or #b64 > M.UPLOAD_CHUNK_MAX or idx < 1 or total < idx or total > 2000 then return fail('chunk') end
  local id = key .. '/' .. name
  if idx == 1 then uploads[id] = { parts = {}, size = 0 } end
  local u = uploads[id]
  if not u or idx ~= #u.parts + 1 then return fail('chunk order') end
  local bin = b64decode(b64)
  u.size = u.size + #bin
  if u.size > M.UPLOAD_MAX then return fail(spanish() and 'archivo demasiado grande (máx. 25 MB)' or 'file too large (max 25 MB)') end
  u.parts[idx] = bin
  if idx == total then
    local dir = M.IMPORT_DIR .. key .. '/'
    pcall(function() FS:directoryCreate(dir, true) end)
    local ok = writeFile(dir .. name, table.concat(u.parts))
    uploads[id] = nil
    if not ok then return fail('write') end
    log('I', TAG, ('upload: %s%s (%d bytes)'):format(dir, name, u.size))
    uploadEvent({ phase = 'file', key = key, file = file, bytes = u.size })
  end
end

-- termina: la ficha (nombre, descripción, enlace...) y la conversión; el menú abre la nueva importación
function M.uiUploadFinish(key, json)
  key = tostring(key or '')
  if not key:match('^[a-z0-9%-]+$') then return end
  local dir = M.IMPORT_DIR .. key .. '/'
  if not FS:directoryExists(dir) then uploadEvent({ phase = 'error', key = key, error = spanish() and 'no hay ruta' or 'no route' }) return end
  local ok, data = pcall(jsonDecode, json or '{}')
  if ok and type(data) == 'table' then
    local meta = {}
    for _, k in ipairs(M.META_KEYS) do
      local v = data[k]
      if type(v) == 'string' then v = v:sub(1, 1200):gsub('^%s+', ''):gsub('%s+$', '') end
      if v ~= nil and v ~= '' then meta[k] = v end
    end
    jsonWriteFile(dir .. 'event.json', meta, true)
  end
  M.uiImportRun(key)
  uploadEvent({ phase = 'done', key = key })
end

-- abre la página de la fuente de un evento en el navegador (solo http/https)
function M.uiOpenLink(url)
  if type(url) == 'string' and url:match('^https?://[%w%.%-]+') then pcall(openWebBrowser, url) end
end
function M.uiImportFolder()
  pcall(function() FS:directoryCreate(M.IMPORT_DIR, true) end)
  local ok = pcall(function() Engine.Platform.exploreFolder(M.IMPORT_DIR) end)
  if not ok then M.toast(FS:getUserPath() .. 'settings\\earthRaid\\import', 8) end
end

-- vuelve a leer el catálogo (paquetes nuevos, KML añadidos a la carpeta de importación)
function M.uiReload()
  M.loadIndex()
  M.toast((spanish() and 'Catálogo: ' or 'Catalogue: ') .. #S.index.events .. (spanish() and ' eventos' or ' events'), 5)
  M.publishState()
end

-- Ir a la salida de un tramo: mode 'gps' | 'teleport'
-- El tramo al revés: mismo trazado de la meta a la salida (id con R, sus propios tiempos)
-- ¿El rally corre este tramo también al revés? (otro tramo que empieza donde este acaba y acaba donde empieza, o
-- una ida y vuelta como Ourense). Solo entonces se ofrece el sentido inverso.
M.REVERSE_MATCH_M = 200
-- Norma (17-nov): «SS 2/5» (una barra y dos números) son dos tramos en la misma carretera, cada uno en un sentido:
-- la primera pasada en el sentido del archivo y la segunda al revés. Así que un tramo con dos o más pasadas tiene
-- inverso, igual que uno cuyo trazado contrario está en el evento.
function M.hasReverse(full, s)
  if s.kind == 'ss' and #(s.runs or {}) >= 2 then return true end
  if not (s.start and s.finish) then return false end
  for _, o in ipairs(full.stages or {}) do
    if o ~= s and o.start and o.finish and catalog.dist(o.start[1], o.start[2], s.finish[1], s.finish[2]) < M.REVERSE_MATCH_M
      and catalog.dist(o.finish[1], o.finish[2], s.start[1], s.start[2]) < M.REVERSE_MATCH_M then return true end
  end
  return false
end

function M.reversed(s) return catalog.reversed(s, spanish()) end
local function stageOf(full, stageId, reverse)
  for _, s in ipairs(full.stages or {}) do
    if s.id == stageId or s.id .. 'R' == stageId then
      if reverse == true or reverse == 'true' or stageId == s.id .. 'R' then return M.reversed(s), s end
      return s, s
    end
  end
end

function M.uiGo(eventId, stageId, mode, reverse)
  local a, full = api(), M.event(eventId)
  if not (a and full) then return end
  local sR = stageOf(full, stageId, reverse)
  for _, s in ipairs({ sR }) do
    do
      local label = full.name .. ' - ' .. s.title
      S.target = { eventId = eventId, stageId = stageId }
      local ok, err
      local es = spanish()
      local tcLat, tcLon = rally.tcPoint(s)
      local tcLabel = 'TC · ' .. s.title
      if mode == 'teleport' then
        -- ahora el teletransporte es "iniciar con carga" (el tramo se prepara y el coche llega a la calzada)
        M.uiClose()
        return M.uiPlay(eventId, stageId, reverse)
      elseif mode == 'teleportOld' then
        -- a la carretera, M.TP_BEFORE_TC_M antes del control horario y mirando hacia él (antes: al aparcamiento más
        -- cercano, que en Obejo era monte); al llegar se coloca el coche en la calzada (onBeamNGEarthTeleported)
        local t = geo.track(clean.stage(s))
        local dx, dy = geo.dirAt(t, 0)
        local back = dressing.TC_BEFORE_M + M.TP_BEFORE_TC_M
        local tlat, tlon = geo.toGeo(t, t.pts[1][1] - dx * back, t.pts[1][2] - dy * back)
        -- mejor por el enlace del organizador que toca la salida (la carretera por la que se llega al TC)
        local road = M.roadFromStart(full, s)
        if road then
          tlat, tlon = geo.toGeo(road, geo.at(road, math.min(back, road.total)))
          tcLat, tcLon = geo.toGeo(road, geo.at(road, math.min(dressing.TC_BEFORE_M, road.total)))
        end
        local okT, errT = a.teleport(tlat, tlon, label)
        if okT then
          S.afterTp = { lat = tcLat, lon = tcLon, name = tcLabel, snap = true }
          M.toast((es and 'Cerca del control horario de ' or 'Near the time control of ') .. s.title
            .. (es and ': sigue el GPS y para en el control para fichar.' or ': follow the GPS and stop at the control to check in.'), 8)
          M.uiClose()
        else
          M.toast('Raid.Earth: ' .. tostring(errT or 'no se pudo'), 6)
          M.publishState()
        end
      else
        ok, err = a.gpsSet(tcLat, tcLon, tcLabel)
        if ok then
          M.toast((es and 'GPS al control horario de ' or 'GPS set to the time control of ') .. s.title, 6)
          M.uiClose()
        else
          M.toast('Raid.Earth: ' .. tostring(err or 'no se pudo'), 6)
          M.publishState()
        end
      end
      return
    end
  end
end

-- Las apps del tramo en el diseño de apps del jugador: la nuestra arriba a la izquierda (como la barra de tramo del
-- juego) y la nativa de notas visuales en el centro
local function ensureHud()
  local L = rawget(_G, 'ui_appLayouts')
  if not (L and L.getCurrentLayout and L.addApp) then return false end
  local ok, cur = pcall(L.getCurrentLayout)
  if not ok or type(cur) ~= 'table' or not cur.filename then return false end
  local has = {}
  for _, a in ipairs(cur.apps or {}) do has[a.appName] = true end
  local changed = false
  -- la nuestra ocupa toda la pantalla (sin bloquear el ratón): dentro, la barra va arriba a la izquierda y la tarjeta al
  -- centro; si estaba con la colocación de una versión anterior, se cambia
  for i, a in ipairs(cur.apps or {}) do
    if a.appName == M.HUD_APP and not (a.placement and a.placement.width == '100%') then
      pcall(L.removeApp, cur.filename, i - 1)
      has[M.HUD_APP] = nil
      break
    end
  end
  if not has[M.HUD_APP] then
    changed = pcall(L.addApp, cur.filename, M.HUD_APP, { left = '0px', top = '0px', width = '100%', height = '100%', position = 'absolute' }) or changed
  end
  -- las notas, arriba en el centro (más altas que antes: ya no a 300 px); se recolocan si eran de una versión anterior
  local ok2, cur2 = pcall(L.getCurrentLayout)
  if ok2 and type(cur2) == 'table' then cur = cur2 end
  for i, a in ipairs(cur.apps or {}) do
    if a.appName == M.NATIVE_VISUAL and a.placement and a.placement.top ~= M.NOTES_TOP then
      pcall(L.removeApp, cur.filename, i - 1)
      has[M.NATIVE_VISUAL] = nil
      break
    end
  end
  if not has[M.NATIVE_VISUAL] then
    changed = pcall(L.addApp, cur.filename, M.NATIVE_VISUAL, { left = 0, right = 0, margin = 'auto', top = M.NOTES_TOP, width = '400px', height = '160px' }) or changed
  end
  if changed then
    pcall(function() guihooks.trigger('UiAppLayoutsChanged') end)
    pcall(L.setCurrentLayout, cur.filename)
  end
  return changed
end

-- Comenzar un tramo: coloca sus objetos y arranca las fases (ir a la salida, colocarse, cuenta atrás, crono)
function M.uiStart(eventId, stageId, reverse, graphReady)
  local a, full = api(), M.event(eventId)
  if not (a and full) then return end
  local n, count, number = 0, 0, nil
  local play, base = stageOf(full, stageId, reverse)
  for _, s in ipairs(full.stages or {}) do if s.kind == 'ss' then count = count + 1 end end
  for _, s0 in ipairs(full.stages or {}) do
    if s0.kind == 'ss' then n = n + 1 end
    if s0 == base then
      local s = play
      number = s0.kind == 'ss' and n or nil
      local ok, err = stage.start(full, s, { number = number, count = count, graphReady = graphReady == true })
      if not ok then M.toast('Raid.Earth: ' .. tostring(err), 6) return end
      stage.setLang(spanish() and 'es' or 'en')
      S.target = { eventId = eventId, stageId = s.id }
      M.toast((spanish() and 'Tramo preparado: ' or 'Stage ready: ') .. s.title, 6)
      M.uiClose()
      return
    end
  end
end

function M.uiCancelStage()
  if S.pre then S.pre = nil freezeCar(false) end
  if loader.active() then pcall(loader.cancel) stage.holdJobs(false) end
  if rally.active() then rally.stop() else stage.stop() end
  M.publishState()
end

-- La pantalla de carga primero, y debajo de ella lo que se ve raro si se hace a la vista (quitar los objetos, cambiar
-- las apps, mover el coche): abandonar y reiniciar (19-nov). MARK:cover-v1
local function coverSpec(statusEs, statusEn, run)
  local es = spanish()
  local st, rs = stage.state(), rally.active() and rally.state() or nil
  local evId = (st and st.eventId) or (rs and rs.ev and rs.ev.id) or (S.pre and S.pre.eventId)
  local full = evId and M.event(evId) or nil
  return { title = (st and st.title) or (full and full.name) or 'Raid.Earth', event = full and full.name or nil,
    logo = full and full._base and full.logo and (full._base .. full.logo) or nil, lang = es and 'es' or 'en',
    description = full and M.loadingText(full, nil, es) or nil, status = es and statusEs or statusEn, run = run }
end

-- Abandonar (los botones del menú): con la pantalla puesta, se quita todo
function M.uiAbandon()
  if not M.busy() then M.publishState() return end
  if loader.active() then M.uiCancelStage() return end
  loader.cover(coverSpec('Abandonando el evento…', 'Retiring from the event…', function() M.uiCancelStage() end))
end

-- Reiniciar el tramo en marcha: otra vez desde 100 m antes del TC, con su pantalla de carga (como "reintentar" del juego)
function M.uiRestartStage()
  local st = stage.state()
  if not st or loader.active() then return end
  local ev, sid = st.eventId, tostring(st.stageId)
  local base = sid:gsub('R$', '')
  local rev = base ~= sid
  local spec = coverSpec('Reiniciando el tramo…', 'Restarting the stage…', function()
    M.uiCancelStage()
    S.noPre = true
    pcall(M.uiPlay, ev, base, rev, true)
    S.noPre = nil
  end)
  M.uiClose()
  loader.cover(spec)
end

-- Rally completo: reiniciar desde el último control horario (la pasada en curso) o desde el principio
function M.uiRestartRally(fromLastTc)
  local R = rally.state()
  if not R or loader.active() then return end
  local evId = R.ev and R.ev.id
  local item = R.it and R.it.items and R.it.items[R.idx]
  local run = fromLastTc and item and item.run or nil
  local spec = coverSpec('Reiniciando el rally…', 'Restarting the rally…', function()
    M.uiCancelStage()
    if evId then M.uiStartRally(evId, run, true) end
  end)
  M.uiClose()
  loader.cover(spec)
end

-- Rally completo desde la pasada fromRun (nil: desde el principio): TC0 en la asistencia, enlaces, controles y tramos
-- Iniciar con carga: el tramo se prepara, el coche va a la zona de salida congelado, se espera a las carreteras, se
-- monta el TC y la salida, y se suelta en la calzada M.TP_BEFORE_TC_M antes del control (loader.lua)
-- el texto de la pantalla de carga: la descripción del evento, y si no tiene, los datos del tramo
function M.loadingText(full, s, es)
  local d = full.description or full.desc
  if type(d) == 'table' then d = d[es and 'es' or 'en'] or d.es or d.en end
  if type(d) == 'string' and d ~= '' then return d:sub(1, 400) end
  local parts = {}
  if full.championship then parts[#parts + 1] = tostring(full.championship) end
  if full.dates then parts[#parts + 1] = tostring(full.dates) end
  if s and s.lengthM then parts[#parts + 1] = ('%.2f km'):format(s.lengthM / 1000) end
  if s and (s.surface or full.surface) then parts[#parts + 1] = tostring(s.surface or full.surface) end
  return #parts > 0 and table.concat(parts, ' · ') or nil
end
M.PLAY_TELEPORT_M = 1000     -- más lejos que esto de la salida: con teletransporte y carga; si no, se empieza ahí mismo
-- ¿hay algo en marcha? (tramo, rally, carga, pantalla de inicio)
function M.busy()
  return (S.pre or stage.state() or loader.active() or rally.active()) and true or false
end
-- Un evento cada vez (19-nov): con otro en marcha no se empieza ninguno hasta abandonarlo. `force` solo lo usan los
-- reinicios y la auditoría, que ya han cancelado lo anterior.
local function refuseIfBusy(force)
  if force or not M.busy() then return false end
  M.toast(spanish() and 'Ya hay un evento en marcha: abandónalo (Esc → Raid.Earth → Abandonar) antes de empezar otro.'
    or 'An event is already running: retire from it (Esc → Raid.Earth → Retire) before starting another.', 8)
  return true
end
function M.uiPlay(eventId, stageId, reverse, force)
  if refuseIfBusy(force) then return end
  local a, full = api(), M.event(eventId)
  if not (a and full) then return end
  local s = stageOf(full, stageId, reverse)
  if not s then return end
  -- siempre con la pantalla de carga (aunque ya estés al lado): se colocan los objetos y, listo, aparece al instante
  -- la pantalla de inicio con el coche parado
  -- lejos: primero el viaje y las carreteras de la zona; el tramo se monta cuando el grafo está cargado allí (18-nov:
  -- así la salida y el control horario se validan contra carreteras de verdad antes de montarse)
  local t = geo.track(clean.stage(s))
  local dx, dy = geo.dirAt(t, 0)
  local back = dressing.TC_BEFORE_M + M.TP_BEFORE_TC_M
  local tlat, tlon = geo.toGeo(t, t.pts[1][1] - dx * back, t.pts[1][2] - dy * back)
  local road = M.roadFromStart(full, s)
  if road then tlat, tlon = geo.toGeo(road, geo.at(road, math.min(back, road.total))) end
  local es = spanish()
  local noPre = S.noPre == true      -- reinicio: sin la pantalla de inicio (se mira ahora: done llega mucho después)
  stage.holdJobs(true)
  local ok, err = loader.begin({
    title = s.title, event = full.name, lang = es and 'es' or 'en', keepFrozen = not noPre,
    fail = function(e)
      stage.holdJobs(false)
      M.toast((es and 'No se puede viajar ahora: ' or 'Cannot travel now: ') .. tostring(e), 6)
      M.publishState()
    end,
    logo = full._base and full.logo and (full._base .. full.logo) or nil,
    description = M.loadingText(full, s, es),
    tpLat = tlat, tpLon = tlon,
    -- (el TC aún es aproximado: se calcula por la carretera real al montar la salida)
    near = { { s.start[1], s.start[2] } },
    dress = function()
      if not stage.state() then
        -- (si las carreteras no llegaron a tiempo, la salida no se valida contra un grafo vacío)
        M.uiStart(eventId, stageId, reverse, loader.roadsOk())
        if not stage.state() then return 0 end
        return 1
      end
      stage.holdJobs(false)
      local pl, po = a.position()
      if pl then dressing.runJobsNear(pl, po, 2) end
      local left = props.pump(loader.PUMP_MS)
      return (pl and dressing.pendingJobsNear(pl, po) or 0) + left
    end,
    place = function()
      local cur = stage.state()
      if not (cur and cur.track) then return end
      stage.retryStart()
      local tt = cur.track
      local atLat, atLon = dressing.lineAt(tt, 0, -(dressing.tcAt(tt) + M.TP_BEFORE_TC_M))
      if not M.placeOnRoad(cur.tcLat, cur.tcLon, atLat, atLon) then
        -- sin carretera del juego por ahí: en la calzada del control (que siempre está en carretera), unos metros
        -- antes, mirando al control
        local bl, bo = dressing.lineAt(tt, 0, -(dressing.tcAt(tt) + 12))
        if not (bl and M.placeOnRoad(cur.tcLat, cur.tcLon, bl, bo)) then
          M.placeAt(cur.tcLat, cur.tcLon, cur.line and cur.line.lat or cur.tcLat, cur.line and cur.line.lon or cur.tcLon)
        end
      end
    end,
    done = function()
      stage.holdJobs(false)
      local cur = stage.state()
      if cur and cur.tcLat and a.gpsSet then pcall(a.gpsSet, cur.tcLat, cur.tcLon, 'TC · ' .. s.title) end
      -- la pantalla de inicio (resumen, normas, ajustes, Iniciar); el coche espera congelado
      if cur and not noPre then M.preStart('stage', eventId, stageId, reverse)
      else
        freezeCar(false)
        if cur then M.toast((es and 'Listo: para en el control horario para fichar.' or 'Ready: stop at the time control to check in.'), 8) end
      end
    end })
  if not ok then
    stage.holdJobs(false)
    M.toast((es and 'No se puede viajar ahora: ' or 'Cannot travel now: ') .. tostring(err), 6)
  else
    -- el menú (y el de pausa) fuera ya, debajo de la pantalla de carga: con el juego en pausa la carga no avanza
    M.uiClose()
  end
end

function M.uiStartRally(eventId, fromRun, force)
  if refuseIfBusy(force) then return end
  local a, full = api(), M.event(eventId)
  if not (a and full) then return end
  if S.pre or (loader.active() and not loader.covering()) then pcall(M.uiCancelStage) end
  stage.stop()
  -- los objetos de la carrera anterior (boxes, TC0 del parque) fuera: si no, al reiniciar quedaban dos TC juntos
  pcall(props.clear)
  S.box, S.park = nil, nil
  local ok, err = rally.start(full, tonumber(fromRun), { onEnd = function() M.publishState() end })
  if not ok then M.toast('Raid.Earth: ' .. tostring(err), 6) return end
  rally.state().lang = spanish() and 'es' or 'en'
  -- (18-nov) ya no se añaden apps a las disposiciones del jugador: las del juego van en earthRaidLoop/earthRaidStage
  S.target = { eventId = eventId }
  local rs = rally.state()
  local start = rs.it.start
  local lat, lon = a.position()
  local es = spanish()
  -- siempre con la pantalla de carga: el parque (boxes, TC0) se monta en ella aunque ya estés al lado
  if start and lat then
    -- al parque de asistencia con carga: el box se monta y el coche aparece en él, no en el monte
    loader.begin({ title = es and 'Parque de asistencia' or 'Service park', event = full.name, lang = es and 'es' or 'en', keepFrozen = true,
      fail = function(e)
        pcall(rally.stop)
        M.toast((es and 'No se puede viajar ahora: ' or 'Cannot travel now: ') .. tostring(e), 6)
        M.publishState()
      end,
      logo = full._base and full.logo and (full._base .. full.logo) or nil, tpLat = start[1], tpLon = start[2],
      description = M.loadingText(full, nil, es),
      near = { { start[1], start[2], 150 } },
      dress = function()
        -- el parque de asistencia: en la mejor explanada cerca del punto del organizador (un aparcamiento, un
        -- descampado con salida a la carretera, llano: servicepark.lua), con sus boxes y el TC0 a la salida; si no
        -- hay sitio, el box de siempre junto a la asistencia
        local first = rs.it and rs.it.items and rs.it.items[1]
        local tw = first and first.stage and first.stage.start
        if S.box == nil then
          if not S.park then S.park = servicepark.search(start[1], start[2], tw and tw[1], tw and tw[2]) or false end
          if S.park and not servicepark.step(S.park, 8) then return 1 end
          local site = S.park and S.park.site
          if site then
            S.box = servicepark.build(site) or false
            local ok, tc = pcall(servicepark.tc0, site, dressing)
            if ok and tc then rally.setTc0(tc.lat, tc.lon) else log('W', TAG, 'TC0: ' .. tostring(tc)) end
          end
          if not S.box then S.box = dressing.serviceBox(start[1], start[2], tw and tw[1], tw and tw[2]) or false end
        end
        local pl, po = a.position()
        if pl then dressing.runJobsNear(pl, po, 2) end
        return (pl and dressing.pendingJobsNear(pl, po) or 0) + props.pump(loader.PUMP_MS)
      end,
      place = function()
        -- de cara al primer control horario (norma 17-nov: orientado hacia el siguiente TC)
        local first = rs.it and rs.it.items and rs.it.items[1]
        local tw = first and first.stage and first.stage.start
        if S.box then M.placeAt(S.box.lat, S.box.lon, S.box.faceLat or (tw and tw[1]), S.box.faceLon or (tw and tw[2]))
        else M.placeOnRoad(start[1], start[2]) end
      end,
      done = function() if rally.active() and not S.noPre then M.preStart('rally', eventId) else freezeCar(false) end end })
    rally.hold(true)
    M.uiClose()
  else
    M.preStart('rally', eventId)
  end
end

-- ---- la pantalla de inicio (como la del modo rally del juego): tras la carga, con el coche parado en el box o antes
-- del control, el resumen, las normas y los ajustes; Iniciar suelta el coche. Petición del usuario, 19-nov: "los
-- Ajustes quitarlos de este menú y ponerlos en otro menú que aparece después de la pantalla de carga".
function M.preStart(kind, eventId, stageId, reverse)
  if S.noPre then return end
  S.pre = { kind = kind, eventId = eventId, stageId = stageId, reverse = reverse == true }
  freezeCar(true)
  if kind == 'rally' then rally.hold(true) end
  U.sel, U.open = eventId, true
  navigate('earthRaidStart')
  M.publishState()
end
-- Iniciar
function M.uiPreGo()
  local p = S.pre
  if not p then M.uiClose() return end
  S.pre = nil
  freezeCar(false)
  local es = spanish()
  if p.kind == 'rally' then
    local rs = rally.state()
    rally.hold(false)
    if rs then
      M.toast((es and 'Rally completo: sales de la asistencia a las ' or 'Full rally: you leave the service park at ')
        .. rally.hhmm(rs.startMin * 60) .. (es and ' (Mayús+E: salir ya).' or ' (Shift+E: leave now).'), 10)
    end
  else
    M.toast((es and 'Listo: para en el control horario para fichar.' or 'Ready: stop at the time control to check in.'), 8)
  end
  M.uiClose()
end
-- la flecha de volver: se deja el tramo (o el rally) y se vuelve a la ficha del evento
function M.uiPreBack()
  if S.pre then S.pre = nil freezeCar(false) M.uiCancelStage() end
  M.uiOpen()
end
-- la pantalla se cerró sin Iniciar (Esc): como volver, sin abrir el menú
function M.uiPreLeft()
  if S.pre then S.pre = nil freezeCar(false) M.uiCancelStage() end
end
function M.uiSkipLiaison()
  local ok = rally.skipLiaison()
  M.toast(ok and (spanish() and 'Enlace saltado: llegas al control a tu hora.' or 'Liaison skipped: you reach the control on time.')
    or (spanish() and 'Ahora no hay un enlace que saltar.' or 'No liaison to skip right now.'), 6)
  if ok then M.uiClose() else M.publishState() end
end

function M.skipWait() return rally.skip() or stage.skipWait() end
function M.sendHud() stage.sendHud() rally.sendHud() end

-- ---- hooks del juego y de BeamNG.Earth -----------------------------------------------------------------------------


-- Versiones anteriores metían nuestra app (EarthRaidHud) y las notas visuales en las disposiciones de apps del jugador
-- (la de BeamNG.Earth, la radial...): se quitan, para no tocar el juego base
local function cleanLayouts()
  local L = rawget(_G, 'ui_appLayouts')
  if not (L and L.getAvailableLayouts and L.removeApp) then return end
  local ok, list = pcall(L.getAvailableLayouts)
  if not ok or type(list) ~= 'table' then return end
  local n = 0
  for _, lay in pairs(list) do
    local fn = type(lay) == 'table' and lay.filename
    if fn and not fn:find('earthRaid', 1, true) then
      for i = #(lay.apps or {}), 1, -1 do
        local a = lay.apps[i]
        if a.appName == M.HUD_APP or (a.appName == M.NATIVE_VISUAL and a.placement and a.placement.top == M.NOTES_TOP) then
          if pcall(L.removeApp, fn, i - 1) then n = n + 1 end
        end
      end
    end
  end
  if n > 0 then log('I', TAG, ('removed %d Raid.Earth apps from the player layouts'):format(n)) end
end
M.cleanLayouts = cleanLayouts

function M.onExtensionLoaded()
  pcall(guide.restoreBlueLine)
  pcall(function()
    local n = require('earthRaid/props').purgeOrphans()
    if n > 0 then log('I', TAG, 'removed ' .. n .. ' leftover objects') end
  end)
  M.loadIndex()
  pcall(cleanLayouts)
  refresh()
  if settings.get().recModsAuto ~= false then pcall(M.enableRecommended) end
  S.earthLevel = M.isEarthLevel()
  log('I', TAG, 'Raid.Earth ' .. M.VERSION .. ' loaded (' .. S.reason .. ')')
end

M.TP_BEFORE_TC_M = 100
-- la carretera que sale de la salida del tramo hacia fuera, por el enlace del organizador que la toca (o nil)
function M.roadFromStart(full, s)
  local f = s.path and s.path[1]
  if not f then return nil end
  local k = math.cos(math.rad(f[1]))
  local function d(p) return math.sqrt(((p[2] - f[2]) * 111195 * k) ^ 2 + ((p[1] - f[1]) * 111195) ^ 2) end
  local best, bd = nil, 80
  for _, l in ipairs(full.liaisons or {}) do
    if l.path and #l.path >= 2 then
      if d(l.path[1]) < bd then best, bd = l.path, d(l.path[1]) end
      if d(l.path[#l.path]) < bd then
        local rev = {}
        for i = #l.path, 1, -1 do rev[#rev + 1] = l.path[i] end
        best, bd = rev, d(l.path[#l.path])
      end
    end
  end
  if not best then return nil end
  local pts = { f }
  for _, p in ipairs(best) do pts[#pts + 1] = p end
  local ok, tr = pcall(geo.track, pts)
  return ok and tr or nil
end
function M.snapAfter(lat, lon) S.afterTp = { lat = lat, lon = lon, snap = true, noGps = true } end
-- El coche, en la calzada de la carretera más cercana (en su carril, el derecho si es de doble sentido), mirando hacia
-- (lat, lon): nunca en el monte ni dentro de una casa tras un teletransporte
-- el coche en (lat, lon), en el suelo, mirando hacia (faceLat, faceLon) (el box del parque de asistencia)
function M.placeAt(lat, lon, faceLat, faceLon)
  local a, v = api(), be:getPlayerVehicle(0)
  if not (a and v and lat) then return false end
  local x, y = a.toGame(lat, lon, 0)
  local fx, fy = a.toGame(faceLat or lat, faceLon or lon, 0)
  local gz = core_terrain and core_terrain.getTerrainHeight and core_terrain.getTerrainHeight(vec3(x, y, 0)) or v:getPosition().z
  local hz = be:getSurfaceHeightBelow(vec3(x, y, (gz or 0) + 0.6))
  local z = (type(hz) == 'number' and hz > -1e5) and hz or gz
  local dir = vec3((fx or x + 1) - x, (fy or y) - y, 0)
  if dir:length() < 0.1 then dir = vec3(1, 0, 0) end
  spawn.safeTeleport(v, vec3(x, y, z + 0.3), quatFromDir(dir:normalized(), vec3(0, 0, 1)), nil, nil, false, nil, true)
  return true
end

function M.placeOnRoad(lat, lon, atLat, atLon)
  local a, v = api(), be:getPlayerVehicle(0)
  if not (a and v) then return false end
  local p = v:getPosition()
  if atLat then
    local x, y, z = a.toGame(atLat, atLon, 0)
    if x then p = vec3(x, y, (core_terrain and core_terrain.getTerrainHeight and core_terrain.getTerrainHeight(vec3(x, y, 0))) or p.z) end
  end
  local n1, n2, d = props.nearestRoad(p.x, p.y, p.z, 300)
  local m = map.getMap()
  if not (n1 and n2 and d and d < 300 and m.nodes[n1] and m.nodes[n2]) then return false end
  local A, B = m.nodes[n1].pos, m.nodes[n2].pos
  -- en un pueblo la carretera más cercana puede ser una calle que cruza: de las que pasan a pocos metros, la que va
  -- hacia el control horario (17-nov: el coche aparecía de cara a una pared en Ourense)
  pcall(function()
    local tx, ty = a.toGame(lat, lon, 0)
    if not tx then return end
    local wx, wy = tx - p.x, ty - p.y
    local wl = math.sqrt(wx * wx + wy * wy)
    if wl < 1 then return end
    wx, wy = wx / wl, wy / wl
    local best, bscore = nil, -1
    for _, sg in ipairs(props.roadsAt(p.x, p.y) or {}) do
      if not sg.virtual then
        local gx, gy = sg.bx - sg.ax, sg.by - sg.ay
        local gl2 = gx * gx + gy * gy
        if gl2 > 1 then
          local u = math.max(0, math.min(1, ((p.x - sg.ax) * gx + (p.y - sg.ay) * gy) / gl2))
          local dd = math.sqrt((p.x - sg.ax - gx * u) ^ 2 + (p.y - sg.ay - gy * u) ^ 2)
          local al = math.abs((gx * wx + gy * wy) / math.sqrt(gl2))
          local score = al - dd / 20
          if dd < 12 and score > bscore then best, bscore = sg, score end
        end
      end
    end
    if best and bscore > 0.5 then A, B = vec3(best.ax, best.ay, A.z), vec3(best.bx, best.by, B.z) end
  end)
  local sx, sy = B.x - A.x, B.y - A.y
  local L2 = sx * sx + sy * sy
  if L2 < 0.01 then return false end
  local u = math.max(0, math.min(1, ((p.x - A.x) * sx + (p.y - A.y) * sy) / L2))
  local cx, cy = A.x + sx * u, A.y + sy * u
  local L = math.sqrt(L2)
  local hx, hy = sx / L, sy / L
  local tx, ty = a.toGame(lat, lon, 0)
  if tx and ((tx - cx) * hx + (ty - cy) * hy) < 0 then hx, hy = -hx, -hy end
  local link = m.nodes[n1].links and m.nodes[n1].links[n2] or (m.nodes[n2].links and m.nodes[n2].links[n1])
  local r = m.nodes[n1].radius or 3
  local off = (link and link.oneWay) and 0 or r * 0.5
  local px, py = cx + hy * off, cy - hx * off
  local gz = core_terrain and core_terrain.getTerrainHeight and core_terrain.getTerrainHeight(vec3(px, py, 0)) or p.z
  local hz = be:getSurfaceHeightBelow(vec3(px, py, (gz or p.z) + 0.6))
  local z = (type(hz) == 'number' and hz > -1e5) and hz or gz or p.z
  local q = quatFromDir(vec3(hx, hy, 0), vec3(0, 0, 1))
  spawn.safeTeleport(v, vec3(px, py, z + 0.3), q, nil, nil, false, nil, true)
  log('I', TAG, ('placed on the road (%.0f m from where it landed)'):format(math.sqrt((px - p.x) ^ 2 + (py - p.y) ^ 2)))
  return true
end

-- tras el teletransporte al box: GPS al control horario cuando el mundo ya está listo (BeamNG.Earth limpia el GPS
-- al teletransportar)
local function afterTeleport(dt)
  local tp = S.afterTp
  if not tp then return end
  tp.t = (tp.t or 0) + (dt or 0)
  local a = api()
  if tp.t > 4 and a and a.ready and a.ready() then
    if tp.snap then
      -- BeamNG.Earth deja el coche en el suelo unos segundos después del aviso: se coloca en la calzada y se vuelve a
      -- mirar dos veces más por si lo ha movido después
      tp.tries = (tp.tries or 0) + 1
      local v = be:getPlayerVehicle(0)
      local _, _, d = v and map.findClosestRoad(v:getPosition())
      -- con el tramo montado: justo M.TP_BEFORE_TC_M antes de su control horario, por la carretera real que llega a él
      local atLat, atLon
      local st = stage.state()
      if st and st.track and st.track.before and not tp.noGps then
        local t = st.track
        local need = dressing.tcAt(t) + M.TP_BEFORE_TC_M
        atLat, atLon = dressing.lineAt(t, 0, -need)
        if st.tcLat then tp.lat, tp.lon = st.tcLat, st.tcLon end
      end
      if atLat and not tp.atDone then
        tp.atDone = true
        local okS, err = pcall(M.placeOnRoad, tp.lat, tp.lon, atLat, atLon)
        if not okS then log('W', TAG, 'place on road: ' .. tostring(err)) end
      elseif not d or d > 2.5 then
        local okS, err = pcall(M.placeOnRoad, tp.lat, tp.lon)
        if not okS then log('W', TAG, 'place on road: ' .. tostring(err)) end
      end
      if tp.tries < 3 then tp.t = 1 if tp.tries == 1 and a.gpsSet and not tp.noGps then pcall(a.gpsSet, tp.lat, tp.lon, tp.name) end return end
    end
    S.afterTp = nil
    if a.gpsSet and not tp.noGps and not tp.snap then pcall(a.gpsSet, tp.lat, tp.lon, tp.name) end
  elseif tp.t > 120 then S.afterTp = nil end
end

-- El diseño de apps de rally mientras hay un tramo o un rally en marcha (como el juego en sus rallies): cronómetro y
-- notas, volante, pedales, fuerzas g, cuentakilómetros, daños; sin minimapa (manda el copiloto). Al terminar, el de antes.
-- las disposiciones de apps del rally del juego (rallyModeStage y rallyModeLoop) con los créditos del mapa
M.RACE_LAYOUT = '/settings/ui_apps/layouts/default/earthRaidStage.uilayout.json'
M.LOOP_LAYOUT = '/settings/ui_apps/layouts/default/earthRaidLoop.uilayout.json'
M.HC_LAYOUT = '/settings/ui_apps/layouts/default/earthRaidHardcore.uilayout.json'
local vhud = require('earthRaid/vhud')
local guard = require('earthRaid/guard')
local audit = require('earthRaid/audit')
M.audit = audit
local layoutT = 0
local function raceLayout(dt)
  layoutT = layoutT + (dt or 0)
  if layoutT < 1 then return end
  layoutT = 0
  local L = rawget(_G, 'ui_appLayouts')
  if not (L and L.getCurrentLayout and L.setCurrentLayout) then return end
  -- el diseño de rally del juego es fijo (no es un ajuste: vanilla no lo tiene); en hardcore, el mínimo
  local on = stage.active() or rally.active()
  local cur = L.getCurrentLayout()
  local curName = type(cur) == 'table' and cur.filename or nil
  local want = settings.get().hardcore and M.HC_LAYOUT or (vhud.wantsStageLayout(stage) and M.RACE_LAYOUT or M.LOOP_LAYOUT)
  local function ours(n) return n == M.RACE_LAYOUT or n == M.LOOP_LAYOUT or n == M.HC_LAYOUT end
  if on then
    if curName ~= want then
      if not S.prevLayout or ours(S.prevLayout) then
        if not ours(curName) then S.prevLayout = curName end
      end
      if not L.setCurrentLayout(want) then
        log('W', TAG, 'race layout not found: ' .. want)
        S.layoutFailed = true
      end
    end
  elseif S.prevLayout then
    if ours(curName) then pcall(L.setCurrentLayout, S.prevLayout) end
    S.prevLayout = nil
  end
end

-- Modo hardcore: sin reparar ni restablecer el coche (las acciones del juego se filtran), sin la línea azul ni las
-- flechas del GPS; la voz del copiloto y el HUD mínimo (settings.lua las notas, la línea de carrera...; layout aparte)
local hcOn = false
local HC_GROUPS = { 'vehicleTeleporting', 'resetPhysics', 'vehicleRecovery', 'vehicleMenues', 'physicsControls', 'vehicleSwitching',
  'miniMap', 'bigMap', 'aiControls' }
local function hardcoreTick()
  local want = settings.get().hardcore == true and (stage.active() or rally.active() or loader.active() or S.pre ~= nil)
  if want == hcOn then return end
  hcOn = want
  local F = rawget(_G, 'core_input_actionFilter')
  if F and F.setGroup and F.addAction then
    local list = {}
    local T = F.getActionTemplates and F.getActionTemplates() or {}
    for _, k in ipairs(HC_GROUPS) do for _, a in ipairs(T[k] or {}) do list[#list + 1] = a end end
    pcall(F.setGroup, 'earthRaidHardcore', list)
    pcall(F.addAction, 0, 'earthRaidHardcore', want)
  end
  pcall(guide.hideNav, want)
  log('I', TAG, 'hardcore ' .. (want and 'on' or 'off'))
end
function M.hardcoreActive() return hcOn end

function M.onUpdate(dtReal, dtSim)
  if S.earthLevel == nil then S.earthLevel = M.isEarthLevel() end
  if not S.earthLevel and not (loader.active() or stage.active() or rally.active()) then return end
  pcall(afterTeleport, dtReal)
  if audit.active() then pcall(audit.update, dtReal) end
  if not loader.active() and not audit.active() then
    pcall(guard.update, stage, rally, function()
      M.toast(spanish() and 'Cambio de vehículo durante el tramo: tramo anulado.' or 'Vehicle changed during the stage: stage cancelled.', 8)
      pcall(M.uiCancelStage)
    end)
  end
  if loader.active() then
    local okLd, errLd = pcall(loader.update, dtReal or 0)
    if not okLd then log('W', TAG, 'loader: ' .. tostring(errLd)) loader.cancel() end
  end
  pcall(hardcoreTick)
  if not S.layoutFailed then
    local okL, errL = pcall(raceLayout, dtReal)
    if not okL then log('W', TAG, 'layout: ' .. tostring(errL)) S.layoutFailed = true end
  end
  local ok, err = pcall(stage.update, dtSim or dtReal or 0, dtReal or 0)
  if not ok then log('W', TAG, 'stage: ' .. tostring(err)) end
  ok, err = pcall(rally.update, dtSim or dtReal or 0, dtReal or 0)
  if not ok then log('W', TAG, 'rally: ' .. tostring(err)) end
  S.timer = S.timer + (dtReal or 0)
  if S.timer < M.CHECK_S then return end
  S.timer = 0
  if not S.earth then refresh() end
  if S.earth then
    local ok, err = pcall(M.check)
    if not ok then log('W', TAG, 'check: ' .. tostring(err)) end
  end
end

-- las apps del rally del juego (vhud.lua): el stream 'rallyLoop' con nuestros datos, después de gameplay_rallyLoop
function M.onGuiUpdate()
  if not S.earthLevel then return end
  local ok, err = pcall(vhud.update, stage, rally, api())
  if not ok and not S.vhudErr then S.vhudErr = true log('W', TAG, 'vhud: ' .. tostring(err)) end
end
-- el botón de "interactuar" del juego (el icono del volante de las apps del rally): saltar la espera del control
function M.onGameplayInteract()
  if not S.earthLevel then return end
  pcall(M.skipWait)
end

function M.onBeamNGEarthWorldReady()
  S.timer = M.CHECK_S
  -- una vez por sesión: dónde está el menú (quien lo instala por primera vez no lo encuentra)
  if not S.hello then
    S.hello = true
    M.toast(spanish() and 'Raid.Earth listo: Esc → pestaña Raid.Earth.'
      or 'Raid.Earth ready: Esc → Raid.Earth tab.', 8)
  end
end
-- en un mapa sin BeamNG.Earth: avisar de que hace falta (si no, parece que el mod no hace nada)
-- En un mapa que no es de BeamNG.Earth (los rallies vanilla de Utah, Italia...) el mod queda dormido: sin avisos, sin
-- cambiar las apps de la pantalla ni el mod Racing Line, nada por fotograma (no debe tocar el juego base)
function M.isEarthLevel()
  local f = (getMissionFilename and getMissionFilename() or ''):lower()
  return f:find('beamng_earth', 1, true) ~= nil
end
function M.onClientPostStartMission()
  S.earthLevel = M.isEarthLevel()
  if not S.earthLevel then
    pcall(M.uiCancelStage)
    pcall(guide.restoreAll)
    if S.prevLayout then
      local L = rawget(_G, 'ui_appLayouts')
      if L and L.setCurrentLayout then pcall(L.setCurrentLayout, S.prevLayout) end
      S.prevLayout = nil
    end
  end
end
function M.onClientEndMission() S.earthLevel = false pcall(guard.release) end
function M.onBeamNGEarthTeleported()
  S.timer = M.CHECK_S
  if S.afterTp then S.afterTp.t = 0 end
  loader.onTeleported()
  pcall(audit.onTeleported)
end
function M.onBeamNGEarthAddonOptions() readOptions() end
function M.onBeamNGEarthRebased() stage.onRebased() end
function M.onExtensionUnloaded() pcall(guard.release) rally.stop() stage.stop() end
function M.onVehicleResetted(vid)
  if not S.earthLevel then return end
  local v = getPlayerVehicle(0)
  if v and v:getID() == vid then stage.onReset() end
end

return M

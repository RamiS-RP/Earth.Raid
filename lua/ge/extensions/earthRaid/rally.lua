-- Raid.Earth: el rally completo, como el modo rally del juego (gameplay_rallyLoop):
--   TC0 en el parque de asistencia -> enlace con hora prevista -> control horario (TC) antes de cada salida -> tramo ->
--   STOP -> enlace al siguiente TC ... -> TC final de vuelta a la asistencia.
-- Reglas del juego (referencia-rally-vanilla-fases.md): el carnet de ruta tiene una hora prevista por control que no se
-- recalcula; fichar fuera de tu minuto cuesta 10 s por minuto (antes o después); la salida del tramo es el siguiente
-- minuto entero con al menos 35 s de margen; el total es la suma de tiempos de tramo y penalizaciones.
-- Diferencias: si llegas pronto al control puedes esperar a tu minuto (o adelantar el reloj con Mayús+E) en vez de
-- fichar con penalización, y un enlace se puede saltar (teletransporte al control a su hora, sin penalización).
-- Los enlaces siguen los trazados reales del evento (liaisons del KMZ) encadenados; si no hay, el GPS de BeamNG.Earth.
local geo = require('earthRaid/geo')
local stage = require('earthRaid/stage')
local dressing = require('earthRaid/dressing')
local guide = require('earthRaid/guide')
local settings = require('earthRaid/settings')
local clean = require('earthRaid/clean')
local M = {}
local catalog = require('earthRaid/catalog')
local TAG = 'earthRaid'

M.PENALTY_PER_MIN = 10
M.START_MARGIN_S = 35       -- salida: el siguiente minuto entero con al menos esto tras fichar
M.TC_ZONE_M = 12            -- radio del punto de fichaje
M.TC_HOLD_S = 0.5           -- parado en él este tiempo: ficha
M.BUILD_M = 2500            -- el montaje del siguiente tramo se coloca al acercarse a esto de su control
M.JOIN_M = 900              -- un enlace del KMZ vale para salir de A / llegar a B si empieza / acaba a menos de esto
M.LINK_M = 600              -- dos enlaces se encadenan si el final de uno queda a menos de esto del inicio del otro...
M.GAP_COST = 4              -- ... y cada metro de hueco cuenta como esto (prefiere la cadena continua)
M.DETOUR = 1.35             -- sin trazado de enlace: distancia por carretera estimada = línea recta x esto
M.STAGE_KMH = 70            -- para el horario: tiempo previsto de un tramo a esta media
M.MIN_LIAISON_MIN = 2
M.FINISH_SHOW_S = 25
M.RESULTS_KEY = 'rally'

local R = nil
local function api() return rawget(_G, 'beamngEarth_api') end
function M.active() return R ~= nil end
function M.state() return R end

local function dist(lat1, lon1, lat2, lon2)
  local k = math.cos(math.rad((lat1 + lat2) / 2))
  local dx = (lon2 - lon1) * geo.M_PER_DEG * k
  local dy = (lat2 - lat1) * geo.M_PER_DEG
  return math.sqrt(dx * dx + dy * dy)
end

-- ---- itinerario ---------------------------------------------------------------------------------------------------------

-- Los tramos en orden de paso: { { run = n, stage = s } } (por `runs`; sin ellos, el orden del archivo)
function M.order(ev)
  local out, any = {}, false
  for _, s in ipairs(ev.stages or {}) do
    if s.kind == 'ss' then
      -- norma «SS 2/5»: la segunda pasada (y la cuarta...) es el mismo tramo en sentido contrario
      local runs = {}
      for _, r in ipairs(s.runs or {}) do runs[#runs + 1] = r end
      table.sort(runs)
      for i, r in ipairs(runs) do
        local rev = i % 2 == 0
        out[#out + 1] = { run = r, stage = rev and catalog.reversed(s, (function() local ok, l = pcall(function() return Lua:getSelectedLanguage() end) return ok and tostring(l):sub(1, 2) == 'es' end)()) or s, reverse = rev }
        any = true
      end
    end
  end
  if not any then
    local n = 0
    for _, s in ipairs(ev.stages or {}) do
      if s.kind == 'ss' then n = n + 1 out[#out + 1] = { run = n, stage = s } end
    end
  end
  table.sort(out, function(a, b) return a.run < b.run end)
  return out
end

-- El punto de partida del rally: la asistencia del evento, o el inicio del primer enlace, o nada
local function servicePoint(ev)
  for _, p in ipairs(ev.points or {}) do
    if p.kind == 'service' and p.pos then return p.pos, p.name end
  end
  local l = ev.liaisons and ev.liaisons[1]
  if l and l.path and l.path[1] then return l.path[1], l.name end
  return nil
end

-- Enlaces del KMZ encadenados de A a B (Dijkstra por longitud): el trazado {lat, lon}... y sus metros, o nil
function M.chain(ev, aLat, aLon, bLat, bLon)
  local L = ev.liaisons or {}
  if #L == 0 then return nil end
  local best, prev, done = {}, {}, {}
  local function gap(l, lat, lon) return l.path and #l.path >= 2 and dist(lat, lon, l.path[1][1], l.path[1][2]) or math.huge end
  for i, l in ipairs(L) do
    local g = gap(l, aLat, aLon)
    if g <= M.JOIN_M then best[i] = (l.lengthM or 0) + g * M.GAP_COST end
  end
  local goal, goalCost = nil, math.huge
  while true do
    local u, uc = nil, math.huge
    for i, c in pairs(best) do if not done[i] and c < uc then u, uc = i, c end end
    if not u or uc >= goalCost then break end
    done[u] = true
    local e = L[u].path[#L[u].path]
    local toB = dist(e[1], e[2], bLat, bLon)
    if toB <= M.JOIN_M and uc + toB * M.GAP_COST < goalCost then goal, goalCost = u, uc + toB * M.GAP_COST end
    for v, l in ipairs(L) do
      local g = gap(l, e[1], e[2])
      if not done[v] and v ~= u and g <= M.LINK_M then
        local c = uc + (l.lengthM or 0) + g * M.GAP_COST
        if not best[v] or c < best[v] then best[v], prev[v] = c, u end
      end
    end
  end
  if not goal then return nil end
  local seq, i = {}, goal
  while i do table.insert(seq, 1, i) i = prev[i] end
  local path = { { aLat, aLon } }
  local names, len = {}, 0
  for _, k in ipairs(seq) do
    names[#names + 1] = L[k].name
    local last = path[#path]
    len = len + (L[k].lengthM or 0) + dist(last[1], last[2], L[k].path[1][1], L[k].path[1][2])
    for _, p in ipairs(L[k].path) do path[#path + 1] = p end
  end
  local last = path[#path]
  len = len + dist(last[1], last[2], bLat, bLon)
  path[#path + 1] = { bLat, bLon }
  return path, len, names
end

-- El punto de fichaje de un tramo: dressing.TC_BEFORE_M antes de la salida, en la prolongación hacia atrás
local function tcPoint(st)
  local t = geo.track(clean.stage(st))
  local x, y = geo.at(t, 0)
  local dx, dy = geo.dirAt(t, 0)
  return geo.toGeo(t, x - dx * dressing.TC_BEFORE_M, y - dy * dressing.TC_BEFORE_M)
end

M.tcPoint = tcPoint

local function liaison(ev, from, to, kmh)
  local path, len, names = M.chain(ev, from[1], from[2], to[1], to[2])
  if not path then
    path, len = { from, to }, dist(from[1], from[2], to[1], to[2]) * M.DETOUR
  end
  local minutes = math.max(M.MIN_LIAISON_MIN, math.ceil(len / 1000 / kmh * 60))
  return { path = path, lengthM = len, minutes = minutes, real = names ~= nil, names = names }
end

-- El itinerario desde la pasada `fromRun` (o la primera) hasta el final: secciones { tc, liaison, run, stage }
function M.itinerary(ev, fromRun, kmh)
  kmh = kmh or 60
  local order = M.order(ev)
  local list = {}
  for _, o in ipairs(order) do if not fromRun or o.run >= fromRun then list[#list + 1] = o end end
  if #list == 0 then return nil, 'no stages' end
  local svc, svcName = servicePoint(ev)
  local here, hereName = svc or list[1].stage.start, svcName
  -- empezando a mitad: desde la meta (el STOP) de la pasada anterior, por su enlace real
  local prev = nil
  for _, o in ipairs(order) do if fromRun and o.run < fromRun then prev = o end end
  if prev then local cp = clean.stage(prev.stage) here, hereName = cp[#cp], 'STOP SS' .. prev.run end
  local items = {}
  local prevFinish = nil
  for _, o in ipairs(list) do
    local st = o.stage
    local tLat, tLon = tcPoint(st)
    local from = prevFinish or here
    items[#items + 1] = { kind = 'tc', label = 'TC' .. o.run, run = o.run, stage = st, pos = { tLat, tLon },
      liaison = liaison(ev, from, { tLat, tLon }, kmh) }
    local cp = clean.stage(st)
    prevFinish = cp[#cp]
  end
  if svc then
    items[#items + 1] = { kind = 'tc', label = 'TC' .. list[#list].run .. 'A', final = true, pos = svc, name = svcName,
      liaison = liaison(ev, prevFinish, svc, kmh) }
  end
  return { items = items, start = here, startName = hereName, count = #order }
end

-- ---- horario ------------------------------------------------------------------------------------------------------------

local function stageMinutes(st) return math.ceil((st.lengthM or 0) / 1000 / M.STAGE_KMH * 60) + 1 end

local function schedule(it, startMin)
  local m = startMin
  local prevStage = nil
  for _, item in ipairs(it.items) do
    if prevStage then m = m + 1 + stageMinutes(prevStage) + 1 end
    m = m + item.liaison.minutes
    item.dueMin = m
    prevStage = item.stage
  end
end

local function hhmm(sec)
  sec = math.floor(sec) % 86400
  return ('%02d:%02d'):format(math.floor(sec / 3600), math.floor(sec / 60) % 60)
end
M.hhmm = hhmm

-- ---- comenzar / terminar ------------------------------------------------------------------------------------------------

local function lang() local ok, l = pcall(function() return Lua:getSelectedLanguage() end) return ok and tostring(l):sub(1, 2) == 'es' and 'es' or 'en' end

-- ev: el evento completo; fromRun: pasada desde la que empezar (nil: la primera)
function M.start(ev, fromRun, hooks)
  M.stop()
  local opt = settings.get()
  local it, err = M.itinerary(ev, fromRun, tonumber(opt.liaisonKmh) or 60)
  if not it then return false, err end
  local tm = os.date('*t')
  local now = tm.hour * 3600 + tm.min * 60 + tm.sec
  local startMin = math.floor(now / 60) + 2
  schedule(it, startMin)
  R = { ev = ev, it = it, idx = 1, clock = now, startMin = startMin, phase = 'service', total = 0, penalties = {},
    rows = {}, hooks = hooks or {}, lang = lang(), holdT = 0, hudT = 0, built = nil, opt = opt, fromRun = fromRun,
    stageTimes = 0 }
  -- TC0: la hora de salida de la asistencia
  R.rows[#R.rows + 1] = { kind = 'tc', label = 'TC0', due = startMin * 60, actual = nil, status = nil }
  for _, item in ipairs(it.items) do
    R.rows[#R.rows + 1] = { kind = 'tc', label = item.label, due = item.dueMin * 60 }
    if item.stage then R.rows[#R.rows + 1] = { kind = 'ss', label = 'SS' .. item.run, title = item.stage.title } end
  end
  log('I', TAG, ('rally %s: %d controls, from run %s, TC0 %s'):format(ev.id, #it.items, tostring(fromRun or 1), hhmm(startMin * 60)))
  return true
end

local function row(label)
  for _, r in ipairs(R.rows) do if r.label == label then return r end end
end

local function penalise(label, s, why)
  R.total = R.total + s
  R.penalties[#R.penalties + 1] = { label = label, s = s, why = why }
end

function M.stop()
  pcall(guide.release)
  if not R then return end
  if stage.active() then stage.stop() end
  stage.trafficBack()
  guide.clear()
  R = nil
  guihooks.trigger('EarthRaidRally', { active = false })
end

-- ---- secciones ----------------------------------------------------------------------------------------------------------

local function item() return R and R.it.items[R.idx] end

local function setGps()
  local cur = item()
  if not cur then return end
  local t = geo.track(cur.liaison.path)
  local label = cur.label .. (cur.stage and (' · ' .. cur.stage.title) or '')
  if cur.liaison.real and #cur.liaison.path > 2 then guide.along(t, label)
  else local a = api() if a and a.gpsSet then pcall(a.gpsSet, cur.pos[1], cur.pos[2], label) end end
end

-- Salida de la asistencia (TC0): el reloj corre y empieza el primer enlace
local function leaveService()
  local r0 = row('TC0')
  r0.actual, r0.status = R.clock, 'ok'
  R.phase = 'liaison'
  stage.trafficBack()
  setGps()
end

function M.begin()
  if R and R.phase == 'service' then
    -- la hora de salida: tu minuto de TC0 (si aún no ha llegado, el reloj se adelanta)
    R.clock = math.max(R.clock, R.startMin * 60)
    leaveService()
    return true
  end
  return false
end

local function buildStage()
  local cur = item()
  if not (cur and cur.stage) or R.built == R.idx or stage.active() then return end
  local ok, err = stage.start(R.ev, cur.stage, { number = cur.run, count = R.it.count, session = {
    onFinish = function(res) M.onStageFinish(res) end,
    onStop = function() M.onStageStop() end,
  } })
  if ok then
    stage.setLang(R.lang)
    R.built = R.idx
    -- el punto de fichaje por la carretera de verdad (el tramo ya lo sabe)
    local sst = stage.state()
    if sst and sst.tcLat then cur.pos = { sst.tcLat, sst.tcLon } end
    if R.hooks.onBuilt then pcall(R.hooks.onBuilt) end
  else
    log('W', TAG, 'rally: stage ' .. tostring(cur.stage.id) .. ': ' .. tostring(err))
  end
end

local function checkIn()
  local cur = item()
  local r = row(cur.label)
  local dueMin = cur.dueMin
  local actMin = math.floor(R.clock / 60)
  r.actual = R.clock
  local off = actMin - dueMin
  if off == 0 then r.status = 'ok'
  else
    r.status = off > 0 and 'late' or 'early'
    local s = math.abs(off) * M.PENALTY_PER_MIN
    r.penalty = s
    penalise(cur.label, s, off > 0 and 'late' or 'early')
  end
  guide.clear()
  if cur.final then
    R.phase, R.finishLeft = 'finished', M.FINISH_SHOW_S
    M.saveResult()
    return
  end
  -- salida del tramo: el siguiente minuto entero con margen; tramo cerrado: sin tráfico
  local startAt = math.ceil((R.clock + M.START_MARGIN_S) / 60) * 60
  R.startAt = startAt
  local srow = row('SS' .. cur.run)
  if srow then srow.startAt = startAt end
  if R.opt.noTraffic then stage.trafficOff() end
  buildStage()
  stage.release(startAt - R.clock)
  R.phase = 'stage'
end

function M.onStageFinish(res)
  if not R then return end
  local cur = item()
  local srow = cur and row('SS' .. cur.run)
  if srow then srow.time, srow.penalty = res.time, res.penalty end
  R.stageTimes = R.stageTimes + res.time
  R.total = R.total + res.time
  -- las penalizaciones del tramo (salida en falso, fuera de hora en la línea, recuperaciones) van a su bloque
  for _, pn in ipairs(res.penalties or {}) do penalise('SS' .. cur.run, pn.s, pn.kind) end
end

-- parado en el STOP: empieza el enlace al siguiente control (con tráfico)
function M.onStageStop()
  if not R then return end
  R.idx = R.idx + 1
  R.built = nil
  stage.trafficBack()
  if not item() then
    R.phase, R.finishLeft = 'finished', M.FINISH_SHOW_S
    M.saveResult()
    return
  end
  R.phase = 'liaison'
  setGps()
end

function M.saveResult()
  local path = stage.RESULTS
  local d = jsonReadFile(path)
  d = type(d) == 'table' and d or {}
  local key = R.ev.id .. '/' .. M.RESULTS_KEY .. (R.fromRun and R.fromRun > 1 and ('@' .. R.fromRun) or '')
  local r = d[key] or { runs = 0, attempts = {} }
  r.runs = (r.runs or 0) + 1
  local pen = 0
  for _, p in ipairs(R.penalties) do pen = pen + p.s end
  if not r.best or R.total < r.best then r.best = R.total R.newBest = true end
  table.insert(r.attempts, 1, { total = R.total, stages = R.stageTimes, penalty = pen, date = os.time() })
  while #r.attempts > 10 do table.remove(r.attempts) end
  d[key] = r
  pcall(jsonWriteFile, path, d, true)
  log('I', TAG, ('rally %s finished: %.1f s (%d s penalties)'):format(R.ev.id, R.total, pen))
end

-- Saltar el enlace en curso: al control, a tu hora (sin penalización)
function M.skipLiaison()
  if not (R and (R.phase == 'liaison' or R.phase == 'service')) then return false end
  if R.phase == 'service' then leaveService() end
  local cur = item()
  local a = api()
  if not (cur and a and a.teleport) then return false end
  -- un poco antes del control, en la prolongación del enlace
  -- el primer punto del enlace (hacia atrás) a más de 80 m del control que no esté pasado de la salida
  local p = cur.liaison.path
  local lat, lon = cur.pos[1], cur.pos[2]
  local s0 = cur.stage and cur.stage.start
  for k = #p - 1, 1, -1 do
    local b = p[k]
    local d = dist(b[1], b[2], lat, lon)
    local pastStart = s0 and dist(b[1], b[2], s0[1], s0[2]) < d
    if d > 120 and not pastStart then
      local f = math.min(1, 100 / d)
      lat, lon = lat + (b[1] - lat) * f, lon + (b[2] - lon) * f
      break
    end
  end
  local ok = a.teleport(lat, lon, cur.label)
  if ok then
    R.clock = math.max(R.clock, cur.dueMin * 60 + 2)
    -- al llegar, el coche en la calzada mirando al control (no en el monte)
    local mn = rawget(_G, 'earthRaid_main')
    if mn and mn.snapAfter then pcall(mn.snapAfter, cur.pos[1], cur.pos[2]) end
  end
  return ok
end

-- Mayús+E: en la asistencia, salir; en el control con tiempo de sobra, adelantar el reloj a tu minuto
function M.skip()
  if not R then return false end
  if R.phase == 'service' then return M.begin() end
  if R.phase == 'liaison' and R.early then
    R.clock = math.max(R.clock, item().dueMin * 60 + 1)
    return true
  end
  if R.phase == 'finished' then R.finishLeft = 0 return true end
  return false
end

-- ---- cada fotograma -----------------------------------------------------------------------------------------------------

local function hud(p)
  local cur = item()
  local a = api()
  local next = nil
  if cur and (R.phase == 'liaison' or R.phase == 'service') then
    local g = a and a.gps and a.gps()
    local d = (g and g.remaining) or (p and dist(p.lat, p.lon, cur.pos[1], cur.pos[2]))
    local lim = a and a.speedLimit and a.speedLimit()
    next = { label = cur.label, distM = d, dueMin = cur.dueMin, limitKmh = lim and lim.ms and math.floor(lim.ms * 3.6 + 0.5) or nil,
      stageTitle = cur.stage and cur.stage.title, liaisonKm = cur.liaison.lengthM / 1000, minutes = cur.liaison.minutes,
      real = cur.liaison.real, early = R.early, final = cur.final }
  end
  local rows = {}
  for _, r in ipairs(R.rows) do rows[#rows + 1] = r end
  guihooks.trigger('EarthRaidRally', { active = true, phase = R.phase, lang = R.lang, eventName = R.ev.name,
    clock = R.clock, total = R.total, stageTimes = R.stageTimes, next = next, rows = rows, penalties = R.penalties,
    startMin = R.startMin, startAt = R.startAt, penaltyPerMin = M.PENALTY_PER_MIN, finishLeft = R.finishLeft,
    newBest = R.newBest, startName = R.it.startName })
end

function M.update(dtSim, dtReal)
  if not R then return end
  R.clock = R.clock + (dtSim or 0)
  local a = api()
  local p = a and a.ready and a.ready() and a.pose() or nil
  local cur = item()
  -- en la asistencia: a tu minuto de TC0 se sale solo
  if R.phase == 'service' and R.clock >= R.startMin * 60 then leaveService() end
  if R.phase == 'liaison' and cur and p and not p.camera then
    -- el punto de fichaje, tal como lo ancla el tramo al eje de la carretera
    local sst = R.built == R.idx and stage.state()
    if sst and sst.tcLat then cur.pos = { sst.tcLat, sst.tcLon } end
    local d = dist(p.lat, p.lon, cur.pos[1], cur.pos[2])
    if cur.stage and d < M.BUILD_M and R.built ~= R.idx then buildStage() end
    -- en el punto de fichaje y parado
    if d < M.TC_ZONE_M and (p.speed or 0) < 0.6 then
      local early = math.floor(R.clock / 60) < cur.dueMin
      R.early = early
      if not early then
        R.holdT = R.holdT + dtSim
        if R.holdT >= M.TC_HOLD_S then R.holdT, R.early = 0, false checkIn() end
      end
    else
      R.holdT, R.early = 0, false
    end
  elseif R.phase == 'finished' then
    R.finishLeft = (R.finishLeft or 0) - (dtReal or dtSim or 0)
    if R.finishLeft <= 0 then
      local done = R
      M.stop()
      if done.hooks.onEnd then pcall(done.hooks.onEnd) end
      return
    end
  end
  R.hudT = R.hudT + (dtReal or dtSim or 0)
  if R.hudT >= 0.2 then R.hudT = 0 hud(p) end
end

function M.sendHud() if R then hud(nil) else guihooks.trigger('EarthRaidRally', { active = false }) end end

return M

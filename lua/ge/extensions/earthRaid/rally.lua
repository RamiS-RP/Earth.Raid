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
local tz = require('earthRaid/trafficzones')
local stage = require('earthRaid/stage')
local dressing = require('earthRaid/dressing')
local guide = require('earthRaid/guide')
local settings = require('earthRaid/settings')
local clean = require('earthRaid/clean')
local M = {}
local catalog = require('earthRaid/catalog')
local TAG = 'earthRaid'

-- las reglas de penalización son las del rally del juego (loop/penalties.lua y recoveryClockAdvance.lua)
local okP, GP = pcall(require, '/lua/ge/extensions/gameplay/rally/loop/penalties')
M.PENALTY_PER_MIN = (okP and GP.timeControlPenaltySecondsPerMinute) or 10
local okC, GC = pcall(require, '/lua/ge/extensions/gameplay/rally/recoveryClockAdvance')
M.LIAISON_RECOVERY_S = (okC and GC.getSeconds('recovery', false)) or 60
-- Ajustes > Rally > «Penalizaciones por llegar pronto»: apagado (por defecto) llegar pronto no penaliza y el reloj se
-- adelanta solo a tu minuto; encendido se ficha enseguida y se penaliza cada minuto de adelanto
local function earlyPenalties()
  local ok, v = pcall(function() return rawget(_G, 'settings').getValue('rallyEnableEarlyTimeControlPenalties') end)
  return ok and v == true
end
M.START_MARGIN_S = 35       -- salida: el siguiente minuto entero con al menos esto tras fichar
M.TC_ZONE_M = 12            -- radio del punto de fichaje
M.TC_HOLD_S = 0.5           -- parado en él este tiempo: ficha
M.TC0_NEAR_M, M.TC0_PASSED_M, M.TC0_FAR_M = 30, 90, 400   -- TC0 pasado de largo: visto a menos de 30 m y ya a más de 90,
                            -- o 400 m más lejos de lo más cerca que se estuvo (salida por otro lado): se ficha solo
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
  local it, err = M.itinerary(ev, fromRun, M.LIAISON_AVG_KMH)
  if not it then return false, err end
  local now = geo.dayClock()
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
  pcall(tz.clear)
  guide.clear()
  R = nil
  guihooks.trigger('EarthRaidRally', { active = false })
end

-- ---- secciones ----------------------------------------------------------------------------------------------------------

local function item() return R and R.it.items[R.idx] end

-- El GPS del enlace (19-nov, el usuario: "a veces se vuelve loco y no me manda donde tengo que ir"): la ruta se pide
-- SIEMPRE desde donde está el coche (antes, desde el principio del enlace: al reponerla a medio camino mandaba de
-- vuelta al primer punto), con pocos puntos de paso del recorrido oficial (cada uno puede caer en la calzada contraria
-- y forzar un cambio de sentido) y acabando en el punto de fichaje de verdad. Lejos del recorrido oficial, o si la
-- ruta planeada sale disparatada (update), la más corta del GPS directa al control. MARK:gps-v2
M.GPS_OFF_M = 500           -- más lejos que esto del recorrido oficial: ruta directa al control
M.GPS_WP_M = 1500           -- un punto de paso cada tantos metros, como poco
M.GPS_CRAZY = 1.8           -- la ruta planeada mide más que esto x el enlace (+1 km): directa al control
local function setGps(direct)
  local cur = item()
  if not cur then return end
  -- en el enlace, siempre la línea azul del GPS (y la de carrera, fuera)
  guide.liaison(settings.get().hardcore == true)
  local label = cur.label .. (cur.stage and (' · ' .. cur.stage.title) or '')
  local a = api()
  if not a then return end
  local tgt, pts = cur.pos, nil
  if not direct and R.gpsDirect ~= R.idx and cur.liaison.real and #cur.liaison.path > 2 and a.gpsSetRoute then
    local t = geo.track(cur.liaison.path)
    local p = a.ready and a.ready() and a.pose and a.pose() or nil
    local from, off = 0, 0
    if p and p.lat then
      local x, y = geo.toLocal(t, p.lat, p.lon)
      from, off = geo.project(t, x, y, 1, 1, #t.pts)
    end
    if off <= M.GPS_OFF_M then
      local ex, ey = geo.toLocal(t, tgt[1], tgt[2])
      local to = geo.project(t, ex, ey, 1, 1, #t.pts)
      if to > from then
        pts = {}
        local step = math.max(M.GPS_WP_M, (to - from) / (guide.GPS_POINTS - 1))
        local al = from + step
        while al < to - step * 0.5 and #pts < guide.GPS_POINTS - 1 do
          local la, lo = geo.toGeo(t, geo.at(t, al))
          pts[#pts + 1] = { lat = la, lon = lo }
          al = al + step
        end
        pts[#pts + 1] = { lat = tgt[1], lon = tgt[2], name = label }
      end
    end
  end
  if pts and #pts > 1 then
    local ok, res = pcall(a.gpsSetRoute, pts)
    if ok and res then return end
  end
  if a.gpsSet then pcall(a.gpsSet, tgt[1], tgt[2], label) end
end

-- Salida de la asistencia (TC0): el reloj corre y empieza el primer enlace
local function leaveService()
  local r0 = row('TC0')
  if not r0.actual then r0.actual, r0.status = R.clock, 'ok' end
  R.phase = 'liaison'
  if settings.liaisonTraffic() then stage.trafficBack(true) end
  guide.liaison(settings.get().hardcore == true)
  setGps()
end

-- El TC0 a la salida del parque de asistencia (servicepark.tc0): se ficha ahí, a tu minuto, como en los demás
-- controles (adelanto o retraso: 10 s por minuto); sin él, se sale solo a la hora
function M.setTc0(lat, lon)
  if not R then return end
  R.tc0 = lat and { lat, lon } or nil
  if R.tc0 and R.phase == 'service' then
    -- del box al TC0, con la línea azul del GPS
    guide.liaison(settings.get().hardcore == true)
    local a = api()
    if a and a.gpsSet then pcall(a.gpsSet, lat, lon, 'TC0') end
  end
end
local function checkInTc0()
  local r0 = row('TC0')
  local off = math.floor(R.clock / 60) - R.startMin
  r0.actual = R.clock
  if off == 0 then r0.status = 'ok'
  else
    r0.status = off > 0 and 'late' or 'early'
    local s = math.abs(off) * M.PENALTY_PER_MIN
    r0.penalty = s
    penalise('TC0', s, off > 0 and 'late' or 'early')
  end
  leaveService()
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
  -- primer tramo en sentido inverso: la meta cae junto al parque de asistencia; el box vuelve a montarse para simular
  -- la vuelta a box (el parque se liberó al empezar el tramo)
  if cur and cur.reverse and cur.run == 1 and R.hooks.onReturnToBox then pcall(R.hooks.onReturnToBox) end
end

-- parado en el STOP: empieza el enlace al siguiente control (con tráfico)
function M.onStageStop()
  if not R then return end
  R.idx = R.idx + 1
  R.built = nil
  if settings.liaisonTraffic() then stage.trafficBack() end
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

-- Recuperar en un enlace (reglas del juego, recoveryClockAdvance): el reloj avanza 60 s por recuperar y 10 s por volcar
-- (no es una línea de penalización: si te pasas de tu minuto, llegas tarde)
function M.onReset(kind)
  if R and R.phase == 'liaison' and not stage.active() then
    local s = (okC and GC.getSeconds(kind or 'recovery', false)) or ((kind == 'flip') and 10 or 60)
    R.clock = R.clock + s
    return true
  end
  return false
end

-- Exceso de velocidad (el detector del juego, loop/speedingDetector.lua: una muestra por segundo, media de 5, probabilidad
-- creciente con el exceso, como mucho una cada 60 s). Solo en enlaces y en el parque (estricto, 30 km/h), nunca en tramo.
M.SPEEDING_S = 10             -- el del juego (recordSpeedingPenalty)
M.LIAISON_LIMIT_KPH = 100     -- el límite por defecto de un enlace en el juego
M.SERVICE_LIMIT_KPH = 30      -- el del parque de asistencia en el juego (modo estricto)
local okD, GD = pcall(require, '/lua/ge/extensions/gameplay/rally/loop/speedingDetector')
local function speedingUpdate(dtSim)
  if not (okD and type(GD) == 'function') then return end
  if not R.speeding then
    local ok, det = pcall(GD, { recordSpeedingPenalty = function(_, data)
      local cur = item()
      penalise((R.phase == 'service' and 'TC0') or (cur and cur.label) or 'TC', M.SPEEDING_S, 'speeding')
      return true
    end })
    R.speeding = ok and det or false
  end
  if R.speeding then
    local service = R.phase == 'service'
    pcall(R.speeding.update, R.speeding, dtSim, service and M.SERVICE_LIMIT_KPH or M.LIAISON_LIMIT_KPH, service)
  end
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
    -- como en el rally del juego: 120 km/h en los enlaces, 30 en el parque de asistencia (no se configura)
    next = { label = cur.label, distM = d, dueMin = cur.dueMin, limitKmh = R.phase == 'service' and M.SERVICE_KMH or M.LIAISON_KMH,
      stageTitle = cur.stage and cur.stage.title, liaisonKm = cur.liaison.lengthM / 1000, minutes = cur.liaison.minutes,
      real = cur.liaison.real, early = R.early, final = cur.final }
    -- en la asistencia con TC0 a la salida: el control que toca es ese, a tu minuto de salida
    if R.phase == 'service' and R.tc0 then
      next.label, next.dueMin, next.stageTitle = 'TC0', R.startMin, nil
      next.distM = p and dist(p.lat, p.lon, R.tc0[1], R.tc0[2]) or nil
    end
  end
  local rows = {}
  for _, r in ipairs(R.rows) do rows[#rows + 1] = r end
  guihooks.trigger('EarthRaidRally', { active = true, phase = R.phase, lang = R.lang, eventName = R.ev.name,
    clock = R.clock, total = R.total, stageTimes = R.stageTimes, next = next, rows = rows, penalties = R.penalties,
    startMin = R.startMin, startAt = R.startAt, penaltyPerMin = M.PENALTY_PER_MIN, finishLeft = R.finishLeft,
    newBest = R.newBest, startName = R.it.startName })
end

-- En espera en la asistencia (la pantalla de inicio, antes de Iniciar): el reloj no corre; al soltar, la hora de
-- salida (TC0) vuelve a ser dos minutos después de ahora y el horario se recalcula desde ahí
function M.hold(on)
  if not R then return end
  if on then R.hold = true return end
  if not R.hold then return end
  R.hold = nil
  local now = geo.dayClock()
  R.clock = now
  R.startMin = math.floor(now / 60) + 2
  schedule(R.it, R.startMin)
  R.rows[1].due = R.startMin * 60
  local i = 2
  for _, item in ipairs(R.it.items) do
    if R.rows[i] then R.rows[i].due = item.dueMin * 60 end
    i = i + (item.stage and 2 or 1)
  end
end
function M.held() return R ~= nil and R.hold == true end

-- como en el rally del juego: límite 120 km/h en los enlaces y 30 en la asistencia, fijos (no se configuran); los tiempos
-- de los enlaces se asignan a una media de 100 km/h
M.LIAISON_KMH, M.SERVICE_KMH, M.LIAISON_AVG_KMH = 120, 30, 100
function M.update(dtSim, dtReal)
  if not R then return end
  if R.hold then return end
  R.clock = R.clock + (dtSim or 0)
  if (R.phase == 'liaison' or R.phase == 'service') and not stage.active() then speedingUpdate(dtSim or 0) end
  -- el sol y el reloj van a la par: si el reloj salta (saltar enlace, esperar al minuto), la hora del mapa lo sigue
  if math.abs(((R.clock - geo.dayClock() + 43200) % 86400) - 43200) > 2 then geo.setDayClock(R.clock) end
  local a = api()
  local p = a and a.ready and a.ready() and a.pose() or nil
  local cur = item()
  -- zonas sin tráfico: los controles, la salida, la meta y el tramo montado (se recalculan cada 3 s)
  R.zoneT = (R.zoneT or 3) + (dtSim or 0)
  if R.zoneT >= 3 then
    R.zoneT = 0
    local zl = {}
    if R.tc0 then zl[#zl + 1] = { lat = R.tc0[1], lon = R.tc0[2] } end
    if cur and cur.pos then zl[#zl + 1] = { lat = cur.pos[1], lon = cur.pos[2] } end
    local sst = stage.state()
    local tk = sst and sst.track
    if tk and tk.pts and #tk.pts > 1 then
      local la, lo = geo.toGeo(tk, tk.pts[1][1], tk.pts[1][2])
      zl[#zl + 1] = { lat = la, lon = lo }
      la, lo = geo.toGeo(tk, tk.pts[#tk.pts][1], tk.pts[#tk.pts][2])
      zl[#zl + 1] = { lat = la, lon = lo }
      for al = tz.CORRIDOR_STEP_M, (tk.total or 0) - 1, tz.CORRIDOR_STEP_M do
        la, lo = geo.toGeo(tk, geo.at(tk, al))
        zl[#zl + 1] = { lat = la, lon = lo, r = tz.CORRIDOR_R_M + 45 }
      end
    end
    pcall(tz.set, zl)
  end
  pcall(tz.update, dtSim)
  -- en la asistencia: con TC0 a la salida del parque se ficha ahí (parado en el punto); sin él, a tu minuto se sale solo
  if R.phase == 'service' then
    if R.tc0 then
      if p and not p.camera then
        local d = dist(p.lat, p.lon, R.tc0[1], R.tc0[2])
        -- el GPS al TC0 mientras se está en la asistencia (si se perdió, se vuelve a poner)
        R.gpsT = (R.gpsT or 0) + dtSim
        if R.gpsT > 4 then
          R.gpsT = 0
          local g = a.gps and a.gps()
          -- (mientras planea, o ya en el punto, no se toca: reponerla cada 4 s no la dejaba acabar nunca)
          if d > 25 and not (g and (g.planning or (g.remaining and g.remaining < 5000))) and a.gpsSet then
            pcall(a.gpsSet, R.tc0[1], R.tc0[2], 'TC0')
          end
        end
        -- pasado de largo sin fichar (19-nov: sin caseta a la vista, el rally se quedaba en la asistencia para siempre,
        -- sin enlace ni GPS): se ficha con la hora de paso, con su penalización si no es tu minuto
        R.tc0Min = math.min(R.tc0Min or d, d)
        if (R.tc0Min < M.TC0_NEAR_M and d > M.TC0_PASSED_M) or d > R.tc0Min + M.TC0_FAR_M then
          R.tc0Min, R.holdT, R.early = nil, 0, false
          checkInTc0()
          return
        end
        if d < M.TC_ZONE_M and (p.speed or 0) < 0.6 then
          local early = math.floor(R.clock / 60) < R.startMin
          if early and not earlyPenalties() then R.clock = math.max(R.clock, R.startMin * 60 + 1) end
          R.early = false
          R.holdT = R.holdT + dtSim
          if R.holdT >= M.TC_HOLD_S then R.holdT = 0 checkInTc0() end
        else
          R.holdT, R.early = 0, false
        end
      end
    elseif R.clock >= R.startMin * 60 then leaveService() end
  end
  -- el GPS del enlace: si se perdió (limpieza de pantalla del tramo, recarga), se vuelve a poner
  if R.phase == 'liaison' and cur and p and not p.camera then
    R.gpsT = (R.gpsT or 0) + (dtSim or 0)
    if R.gpsT > 4 then
      R.gpsT = 0
      local g = a.gps and a.gps()
      if not (g and (g.remaining or g.planning)) then setGps()
      elseif g.remaining and not g.planning and R.gpsDirect ~= R.idx then
        -- una ruta disparatada (vueltas por puntos de paso mal caídos): la más corta, directa al control
        local plan = math.max(cur.liaison.lengthM or 0, dist(p.lat, p.lon, cur.pos[1], cur.pos[2]) * M.DETOUR)
        if g.remaining > plan * M.GPS_CRAZY + 1000 then
          R.gpsDirect = R.idx
          log('I', TAG, string.format('gps: planned %.1f km for a %.1f km liaison, straight to the control', g.remaining / 1000, plan / 1000))
          setGps(true)
        end
      end
    end
    -- el punto de fichaje, tal como lo ancla el tramo al eje de la carretera
    local sst = R.built == R.idx and stage.state()
    if sst and sst.tcLat then cur.pos = { sst.tcLat, sst.tcLon } end
    local d = dist(p.lat, p.lon, cur.pos[1], cur.pos[2])
    if cur.stage and d < M.BUILD_M and R.built ~= R.idx then buildStage() end
    -- en el punto de fichaje y parado
    if d < M.TC_ZONE_M and (p.speed or 0) < 0.6 then
      local early = math.floor(R.clock / 60) < cur.dueMin
      if early and not earlyPenalties() then R.clock = math.max(R.clock, cur.dueMin * 60 + 1) end
      R.early = false
      R.holdT = R.holdT + dtSim
      if R.holdT >= M.TC_HOLD_S then R.holdT = 0 checkIn() end
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

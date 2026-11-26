-- Raid.Earth: un tramo en marcha, con las fases del rally del juego:
--   hold      (rally completo) montado, a la espera de que el jugador fiche en el control horario (rally.lua)
--   approach  GPS hasta la salida
--   staging   colocarse en la línea: el morro a menos de 1 m de ella, sin pasarla y parado (como el juego). 60 s (en el
--             rally, hasta el minuto de salida); sin colocar al acabar: +10 s y el contador vuelve a empezar
--   countdown 10 s con el reloj LED, la cámara con zoom al reloj y la voz 5-4-3-2-1; avanzar antes: salida en falso
--   running   crono, parcial, notas de copiloto (voz y visuales), crestas y saltos por delante, GPS por el trazado
--   toStop    meta lanzada cruzada: SLOW hasta el STOP, 150 m más allá
--   done      parado en el STOP: resultado unos segundos; luego se limpia la pantalla y, al alejarse, el montaje
-- Todo en metros locales del tramo (geo.lua): no depende del origen del mundo de BeamNG.Earth.
local geo = require('earthRaid/geo')
local props = require('earthRaid/props')
local dressing = require('earthRaid/dressing')
local startclock = require('earthRaid/startclock')
local pathgen = require('earthRaid/pathgen')
local audio = require('earthRaid/audio')
local pacenotes = require('earthRaid/pacenotes')
local relief = require('earthRaid/relief')
local guide = require('earthRaid/guide')
local phys = require('earthRaid/phys')
local settings = require('earthRaid/settings')
local clean = require('earthRaid/clean')
local winter = require('earthRaid/winter')
local M = {}
local function spanishUI()
  local ok, l = pcall(function() return Lua:getSelectedLanguage() end)
  return ok and tostring(l):sub(1, 2) == 'es'
end
local TAG = 'earthRaid'

M.STAGING_S = 60
M.RESCHEDULE_S = 60       -- el juego (slotSizeMinutes = 1): no colocado a -10 s, la salida pasa a +60 s sobre la hora prevista
M.COUNTDOWN_S = 10
M.PRECOUNT_MAX_S = 1.5    -- el aviso de antes de la cuenta atrás, como mucho esto de largo
-- las del rally del juego (loop/penalties.lua y recoveryClockAdvance.lua)
local okP, GP = pcall(require, '/lua/ge/extensions/gameplay/rally/loop/penalties')
local okC, GC = pcall(require, '/lua/ge/extensions/gameplay/rally/recoveryClockAdvance')
M.FALSE_START_S = (okP and GP.falseStartPenaltySeconds) or 10
M.RECOVERY_S = (okC and GC.getSeconds('recovery', true)) or 5
M.NEAR_M = 40
M.STAGED_MAX_M = 1.2       -- colocado: el morro como mucho a esto antes de la línea (el juego: < 1 m)...
M.STAGED_OVER_M = 0.3      -- ... y como mucho esto por encima de ella; más: "te has pasado", no vale
M.FALSE_START_M = 1.0      -- en la cuenta atrás, avanzar esto: salida en falso
M.CAR_HALF_M = 2.2         -- si no se puede medir el coche
M.STOP_MS = 0.6
M.CIRCUIT_M = 300          -- la meta a menos de esto de la salida: circuito cerrado
M.DEFAULT_LAPS = 3         -- vueltas de un circuito si el jugador no dice otra cosa (norma del usuario, 21-nov)
M.MAX_LAPS = 20
M.GRID_COUNTDOWN_S = 5       -- circuito: la cuenta atrás del semáforo 2D del juego, desde la parrilla
M.lapsFor = {}             -- las vueltas elegidas por circuito (evento/tramo), para los reinicios
M.LINE_HALF_M = 5
M.HUD_S = 0.1
M.CALL_S = 4.5             -- la nota se dice con este tiempo de antelación a la velocidad actual
M.CALL_MIN_M = 70
M.INTO_M = 40              -- dos notas a menos de esto se encadenan con "into"
M.RELIEF_S = 1.5
M.CLOSURES_S = 8           -- las cintas se completan en marcha, según BeamNG.Earth carga el grafo de carreteras
M.DONE_SHOW_S = 10         -- el resultado en pantalla (rally completo)
M.DONE_ACCEPT_S = 90       -- tramo suelto: el resultado se queda hasta aceptarlo con Mayús+E, o esto
M.CLEANUP_M = 300          -- el montaje se retira al alejarse esto de la meta...
M.CLEANUP_S = 120          -- ... o pasado este tiempo
M.REGROUND_S = 1.5         -- cada esto, los objetos cercanos se recolocan en altura (terreno recién cargado)
M.REGROUND_M = 900
M.CLEAR_AFTER_M = 5
M.TC_ZONE_M = 12           -- tramo suelto: radio del punto de fichaje del control horario
M.TC_MARGIN_S = 35        -- la nota se retira de la pantalla al pasar esto del final de su curva
M.RESULTS = '/settings/earthRaid/results.json'

local S = nil              -- el tramo activo
local post = nil           -- tras terminar: { at = tiempo, finish = {lat, lon} } hasta retirar el montaje
local trafficWas = nil
local hudTimer, clock = 0, 0

local function api() return rawget(_G, 'beamngEarth_api') end
function M.active() return S ~= nil end
function M.state() return S end

-- ---- tráfico ------------------------------------------------------------------------------------------------------------

-- Como el juego (gameplay/rally/trafficExclusion.lua): el tráfico NO se borra al empezar un tramo ni se vuelve a crear
-- al acabarlo (eso es lo que daba el tirón al salir del TC0): la carretera del tramo se marca como zona de exclusión
-- del tráfico (map.setTrafficExclusionZones, círculos cada 1,5 radios) y el sistema de tráfico del juego sigue con su
-- propia lógica (aparece lejos, fuera de la vista). En tramos largos las zonas cubren solo una ventana alrededor del
-- coche y se rehacen al avanzar. Sin esa función en el juego, se vuelve a lo de antes (borrar y recrear).
M.TRAFFIC_EXCL_M = 22          -- radio de cada zona (el juego usa 10)
M.TRAFFIC_WINDOW_M = 2500      -- a cada lado del coche
M.TRAFFIC_REBUILD_M = 900      -- se rehacen al alejarse tanto del centro de la ventana
local wantExcl, exclT, exclAt, exclOn = false, nil, nil, false

local function exclusionSupported()
  return type(map) == 'table' and type(map.setTrafficExclusionZones) == 'function' and type(map.clearTrafficExclusionZones) == 'function'
end

local function applyExclusion(t, center)
  local a = api()
  if not (t and a and a.toGame and exclusionSupported()) then return false end
  local zones = {}
  local step = M.TRAFFIC_EXCL_M * 1.5
  local d0, d1 = math.max(0, center - M.TRAFFIC_WINDOW_M), math.min(t.total, center + M.TRAFFIC_WINDOW_M)
  for d = d0, d1, step do
    local x, y = geo.at(t, d)
    local la, lo = geo.toGeo(t, x, y)
    local gx, gy = a.toGame(la, lo, 0)
    if gx then
      local z = core_terrain and core_terrain.getTerrainHeight and core_terrain.getTerrainHeight(vec3(gx, gy, 0)) or 0
      zones[#zones + 1] = { pos = vec3(gx, gy, z or 0), radius = M.TRAFFIC_EXCL_M }
    end
  end
  -- (22-nov, el usuario: "hay tráfico por el TC1 cuando no debería haber jamás, ni cerca del tramo"): también el enlace
  -- de llegada (t.before) entero, con radio mayor, y la zona del TC1
  local tb = t.before
  if tb and tb.total and tb.total > 1 then
    for d = 0, tb.total, step do
      local x, y = geo.at(tb, d)
      local la, lo = geo.toGeo(tb, x, y)
      local gx, gy = a.toGame(la, lo, 0)
      if gx then
        local z = core_terrain and core_terrain.getTerrainHeight and core_terrain.getTerrainHeight(vec3(gx, gy, 0)) or 0
        zones[#zones + 1] = { pos = vec3(gx, gy, z or 0), radius = 30 }
      end
    end
  end
  local ok = pcall(function() map.setTrafficExclusionZones(zones) map.reset() end)
  if ok then exclT, exclAt, exclOn = t, center, true log('I', TAG, ('traffic exclusion: %d zones'):format(#zones)) end
  return ok
end

-- el tramo marca "sin tráfico" (en un rally, antes de montarlo): las zonas se ponen al conocer el trazado
function M.trafficOff()
  wantExcl = true
  if S and S.track and applyExclusion(S.track, S.along or 0) then return end
  if exclusionSupported() then return end
  local tr = rawget(_G, 'gameplay_traffic')
  if not tr then return end
  pcall(function()
    local n = tr.getNumOfTraffic and tr.getNumOfTraffic() or 0
    if n > 0 then
      trafficWas = math.max(trafficWas or 0, n)
      tr.deleteVehicles()
      log('I', TAG, ('traffic off for the stage (%d vehicles)'):format(n))
    end
  end)
end

-- El parque de asistencia (22-nov, el usuario: "el tráfico no debe aparecer cerca del box; que se genere al parar en el TC0,
-- con una pequeña carga, y ya aparezca a una distancia prudente, como en el vanilla"): al montar el box se borra el tráfico
-- que hubiera, se marca el entorno del box como zona sin tráfico y no se vuelve a crear hasta que sales por el TC0.
M.SERVICE_NO_TRAFFIC_M = 200
local svcN = nil
function M.serviceTraffic(x, y)
  local tr = rawget(_G, 'gameplay_traffic')
  if tr then
    pcall(function()
      local n = tr.getNumOfTraffic and tr.getNumOfTraffic() or 0
      if n > 0 then svcN = math.max(svcN or 0, n) tr.deleteVehicles() end
    end)
  end
  if x and exclusionSupported() then
    local z = core_terrain and core_terrain.getTerrainHeight and core_terrain.getTerrainHeight(vec3(x, y, 0)) or 0
    local zones = {}
    for _, d in ipairs({ { 0, 0 }, { 80, 0 }, { -80, 0 }, { 0, 80 }, { 0, -80 } }) do
      zones[#zones + 1] = { pos = vec3(x + d[1], y + d[2], z or 0), radius = M.SERVICE_NO_TRAFFIC_M * 0.8 }
    end
    if pcall(function() map.setTrafficExclusionZones(zones) map.reset() end) then exclOn = true end
  end
  log('I', TAG, ('service park: traffic off around the box (%s vehicles were around)'):format(tostring(svcN)))
end

-- Circuito cerrado (21-nov, el usuario: "si es un circuito no debería haber tráfico dentro de él"): ni tráfico ni coches
-- aparcados mientras dura. Se desactivan con la función del juego (setActiveAmount), no se borran: sin tirones al
-- quitarlos ni al devolverlos. Las zonas sin tráfico no bastan: no cubren la llegada al control y no mueven lo que ya está.
local hid = nil
function M.trafficHide()
  local tr, pk = rawget(_G, 'gameplay_traffic'), rawget(_G, 'gameplay_parking')
  if not hid then
    hid = { tr = 0, pk = 0 }
    pcall(function() hid.tr = tr.getNumOfTraffic(true) or 0 end)
    pcall(function()
      for _, id in ipairs(pk.getParkedCarsList() or {}) do
        local v = be:getObjectByID(id)
        if v and v:getActive() then hid.pk = hid.pk + 1 end
      end
    end)
  end
  pcall(function() tr.setActiveAmount(0) end)
  pcall(function() pk.setActiveAmount(0) end)
end
function M.trafficShow()
  if not hid then return end
  local h = hid
  hid = nil
  local tr, pk = rawget(_G, 'gameplay_traffic'), rawget(_G, 'gameplay_parking')
  if h.tr > 0 then pcall(function() tr.setActiveAmount(h.tr) end) end
  if h.pk > 0 then pcall(function() pk.setActiveAmount(h.pk) end) end
end
local hideTick = 0
local function hideUpdate(dt)
  if not S then return end
  -- (22-nov, el usuario: "hay tráfico durante un tramo, y por el TC1, cuando no debería haber jamás"): desde que se monta el
  -- tramo (TC) hasta que acaba, ni tráfico ni coches aparcados activos; en el enlace, sí
  local want = S.circuit or (S.phase ~= nil and S.phase ~= 'done')
  if not want then M.trafficShow() return end
  hideTick = hideTick + dt
  if hideTick < 2 then return end
  hideTick = 0
  local n = 0
  pcall(function() n = gameplay_traffic.getNumOfTraffic(true) or 0 end)
  if n > 0 or not hid then M.trafficHide() end
end

-- withLoad: al salir del TC0, como el juego, con una pequeña carga (setupTrafficWaitForUi) y el tráfico aparece lejos
function M.trafficBack(withLoad)
  wantExcl = false
  M.trafficShow()
  if exclOn then
    exclOn, exclT, exclAt = false, nil, nil
    pcall(function() map.clearTrafficExclusionZones() map.reset() end)
  end
  local n = trafficWas or svcN
  trafficWas, svcN = nil, nil
  local tr = rawget(_G, 'gameplay_traffic')
  if not (n and tr) then return end
  if withLoad and tr.setupTrafficWaitForUi then
    if pcall(tr.setupTrafficWaitForUi, true, false) then return end
  end
  if tr.setupTraffic then pcall(tr.setupTraffic, n) end
end

-- cada segundo, desde el bucle del tramo: la ventana de zonas sigue al coche
local exclTick = 0
local function exclusionUpdate(dt)
  if not (exclOn and exclT and S and S.along) then return end
  exclTick = exclTick + dt
  if exclTick < 1 then return end
  exclTick = 0
  if math.abs(S.along - (exclAt or 0)) > M.TRAFFIC_REBUILD_M and exclT.total > 2 * M.TRAFFIC_WINDOW_M then applyExclusion(exclT, S.along) end
end

-- ---- resultados ---------------------------------------------------------------------------------------------------------

local function readResults()
  local d = jsonReadFile(M.RESULTS)
  return type(d) == 'table' and d or {}
end
function M.results() return readResults() end
function M.best(eventId, stageId)
  local r = readResults()[eventId .. '/' .. stageId]
  return r and r.best or nil
end
-- los tiempos de un circuito a N vueltas se guardan aparte (no se comparan con los de una sola pasada)
local function resultId() return (S.laps or 1) > 1 and (S.stageId .. '@' .. S.laps .. 'L') or S.stageId end
local function saveResult()
  local d = readResults()
  local key = S.eventId .. '/' .. resultId()
  local r = d[key] or { runs = 0, attempts = {} }
  r.attempts = r.attempts or {}
  r.runs = (r.runs or 0) + 1
  local total = S.time + S.penalty
  r.last = total
  local newBest = not r.best or total < r.best
  if newBest then r.best = total end
  table.insert(r.attempts, 1, { time = S.time, penalty = S.penalty, total = total, split = S.splitTime, date = os.time(),
    vehicle = S.vehicle, laps = (S.laps or 1) > 1 and S.laps or nil, lapTimes = (S.laps or 1) > 1 and S.lapTimes or nil })
  while #r.attempts > 10 do table.remove(r.attempts) end
  d[key] = r
  pcall(jsonWriteFile, M.RESULTS, d, true)
  return newBest
end

local function penalise(kind, seconds)
  S.penalty = S.penalty + seconds
  S.penalties[#S.penalties + 1] = { kind = kind, s = seconds }
end

-- ---- comenzar y terminar ------------------------------------------------------------------------------------------------

local function hazardsOf(st, t)
  local out = {}
  for _, h in ipairs(st.hazards or {}) do
    local lvl = h.type == 'jump' and 3 or h.type == 'chicane' and 2 or 1
    local at = h.atM or 0
    if h.pos then
      local ok, a2 = pcall(function()
        local x, y = geo.toLocal(t, h.pos[1], h.pos[2])
        return (geo.project(t, x, y, 1, 0, #t.pts))
      end)
      if ok and a2 then at = a2 end
    end
    out[#out + 1] = { at = at, level = lvl, what = h.type == 'jump' and 'jump' or nil, source = 'organizer' }
  end
  table.sort(out, function(p, q) return p.at < q.at end)
  return out
end

local function vehicleName()
  local v = getPlayerVehicle(0)
  if not v then return nil end
  local ok, m = pcall(function() return core_vehicles.getModel(v.jbeam) end)
  local model = ok and m and m.model
  return model and ((model.Brand and (model.Brand .. ' ') or '') .. (model.Name or v.jbeam)) or v.jbeam
end

local function cleanupProps(keepTraffic, recycle)
  pcall(pathgen.clear)
  if recycle then props.retire() else props.clear() props.setVirtualRoad(nil) end
  startclock.clear()
  if not keepTraffic then M.trafficBack() end
  post = nil
end

-- La carretera tras la meta (para el STOP y su zona de control): el enlace del organizador que sale de la meta
-- ("Flying Finish -> Stop Control"), o la red de carreteras del juego si está cargada allí, o nada (en recta)
M.AFTER_M = 260
local function distLL(a, b)
  local k = math.cos(math.rad(a[1]))
  return math.sqrt(((b[2] - a[2]) * 111195 * k) ^ 2 + ((b[1] - a[1]) * 111195) ^ 2)
end
-- Por el grafo de carreteras del juego desde el punto f, en el sentido de f0 -> f: de nodo en nodo, el enlace que
-- menos gira, M.AFTER_M metros
local function walkRoads(f, f0)
  local a = api()
  local ok, out = pcall(function()
    local m = map.getMap()
    local x, y, z = props.ground(f[1], f[2])
    local x0, y0 = a.toGame(f0[1], f0[2], 0)
    local hx, hy = x - x0, y - y0
    local hl = math.sqrt(hx * hx + hy * hy)
    if hl < 1 then return nil end
    hx, hy = hx / hl, hy / hl
    local n1, n2, d = map.findClosestRoad(vec3(x, y, z))
    if not (n1 and d and d < 25) then return nil end
    local function ahead(n) local p = m.nodes[n].pos return (p.x - x) * hx + (p.y - y) * hy end
    local cur = (n2 and ahead(n2) > ahead(n1)) and n2 or n1
    local seen, pts, L = { [cur] = true }, { f }, 0
    local px, py = x, y
    -- ¿la calle que sigue por `via` se acaba pronto (calle sin salida)? Metros que se pueden seguir desde ahí, hasta `limit`
    -- (21-nov, el usuario: "el TC1 está en una calle sin salida"). MARK:deadend-v1
    local function reach(from, via, limit)
      local best, guard = 0, 0
      local stack = { { via, from, math.sqrt((m.nodes[via].pos.x - m.nodes[from].pos.x) ^ 2 + (m.nodes[via].pos.y - m.nodes[from].pos.y) ^ 2) } }
      while #stack > 0 and guard < 300 do
        guard = guard + 1
        local e = table.remove(stack)
        if e[3] > best then best = e[3] end
        if best >= limit then return best end
        for nb in pairs(props.neighbors(e[1])) do
          if nb ~= e[2] and m.nodes[nb] then
            local pa, pb = m.nodes[e[1]].pos, m.nodes[nb].pos
            stack[#stack + 1] = { nb, e[1], e[3] + math.sqrt((pb.x - pa.x) ^ 2 + (pb.y - pa.y) ^ 2) }
          end
        end
      end
      return best
    end
    while L < M.AFTER_M do
      local node = m.nodes[cur]
      local best, bd, bestScore = nil, -2, -99
      for nb in pairs(props.neighbors(cur)) do
        if not seen[nb] and m.nodes[nb] then
          local q = m.nodes[nb].pos
          local vx, vy = q.x - node.pos.x, q.y - node.pos.y
          local vl = math.sqrt(vx * vx + vy * vy)
          if vl > 0.1 then
            local dot = (vx * hx + vy * hy) / vl
            local score = dot - 5
            if dot >= 0.3 then score = dot end
            -- una calle sin salida (< 100 m de camino) solo si no hay otra que siga
            if dot >= 0.3 and reach(cur, nb, 100) < 100 then score = dot - 1.2 end
            if score > bestScore then best, bd, bestScore = nb, dot, score end
          end
        end
      end
      if (not best or bd < 0.3) and L < 30 then
        -- junto al extremo del tramo la carretera puede llegar girando (la salida en un cruce, en una T): vale
        -- cualquier enlace que no vuelva por el propio tramo (17-nov: Asturias, el TC caía en un prado en recta)
        local b2, d2 = nil, -0.6
        for nb in pairs(props.neighbors(cur)) do
          if not seen[nb] and m.nodes[nb] then
            local q = m.nodes[nb].pos
            local vx, vy = q.x - node.pos.x, q.y - node.pos.y
            local vl = math.sqrt(vx * vx + vy * vy)
            if vl > 0.1 then
              local dot = (vx * hx + vy * hy) / vl
              if dot > d2 then b2, d2 = nb, dot end
            end
          end
        end
        if b2 then best, bd = b2, 1 end
      end
      if not best or bd < 0.3 then
        -- el grafo de BeamNG.Earth se corta entre zonas: un nodo cercano que siga en el mismo sentido
        best, bd = nil, 0.5
        local cp = node.pos
        for id, nd in pairs(m.nodes) do
          if not seen[id] then
            local vx, vy = nd.pos.x - cp.x, nd.pos.y - cp.y
            local vl = math.sqrt(vx * vx + vy * vy)
            if vl > 0.5 and vl < 18 then
              local dot = (vx * hx + vy * hy) / vl
              if dot > bd then best, bd = id, dot end
            end
          end
        end
        if not best then break end
      end
      local q = m.nodes[best].pos
      L = L + math.sqrt((q.x - px) ^ 2 + (q.y - py) ^ 2)
      local vx, vy = q.x - px, q.y - py
      local vl = math.sqrt(vx * vx + vy * vy)
      if vl > 0.1 then hx, hy = vx / vl, vy / vl end
      px, py = q.x, q.y
      local la, lo = a.toGeo(q.x, q.y, q.z)
      pts[#pts + 1] = { la, lo }
      seen[best], cur = true, best
    end
    return #pts >= 2 and pts or nil
  end)
  return ok and out or nil
end

local function trimFrom(f, list)
  local out, L = { f }, 0
  for _, q in ipairs(list) do
    L = L + distLL(out[#out], q)
    out[#out + 1] = q
    if L > M.AFTER_M then break end
  end
  return out
end

-- La carretera tras la meta (para el STOP y su zona de control): el enlace del organizador que sale de la meta
-- ("Flying Finish -> Stop Control"), o la red de carreteras del juego si está cargada allí, o nada (en recta)
-- un punto del trazado a al menos `m` metros de su extremo (para el rumbo; los primeros puntos pueden estar pegados)
local function refPoint(path, fromEnd, m)
  local f = fromEnd and path[#path] or path[1]
  local n = #path
  for k = 2, n do
    local q = fromEnd and path[n - k + 1] or path[k]
    if distLL(f, q) >= m then return q end
  end
  return fromEnd and path[1] or path[n]
end

-- La carretera que sale del tramo por un extremo (atEnd: la meta; si no, la salida), alejándose de él: el enlace del
-- organizador que toca ese extremo (llegue o salga de él: así el tramo al revés usa la misma carretera y el mismo puesto
-- de control), o la red de carreteras del juego, o nada (en recta)
local function endRoad(ev, path, atEnd)
  local f, f0 = atEnd and path[#path] or path[1], refPoint(path, atEnd, 15)
  local best, bd = nil, 80
  for _, l in ipairs(ev.liaisons or {}) do
    if l.path and #l.path >= 2 then
      local d1, d2 = distLL(l.path[1], f), distLL(l.path[#l.path], f)
      if d1 < bd then best, bd = l.path, d1 end
      if d2 < bd then
        local rev = {}
        for k = #l.path, 1, -1 do rev[#rev + 1] = l.path[k] end
        best, bd = rev, d2
      end
    end
  end
  if best then return trimFrom(f, best), 'liaison' end
  local out = walkRoads(f, f0)
  if out then return out, 'roads' end
  return nil
end
M.AFTER_ROAD_M = 9        -- tras la meta, a más de esto de una carretera del juego no se cuenta como carretera
-- ¿va de verdad por carretera? cada 15 m entre from y upTo, la carretera del juego a menos de AFTER_ROAD_M.
-- nil: no hay grafo cargado por ahí (no se puede saber)
local function onRoadFrac(tr, from, upTo)
  local n, ok, any = 0, 0, false
  for d = math.max(0, from), math.min(tr.total, upTo), 15 do
    local x, y = geo.at(tr, d)
    local la, lo = geo.toGeo(tr, x, y)
    local gx, gy, gz = props.ground(la, lo)
    if gx then
      local n1, _, dd = props.nearestRoad(gx, gy, gz, 60)
      n = n + 1
      if n1 then any = true end
      if dd and dd <= M.AFTER_ROAD_M then ok = ok + 1 end
    end
  end
  if n == 0 or not any then return nil end
  return ok / n
end
M.onRoadFrac = onRoadFrac

-- Norma de oro (18-nov, Salas): la salida y el control horario siempre en una carretera del juego, alineados y con
-- sitio para la carpa. Si los primeros metros del trazado del organizador no van por carretera (pista que el mapa no
-- tiene, trazado desplazado), la salida se adelanta hasta donde sí; y si no hay carretera antes de la salida para el
-- control horario, la salida se adelanta TC_BEFORE_M + 60 m por el propio tramo y el trozo quitado hace de acceso.
-- Devuelve los metros quitados (0 si nada) y el trozo quitado como path
M.START_CHECK_M = 120
local function validateStart(t, hasBefore, graphReady)
  local fr = onRoadFrac(t, 0, M.START_CHECK_M)
  -- nil: ninguna carretera del juego cerca. Si el grafo de la zona ya está cargado (viaje con carga), es que no la
  -- hay: se busca más adelante
  t.startInfo = { frac = fr, hasBefore = hasBefore == true, graphReady = graphReady == true }
  if fr == nil then
    if not graphReady then return 0, nil end
    fr = 0
  end
  local cut = 0
  if fr < 0.8 then
    for a0 = 10, t.total - 600, 10 do
      local f2 = onRoadFrac(t, a0, a0 + M.START_CHECK_M)
      if f2 and f2 >= 0.8 then cut = a0 break end
    end
    if cut == 0 then return 0, nil end
    log('W', TAG, ('start: the first %.0f m are not on a road (%.0f%%): start moved forward'):format(cut, fr * 100))
  end
  if not hasBefore and cut < dressing.TC_BEFORE_M + 60 then
    cut = dressing.TC_BEFORE_M + 60
    log('W', TAG, 'start: no road before the start for the time control: start moved ' .. cut .. ' m forward')
  end
  if cut <= 0 or cut >= t.total - 500 then return 0, nil end
  local removed = geo.cutStart(t, cut)
  return cut, removed
end
local function afterPath(ev, path) return endRoad(ev, path, true) end
local function beforePath(ev, path) return endRoad(ev, path, false) end

-- Empieza un tramo: ev (el evento completo), st (su tramo con path), info (stageNumber, stageCount, surface)
-- ¿circuito cerrado? Lo dice el paquete o se ve en el trazado: la meta junto a la salida y el tramo mucho más largo
function M.isCircuit(st)
  if type(st) ~= 'table' then return false end
  if st.circuit ~= nil then return st.circuit == true end
  local p = st.path
  if not (p and #p >= 4) then return false end
  local gap = distLL(p[1], p[#p])
  if gap >= M.CIRCUIT_M then return false end
  local len = 0
  for i = 2, #p do len = len + distLL(p[i - 1], p[i]) if len > 4 * M.CIRCUIT_M then return true end end
  return false
end
-- Vueltas del circuito montado: solo antes de salir. Devuelve las que quedan puestas.
function M.setLaps(n)
  if not (S and S.circuit) or S.session then return S and S.laps or 1 end
  if S.phase == 'running' or S.phase == 'toStop' or S.phase == 'done' then return S.laps end
  n = math.max(1, math.min(M.MAX_LAPS, math.floor(tonumber(n) or S.laps or 1)))
  S.laps = n
  M.lapsFor[S.eventId .. '/' .. S.stageId] = n
  S.best = M.best(S.eventId, resultId())
  return n
end

-- Circuito: el coche espera en la parrilla; Iniciar arma el semáforo
function M.gridGo()
  if not (S and S.phase == 'grid') then return false end
  local t = S.track
  S.phase, S.countdown, S.noseAtArm, S.saidCount = 'countdown', M.GRID_COUNTDOWN_S, nil, {}
  guide.clear()
  guide.along(t, (S.eventName or '') .. ' - ' .. (S.title or ''), S.notes)
  guide.racingLine(S.opt.hardcore ~= true)   -- en circuito, la línea de carrera hace de copiloto
  S.lineArmed = true
  audio.clear()
  return true
end
local function beep(go)
  pcall(function() Engine.Audio.playOnce('AudioGui', go and 'event:UI_CountdownGo' or 'event:UI_Countdown1') end)
end
local function flash(msg, secs, big)
  pcall(function() guihooks.trigger('ScenarioFlashMessage', { { msg, secs or 2, '', big == true } }) end)
end

function M.start(ev, st, info)
  -- (22-nov: una prueba dejó el guiado por script activo y el volante se quedó sin force feedback) al empezar un tramo, la
  -- IA del coche del jugador siempre apagada
  pcall(function() require('earthRaid/dbg').aiOff() end)
  -- (23-nov: la cámara libre de una prueba se quedaba activa y el tramo empezaba mirando desde otro sitio) al empezar, la
  -- cámara siempre en el coche del jugador
  pcall(function()
    local cn = core_camera and core_camera.getActiveCamName and core_camera.getActiveCamName()
    if cn == 'free' or cn == 'path' then commands.setGameCamera() end
  end)
  -- otro tramo encima: el tráfico sigue fuera (se devolverá al acabar este)
  M.stop(true, true)
  -- lo del tramo anterior queda de repuesto: lo que coincida con este (ida y vuelta, salida en la meta) se reutiliza
  cleanupProps(true, true)
  local orphans = props.purgeOrphans() + phys.purgeOrphans()
  if orphans > 0 then log('I', TAG, 'removed ' .. orphans .. ' leftover objects') end
  if not (st and st.path and #st.path >= 2) then return false, 'no path' end
  local opt = settings.get()
  local cpath = clean.stage(st)
  local t = geo.track(cpath)
  -- ¿grafo cargado en la salida? lo dice el cargador tras el viaje; si no (rally completo, tramo cercano), se mira si
  -- hay alguna carretera del juego a menos de 150 m de la salida
  info = info or {}
  if info.graphReady == nil then
    local okG, g = pcall(function()
      local la, lo = geo.toGeo(t, t.pts[1][1], t.pts[1][2])
      local gx, gy, gz = props.ground(la, lo)
      return gx and props.nearestRoad(gx, gy, gz, 150) ~= nil
    end)
    info.graphReady = okG and g == true
  end
  -- Trazado desplazado (19-nov, Canarias ss01 a 50 m de la carretera, Cristian López ss01 a 20 m): si al principio
  -- del tramo hay una carretera del juego paralela a una distancia constante (mismo vector en todas las muestras),
  -- el archivo del organizador está mal georreferenciado y se corrige todo el trazado con ese vector
  if info and info.graphReady then
    local okO, moved = pcall(function()
      local vx, vy, n = {}, {}, 0
      for d = 0, math.min(t.total, 240), 20 do
        local x, y = geo.at(t, d)
        local la, lo = geo.toGeo(t, x, y)
        local gx, gy, gz = props.ground(la, lo)
        if gx then
          local n1, n2, dd, cx, cy = props.nearestRoad(gx, gy, gz, 90)
          if n1 and dd and cx then n = n + 1 vx[n], vy[n] = cx - gx, cy - gy end
        end
      end
      if n < 6 then return nil end
      local mx, my = 0, 0
      for i = 1, n do mx, my = mx + vx[i], my + vy[i] end
      mx, my = mx / n, my / n
      local mag = math.sqrt(mx * mx + my * my)
      if mag < 8 then return nil end
      local spread = 0
      for i = 1, n do spread = math.max(spread, math.sqrt((vx[i] - mx) ^ 2 + (vy[i] - my) ^ 2)) end
      if spread > 6 then return nil end
      for i = 1, #t.pts do t.pts[i][1], t.pts[i][2] = t.pts[i][1] + mx, t.pts[i][2] + my end
      t.offsetFix = { mx, my }
      return mag
    end)
    if okO and moved then
      cpath = {}
      for i, p in ipairs(t.pts) do cpath[i] = { geo.toGeo(t, p[1], p[2]) } end
      log('W', TAG, ('stage path %.0f m off the game road everywhere: whole path shifted onto it'):format(moved))
    elseif not okO then log('W', TAG, 'offset fix: ' .. tostring(moved)) end
  end
  -- la carretera tras la meta: ya si es un enlace del organizador; si no, al montar la meta (grafo cargado allí)
  local function findAfter()
    -- (otra vez al acercarse si el de antes era corto: el grafo de carreteras no estaba cargado allí)
    if t.afterFixed or (t.after and t.after.total >= dressing.STOP_AFTER_M + 40) then return end
    local ap, how = afterPath(ev, cpath)
    local nt = ap and geo.track(ap)
    if nt and (not t.after or nt.total > t.after.total + 5) then
      t.after, t._snapT, t.afterOff = nt, nil, nil
      t.stopAt = math.max(60, math.min(dressing.STOP_AFTER_M, t.after.total))
      log('I', TAG, ('after the finish: %s, %.0f m, STOP at %.0f m'):format(how, t.after.total, t.stopAt))
    end
  end
  -- (23-nov, el usuario) tramo posterior FIJO: el paquete puede traer st.afterPts (lat/lon, desde la meta hasta una calle
  -- real); se usa tal cual y no se busca ni se recorta nada (meta en un río, STOP junto a la calle más próxima)
  if type(st.afterPts) == 'table' and #st.afterPts >= 2 then
    local nt = geo.track(st.afterPts)
    if nt and nt.total >= 30 then
      t.after, t._snapT, t.afterOff = nt, nil, nil
      t.stopAt = math.max(30, nt.total - 3)   -- justo en el borde de la calle (23-nov)
      t.afterFixed, t.finishCut, t.finishMoved, t.trimmed = true, true, 0, true
      log('I', TAG, ('after the finish: fixed by the pack, %.0f m, STOP at %.0f m'):format(nt.total, t.stopAt))
    end
  end
  if not t.afterFixed then findAfter() end
  local bp, bhow = beforePath(ev, cpath)
  -- norma de oro: salida y control horario en carretera (con el grafo cargado; si no, se repite en startLater)
  local cutM, removed = 0, nil
  do
    local okV, c, r = pcall(validateStart, t, bp ~= nil and onRoadFrac(geo.track(bp), 0, dressing.TC_BEFORE_M) ~= nil
      and (onRoadFrac(geo.track(bp), 0, dressing.TC_BEFORE_M) or 0) >= 0.8, info and info.graphReady)
    if okV then cutM, removed = c or 0, r else log('W', TAG, 'validateStart: ' .. tostring(c)) end
  end
  if cutM > 0 then
    t.cutStart = cutM
    bp, bhow = nil, nil
    -- el acceso: el trozo quitado si va por carretera; si no, la carretera del juego hacia atrás desde la nueva salida
    if removed and #removed >= 2 then
      local rt = geo.track(removed)
      if (onRoadFrac(rt, 0, rt.total) or 0) >= 0.8 then bp, bhow = removed, 'stage cut' end
    end
    if not bp then
      local np = {}
      for i, p in ipairs(t.pts) do np[i] = { geo.toGeo(t, p[1], p[2]) } end
      bp, bhow = beforePath(ev, np)
    end
  end
  if bp then
    t.before = geo.track(bp)
    log('I', TAG, ('before the start: %s, %.0f m'):format(bhow, t.before.total))
  end
  -- el repuesto lejos de este tramo (y de sus accesos) no se va a aprovechar
  local function nearTrack(it)
    for _, tr in ipairs({ t, t.before, t.after }) do
      local x, y = geo.toLocal(tr, it.lat, it.lon)
      local _, d = geo.project(tr, x, y, 1, 0, #tr.pts)
      if d < M.SPARE_KEEP_M then return true end
    end
    return false
  end
  local dropped = props.flushSpare(nearTrack)
  if props.spareCount() > 0 or dropped > 0 then
    log('I', TAG, ('recycling: %d objects kept from the previous stage, %d removed'):format(props.spareCount(), dropped))
  end
  -- la línea del mod Racing Line, solo dentro del tramo; fuera de él, la azul del GPS
  guide.hold()
  guide.liaison(opt.hardcore == true)
  local splitAt = t.total > 1500 and math.floor(t.total / 2 / 100 + 0.5) * 100 or nil
  local hazards = hazardsOf(st, t)
  S = { eventId = ev.id, eventName = ev.name, stageId = st.id, title = st.title, runs = st.runs or {}, track = t,
    surface = st.surface or ev.surface, stageNumber = info and info.number, stageCount = info and info.count,
    phase = 'approach', time = 0, penalty = 0, penalties = {}, hint = 1, along = 0, splitAt = splitAt, splitTime = nil,
    stagingLeft = M.STAGING_S, countdown = M.COUNTDOWN_S, distM = nil, staged = false, best = M.best(ev.id, st.id),
    opt = opt, reliefTimer = 0, reliefSeen = {}, saidWarn = {}, saidCount = {}, wall = 0, vehicle = vehicleName() }
  pacenotes.safe = opt.notesSafe == true
  local okN, notes = pcall(pacenotes.generate, t, hazards)
  S.notes = okN and notes or {}
  if not okN then log('W', TAG, 'pacenotes: ' .. tostring(notes)) end
  S.noteIdx, S.noteSerial, S.shown = 1, 0, {}
  -- circuito: vueltas (en el rally completo, una pasada como en la prueba real)
  S.circuit = M.isCircuit(st)
  -- modo circuito (tramo suelto): parrilla -> cuenta atrás -> vueltas -> bandera -> resultado; sin copiloto
  S.circuitMode = S.circuit and not (info and info.session) or nil
  S.lap, S.laps, S.lapTimes, S.lapStart = 1, 1, {}, 0
  if S.circuit then M.trafficHide() else M.trafficShow() end
  if S.circuit and not (info and info.session) then
    S.laps = M.lapsFor[ev.id .. '/' .. st.id] or M.DEFAULT_LAPS
    S.best = M.best(ev.id, resultId())
  end
  -- en el rally completo el tráfico lo lleva rally.lua (fuera en los tramos, dentro en los enlaces)
  S.session = info and info.session or nil
  if S.session then S.phase = 'hold' end
  -- tramo suelto: primero el control horario (TC), como en el juego: allí se ficha y se da la hora de salida
  do
    local sx, sy = t.pts[1][1], t.pts[1][2]
    local dx, dy = geo.dirAt(t, 0)
    S.tcX, S.tcY = sx - dx * dressing.TC_BEFORE_M, sy - dy * dressing.TC_BEFORE_M
    S.tcLat, S.tcLon = geo.toGeo(t, S.tcX, S.tcY)
    -- por la carretera de verdad si se conoce (en una curva, la recta hacia atrás se sale de ella)
    if t.before then
      S.tcLat, S.tcLon = geo.toGeo(t.before, geo.at(t.before, dressing.tcAt(t)))
      S.tcX, S.tcY = geo.toLocal(t, S.tcLat, S.tcLon)
    end
    if not S.session then S.phase, S.tcHold = 'tc', 0 end
    if S.circuitMode then S.phase = 'grid' end
  end
  if opt.noTraffic or wantExcl then M.trafficOff() end
  startclock.ensure()
  -- la meta y todo lo de más allá de la salida se monta al acercarse (M.DRESS_AHEAD_M): calzada y edificios reales
  -- Norma: el tramo termina siempre en la calzada (asfalto o tierra). Si el final del archivo se sale de la carretera
  -- (Ourense: un enlace al parque tomado como tramo; organizadores que acaban el trazo en un aparcamiento), la meta se
  -- recorta hacia atrás hasta el último punto en la carretera, y lo de después se busca por la red desde ahí.
  M.ON_ROAD_M = 4
  local function onRoad(x, y)
    local la, lo = geo.toGeo(t, x, y)
    local a = api()
    local gx, gy = a.toGame(la, lo, 0)
    if not gx then return nil end
    local z = core_terrain and core_terrain.getTerrainHeight and core_terrain.getTerrainHeight(vec3(gx, gy, 0)) or 0
    local n1, n2 = map.findClosestRoad(vec3(gx, gy, z or 0))
    local m = map.getMap()
    if not (n1 and n2 and m.nodes[n1] and m.nodes[n2]) then return nil end
    local A, B = m.nodes[n1].pos, m.nodes[n2].pos
    local sx, sy = B.x - A.x, B.y - A.y
    local L2 = sx * sx + sy * sy
    local u = L2 > 0.01 and math.max(0, math.min(1, ((gx - A.x) * sx + (gy - A.y) * sy) / L2)) or 0
    local d = math.sqrt((gx - A.x - sx * u) ^ 2 + (gy - A.y - sy * u) ^ 2)
    return d <= (m.nodes[n1].radius or 3) + M.ON_ROAD_M, d
  end
  local function trimFinishToRoad()
    if t.trimmed then return end
    t.trimmed = true
    local ok = onRoad(geo.at(t, t.total))
    if ok ~= false then return end
    for d = t.total - 5, math.max(t.total * 0.5, t.total - 300), -5 do
      local x, y = geo.at(t, d)
      if onRoad(x, y) then
        local cut = t.total - d
        geo.truncate(t, d)
        t.finishCut = true
        -- lo de después de la meta: por la red de carreteras desde la nueva meta
        local f = { geo.toGeo(t, geo.at(t, t.total)) }
        local f0 = { geo.toGeo(t, geo.at(t, math.max(0, t.total - 15))) }
        local ap = walkRoads(f, f0)
        if ap then
          t.after, t._snapT, t.afterOff = geo.track(ap), nil, nil
          t.stopAt = math.max(60, math.min(dressing.STOP_AFTER_M, t.after.total))
        elseif t.after then
          -- sin red de carreteras desde la meta nueva: el enlace de antes, pero empezando EN la meta nueva. Si no,
          -- todo lo de "pasada la meta" se medía desde la meta vieja (19-nov, Córdoba SS1: la meta retrocedió 45 m y
          -- los carteles del otro sentido y el reloj quedaron 46 m más allá de la línea, como otra meta)
          local np = { f }
          for _, q in ipairs(t.after.pts) do np[#np + 1] = { geo.toGeo(t.after, q[1], q[2]) } end
          t.after, t._snapT, t.afterOff = geo.track(np), nil, nil
          t.stopAt = math.max(60, math.min(dressing.STOP_AFTER_M, t.after.total - 5))
        end
        log('W', TAG, ('finish off the road: moved %.0f m back onto the road'):format(cut))
        return
      end
    end
  end
  M._trimFinish = trimFinishToRoad
  -- Sin carretera después de la meta (la ruta acaba en un fondo de saco, en el monte, o el grafo no sigue): la meta se
  -- adelanta por el propio trazado para que el STOP quede en la calzada del tramo, a la distancia de frenada de la
  -- meta (norma 18-nov: nunca un control fuera de la calzada; Rey Silo dejaba el STOP en mitad del monte)
  local function pullFinishBack()
    if t.afterFixed or (t.after and t.after.total >= 60) then return end
    local want = math.min(dressing.STOP_AFTER_M, math.max(60, t.total * 0.12))
    if t.total - want < 500 then want = math.max(60, t.total - 500) end
    if want < 60 then return end
    local newTotal = t.total - want
    local pts = {}
    local x0, y0 = geo.at(t, newTotal)
    pts[1] = { geo.toGeo(t, x0, y0) }
    for i = 1, #t.pts do
      if t.cum[i] > newTotal + 0.5 then pts[#pts + 1] = { geo.toGeo(t, t.pts[i][1], t.pts[i][2]) } end
    end
    if #pts < 2 then return end
    geo.truncate(t, newTotal)
    t.after, t._snapT, t.afterOff = geo.track(pts), nil, nil
    t.stopAt = math.max(60, math.min(dressing.STOP_AFTER_M, t.after.total - 5))
    t.finishCut = true
    log('W', TAG, ('no road after the finish: finish moved %.0f m back, STOP on the stage road'):format(want))
  end
  -- los enlaces del organizador suelen estar dibujados a mano (rectas por el monte): hasta pasado el STOP tiene que ir
  -- por carretera de verdad
  -- devuelve 'unknown' si el grafo de carreteras aún no está cargado por ahí (hay que esperar)
  local function checkAfter()
    if t.finishCut or not t.after then return end
    local need = (t.stopAt or dressing.STOP_AFTER_M) + 20
    local fr = onRoadFrac(t.after, 10, need)
    if fr == nil then return 'unknown' end
    if fr >= 0.8 then return end
    log('W', TAG, ('after the finish: only %.0f%% on a road, looking for the real road'):format(fr * 100))
    local f, f0 = cpath[#cpath], refPoint(cpath, true, 15)
    local wr = walkRoads(f, f0)
    local nt = wr and geo.track(wr)
    if nt and nt.total >= 60 and (onRoadFrac(nt, 10, need) or 0) >= 0.8 then
      t.after, t._snapT, t.afterOff = nt, nil, nil
      t.stopAt = math.max(60, math.min(dressing.STOP_AFTER_M, nt.total - 5))
      log('I', TAG, ('after the finish: roads, %.0f m, STOP at %.0f m'):format(nt.total, t.stopAt))
    else
      t.after = nil   -- pullFinishBack: el STOP en la calzada del tramo
    end
  end
  -- Norma de oro en la meta (18-nov, Ingenio, Cristian López, Canarias ss01): si los últimos 120 m del trazado no van
  -- por carretera del juego (el KMZ sigue por donde el mapa no tiene carretera, o va desplazado), la meta retrocede
  -- hasta el último tramo que sí va por carretera. En tramos de tierra no se aplica (el camino puede no estar en el
  -- mapa y cuenta la calzada virtual). Devuelve 'unknown' si el grafo no está cargado por ahí.
  local function checkFinish()
    if t.finishCut or t.finishMoved then return end
    local fr = onRoadFrac(t, t.total - 120, t.total)
    if fr == nil then return 'unknown' end
    -- en tierra el camino puede no estar en el mapa (cuenta la calzada virtual): solo si el último kilómetro sí va
    -- por carretera del juego, es que el mapa la tiene y la meta debe ir por ella
    if dressing.normSurface(S.surface) == 'gravel' and (onRoadFrac(t, t.total - 1000, t.total - 120) or 0) < 0.6 then return end
    if fr >= 0.8 then return end
    for a0 = t.total - 20, 700, -20 do
      local f2 = onRoadFrac(t, a0 - 120, a0)
      if f2 and f2 >= 0.8 then
        local moved = t.total - a0
        geo.truncate(t, a0)
        t.after, t._snapT, t.afterOff, t.finishMoved = nil, nil, nil, moved
        log('W', TAG, ('finish: the last %.0f m are not on a road (%.0f%%): finish moved %.0f m back'):format(120, fr * 100, moved))
        return
      end
    end
  end
  local finishLater
  finishLater = function()
    -- la meta espera a que el eje de la carretera se encuentre en la línea (hasta ~30 s; en tierra sin carretera del
    -- mapa no se espera): con el grafo a medias la línea de meta y sus carteles quedaban fuera del eje. MARK:ends-ready-v1
    -- (sin límite práctico mientras el coche está lejos; a menos de 200 m de la meta se monta ya, esté o no el eje: quien
    -- llega lanzado tiene que ver la meta)
    local maxTries = dressing.normSurface(S.surface) == 'gravel' and 8 or 60
    local near = false
    pcall(function()
      local pl, po = api().position()
      if pl then
        local x, y = geo.toLocal(t, pl, po)
        local fx, fy = t.pts[#t.pts][1], t.pts[#t.pts][2]
        near = (x - fx) ^ 2 + (y - fy) ^ 2 < 200 * 200 and S.phase == 'running'
      end
    end)
    if not near then
      local okR, ready = pcall(function()
        local la, lo = geo.toGeo(t, t.pts[#t.pts][1], t.pts[#t.pts][2])
        local dx, dy = geo.dirAt(t, t.total)
        return dressing.snap(la, lo, dx, dy) ~= nil
      end)
      local paused = simTimeAuthority and simTimeAuthority.getPause and simTimeAuthority.getPause()
      if okR and not ready and (paused or (S.finishSnapTries or 0) < maxTries) then
        if not paused then S.finishSnapTries = (S.finishSnapTries or 0) + 1 end
        dressing.later(t.total, finishLater, t, 1.5)
        return
      end
    end
    pcall(trimFinishToRoad)
    local okF, vF = pcall(checkFinish)
    if not okF then log('W', TAG, 'checkFinish: ' .. tostring(vF)) end
    if not t.finishCut then findAfter() end
    -- (23-nov, el usuario: «la salida de la meta termina dentro de una casa») el STOP final del tramo posterior fijo cae en
    -- zona libre: sin techo ni pared a menos de 3,5 m; si no, retrocede por el camino hasta el primer punto libre
    pcall(function()
      if not (t.afterFixed and t.after and t.stopAt) then return end
      local a = api()
      local function free(d)
        local x, y = geo.at(t.after, d)
        local la, lo = geo.toGeo(t.after, x, y)
        local gx, gy = a.toGame(la, lo, 0)
        if not gx then return nil end
        local z = core_terrain.getTerrainHeight(vec3(gx, gy, 0))
        if type(z) ~= 'number' or z < -10 then return nil end          -- terreno sin cargar: no se sabe
        local dn = castRayStatic(vec3(gx, gy, z + 40), vec3(0, 0, -1), 80)
        if type(dn) == 'number' and 40 - dn > z + 1.5 then return false end   -- techo o algo alto encima
        for k = 0, 7 do
          local an = k * math.pi / 4
          local h = castRayStatic(vec3(gx, gy, z + 1.2), vec3(math.cos(an), math.sin(an), 0), 3.5)
          if type(h) == 'number' and h < 3.4 then return false end
        end
        return true
      end
      local d0, d = t.stopAt, t.stopAt
      while d >= 30 do
        local f = free(d)
        if f == nil then return end
        if f then break end
        d = d - 2
      end
      if d < 30 then d = 30 end
      if d < d0 - 0.5 then
        t.stopAt = d
        log('W', TAG, ('after the finish: STOP moved %.0f m back to a free spot (house/roof at the end)'):format(d0 - d))
      end
    end)
    local okC, verdict = pcall(checkAfter)
    if (okC and verdict == 'unknown') or (okF and vF == 'unknown') then
      -- las carreteras tras la meta aún no están cargadas: la meta se monta cuando lo estén (si el coche no está ya
      -- encima), hasta 90 s (18-nov: el STOP de Rey Silo se montaba en el monte por montarse antes de tiempo)
      -- (con el juego en pausa por la carga de BeamNG.Earth no se cuenta el intento)
      if simTimeAuthority and simTimeAuthority.getPause and simTimeAuthority.getPause() then
        dressing.later(t.total, finishLater, t, 1.5)
        return
      end
      S.finishWait = (S.finishWait or 0) + 1
      local far = true
      pcall(function()
        local a = api()
        local pl, po = a.position()
        if pl then
          local x, y = geo.toLocal(t, pl, po)
          local fx, fy = t.pts[#t.pts][1], t.pts[#t.pts][2]
          far = (x - fx) ^ 2 + (y - fy) ^ 2 > 150 * 150
        end
      end)
      if far and S.finishWait < 60 then
        dressing.later(t.total, finishLater, t, 1.5)
        return
      end
      -- el grafo nunca llegó: por ahí no hay carretera del juego. La meta, atrás hasta donde sí la hay
      if okF and vF == 'unknown' and dressing.normSurface(S.surface) ~= 'gravel' then
        pcall(function()
          for a0 = t.total - 20, 700, -20 do
            local f2 = onRoadFrac(t, a0 - 120, a0)
            if f2 and f2 >= 0.8 then
              local moved = t.total - a0
              geo.truncate(t, a0)
              t.after, t._snapT, t.afterOff, t.finishMoved = nil, nil, nil, moved
              log('W', TAG, ('finish: no road near the finish: finish moved %.0f m back'):format(moved))
              findAfter()
              break
            end
          end
        end)
      end
    end
    pcall(pullFinishBack)
    pcall(S.setVirtual)
    local flat, flon = geo.toGeo(t, t.pts[#t.pts][1], t.pts[#t.pts][2])
    dressing.finishLine(t, dressing.hwAt(t, t.total))
    log('I', TAG, ('finish dressed (%s)'):format(flat and 'ok' or '?'))
  end
  -- la carretera antes de la salida, otra vez al acercarse (el TC está a 150 m: hace falta entera)
  local startLater = function()
    -- (21-nov: en un rally el tramo se monta a 2,5 km, con el grafo de allí a medias, y el camino de antes podía salir por
    -- una calle sin salida; al acercarse, con el grafo cargado, se vuelve a calcular y vale el nuevo si cambia de rama. MARK:before-recheck-v1)
    if t.cutStart and t.cutStart > 0 then return end
    local bp2, how2 = beforePath(ev, cpath)
    local nb = bp2 and geo.track(bp2)
    local moved = false
    if nb and t.before then
      local ex, ey = geo.at(nb, math.min(nb.total, dressing.TC_BEFORE_M + 40))
      local ox, oy = geo.at(t.before, math.min(t.before.total, dressing.TC_BEFORE_M + 40))
      local nla, nlo = geo.toGeo(nb, ex, ey)
      local ola, olo = geo.toGeo(t.before, ox, oy)
      moved = distLL({ nla, nlo }, { ola, olo }) > 12
    end
    if nb and (not t.before or moved or nb.total > t.before.total + 5) then
      t.before, t._snap0 = nb, nil
      log('I', TAG, ('before the start (near): %s, %.0f m'):format(how2, nb.total))
      M.refreshLine()
    end
  end
  S.startLater = startLater
  -- el trazado (con sus accesos) cuenta como calzada donde el juego no tiene carretera: caminos de tierra, pistas
  dressing.surface = dressing.normSurface(S.surface)
  winter.forStage(dressing.surface == 'snow')   -- nevada + agarre de nieve + suelo blanco (solo tramos de nieve)
  S.setVirtual = function()
    local a = extensions.beamngEarth_api
    local hw = dressing.defaultHalfWidth()
    local pts = {}
    local function add(tr, rev)
      if not tr then return end
      local n = #tr.pts
      for k = 1, n do
        local p = tr.pts[rev and (n - k + 1) or k]
        local la, lo = geo.toGeo(tr, p[1], p[2])
        local x, y = a.toGame(la, lo, 0)
        if x then pts[#pts + 1] = { x, y } end
      end
    end
    add(t.before, true)
    add(t)
    add(t.after)
    props.setVirtualRoad(pts, hw)
    if winter.active() then winter.setRoad(pts, hw) end   -- bancos de nieve a los lados del tramo
  end
  pcall(S.setVirtual)
  local okB, startObj = pcall(dressing.build, t, opt.arrows and S.notes or {}, opt.cautions and hazards or {}, splitAt,
    { circuit = S.circuitMode == true, ambience = opt.ambience, sounds = opt.sounds, closures = opt.closures, finishLater = finishLater, startLater = startLater,
      surface = S.surface,
      -- la salida y el control se montan cuando la carretera de allí se puede usar: el eje encontrado en la línea y en el
      -- punto del TC (con el grafo a medias las líneas quedaban fuera del eje o torcidas). MARK:ends-ready-v1
      startReady = function()
        local la, lo = geo.toGeo(t, t.pts[1][1], t.pts[1][2])
        local gx, gy, gz = props.ground(la, lo)
        if not gx then return false end
        if props.nearestRoad(gx, gy, gz, 60) == nil then return false end
        local dx, dy = geo.dirAt(t, 0)
        if not dressing.snap(la, lo, dx, dy) then return false end
        local tl, to = dressing.lineAt(t, 0, -dressing.tcAt(t))
        if tl then
          local tx, ty, tz = props.ground(tl, to)
          if tx and props.nearestRoad(tx, ty, tz, 30) == nil then return false end
        end
        return true
      end,
      reversed = st.reverse == true,
      onStartClock = function(obj) startclock.setClock(obj) M.refreshLine() end })
  S.dressT = 0
  if okB and startObj then startclock.setClock(startObj) end
  M.collision()
  startclock.setStage(tostring((st.runs and st.runs[1]) or (info and info.number) or ''))
  if not okB then log('W', TAG, 'dressing: ' .. tostring(startObj)) end
  M.refreshLine()
  audio.setPack(settings.voiceDir())
  audio.clear()
  S.wall = geo.dayClock()
  if not S.session then
    local a0 = api()
    if a0 and a0.gpsSet then pcall(a0.gpsSet, S.tcLat, S.tcLon, 'TC · ' .. (st.title or '')) end
  end
  log('I', TAG, ('stage %s / %s started: %.0f m, %d notes, %d objects'):format(ev.id, st.id, t.total, #S.notes, props.count()))
  return true
end

-- Rally completo: fichado el control horario, el tramo pasa a la línea de salida con `seconds` hasta el minuto de salida
function M.release(seconds)
  if not (S and S.phase == 'hold') then return false end
  S.phase, S.stagingInit = 'approach', seconds
  return true
end

-- la línea de salida en coordenadas del juego (para la cámara del reloj; cambia tras un rebase)
-- La línea de salida y el punto de fichaje, anclados al eje de la carretera (se recalculan hasta que el grafo de
-- carreteras está cargado allí: entonces coinciden con lo pintado)
-- la carga (loader.lua) retiene el montaje hasta que las carreteras de la zona están cargadas
M.jobsHeld = false
function M.holdJobs(on) M.jobsHeld = on == true end
-- vuelve a buscar la carretera antes de la salida (y el TC) con el grafo ya cargado
function M.retryStart()
  if S and S.startLater then pcall(S.startLater) end
  M.refreshLine()
end

function M.refreshLine()
  if not S then return end
  local t = S.track
  local la, lo, dx, dy = dressing.lineAt(t, 0, 0)
  if la then S.line = { lat = la, lon = lo, dx = dx, dy = dy } end
  local tl, to = dressing.lineAt(t, 0, -dressing.tcAt(t))
  if tl then
    S.tcLat, S.tcLon = tl, to
    S.tcX, S.tcY = geo.toLocal(t, tl, to)
  end
  local a = api()
  local x, y, z = a.toGame(S.line.lat, S.line.lon, 0)
  if x then
    -- (22-nov) con el sentido de la carretera en la salida: la cámara del reloj se coloca como la del juego
    local fwd
    pcall(function()
      local ax, ay = geo.at(t, 0)
      local bx, by = geo.at(t, 12)
      local la, lo = geo.toGeo(t, ax, ay)
      local lb, lb2 = geo.toGeo(t, bx, by)
      local g1x, g1y = a.toGame(la, lo, 0)
      local g2x, g2y = a.toGame(lb, lb2, 0)
      if g1x and g2x then fwd = vec3(g2x - g1x, g2y - g1y, 0) end
    end)
    startclock.setLine(vec3(x, y, z or 0), fwd)
  end
end

local function clearScreen()
  audio.clear()
  pcall(function() guihooks.trigger('clearAllVisualPacenotes') end)
  guide.clear()
end

-- Cancelar: todo fuera ya
-- (23-nov) al terminar o cancelar, el terreno vuelve a como estaba (se quita el camino generado, los bancos, la nieve): si el
-- coche queda por debajo del suelo restaurado (o dentro de lo que se levantó) se sube a la superficie, sin tocar su giro
local function safeCar()
  pcall(function()
    local veh = be:getPlayerVehicle(0)
    if not veh then return end
    local p = veh:getPosition()
    local gz = core_terrain and core_terrain.getTerrainHeight and core_terrain.getTerrainHeight(vec3(p.x, p.y, 0))
    if type(gz) ~= 'number' or gz < -10 then return end
    local sf = be:getSurfaceHeightBelow(vec3(p.x, p.y, math.max(p.z, gz) + 3))
    local top = math.max(gz, type(sf) == 'number' and sf or gz)
    if p.z < top - 0.15 then
      local q = quatFromDir(veh:getDirectionVector(), veh:getDirectionVectorUp())
      veh:setPositionRotation(p.x, p.y, top + 0.6, q.x, q.y, q.z, q.w)
      log('W', TAG, ('car was under the restored ground (%.2f < %.2f): lifted'):format(p.z, top))
    end
  end)
end

function M.stop(keepTraffic, recycle)
  if not recycle then guide.release() end
  if S then
    S = nil
    if not recycle then winter.disable() end
    clearScreen()
    guihooks.trigger('EarthRaidHud', { phase = 'idle' })
    cleanupProps(keepTraffic, recycle)
    safeCar()
    pcall(function() core_jobsystem.create(function(job) job.sleep(1.2) safeCar() end, 1) end)
  elseif not recycle then
    props.flushSpare()
    -- (23-nov, el usuario: «al terminar el rally sigue habiendo nieve»): sin tramo en curso (fin del rally, tramo ya
    -- cerrado) la nieve tampoco se queda; solo se aplica mientras hay un tramo de nieve montado
    winter.disable()
  end
end

-- ---- notas de copiloto --------------------------------------------------------------------------------------------------

-- La app de notas del juego es una cola: cada nota se retira (clearOneVisualPacenote) al pasar su curva, y entonces
-- avanza la siguiente
local function sendVisual(list)
  if not S.opt.visualNotes then return end
  S.noteSerial = S.noteSerial + 1
  local last = list[#list].nt
  S.shown[#S.shown + 1] = { serial = S.noteSerial, clearAt = (last.endAt or last.at or 0) + M.CLEAR_AFTER_M }
  local vis = {}
  for i, it in ipairs(list) do
    vis[#vis + 1] = pacenotes.visual(it.nt, ('er%d_%d'):format(S.noteSerial, i), tostring(S.noteSerial), it.dist, i > 1)
  end
  pcall(function() guihooks.trigger('showVisualPacenote2', { serialNo = S.noteSerial, visualPacenotes = vis }) end)
end

local function callAt(idx)
  local nt = S.notes[idx]
  local words = pacenotes.words(nt)
  if nt.overCrest then words[#words + 1] = 'over_crest' end
  local list = { { nt = nt } }
  local nx = S.notes[idx + 1]
  local used = 1
  if nx and nx.at - nt.endAt < M.INTO_M then
    words[#words + 1] = 'into'
    for _, w in ipairs(pacenotes.words(nx)) do words[#words + 1] = w end
    list[2] = { nt = nx, dist = nx.dist }
    used = 2
  else
    list[1].dist = nt.dist
    local dw = pacenotes.distWords(nt.dist or 0)
    if dw then words[#words + 1] = dw end
  end
  local last = S.notes[idx + used - 1]
  if last.overFinish then words[#words + 1] = 'over_finish' end
  if S.opt.voice then audio.say(words) end
  sendVisual(list)
  S.lastNote = pacenotes.short(nt) .. (used == 2 and (' > ' .. pacenotes.short(nx)) or '')
  return used
end

function M.clearPassed()
  local i = 1
  while S.shown[i] do
    local sh = S.shown[i]
    if S.along >= sh.clearAt then
      pcall(function() guihooks.trigger('clearOneVisualPacenote', sh.serial) end)
      table.remove(S.shown, i)
    else
      i = i + 1
    end
  end
end

-- Las curvas que vienen, medidas otra vez sobre la carretera real del juego (el KMZ recorta y suaviza las curvas: se
-- cantaban más abiertas de lo que son). Solo con la carretera ya cargada, entre REFINE_MIN_M y REFINE_MAX_M por delante.
M.REFINE_MIN_M, M.REFINE_MAX_M, M.REFINE_STEP_M = 40, 420, 4
M.refined = 0
function M.refineNotes()
  local t = S and S.track
  if not (t and S.notes) then return end
  local done = 0
  for k = S.noteIdx, #S.notes do
    local nt = S.notes[k]
    local ahead = nt.at - S.along
    if ahead > M.REFINE_MAX_M then break end
    if nt.kind == 'corner' and not nt.refined and not nt.said and ahead > M.REFINE_MIN_M then
      local pts, ok, tot = {}, 0, 0
      local a0, a1 = math.max(0, nt.at - 20), math.min(t.total, (nt.endAt or nt.at) + 20)
      for d = a0, a1, M.REFINE_STEP_M do
        tot = tot + 1
        local x, y = geo.at(t, d)
        local dx, dy = geo.dirAt(t, d)
        local la, lo = geo.toGeo(t, x, y)
        local cl, co = dressing.snap(la, lo, dx, dy)
        if cl then
          local px, py = geo.toLocal(t, cl, co)
          local last = pts[#pts]
          if not last or (px - last[1]) ^ 2 + (py - last[2]) ^ 2 > 1 then pts[#pts + 1] = { px, py } ok = ok + 1 end
        end
      end
      if tot > 0 and ok >= tot * 0.7 then
        local before = nt.grade
        if pacenotes.refine(nt, pts, M.REFINE_STEP_M) then
          M.refined = M.refined + 1
          log('I', TAG, ('note at %d m: %s -> %s (r %.0f m)'):format(nt.at, tostring(before), tostring(nt.grade), nt.radius))
        end
        nt.refined = true
      end
      done = done + 1
      if done >= 3 then break end
    end
  end
end

function M.callNotes(speed, force)
  local nt = S.notes[S.noteIdx]
  if not nt then return end
  local ahead = math.max(M.CALL_MIN_M, (speed or 0) * ((S.opt and S.opt.notesLeadS) or M.CALL_S))
  if force or nt.at - S.along <= ahead then
    S.noteIdx = S.noteIdx + callAt(S.noteIdx)
  end
end

-- crestas, saltos y badenes por delante: se añaden a las notas que quedan
local function scanRelief()
  local found = relief.scan(S.track, S.along + 120)
  local changed = false
  for _, r in ipairs(found) do
    local key = math.floor(r.at / 40)
    if not S.reliefSeen[key] then
      S.reliefSeen[key] = true
      -- en una curva que aún no se ha dicho: "over crest"
      local merged = false
      for k = S.noteIdx, #S.notes do
        local nt = S.notes[k]
        if nt.kind == 'corner' and r.at >= nt.at - 30 and r.at <= nt.endAt + 10 and (r.mod == 'crest' or r.mod == 'bigCrest') then
          nt.overCrest, merged = true, true
          break
        end
      end
      if not merged then
        local insertAt = #S.notes + 1
        for k = S.noteIdx, #S.notes do if S.notes[k].at > r.at then insertAt = k break end end
        table.insert(S.notes, math.max(S.noteIdx, insertAt), { kind = 'mod', mod = r.mod, at = r.at, endAt = r.at + 10 })
        changed = true
      end
    end
  end
  if changed then pacenotes.relink(S.notes, S.track.total) end
end

-- ---- HUD ----------------------------------------------------------------------------------------------------------------

local function hud()
  local t = S.track
  guihooks.trigger('EarthRaidHud', { phase = S.phase, title = S.title, runs = S.runs, eventName = S.eventName,
    stageNumber = S.stageNumber, stageCount = S.stageCount, surface = S.surface,
    totalM = t.total, along = S.along, splitM = S.splitAt, splitTime = S.splitTime, time = S.time, penalty = S.penalty,
    penalties = S.penalties, distM = S.distM, staged = S.staged, stagingLeft = S.stagingLeft, countdown = S.countdown,
    best = S.best, newBest = S.newBest, lang = S.lang, note = S.lastNote, doneLeft = S.doneLeft, overLine = S.overLine, tcTime = S.tcTime, startAt = S.startAt,
    session = S.session ~= nil, lap = S.lap, laps = S.laps, lapTimes = S.lapTimes })
end

-- Metros del morro del coche a la línea de salida (positivo: antes de la línea): con su caja orientada si se puede
local function noseToLine(t, ahead)
  local a, veh = api(), getPlayerVehicle(0)
  local ok, nose = pcall(function()
    -- la línea pintada (anclada al eje de la carretera), no el punto del KMZ
    local L = S.line
    local x0, y0 = a.toGame(L.lat, L.lon, 0)
    local k = math.cos(math.rad(L.lat)) * 111195
    local x1, y1 = a.toGame(L.lat + L.dy * 10 / 111195, L.lon + L.dx * 10 / k, 0)
    local dx, dy = x1 - x0, y1 - y0
    local l = math.sqrt(dx * dx + dy * dy)
    if l < 1 then return nil end
    dx, dy = dx / l, dy / l
    local box = veh:getSpawnWorldOOBB()
    local front = -1e9
    for i = 0, 7 do
      local p = box:getPoint(i)
      front = math.max(front, (p.x - x0) * dx + (p.y - y0) * dy)
    end
    return -front
  end)
  if ok and nose then return nose end
  return -(ahead + M.CAR_HALF_M)
end

-- ---- precarga del mapa por delante ---------------------------------------------------------------------------------------
-- BeamNG.Earth guarda en disco lo que descarga (relieve, imágenes, datos del mapa) y tiene una orden para traer un
-- sitio por adelantado (core.preloadPlace: la que usa su mapa antes de un viaje). Aquí se le pide el tramo por delante
-- del coche, un punto cada PRELOAD_STEP_M hasta PRELOAD_AHEAD_M, de uno en uno: así al llegar ya está en la caché y no
-- hay que esperar a la descarga mientras se conduce (19-nov, el usuario: "¿se está precacheando el mapa?").
-- No es de la API estable de complementos: si no existe, no se hace nada. MARK:preload-v1
M.PRELOAD_STEP_M = 1200
M.PRELOAD_AHEAD_M = 6000
M.PRELOAD_EVERY_S = 1.0
local function preloadAhead(dt)
  if not (S and S.track) then return end
  S.preT = (S.preT or 0) + dt
  if S.preT < M.PRELOAD_EVERY_S then return end
  S.preT = 0
  local t = S.track
  S.preNext = S.preNext or 0
  if S.preNext > t.total or S.preNext > (S.along or 0) + M.PRELOAD_AHEAD_M then return end
  local core = rawget(_G, 'beamngEarth_core')
  if not (core and type(core.preloadPlace) == 'function') then S.preNext = math.huge return end
  local x, y = geo.at(t, math.min(t.total, S.preNext))
  local la, lo = geo.toGeo(t, x, y)
  local ok, sent = pcall(core.preloadPlace, la, lo)
  if ok and sent then
    S.preSent = (S.preSent or 0) + 1
    S.preNext = math.max(S.preNext, (S.along or 0)) + M.PRELOAD_STEP_M
  end
end

-- ---- cada fotograma -----------------------------------------------------------------------------------------------------

local regroundT = 0
local function reground(dt)
  regroundT = regroundT + dt
  if regroundT < M.REGROUND_S then return end
  regroundT = 0
  local a = api()
  local lat, lon
  if a and a.position then lat, lon = a.position() end
  if lat then
    local ok, n, trees = pcall(props.reground, lat, lon, M.REGROUND_M, dressing.loading())
    if ok and trees and trees > 0 then startclock.ensure() end
    -- y nada en la calzada: lo que se colocó sin la carretera cargada se repasa al acercarse
    local okR, err = pcall(dressing.recheck, lat, lon)
    if not okR then log('W', TAG, 'recheck: ' .. tostring(err)) end
  end
end

-- el punto del STOP (tras la meta, por la carretera que sigue o en la prolongación del trazado)
function M.stopPoint(t)
  local s = dressing.stopAt(t)
  if t.after then return geo.toGeo(t.after, geo.at(t.after, math.min(s, t.after.total))) end
  local x, y = geo.at(t, t.total)
  local dx, dy = geo.dirAt(t, t.total)
  return geo.toGeo(t, x + dx * s, y + dy * s)
end

-- metros recorridos tras la meta
local function pastFinish(t, lat, lon)
  if t.after then
    local ax, ay = geo.toLocal(t.after, lat, lon)
    local along, _, i = geo.project(t.after, ax, ay, S.afterHint or 1, 10, 200)
    S.afterHint = i
    return along
  end
  local x, y = geo.toLocal(t, lat, lon)
  local fx, fy = t.pts[#t.pts][1], t.pts[#t.pts][2]
  local fdx, fdy = geo.dirAt(t, t.total)
  return (x - fx) * fdx + (y - fy) * fdy
end

-- los objetos nuevos chocan cuando el juego rehace la colisión estática
function M.collision() pcall(function() be:reloadStaticCollision(false) end) end

M.DRESS_AHEAD_M = 1500
M.DRESS_S = 0.25          -- un trabajo de montaje cada tanto (antes todos de golpe cada segundo)

M.COLLISION_EVERY_S = 2
local collT = 0
M.SPARE_KEEP_M = 40       -- repuesto a más de esto del nuevo trazado: se borra al empezar
M.SPARE_DROP_M = 150      -- y el de alrededor del coche, cuando su zona ya está montada
function M.update(dtSim, dtReal)
  clock = clock + (dtReal or dtSim)
  -- los objetos encolados, poco a poco; la colisión se rehace una vez cuando ya están todos (no tras cada tanda)
  guide.tick(dtReal or dtSim)
  winter.update(dtReal or dtSim)
  pcall(preloadAhead, dtReal or dtSim or 0)
  -- carteles, conos y cintas con física cerca del coche
  if props.count() > 0 then
    local v = be:getPlayerVehicle(0)
    if v then
      local p = v:getPosition()
      phys.quiet = S ~= nil and (S.phase == 'countdown' or S.phase == 'running' or (S.phase == 'staging' and (S.stagingLeft or 99) < 8))
      local okP, errP = pcall(phys.update, dtReal or dtSim or 0, p.x, p.y, props.all(), require('earthRaid/loader').active())
      if not okP then log('W', TAG, 'phys: ' .. tostring(errP)) end
    end
  end
  local left = props.pump()
  collT = collT + (dtReal or dtSim or 0)
  if left == 0 and props.collisionDirty and collT >= M.COLLISION_EVERY_S then
    props.collisionDirty, collT = false, 0
    M.collision()
  end
  if (S or post) and props.count() > 0 then reground(dtReal or dtSim or 0) end
  if S and not M.jobsHeld and dressing.pendingJobs() > 0 then
    S.dressT = (S.dressT or 0) + (dtReal or dtSim or 0)
    if S.dressT >= M.DRESS_S then
      S.dressT = 0
      local a = api()
      local plat, plon
      if a and a.position then plat, plon = a.position() end
      local n = plat and dressing.runJobsNear(plat, plon, require('earthRaid/loader').active() and 4 or 1) or 0
      -- el repuesto de esta zona que no se ha reutilizado, fuera (ya está montada)
      if plat and props.spareCount() > 0 and dressing.pendingJobsNear(plat, plon) == 0 then
        local k = math.cos(math.rad(plat))
        props.flushSpare(function(it)
          return ((it.lon - plon) * 111195 * k) ^ 2 + ((it.lat - plat) * 111195) ^ 2 > M.SPARE_DROP_M ^ 2
        end)
      end
      -- la línea y el control se reajustan al eje de la carretera mientras no se haya salido
      if S.phase == 'tc' or S.phase == 'approach' or S.phase == 'staging' or S.phase == 'hold' then M.refreshLine() end
      -- un semáforo nuevo (el de meta): que el reloj del juego lo encuentre; objetos nuevos: colisión
      if n > 0 then startclock.ensure() end
    end
  end
  -- tras terminar: el montaje se retira al alejarse o pasado un tiempo
  if post and not S then
    local a = api()
    local lat, lon
    if a and a.position then lat, lon = a.position() end
    local far = false
    if lat and post.lat then
      local ex = (lon - post.lon) * 111195 * math.cos(math.rad(lat))
      local ny = (lat - post.lat) * 111195
      far = math.sqrt(ex * ex + ny * ny) > M.CLEANUP_M
    end
    if far or clock - post.at > M.CLEANUP_S then cleanupProps(false, post.recycle) end
    return
  end
  if not S then return end
  audio.update(dtReal or dtSim)
  exclusionUpdate(dtReal or dtSim)
  hideUpdate(dtReal or dtSim)
  -- la hora del reloj: la del ordenador (con ella se fija la hora de salida en el TC), suave entre segundos
  S.wall = (S.wall or 0) + dtSim
  local osNow = geo.dayClock()
  local drift = ((osNow - S.wall + 43200) % 86400) - 43200
  if math.abs(drift) > 1.2 then S.wall = osNow elseif drift > 0.5 then S.wall = S.wall + 0.05 end
  local code = (S.phase == 'running' or S.phase == 'toStop') and 'G' or (S.phase == 'countdown' and S.countdown <= 5) and 'A' or 'R'
  -- segundos hasta la salida, en el reloj: el minuto de espera en la línea y la cuenta atrás (como el del juego)
  local left
  if S.phase == 'countdown' then left = math.max(0, S.countdown)
  elseif S.phase == 'staging' then left = math.max(0.01, S.stagingLeft or 0)
  elseif S.phase == 'approach' and S.startAt then left = math.max(0.01, ((S.startAt - S.wall + 43200) % 86400) - 43200)
  elseif S.phase == 'running' or S.phase == 'toStop' then left = 0 end
  startclock.feed(S.phase == 'countdown' and 'countdown' or ((S.phase == 'running' or S.phase == 'toStop') and 'stageActive' or 'vehicleProximity'),
    S.wall, left)
  startclock.update(dtReal or dtSim, S.phase == 'countdown' and not S.circuitMode, code)

  local a = api()
  if not (a and a.ready and a.ready()) then return end
  S.closureTimer = (S.closureTimer or 0) + dtSim
  if S.opt.closures and S.closureTimer > M.CLOSURES_S and S.phase ~= 'toStop' and S.phase ~= 'done' then
    S.closureTimer = 0
    pcall(dressing.closures, S.track, S.along - 100, S.along + 2000)
    pcall(dressing.pumpMedic)
  end
  if S.phase == 'running' and not S.circuitMode and S.along then
    pcall(guide.watch, S.track, S.along, dtReal or dtSim)
  end
  -- piloto de pruebas (dbg.pilot): solo si se ha cargado el modo de pruebas y está en marcha
  do
    local dg = package.loaded['earthRaid/dbg']
    if dg and dg.tick then pcall(dg.tick, dtReal or dtSim) end
  end
  -- caminos generados donde el mapa no tiene camino (por delante del coche, en cualquier fase)
  if not S.circuitMode then pcall(pathgen.update, S.track, S.along or 0, dtReal or dtSim) end
  local p = a.pose()
  if not p or p.camera then return end
  local t = S.track
  local x, y = geo.toLocal(t, p.lat, p.lon)
  local speed = p.speed or 0
  local sx, sy = t.pts[1][1], t.pts[1][2]
  local dx, dy = geo.dirAt(t, 0)
  local ahead = (x - sx) * dx + (y - sy) * dy
  local lat0 = math.abs((x - sx) * dy - (y - sy) * dx)
  local nose = (S.phase == 'staging' or S.phase == 'countdown' or S.phase == 'approach') and noseToLine(t, ahead) or 0

  if S.phase == 'hold' then
    return
  elseif S.phase == 'grid' then
    S.distM = 0
  elseif S.phase == 'tc' then
    -- al control horario y parado en su punto: fichado; la salida, al siguiente minuto entero con 35 s de margen
    S.distM = math.sqrt((x - S.tcX) ^ 2 + (y - S.tcY) ^ 2)
    local atStart = math.sqrt((x - sx) ^ 2 + (y - sy) ^ 2) < 15
    if (S.distM < M.TC_ZONE_M and speed < M.STOP_MS) or atStart then
      S.tcHold = S.tcHold + dtSim
      if S.tcHold >= 0.5 or atStart then
        local now = geo.dayClock()
        S.tcTime = now
        S.startAt = math.ceil((now + M.TC_MARGIN_S) / 60) * 60
        S.stagingInit = S.startAt - now
        S.phase = 'approach'
        -- del TC a la línea de salida, con la línea azul del GPS del juego
        guide.clear()
        guide.toStart(t, (S.title or '') .. ' - ' .. (spanishUI() and 'Salida' or 'Start'))
        log('I', TAG, ('TC %s checked in, start at +%d s'):format(S.stageId, S.stagingInit))
      end
    else
      S.tcHold = 0
    end
  elseif S.phase == 'approach' then
    S.distM = math.sqrt((x - sx) ^ 2 + (y - sy) ^ 2)
    if S.distM < M.NEAR_M then
      -- lo que falta para la hora de salida fijada en el TC (no lo que faltaba al fichar)
      local left = S.startAt and (((S.startAt - (S.wall or 0) + 43200) % 86400) - 43200)
      S.phase, S.stagingLeft = 'staging', (left and left > M.COUNTDOWN_S + 1) and left or S.stagingInit or M.STAGING_S
      S.stagingInit = nil
      -- una sola hora de salida para tarjeta, «Saltar reloj» y reloj de pista: startAt contra el reloj (calcado al juego)
      S.startAt = ((S.wall or 0) + S.stagingLeft) % 86400
      guide.clear()
    end
  elseif S.phase == 'staging' then
    -- distancia del morro a la línea; pasado de ella no vale (hay que dar marcha atrás), como en el juego
    S.overLine = nose < -M.STAGED_OVER_M
    S.distM = S.overLine and nose or math.max(0, nose)   -- pasado de la línea: negativo (BACK)
    S.staged = not S.overLine and nose <= M.STAGED_MAX_M and lat0 < 6 and speed < M.STOP_MS
    S.stagingLeft = S.startAt and (((S.startAt - (S.wall or 0) + 43200) % 86400) - 43200) or (S.stagingLeft - dtSim)
    if S.staged and S.opt.voice then
      if not S.saidWarn[30] and S.stagingLeft <= 30 then S.saidWarn[30] = true audio.say({ 'system_warningSeconds30' }) end
      if not S.saidWarn[15] and S.stagingLeft <= 15 then S.saidWarn[15] = true audio.say({ 'system_warningSeconds15' }) end
    end
    if S.stagingLeft <= M.COUNTDOWN_S and S.staged then
      S.phase, S.countdown, S.noseAtArm, S.saidCount = 'countdown', M.COUNTDOWN_S, nose, {}
      -- la ruta del GPS y la línea verde se arman ya, en la cuenta atrás: el planificador tarda en tenerlas y a la salida
      -- (GO) la línea verde no estaba (20-nov)
      guide.along(t, (S.eventName or '') .. ' - ' .. (S.title or ''), S.notes)
      guide.racingLine(S.opt.racingLine)
      S.lineArmed = true
      audio.clear()
      -- «preparados»: solo si es un aviso corto. En algún voicepack grabado (Xpectro99: 4,3 s) esa grabación ya trae
      -- su propia cuenta atrás, que sonaba a destiempo y se cortaba al llegar la de verdad (19-nov)
      local preLen = audio.length('system_precountdown')
      if S.opt.voice and preLen and preLen <= M.PRECOUNT_MAX_S then audio.say({ 'system_precountdown' }) end
    elseif S.stagingLeft <= M.COUNTDOWN_S then
      -- sin colocar a -10 s (rallyLoopManager:rescheduleNextSSStart + rallySuperCountdown): el juego pasa la salida a la
      -- siguiente franja de 1 minuto = hora de salida + 60 s, sin penalizar (24-nov, el usuario: "el reloj se reiniciaba en 60 s")
      S.startAt = ((S.startAt or ((S.wall or 0) + S.stagingLeft)) + M.RESCHEDULE_S) % 86400
      S.stagingLeft, S.saidWarn = S.stagingLeft + M.RESCHEDULE_S, {}
      if S.opt.voice then audio.say({ 'system_warningSeconds30' }) end
    elseif math.sqrt((x - sx) ^ 2 + (y - sy) ^ 2) > M.NEAR_M * 3 then
      S.phase = 'approach'
    end
  elseif S.phase == 'countdown' then
    S.distM = math.max(0, nose)
    S.noseAtArm = S.noseAtArm or nose
    S.countdown = S.countdown - dtSim
    local c = math.ceil(S.countdown)
    if S.circuitMode then
      if c >= 1 and c <= 3 and not S.saidCount[c] then S.saidCount[c] = true beep(false) end
    elseif S.opt.voice and c >= 1 and c <= 5 and not S.saidCount[c] then S.saidCount[c] = true audio.say({ 'system_countdown' .. c }, true) end
    local function go(falseStart)
      S.phase, S.time, S.hint = 'running', 0, 1
      pcall(props.releasePark)   -- el tramo empieza: el parque de asistencia fuera (memoria)
      if falseStart and S.opt.falseStart then
        penalise('falseStart', M.FALSE_START_S)
        if S.circuitMode then flash(spanishUI() and 'Salida en falso' or 'False start', 3, false)
        elseif S.opt.voice then audio.say({ 'system_falseStart' }, true) end
      elseif S.circuitMode then
        beep(true)
      elseif S.opt.voice then
        audio.say({ 'system_countdowngo' }, true)
      end
      if not S.lineArmed then
        guide.along(t, (S.eventName or '') .. ' - ' .. (S.title or ''), S.notes)
        guide.racingLine(S.opt.racingLine)
      end
      if not S.circuitMode then M.callNotes(0, true) end
    end
    if nose < S.noseAtArm - M.FALSE_START_M and S.countdown > 0 then go(true)
    elseif S.countdown <= 0 then go(false) end
  elseif S.phase == 'running' then
    S.time = S.time + dtSim
    local along, lateral, i = geo.project(t, x, y, S.hint)
    if along >= S.along - 30 then S.along, S.hint = math.max(S.along, along), i end
    -- entre la meta y la salida de un circuito (vuelta nueva): sin notas hasta volver al trazado
    if S.lapGap and lateral < 25 then S.lapGap = nil end
    if S.splitAt and not S.splitTime and S.along >= S.splitAt then S.splitTime = S.time end
    S.reliefTimer = S.reliefTimer + dtSim
    if S.reliefTimer > M.RELIEF_S then S.reliefTimer = 0 pcall(scanRelief) end
    S.refineT = (S.refineT or 0) + dtSim
    if S.refineT > 0.7 then
      S.refineT = 0
      pcall(M.refineNotes)
      if S.opt.props ~= false then pcall(dressing.cheer, t, S.along) end
    end
    if not S.lapGap and not S.circuitMode then M.callNotes(speed) end
    M.clearPassed()
    -- meta lanzada
    local fx, fy = t.pts[#t.pts][1], t.pts[#t.pts][2]
    local fdx, fdy = geo.dirAt(t, t.total)
    local past = (x - fx) * fdx + (y - fy) * fdy
    local side = math.abs((x - fx) * fdy - (y - fy) * fdx)
    if S.along > t.total * 0.9 and past >= 0 and side < 15 and S.circuit and S.lap < S.laps then
      -- circuito: paso por meta, vuelta nueva (el crono sigue)
      S.lapTimes[#S.lapTimes + 1] = S.time - (S.lapStart or 0)
      S.lapStart = S.time
      S.lap = S.lap + 1
      S.along, S.hint, S.noteIdx, S.lapGap = 0, 1, 1, true
      for _, sh in ipairs(S.shown) do pcall(function() guihooks.trigger('clearOneVisualPacenote', sh.serial) end) end
      S.shown = {}
      audio.clear()
      flash((spanishUI() and 'Vuelta ' or 'Lap ') .. S.lap .. ' / ' .. S.laps, 2.5, false)
      log('I', TAG, ('stage %s: lap %d / %d (%.1f s)'):format(S.stageId, S.lap, S.laps, S.lapTimes[#S.lapTimes]))
    elseif S.along > t.total * 0.9 and past >= 0 and side < 15 then
      S.along = t.total
      if S.circuit then S.lapTimes[#S.lapTimes + 1] = S.time - (S.lapStart or 0) end
      S.phase = 'toStop'
      -- la línea de carrera solo dentro del tramo: en la meta vuelve el GPS normal
      guide.clear()
      S.newBest = saveResult()
      S.best = M.best(S.eventId, resultId())
      if S.session and S.session.onFinish then
        pcall(S.session.onFinish, { time = S.time, penalty = S.penalty, penalties = S.penalties, split = S.splitTime })
      end
      audio.clear()
      pcall(function() guihooks.trigger('clearAllVisualPacenotes') end)
      -- el GPS al STOP, donde hay que parar: otra vez la línea azul
      if not S.circuitMode then guide.liaison(S.opt.hardcore == true) end
      local a2 = not S.circuitMode and api() or nil
      local slat, slon = M.stopPoint(t)
      if a2 then
        -- línea propia hasta el STOP (el GPS de Earth, sin carretera tras la meta, daba vueltas)
        local gp, sa = {}, dressing.stopAt(t)
        for f = 8, sa, 8 do
          local la, lo = dressing.lineAt(t, t.total, f)
          if la then gp[#gp + 1] = { la, lo } end
        end
        if slat then gp[#gp + 1] = { slat, slon } end
        local okL, doneL = pcall(guide.toStop, gp)
        if not (okL and doneL) and a2.gpsSet then pcall(a2.gpsSet, slat, slon, 'STOP') end
      end
      log('I', TAG, ('stage %s finished: %.1f s + %d s'):format(S.stageId, S.time, S.penalty))
      -- circuito: bandera y resultado, sin control STOP
      if S.circuitMode then
        S.phase, S.doneLeft = 'done', M.DONE_ACCEPT_S
        beep(true)
        flash(spanishUI() and 'META' or 'FINISH', 3, true)
      end
    end
  elseif S.phase == 'toStop' then
    pcall(guide.watchStop, dtReal or dtSim)
    local past = pastFinish(t, p.lat, p.lon)
    local stopAt = dressing.stopAt(t)
    S.distM = math.max(0, stopAt - past)
    if (math.abs(S.distM) < 12 and speed < M.STOP_MS) or past > stopAt + 80 then
      -- el resultado: en un rally, unos segundos; en un tramo suelto, hasta aceptarlo (Mayús+E) o DONE_ACCEPT_S
      S.phase, S.doneLeft = 'done', S.session and M.DONE_SHOW_S or M.DONE_ACCEPT_S
      guide.clear()
      if S.session and S.session.onStop then pcall(S.session.onStop) end
    end
  elseif S.phase == 'done' then
    S.doneLeft = S.doneLeft - dtReal
    if S.doneLeft <= 0 then
      -- se acabó: pantalla limpia; el montaje sigue hasta alejarse. Fuera de un rally, el mod Racing Line vuelve a
      -- seguir el GPS como siempre
      if not S.session then guide.release() end
      local flat, flon = geo.toGeo(t, t.pts[#t.pts][1], t.pts[#t.pts][2])
      -- en un rally, lo de este tramo puede servir al siguiente (se recicla al limpiar)
      post = { at = clock, lat = flat, lon = flon, recycle = S.session ~= nil }
      local accepted = S.accepted
      local keepGps = S.session ~= nil
      S = nil
      -- en un rally el GPS del enlace al siguiente control ya está puesto: no se borra (19-nov: tras la meta del
      -- segundo tramo no salía la línea azul)
      if keepGps then audio.clear() pcall(function() guihooks.trigger('clearAllVisualPacenotes') end) else clearScreen() end
      guihooks.trigger('EarthRaidHud', { phase = 'idle' })
      -- aceptado: el montaje se retira ya (sin esperar a alejarse)
      if accepted then post = nil cleanupProps(false, false) end
      return
    end
  end

  -- (las líneas de salida, meta y STOP están pintadas en el suelo: dressing.lua)

  hudTimer = hudTimer + dtSim
  if hudTimer >= M.HUD_S then hudTimer = 0 hud() end
end

-- Mayús+E: con el coche colocado, salta la espera y arranca la cuenta atrás
function M.skipWait()
  if S and S.phase == 'tc' then
    S.phase, S.stagingInit = 'approach', nil
    guide.clear()
    return true
  end
  if S and S.phase == 'staging' and S.staged then
    S.stagingLeft = math.min(S.stagingLeft, M.COUNTDOWN_S)
    S.startAt = ((S.wall or 0) + S.stagingLeft) % 86400
    return true
  end
  -- en el resultado: aceptar (se cierra y se retira el montaje del tramo)
  if S and S.phase == 'done' and not S.session then
    S.accepted, S.doneLeft = true, 0
    return true
  end
  return false
end

-- R en un tramo: +5 s, como en el juego
function M.onReset(kind)
  -- reglas del juego (recoveryClockAdvance): en un tramo, recuperar +5 s y volcar 0 s
  if S and S.phase == 'running' and S.opt.recoveryPenalty and kind ~= 'flip' then penalise('recovery', M.RECOVERY_S) end
end

function M.sendHud() if S then hud() else guihooks.trigger('EarthRaidHud', { phase = 'idle' }) end end
function M.setLang(l) if S then S.lang = l end end
function M.onRebased() props.replace() M.refreshLine() end

return M

-- ███ BLOQUEADO (23-nov, orden del usuario): funciona y está aprobado. NO modificar sin su permiso expreso. Ver LOCKED.md ███
-- Raid.Earth: la carga al iniciar un tramo o un rally (como la pantalla de carga del juego).
-- Al darle a Iniciar: el coche se congela, se lleva a la zona de salida, se espera a que BeamNG.Earth cargue el mundo
-- y las carreteras de allí, se monta lo de esa zona (TC, salida, box) y se coloca todo; solo entonces se suelta el coche
-- en la calzada, M.BEFORE_TC_M antes del control horario y mirando hacia él (o en el box del rally). Así los objetos no
-- se ponen antes de que exista la carretera (se quedaban mal) y no hay tirones mientras se conduce.
local M = {}
local TAG = 'earthRaid'
local props = require('earthRaid/props')

M.BEFORE_TC_M = 100
-- (depende del PC y de la conexión del jugador: las carreteras pueden tardar; con el juego en pausa por la carga de
-- BeamNG.Earth el tiempo no corre)
M.TIMEOUT = { tp = 90, roads = 75, dress = 40, settle = 2 }
M.ROAD_OK_M = 15             -- una carretera a menos de esto de cada punto: la zona está cargada
M.PUMP_MS = 12               -- presupuesto para crear objetos por fotograma durante la carga
-- La pantalla primero (19-nov, el usuario: "teleporta el coche antes de cargar y se ve raro"): nada se mueve ni se
-- quita hasta que la pantalla de carga tapa el juego. MARK:cover-v1
M.COVER_S = 0.4              -- la pantalla aparece en 0,2 s; con margen, a esto ya es opaca
M.LEAVE_S = 0.8              -- abandonar: lo que se queda la pantalla tras limpiar el tramo
M.TP_RETRY_S = 25            -- BeamNG.Earth rechaza el viaje mientras carga el suelo: se reintenta hasta esto
-- (20-nov, Trans Sierra Nevada: el coche se colocó en un aparcamiento a 492 m, en un bloque de terreno sin cargar, y
-- cayó al vacío.) Dos garantías: 1) lo que se monta lejos del coche se alcanza con un viaje de BeamNG.Earth (carga el
-- bloque y deja el coche en el suelo) antes de montarlo y colocar; 2) antes de soltar el coche se comprueba que está
-- sobre suelo firme, y si no, se viaja de nuevo y se prueba otra colocación (hasta M.GROUND_TRIES veces).
M.GROUND_WAIT_S = 5          -- lo que se espera, tras colocar, a que el coche quede sobre suelo firme
M.GROUND_TRIES = 3
M.PLACE_WAIT_S = 6           -- la colocación puede decir «aún no hay suelo fiable»: se reintenta hasta esto
M.HOP_ROADS_S = 25           -- tras un viaje intermedio, lo que se espera a que haya carretera en el destino

local L                      -- la carga en curso
local shownAt                -- desde cuándo está puesta la pantalla (os.clock), o nil
local function api() return rawget(_G, 'beamngEarth_api') end

M.STEPS = { 'tp', 'roads', 'dress', 'place', 'settle' }
local function send()
  if not L then shownAt = nil guihooks.trigger('EarthRaidLoading', { on = false }) return end
  shownAt = shownAt or os.clock()
  if L.only then
    -- solo tapar (abandonar, o el principio de un reinicio): la barra según el tiempo, con su propio texto
    local p = math.floor(math.min(1, L.frac or 0) * 100)
    local ic = {}
    for _, s in ipairs(M.STEPS) do ic[s] = p end
    guihooks.trigger('EarthRaidLoading', { on = true, title = L.title, event = L.event, logo = L.logo, step = 'leave',
      status = L.status, progress = math.min(1, L.frac or 0), lang = L.lang, description = L.description, icons = ic,
      history = {} })
    return
  end
  local idx = 1
  for i, s in ipairs(M.STEPS) do if s == L.step then idx = i end end
  -- cada icono (como la pantalla de carga del juego): 100 lo hecho, el paso en curso según su avance
  local icons = {}
  for i, s in ipairs(M.STEPS) do icons[s] = i < idx and 100 or (i == idx and math.floor(math.min(1, L.frac or 0) * 100) or 0) end
  guihooks.trigger('EarthRaidLoading', { on = true, title = L.title, event = L.event, logo = L.logo, step = L.step,
    progress = math.min(1, (idx - 1 + math.min(1, L.frac or 0)) / #M.STEPS), lang = L.lang, detail = L.detail,
    description = L.description, icons = icons, history = L.hist or {} })
end

-- una línea del historial (las tres últimas se ven bajo la barra)
local function note(es, en)
  L.hist = L.hist or {}
  L.hist[#L.hist + 1] = L.lang == 'es' and es or en
  while #L.hist > 3 do table.remove(L.hist, 1) end
end

local function freeze(on)
  local v = getPlayerVehicle and getPlayerVehicle(0) or be:getPlayerVehicle(0)
  if v then pcall(function() v:queueLuaCommand('controller.setFreeze(' .. (on and 1 or 0) .. ')') end) end
end

-- ¿está el coche sobre suelo firme (no cayendo, con superficie sólida justo debajo)? true | false, motivo
local function standing()
  local v = getPlayerVehicle and getPlayerVehicle(0) or be:getPlayerVehicle(0)
  if not v then return true end
  local p, vel = v:getPosition(), v:getVelocity()
  if p.z < -400 or vel.z < -8 then return false, 'falling' end
  local hz = be:getSurfaceHeightBelow(vec3(p.x, p.y, p.z + 1.5))
  if type(hz) ~= 'number' or hz < -1e5 then return false, 'no ground below' end
  if p.z - hz > 3 then return false, 'in the air' end
  return true
end
M.standing = standing

local function roadNear(lat, lon, r)
  local a = api()
  local x, y = a.toGame(lat, lon, 0)
  if not x then return false end
  local z = core_terrain and core_terrain.getTerrainHeight and core_terrain.getTerrainHeight(vec3(x, y, 0)) or 0
  local n1, _, d = props.nearestRoad(x, y, z, r or M.ROAD_OK_M)
  return n1 ~= nil and d ~= nil and d < (r or M.ROAD_OK_M)
end

-- spec: { title, event, logo, lang, tpLat, tpLon (a dónde llevar primero), near = { {lat, lon}... } (puntos que deben
-- tener carretera; un tercer valor, el radio en m: una asistencia en un aparcamiento puede estar lejos del asfalto), dress = function(dt) -> pendientes (monta; 0 cuando ya está), place = function() (coloca el coche),
-- done = function(), fail = function(err) (el viaje no se pudo hacer) }
-- Primero la pantalla (paso 'cover'); el viaje sale cuando ya tapa el juego. Si ya estaba puesta (un reinicio), al momento.
function M.begin(spec)
  local a = api()
  if not (a and a.teleport) then return false, 'BeamNG.Earth no está cargado' end
  local covered = shownAt ~= nil and (os.clock() - shownAt) >= M.COVER_S
  L = spec
  L.step, L.t, L.frac = 'cover', covered and M.COVER_S or 0, 0
  L.startAt = os.clock()
  freeze(true)
  send()
  log('I', TAG, 'loading: ' .. tostring(spec.title))
  return true
end

-- Solo la pantalla: se pone, y cuando tapa el juego se ejecuta spec.run (quitar el tramo, o reiniciarlo: si run empieza
-- una carga con M.begin, la pantalla sigue con ella sin parpadeo). spec: { title, event, logo, lang, status, run }
function M.cover(spec)
  if L then
    -- ya hay una pantalla puesta: se hace ya, debajo de ella
    if spec.run then pcall(spec.run) end
    return true
  end
  L = spec
  L.only = true
  L.step, L.t, L.frac = 'cover', 0, 0
  send()
  return true
end

local function fail(err)
  local f = L and L.fail
  L = nil
  freeze(false)
  send()
  log('W', TAG, 'loading: travel refused: ' .. tostring(err))
  if f then pcall(f, err) end
end

-- el viaje, ya con la pantalla puesta
local function travel()
  local a = api()
  local ok, err = a.teleport(L.tpLat, L.tpLon, L.title)
  if ok then
    L.step, L.t, L.frac, L.teleported = 'tp', 0, 0, false
    send()
    return
  end
  L.refusedAt = L.refusedAt or L.t
  if L.t - L.refusedAt >= M.TP_RETRY_S then fail(err) else L.retryAt = L.t + 1 end
end

function M.hopped(key) return L ~= nil and L.hopDone ~= nil and L.hopDone[key] == true end
function M.active() return L ~= nil end
function M.covering() return L ~= nil and L.only == true end
function M.roadsOk() return L ~= nil and L.roadsOk == true end
function M.onTeleported() if L then L.teleported = true L.tpT = 0 end end

local function nextStep(s)
  -- lo que deja hecho el paso que acaba
  local ok = pcall(function()
    if L.step == 'tp' then note('Mundo: BeamNG.Earth listo', 'World: BeamNG.Earth ready')
    elseif L.step == 'roads' then
      local ix = props.roadIndex()
      local n = ix and #ix.segs or 0
      note(('Carreteras: se han cargado %d tramos'):format(n), ('Roads: %d segments loaded'):format(n))
    elseif L.step == 'dress' then
      note(('Objetos: se han colocado %d'):format(props.count()), ('Objects: %d placed'):format(props.count()))
    elseif L.step == 'place' then note('Coche: en la calzada, antes del control', 'Car: on the road, before the control') end
  end)
  -- (22-nov) tiempos reales de cada paso, en el registro: ahí se ve qué tarda al cargar o reiniciar
  local nowC = os.clock()
  L.times = L.times or {}
  L.times[#L.times + 1] = ('%s %.1fs'):format(L.step, nowC - (L.stepAt or L.startAt or nowC))
  L.stepAt = nowC
  L.step, L.t, L.frac = s, 0, 0
  send()
end

local function finish(why)
  if not L then return end
  local done, keep = L.done, L.keepFrozen
  if not L.only then
    -- con keepFrozen el coche sigue congelado: quien recibe done (la pantalla de inicio) lo suelta al darle a Iniciar
    if not (keep and done) then freeze(false) end
    -- la cámara detrás del coche, mirando la carretera (tras el teletransporte se queda donde estaba)
    pcall(function() if core_camera and core_camera.resetCamera then core_camera.resetCamera(0) end end)
  end
  local nowC = os.clock()
  local times = (L.times and table.concat(L.times, ', ') or '') .. (L.step and (', ' .. L.step .. ' ' .. ('%.1fs'):format(nowC - (L.stepAt or nowC))) or '')
  log('I', TAG, 'loading finished' .. (why and (' (' .. why .. ')') or '') .. ' [' .. times .. '; total ' .. ('%.1f'):format(nowC - (L.startAt or nowC)) .. 's]')
  L = nil
  -- primero la pantalla de inicio y después se quita la de carga: sin hueco en el que el coche se pueda mover
  if done then pcall(done) end
  send()
end

-- (la pantalla de solo tapar no se cancela: quien la puso está en mitad de su run)
function M.cancel() if L and not L.only then L.done = nil finish('cancelled') end end

function M.update(dt)
  if not L then return end
  -- BeamNG.Earth pausa el juego mientras carga el terreno tras un viaje: ese tiempo no cuenta para los plazos
  if simTimeAuthority and simTimeAuthority.getPause and simTimeAuthority.getPause() and L.step ~= 'tp' and L.step ~= 'cover' then return end
  L.t = L.t + (dt or 0)
  L.sendT = (L.sendT or 0) + (dt or 0)
  if L.sendT >= 0.2 then L.sendT = 0 send() end
  if not L then return end
  local a = api()
  if L.step == 'cover' then
    if L.t < M.COVER_S then return end
    if L.only then
      if L.run then
        local me, run = L, L.run
        L.run = nil
        local okR, errR = pcall(run)
        if not okR then log('W', TAG, 'loading cover: ' .. tostring(errR)) end
        if L ~= me then return end           -- run ha empezado una carga: la pantalla sigue con ella
        L.t = M.COVER_S
      end
      L.frac = (L.t - M.COVER_S) / M.LEAVE_S
      if L.t >= M.COVER_S + M.LEAVE_S then finish('cover') end
    elseif not L.retryAt or L.t >= L.retryAt then
      travel()
    end
    return
  end
  if L.step == 'tp' then
    -- el aviso del teletransporte y el mundo listo (BeamNG.Earth deja el coche en el suelo con algo de retraso)
    if L.teleported then L.tpT = (L.tpT or 0) + dt end
    L.frac = math.min(0.95, L.t / 12)
    if L.teleported and L.tpT > (L.fast and 0.7 or 2) and a.ready and a.ready() then nextStep('roads')
    elseif L.t > M.TIMEOUT.tp then nextStep('roads') end
  elseif L.step == 'roads' then
    local okN, total = 0, #(L.near or {})
    for _, p in ipairs(L.near or {}) do if roadNear(p[1], p[2], p[3]) then okN = okN + 1 end end
    L.frac = total > 0 and okN / total or 1
    if okN == total or L.t > M.TIMEOUT.roads then
      if okN < total then log('W', TAG, ('loading: roads %d/%d after %.0f s'):format(okN, total, L.t)) end
      L.roadsOk = okN == total
      nextStep('dress')
    end
  elseif L.step == 'dress' then
    local left = 0
    -- un viaje intermedio en curso (lo que hay que montar queda lejos del coche): se espera a que llegue
    if L.hop then
      local h = L.hop
      h.t = h.t + (dt or 0)
      if not h.sent then
        local okT = a.teleport(h.lat, h.lon, L.title)
        if okT then h.sent, h.t, L.teleported, L.tpT = true, 0, false, 0
        elseif h.t >= M.TP_RETRY_S then
          log('W', TAG, 'loading: intermediate travel refused')
          L.hopDone[h.key], L.hop, L.t = true, nil, 0
        end
      else
        if L.teleported then L.tpT = (L.tpT or 0) + (dt or 0) end
        local ready = L.teleported and L.tpT > 2 and a.ready and a.ready()
        if ready and (roadNear(h.lat, h.lon, 80) or h.t > M.HOP_ROADS_S) or h.t > M.TIMEOUT.tp + M.HOP_ROADS_S then
          note('Mundo: llegado al parque de asistencia', 'World: arrived at the service park')
          L.hopDone[h.key], L.hop, L.t = true, nil, 0
        end
      end
      L.frac = 0.5
      return
    end
    if L.dress then
      local ok, n, hop = pcall(L.dress, dt)
      left = ok and (n or 0) or 0
      if not ok then log('W', TAG, 'loading dress: ' .. tostring(n)) end
      L.hopDone = L.hopDone or {}
      if ok and type(hop) == 'table' and hop.lat and not L.hopDone[hop.key or 'hop'] then
        L.hop = { lat = hop.lat, lon = hop.lon, key = hop.key or 'hop', t = 0 }
        send()
        return
      end
    end
    L.left0 = math.max(L.left0 or 0, left)
    L.frac = L.left0 > 0 and (1 - left / L.left0) or 1
    if (left == 0 and L.t > 0.5) or L.t > M.TIMEOUT.dress then nextStep('place') end
  elseif L.step == 'place' then
    local placed = true
    if L.place then
      local ok, res = pcall(L.place)
      if not ok then log('W', TAG, 'loading place: ' .. tostring(res)) end
      placed = not ok or res ~= false
    end
    -- «false»: aún no hay suelo fiable donde colocar el coche; se reintenta un rato (si no, la comprobación de después
    -- lo resuelve con un viaje nuevo)
    if placed or L.t > M.PLACE_WAIT_S then
      if not placed then log('W', TAG, 'loading: could not place the car, relying on the ground check') end
      nextStep('settle')
    end
  elseif L.step == 'settle' then
    -- un momento para que el coche se asiente y la colisión de los objetos se rehaga; y la comprobación de suelo firme
    local settleS = L.fast and 1.2 or M.TIMEOUT.settle   -- reinicio: el mundo ya estaba cargado
    L.frac = math.min(1, L.t / settleS)
    if L.t < settleS then return end
    local okS, why = standing()
    L.okT = okS and ((L.okT or 0) + (dt or 0)) or 0
    if L.okT >= 0.6 then finish() return end
    if L.t > M.TIMEOUT.settle + M.GROUND_WAIT_S then
      L.groundTries = (L.groundTries or 0) + 1
      log('W', TAG, ('loading: the car is not on solid ground (%s), attempt %d/%d'):format(tostring(why), L.groundTries, M.GROUND_TRIES))
      if L.groundTries >= M.GROUND_TRIES then
        fail(L.lang == 'es' and 'no se ha podido colocar el coche en suelo firme' or 'could not place the car on solid ground')
        return
      end
      if L.onGroundFail then pcall(L.onGroundFail, L.groundTries) end
      -- otra vez desde el principio: viaje (BeamNG.Earth deja el coche en el suelo), carreteras, montaje y colocación
      L.hopDone, L.hop, L.okT, L.refusedAt, L.retryAt, L.roadsOk, L.left0 = {}, nil, 0, nil, nil, nil, nil
      L.step, L.t, L.frac = 'cover', M.COVER_S, 0     -- (el paso 'cover' ya sabe viajar y reintentar)
    end
  end
end

return M

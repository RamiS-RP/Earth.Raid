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

local L                      -- la carga en curso
local function api() return rawget(_G, 'beamngEarth_api') end

M.STEPS = { 'tp', 'roads', 'dress', 'place', 'settle' }
local function send()
  if not L then guihooks.trigger('EarthRaidLoading', { on = false }) return end
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
-- done = function() }
function M.begin(spec)
  local a = api()
  if not (a and a.teleport) then return false, 'BeamNG.Earth no está cargado' end
  L = spec
  L.step, L.t, L.frac = 'tp', 0, 0
  freeze(true)
  local ok, err = a.teleport(spec.tpLat, spec.tpLon, spec.title)
  if not ok then L = nil freeze(false) send() return false, err end
  L.teleported = false
  send()
  log('I', TAG, 'loading: ' .. tostring(spec.title))
  return true
end

function M.active() return L ~= nil end
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
  L.step, L.t, L.frac = s, 0, 0
  send()
end

local function finish(why)
  if not L then return end
  local done, keep = L.done, L.keepFrozen
  -- con keepFrozen el coche sigue congelado: quien recibe done (la pantalla de inicio) lo suelta al darle a Iniciar
  if not (keep and done) then freeze(false) end
  -- la cámara detrás del coche, mirando la carretera (tras el teletransporte se queda donde estaba)
  pcall(function() if core_camera and core_camera.resetCamera then core_camera.resetCamera(0) end end)
  log('I', TAG, 'loading finished' .. (why and (' (' .. why .. ')') or ''))
  L = nil
  -- primero la pantalla de inicio y después se quita la de carga: sin hueco en el que el coche se pueda mover
  if done then pcall(done) end
  send()
end

function M.cancel() if L then L.done = nil finish('cancelled') end end

function M.update(dt)
  if not L then return end
  -- BeamNG.Earth pausa el juego mientras carga el terreno tras un viaje: ese tiempo no cuenta para los plazos
  if simTimeAuthority and simTimeAuthority.getPause and simTimeAuthority.getPause() and L.step ~= 'tp' then return end
  L.t = L.t + (dt or 0)
  L.sendT = (L.sendT or 0) + (dt or 0)
  if L.sendT >= 0.2 then L.sendT = 0 send() end
  if not L then return end
  local a = api()
  if L.step == 'tp' then
    -- el aviso del teletransporte y el mundo listo (BeamNG.Earth deja el coche en el suelo con algo de retraso)
    if L.teleported then L.tpT = (L.tpT or 0) + dt end
    L.frac = math.min(0.95, L.t / 12)
    if L.teleported and L.tpT > 2 and a.ready and a.ready() then nextStep('roads')
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
    if L.dress then
      local ok, n = pcall(L.dress, dt)
      left = ok and (n or 0) or 0
      if not ok then log('W', TAG, 'loading dress: ' .. tostring(n)) end
    end
    L.left0 = math.max(L.left0 or 0, left)
    L.frac = L.left0 > 0 and (1 - left / L.left0) or 1
    if (left == 0 and L.t > 0.5) or L.t > M.TIMEOUT.dress then nextStep('place') end
  elseif L.step == 'place' then
    if L.place then
      local ok, err = pcall(L.place)
      if not ok then log('W', TAG, 'loading place: ' .. tostring(err)) end
    end
    nextStep('settle')
  elseif L.step == 'settle' then
    -- un momento para que el coche se asiente y la colisión de los objetos se rehaga
    L.frac = L.t / M.TIMEOUT.settle
    if L.t >= M.TIMEOUT.settle then finish() end
  end
end

return M

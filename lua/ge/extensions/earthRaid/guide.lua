-- Earth.Raid: el GPS de BeamNG.Earth para llevar al jugador a la salida y, en el tramo, por el trazado hasta la meta.
local geo = require('earthRaid/geo')
local M = {}
local TAG = 'earthRaid'

M.GPS_POINTS = 11          -- lo que admite gpsSetRoute (10 waypoints + destino)
M.GPS_PAST_M = 30          -- el destino, tras la línea de meta

local function api() return rawget(_G, 'beamngEarth_api') end

function M.toStart(t, name)
  local a = api()
  if not (a and a.gpsSet) then return false end
  local ok = a.gpsSet(t.lat0, t.lon0, name)
  return ok
end

-- por el trazado: puntos repartidos y la meta como destino
function M.along(t, name, notes)
  local a = api()
  if not (a and a.gpsSetRoute) then return false end
  local pts = {}
  M.lastAlong = 0
  M.rollAt, M.rollShort = nil, nil
  for i = 1, M.GPS_POINTS - 1 do
    local along = t.total * i / (M.GPS_POINTS - 1)
    -- (22-nov, el usuario: "el GPS me ha perdido y no sabe llevarme por la ruta"): el planificador toma el camino más corto
    -- entre puntos; un punto a media recta se pega a la calle más cercana, que puede ser una paralela. Cada punto se lleva
    -- al ápice de la curva más cercana (un cruce de decisión) si hay una a menos del 40 % del espaciado
    if notes then
      local reach, best = t.total / (M.GPS_POINTS - 1) * 0.4, nil
      for _, nt in ipairs(notes) do
        if nt.kind == 'corner' and (nt.deg or 0) >= 40 and nt.at and nt.endAt then
          local mid = (nt.at + nt.endAt) / 2
          local d = math.abs(mid - along)
          if d <= reach and (not best or d < best.d) then best = { d = d, at = mid } end
        end
      end
      if best and best.at > (M.lastAlong or 0) + 40 then along = best.at end
    end
    M.lastAlong = along
    -- (la última no está en la meta, sino M.GPS_PAST_M m pasada: el planificador de rutas corta la línea en el nodo de
    -- carretera anterior al destino y la verde terminaba antes de la línea de meta, 21-nov)
    if i < M.GPS_POINTS - 1 then
      local lat, lon = geo.toGeo(t, geo.at(t, along))
      pts[#pts + 1] = { lat = lat, lon = lon }
    end
  end
  do
    local lat, lon
    if t.after and t.after.total > 10 then
      lat, lon = geo.toGeo(t.after, geo.at(t.after, math.min(M.GPS_PAST_M + (t.afterOff or 0), t.after.total)))
    else
      local x, y = geo.at(t, t.total)
      local dx, dy = geo.dirAt(t, t.total)
      lat, lon = geo.toGeo(t, x + dx * M.GPS_PAST_M, y + dy * M.GPS_PAST_M)
    end
    pts[#pts + 1] = { lat = lat, lon = lon, name = name }
  end
  local ok, err = a.gpsSetRoute(pts)
  if not ok then log('W', TAG, 'gps: ' .. tostring(err)) end
  return ok
end

-- NORMA (22-nov, el usuario: "el GPS me indica por una calle que está cortada"): el juego solo tiene cargadas las carreteras
-- de unos 500 m alrededor del coche y el planificador evita las pistas estrechas, así que una ruta puesta en la salida con
-- un punto cada 340 m se iba por otras calles (incluso cortadas). Durante el tramo la ruta se renueva sobre la marcha: un
-- punto cada ROLL_STEP_M sobre el trazado para los próximos ~650 m, y se vuelve a poner cada ROLL_EVERY_M recorridos.
M.ROLL_STEP_M = 15           -- un punto de la línea cada esto
M.ROLL_AHEAD_M = 650         -- la línea llega hasta aquí por delante del coche
M.ROLL_EVERY_M = 250         -- y se rehace cada esto recorrido
M.ROLL_SNAP_M = 12           -- un punto se pega al eje de la carretera del juego si la hay a menos de esto y va paralela
-- La línea del tramo NO sale de ningún planificador de rutas. Ni el GPS de BeamNG.Earth (calcula por la red de carreteras
-- reales, evita las pistas) ni el del juego (su grafo tiene huecos: partes del tramo sin carretera, y entonces da un rodeo
-- de cientos de metros) garantizan seguir el tramo. Se construye con los puntos del PROPIO TRAZADO (pegados al eje de la
-- carretera del juego donde existe) y se entrega ya hecha al dibujante de la línea del juego (core_groundMarkers), que es
-- también de donde la toma el mod Racing Line. Así siempre hay línea y siempre va por el tramo.
local function linePoint(a, t, s)
  -- por un camino generado (pathgen): su eje (en un puente va por el centro del tablero, no por el trazado)
  local pg = package.loaded['earthRaid/pathgen']
  if pg and pg.centerAt then
    local okC, c = pcall(pg.centerAt, t, s)
    if okC and c then return c end
  end
  local x, y = geo.at(t, s)
  local lat, lon = geo.toGeo(t, x, y)
  local gx, gy = a.toGame(lat, lon, 0)
  if not gx then return nil end
  local x2, y2 = geo.at(t, math.min(t.total, s + 5))
  local x1, y1 = geo.at(t, math.max(0, s - 5))
  local dx, dy = x2 - x1, y2 - y1
  local dl = math.sqrt(dx * dx + dy * dy)
  local z = core_terrain and core_terrain.getTerrainHeight and core_terrain.getTerrainHeight(vec3(gx, gy, 0)) or 0
  local ok, p = pcall(function()
    local n1, n2, d = map.findClosestRoad(vec3(gx, gy, z))
    local m = map.getMap()
    if not (n1 and n2 and d and d <= M.ROLL_SNAP_M and m.nodes[n1] and m.nodes[n2]) or dl < 0.1 then return nil end
    local A, B = m.nodes[n1].pos, m.nodes[n2].pos
    local sx, sy = B.x - A.x, B.y - A.y
    local L2 = sx * sx + sy * sy
    if L2 < 0.01 or math.abs(sx * dx + sy * dy) / (math.sqrt(L2) * dl) < 0.8 then return nil end
    local u = math.max(0, math.min(1, ((gx - A.x) * sx + (gy - A.y) * sy) / L2))
    return vec3(A.x + sx * u, A.y + sy * u, A.z + (B.z - A.z) * u)
  end)
  return (ok and p) or vec3(gx, gy, z)
end
M.linePoint = linePoint
function M.roll(t, along)
  if M.rollAt and along < M.rollAt + M.ROLL_EVERY_M then return false end
  local a = api()
  local gm = core_groundMarkers
  local v = be:getPlayerVehicle(0)
  if not (a and a.toGame and gm and gm.setPath and gm.routePlanner and v and map and map.findClosestRoad) then return false end
  local pts = { vec3(v:getPosition()) }
  local function push(p)
    if p and p:squaredDistance(pts[#pts]) > 9 then pts[#pts + 1] = p end
  end
  local s = along + 12
  local last = math.min(t.total, along + M.ROLL_AHEAD_M)
  while s <= last do
    push(linePoint(a, t, s))
    s = s + M.ROLL_STEP_M
  end
  if last >= t.total then
    -- hasta pasada la meta (el control STOP), por la carretera de después si se conoce
    push(linePoint(a, t, t.total))
    local lat, lon
    if t.after and t.after.total > 10 then
      lat, lon = geo.toGeo(t.after, geo.at(t.after, math.min(M.GPS_PAST_M + (t.afterOff or 0), t.after.total)))
    else
      local x, y = geo.at(t, t.total)
      local dx, dy = geo.dirAt(t, t.total)
      lat, lon = geo.toGeo(t, x + dx * M.GPS_PAST_M, y + dy * M.GPS_PAST_M)
    end
    local gx, gy = a.toGame(lat, lon, 0)
    if gx then push(vec3(gx, gy, core_terrain and core_terrain.getTerrainHeight and core_terrain.getTerrainHeight(vec3(gx, gy, 0)) or 0)) end
  end
  M.rollAt, M.rollShort = along, false
  if not M.inject(pts) then return false end
  -- la línea de carrera del mod sigue la ruta del GPS: se le pide de nuevo
  if M.rlRefresh then M.rlRefresh() end
  return true
end

-- De la meta al control STOP (22-nov, el usuario: "el GPS azul al pasar por meta, y no haber camino, se vuelve loco"): la
-- misma línea propia, por los puntos que da el montaje (la carretera de después de la meta o su prolongación), no una ruta
-- del GPS de Earth. geoPts = { { lat, lon }, ... } de la meta al STOP.
function M.toStop(geoPts)
  M.stopGeo = geoPts
  return M.stopLine()
end
function M.stopLine()
  local a = api()
  local v = be:getPlayerVehicle(0)
  if not (a and a.toGame and v and M.stopGeo and #M.stopGeo > 0) then return false end
  local cp = vec3(v:getPosition())
  local P, best, bd = {}, 1, 1e18
  for i, g in ipairs(M.stopGeo) do
    local x, y = a.toGame(g[1], g[2], 0)
    if x then
      local z = core_terrain and core_terrain.getTerrainHeight and core_terrain.getTerrainHeight(vec3(x, y, 0)) or cp.z
      P[#P + 1] = vec3(x, y, z)
      local d = (x - cp.x) ^ 2 + (y - cp.y) ^ 2
      if d < bd then best, bd = #P, d end
    end
  end
  local pts = { cp }
  for i = best, #P do if P[i]:squaredDistance(pts[#pts]) > 9 then pts[#pts + 1] = P[i] end end
  if #pts < 2 and #P > 0 then pts[2] = P[#P] end
  return M.inject(pts)
end
local stopT = 0
function M.watchStop(dt)
  if not M.stopGeo then return end
  stopT = stopT + (dt or 0)
  if stopT < M.WATCH_S then return end
  stopT = 0
  local rp = core_groundMarkers and core_groundMarkers.routePlanner
  if not (rp and rp.path and rp.path._earthRaid and #rp.path >= 2) then M.stopLine() end
end

-- entrega una línea ya hecha (puntos del juego, el primero el coche) al dibujante de la línea del GPS del juego
function M.inject(pts)
  local a = api()
  local gm = core_groundMarkers
  if not (gm and gm.setPath and gm.routePlanner) or #pts < 2 then return false end
  -- el GPS de Earth fuera (si sigue activo vuelve a calcular su ruta y pisa esta)
  if a and a.gpsClear then pcall(a.gpsClear) end
  local ok, err = pcall(function()
    -- el destino, para que el juego prepare el dibujo; y encima, la línea ya hecha
    pcall(gm.setPath, { pts[#pts] })
    gm.endWP = gm.endWP or { pts[#pts] }
    local path = {}
    for i, p in ipairs(pts) do path[i] = { pos = p, wp = nil, linkCount = 1 } end
    path._earthRaid = true
    gm.routePlanner.path = path
    gm.routePlanner:calcDistance()
    if gm.sendToApp then gm.sendToApp() end
  end)
  if not ok then log('W', TAG, 'gps line: ' .. tostring(err)) return false end
  return true
end

-- NORMA (22-nov, el usuario: "el GPS desaparece y no sé hacia dónde ir; que no pueda pasar nunca"): vigilancia cada
-- WATCH_S durante el tramo. Si no hay ruta (se acabó, la borró otra cosa, el coche se recuperó atrás) se pone otra vez
-- al momento; si el planificador del juego no da ruta dos veces seguidas, se recurre al GPS de BeamNG.Earth.
M.WATCH_S = 1.0
local watchT = 0
function M.watch(t, along, dt)
  watchT = watchT + (dt or 0)
  if watchT < M.WATCH_S then return end
  watchT = 0
  -- el coche ha vuelto atrás (recuperación): la línea se rehace desde donde está
  if M.rollAt and along < M.rollAt - 30 then M.rollAt = nil end
  -- la línea ya no es la nuestra (se acabó, la borró otra cosa, o el juego la recalculó por su grafo al salirse el coche)
  local rp = core_groundMarkers and core_groundMarkers.routePlanner
  if M.rollAt and not (rp and rp.path and rp.path._earthRaid and #rp.path >= 2) then M.rollAt = nil end
  M.roll(t, along)
end

-- La línea de carrera del mod "Racing Line" (racingline_v122, si está instalado): en el tramo sustituye a la línea azul
-- del GPS. Sigue la ruta del GPS (el trazado), así que se oculta la azul del suelo y se le pide su línea de velocidad;
-- al acabar se devuelve todo como estaba.
M.RL_DELAY_S = 1.0          -- el planificador de rutas tarda un poco en tener la ruta nueva
local racingLineOffForce
local rl = { on = false, wait = nil, saved = nil }
local function rlAction(name, v)
  local ext = rawget(_G, 'racingline')
  if ext and ext.uiAction then pcall(ext.uiAction, name, v) end
end

function M.racingLineAvailable()
  return FS:fileExists('/lua/ge/extensions/racingline.lua') == true
end

local function rlExt()
  if rawget(_G, 'racingline') then return racingline end
  if not M.racingLineAvailable() then return nil end
  pcall(extensions.load, 'racingline')
  return rawget(_G, 'racingline')
end

-- si el juego se cierra en mitad de un tramo, lo guardado aquí permite devolver la línea azul al volver a cargar
M.RL_FILE = '/settings/earthRaid/blueline.json'

local function blueLine(show)
  pcall(function()
    -- lo guardado en disco (un cierre a mitad de tramo, o una recarga del módulo) vale más que lo que hay ahora: si ya
    -- estaba oculta por nosotros, lo "actual" es false y se perdería para siempre la preferencia del jugador (19-nov:
    -- el GPS azul desaparecido)
    if not rl.saved and FS:fileExists(M.RL_FILE) then
      local ok, d = pcall(jsonReadFile, M.RL_FILE)
      if ok and type(d) == 'table' then rl.saved = d end
    end
    if not show and not rl.saved then
      rl.saved = { gm = settings.getValue('showNavigationGroundmarkers'), ar = settings.getValue('showNavigationArrows') }
      pcall(jsonWriteFile, M.RL_FILE, rl.saved)
    end
    if show then pcall(function() FS:removeFile(M.RL_FILE) end) end
    if show and rl.saved then
      settings.setValue('showNavigationGroundmarkers', rl.saved.gm ~= false)
      settings.setValue('showNavigationArrows', rl.saved.ar ~= false)
      rl.saved = nil
    elseif not show then
      settings.setValue('showNavigationGroundmarkers', false)
      settings.setValue('showNavigationArrows', false)
    end
    local gm = core_groundMarkers or rawget(_G, 'core_groundmarkers')
    if gm and gm.onSettingsChanged then gm.onSettingsChanged() end
  end)
end

-- modo hardcore: ni la línea azul ni las flechas del GPS mientras dure el tramo o el rally
function M.hideNav(on) blueLine(not on) end

-- en la salida del tramo (tras poner la ruta del GPS): on = ajuste del jugador
function M.racingLine(on)
  if not on then return false end
  local ext = rlExt()
  if not (ext and ext.uiAction) then return false end
  rl.on, rl.wait = true, M.RL_DELAY_S
  rlAction('tg_navFollow', true)
  -- la línea azul del GPS fuera mientras dure el tramo: el propio mod la oculta (17-nov: se veían las dos)
  rlAction('tg_hideNav', true)
  blueLine(false)
  return true
end

function M.rlRefresh() if rl.on then rl.wait = M.RL_DELAY_S end end

function M.tick(dt)
  if rl.wait then
    rl.wait = rl.wait - (dt or 0)
    if rl.wait <= 0 then
      rl.wait = nil
      local ext = rawget(_G, 'racingline')
      if ext and ext.uiAction then pcall(ext.uiAction, 'navline') end
    end
  end
end

-- al cargar el addon: la línea azul que quedó oculta por un cierre a mitad de tramo
function M.restoreBlueLine()
  if FS:fileExists(M.RL_FILE) then blueLine(true) end
end

-- Fuera del tramo (hacia el TC y del TC a la salida) solo la línea azul del GPS: el mod Racing Line sigue por su cuenta
-- cualquier ruta del GPS ("seguir navegación"), así que mientras Earth.Raid tiene un tramo se le apaga eso y se borra
-- su línea; al terminar con Earth.Raid se le devuelve.
function M.hold()
  rl.held = true
  rlAction('tg_navFollow', false)
  rlAction('clear')
  rlAction('tg_navFollow', false)
end
-- en un mapa normal (rally vanilla, etc.): el mod Racing Line, tal como estaba sin Earth.Raid
function M.restoreAll()
  rl.held = true
  M.release()
  pcall(racingLineOffForce)
end
function M.release()
  if not rl.held then return end
  rl.held = false
  rlAction('tg_navFollow', true)
end

local function racingLineOff()
  if not rl.on then return end
  racingLineOffForce()
end
racingLineOffForce = function()
  rl.on, rl.wait = false, nil
  rlAction('clear')
  rlAction('tg_hideNav', false)
  if rl.held then rlAction('tg_navFollow', false) end
  blueLine(true)
end

-- Fuera del tramo (en la asistencia, en los enlaces, hacia el TC, tras la meta hacia el STOP): SIEMPRE la línea azul
-- del GPS y nunca la línea de carrera (19-nov, el usuario: salía la verde al dejar el box y la azul había desaparecido:
-- el ajuste del juego se había quedado apagado tras una recarga a mitad de tramo). Se fuerza todo, sin fiarse de lo
-- guardado: el mod Racing Line deja de seguir el GPS y de ocultarlo, se borra su línea y los marcadores azules se
-- encienden. En hardcore no (main.hardcoreTick los apaga). MARK:liaison-v1
function M.liaison(hardcore)
  rl.on, rl.wait, rl.held = false, nil, true
  rlAction('tg_navFollow', false)
  rlAction('clear')
  rlAction('tg_hideNav', false)
  rlAction('tg_navFollow', false)
  if hardcore then return end
  pcall(function()
    rl.saved = nil
    if FS:fileExists(M.RL_FILE) then FS:removeFile(M.RL_FILE) end
    local changed = false
    if settings.getValue('showNavigationGroundmarkers') ~= true then settings.setValue('showNavigationGroundmarkers', true) changed = true end
    if settings.getValue('showNavigationArrows') ~= true then settings.setValue('showNavigationArrows', true) changed = true end
    if changed then
      local gm = core_groundMarkers or rawget(_G, 'core_groundmarkers')
      if gm and gm.onSettingsChanged then gm.onSettingsChanged() end
    end
  end)
end

function M.clear()
  racingLineOff()
  local a = api() if a and a.gpsClear then pcall(a.gpsClear) end
  -- y la ruta puesta al planificador del juego durante el tramo (M.roll)
  if (M.rollAt or M.stopGeo) and core_groundMarkers and core_groundMarkers.setPath then pcall(core_groundMarkers.setPath, nil) end
  M.rollAt, M.rollShort, M.stopGeo = nil, nil, nil
end

return M

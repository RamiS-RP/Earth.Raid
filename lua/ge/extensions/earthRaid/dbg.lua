-- Earth.Raid: modo de pruebas (22-nov). Atajos para comprobar un tramo sin conducirlo entero, desde la consola del juego
-- (o por MCP):  local d = require('earthRaid/dbg')
--   d.status()        fase, metros, línea de guía (propia o no, longitud, desvío máximo del trazado), caminos generados
--   d.go(metros)      lleva el coche a ese punto del tramo, en el CENTRO de la calzada y mirando en el sentido de marcha
--   d.run()           pasa de la fase actual hacia la carrera (control horario → línea de salida → cuenta atrás); llamarlo
--                     cada pocos segundos hasta que status() diga 'running'
--   d.handBack()      deja el coche como lo tenía el jugador: IA y guiado por script apagados (si quedan activos el juego
--                     anula el force feedback del volante), cámara del coche. LLAMARLO SIEMPRE AL ACABAR UNA PRUEBA.
-- NORMA: una prueba nunca deja el coche con la IA activa, la cámara libre ni mirando a un obstáculo.
local geo = require('earthRaid/geo')
local M = {}

local function api() return rawget(_G, 'beamngEarth_api') end
local function stage() return require('earthRaid/stage') end

local function gpos(t, s)
  local a = api()
  local la, lo = geo.toGeo(t, geo.at(t, math.max(0, math.min(t.total, s))))
  return a.toGame(la, lo, 0)
end

function M.go(along, back)
  local st = stage().state()
  local v = be:getPlayerVehicle(0)
  if not (st and st.track and v) then return false end
  local t = st.track
  local x, y = gpos(t, along)
  local x2, y2 = gpos(t, along + 8)
  local dx, dy = x2 - x, y2 - y
  local z = core_terrain.getTerrainHeight(vec3(x, y, 0)) or 0
  local n1, n2, d = map.findClosestRoad(vec3(x, y, z))
  local m = map.getMap()
  if n1 and n2 and d and d < 15 and m.nodes[n1] and m.nodes[n2] then
    local A, B = m.nodes[n1].pos, m.nodes[n2].pos
    local sx, sy = B.x - A.x, B.y - A.y
    local L2 = sx * sx + sy * sy
    if L2 > 0.01 then
      local u = math.max(0, math.min(1, ((x - A.x) * sx + (y - A.y) * sy) / L2))
      x, y = A.x + sx * u, A.y + sy * u
      if sx * dx + sy * dy < 0 then sx, sy = -sx, -sy end
      dx, dy = sx, sy
    end
  end
  local l = math.sqrt(dx * dx + dy * dy)
  if l < 0.01 then return false end
  dx, dy = dx / l, dy / l
  x, y = x - dx * (back or 0), y - dy * (back or 0)
  z = core_terrain.getTerrainHeight(vec3(x, y, 0)) or z
  local q = quatFromDir(vec3(-dx, -dy, 0), vec3(0, 0, 1))
  v:setPositionRotation(x, y, z + 0.5, q.x, q.y, q.z, q.w)
  return true
end

function M.run()
  local s = stage()
  local st = s.state()
  if not st then return 'sin tramo' end
  if st.phase == 'tc' then s.skipWait() M.go(0, 2.6) return 'a la línea de salida'
  elseif st.phase == 'approach' or (st.phase == 'staging' and not st.staged) then M.go(0, 2.6) return 'colocando'
  elseif st.phase == 'staging' then s.skipWait() return 'cuenta atrás' end
  return tostring(st.phase)
end

function M.status()
  local st = stage().state()
  if not st then return 'sin tramo' end
  local t = st.track
  local a = api()
  local rp = core_groundMarkers and core_groundMarkers.routePlanner
  local n, worst = rp and rp.path and #rp.path or 0, 0
  for i = 1, n do
    local q = rp.path[i].pos
    local la, lo = a.toGeo(q.x, q.y, q.z)
    local lx, ly = geo.toLocal(t, la, lo)
    local _, lat = geo.project(t, lx, ly, 1, 0, #t.pts)
    if lat > worst then worst = lat end
  end
  local pg = package.loaded['earthRaid/pathgen']
  local secs = {}
  for _, s2 in ipairs(pg and pg.sections() or {}) do secs[#secs + 1] = ('%.0f-%.0f%s'):format(s2.from, s2.to, s2.built and '' or '?') end
  return ('fase=%s along=%.0f/%.0f linea=%d pts propia=%s largo=%.0fm desvio=%.0fm caminos=[%s]'):format(tostring(st.phase), st.along or -1,
    t.total, n, tostring(rp and rp.path and rp.path._earthRaid == true), rp and rp.distance or 0, worst, table.concat(secs, ' '))
end

-- la IA y el guiado por script del coche del jugador, apagados (con cualquiera activo el juego deja el volante sin fuerza)
function M.aiOff()
  local v = be:getPlayerVehicle(0)
  if v then
    v:queueLuaCommand("if ai then pcall(ai.stopFollowing) pcall(ai.scriptStop) if ai.mode ~= 'disabled' then pcall(ai.setState, { mode = 'disabled' }) end end")
  end
end

function M.handBack()
  M.aiOff()
  if commands and commands.isFreeCamera and commands.isFreeCamera() then pcall(core_camera.setByName, 0, 'orbit') end
  return true
end

-- ---- piloto de pruebas ------------------------------------------------------------------------------------------------
-- (22-nov, el usuario: "una conducción de prueba como un piloto profesional, para ver si la inteligencia del juego puede
-- añadir otros coches competitivos"). La IA normal del juego necesita carreteras en su grafo y el tramo tiene trozos sin
-- ellas, así que se usa el guiado por trayectoria del juego (scriptai): se le da la línea del tramo (la misma de la guía)
-- con una hora para cada punto, calculada con un perfil de velocidad de piloto: en cada punto, lo que permite el radio de
-- la curva (agarre lateral `alat`), frenando antes (`brake`) y acelerando después (`acc`), con tope `vmax`. Se replanifica
-- cada REPLAN_M desde la posición y velocidad reales. Se mide: tiempo, velocidad media, separación máxima de la línea,
-- segundos y veces fuera del camino, daños.
local P
M.REPLAN_M = 120
M.PLAN_AHEAD_M = 450
M.OFF_M = 3.0
M.RESCUE_S = 10          -- atascado más de esto: rescate al centro de la calzada
function M.pilot(opts)
  opts = opts or {}
  P = { on = true, alat = opts.alat or 3.0, acc = opts.acc or 2.2, brake = opts.brake or 4.0, vmax = opts.vmax or 30,
    maxOff = 0, offTime = 0, offEvents = 0, time = 0, dist = 0, plans = 0, worst = {}, vTop = 0 }
  return true
end
function M.pilotStop()
  if P then P.on = false end
  M.handBack()
end
function M.pilotReport()
  if not P then return 'sin piloto' end
  local w = {}
  for _, e in ipairs(P.worst) do w[#w + 1] = ('%.0fm:%.1f'):format(e[1], e[2]) end
  return ('piloto on=%s fin=%s tiempo=%.1fs dist=%.0fm media=%.0f km/h punta=%.0f km/h planes=%d sepMax=%.1fm fuera=%.1fs (%d veces) daño=%s crono=%s rescates=%s | peores: %s')
    :format(tostring(P.on), tostring(P.finished), P.time, P.dist, P.time > 0 and P.dist / P.time * 3.6 or 0, P.vTop * 3.6, P.plans, P.maxOff,
      P.offTime, P.offEvents, tostring(P.damage), tostring(P.stageTime), P.rescues and table.concat(P.rescues, ',') or '0', table.concat(w, ' '))
end

local function plan(st, veh, along)
  local t = st.track
  local a = api()
  local guide = require('earthRaid/guide')
  local dressing = require('earthRaid/dressing')
  local cp = veh:getPosition()
  local pts = { vec3(cp.x, cp.y, cp.z) }
  local toEnd = false
  for s = along + 4, along + M.PLAN_AHEAD_M, 2.5 do
    local p
    if s <= t.total then p = guide.linePoint(a, t, s)
    else
      -- pasada la meta: hasta el control STOP, donde se para
      local over = s - t.total
      local sa = dressing.stopAt(t)
      if over > sa - 4 then toEnd = true break end
      local la, lo = dressing.lineAt(t, t.total, over)
      if la then
        local x, y = a.toGame(la, lo, 0)
        if x then p = vec3(x, y, core_terrain.getTerrainHeight(vec3(x, y, 0)) or cp.z) end
      end
    end
    if p and p:squaredDistance(pts[#pts]) > 2.25 then pts[#pts + 1] = p end
  end
  local n = #pts
  if n < 4 then return false end
  -- velocidad que permite la curva en cada punto (radio por tres puntos separados ~7,5 m)
  local v = {}
  for i = 1, n do
    local p0, p1, p2 = pts[math.max(1, i - 3)], pts[i], pts[math.min(n, i + 3)]
    local ax, ay, bx, by = p1.x - p0.x, p1.y - p0.y, p2.x - p1.x, p2.y - p1.y
    local la, lb = math.sqrt(ax * ax + ay * ay), math.sqrt(bx * bx + by * by)
    local vi = P.vmax
    if la > 0.5 and lb > 0.5 then
      local cross = math.abs(ax * by - ay * bx) / (la * lb)
      local dot = (ax * bx + ay * by) / (la * lb)
      local ang = math.atan2(cross, dot)
      if ang > 0.01 then
        local R = (la + lb) / 2 / ang
        vi = math.min(P.vmax, math.sqrt(P.alat * R))
      end
    end
    v[i] = math.max(5, vi)
  end
  -- al final de lo planificado: parado si es el STOP; si no, una velocidad prudente (aún no se ve lo que viene)
  v[n] = toEnd and 0.5 or math.min(v[n], 12)
  local vel = veh:getVelocity()
  v[1] = math.max(1, math.sqrt(vel.x * vel.x + vel.y * vel.y))
  local ds = {}
  for i = 2, n do ds[i] = pts[i]:distance(pts[i - 1]) end
  for i = n - 1, 2, -1 do v[i] = math.min(v[i], math.sqrt(v[i + 1] ^ 2 + 2 * P.brake * ds[i + 1])) end
  for i = 2, n do v[i] = math.min(v[i], math.sqrt(v[i - 1] ^ 2 + 2 * P.acc * ds[i])) end
  local tt = 0
  local parts = { ('{x=%.2f,y=%.2f,z=%.2f,t=0}'):format(pts[1].x, pts[1].y, pts[1].z) }
  for i = 2, n do
    tt = tt + ds[i] / math.max(0.5, (v[i] + v[i - 1]) / 2)
    parts[#parts + 1] = ('{x=%.2f,y=%.2f,z=%.2f,t=%.3f}'):format(pts[i].x, pts[i].y, pts[i].z, tt)
  end
  veh:queueLuaCommand('ai.startFollowing({' .. table.concat(parts, ',') .. '}, 0, 1, "neverReset")')
  P.pts, P.planAt, P.plans, P.toEnd = pts, along, P.plans + 1, toEnd
  return true
end

function M.tick(dt)
  if not (P and P.on) then return end
  local st = stage().state()
  local veh = be:getPlayerVehicle(0)
  if not (st and veh) then P.on = false return end
  if st.phase ~= 'running' and st.phase ~= 'toStop' then
    if P.started then P.on, P.finished = false, true P.stageTime = st.time M.handBack() end
    return
  end
  P.started = true
  local along = st.along or 0
  if st.phase == 'toStop' then along = math.max(along, st.track.total) + (P.afterD or 0) end
  local cp = veh:getPosition()
  local vel = veh:getVelocity()
  local sp = math.sqrt(vel.x * vel.x + vel.y * vel.y)
  if st.phase == 'running' then
    P.time, P.dist = P.time + dt, P.dist + sp * dt
    if sp > P.vTop then P.vTop = sp end
  else
    P.afterD = (P.afterD or 0) + sp * dt
    if P.toEnd and sp < 0.6 then P.on, P.finished = false, true P.stageTime = st.time M.handBack() return end
  end
  -- separación de la línea planificada
  if P.pts then
    local best = 1e9
    for i = 2, #P.pts do
      local d = cp:squaredDistanceToLineSegment(P.pts[i - 1], P.pts[i])
      if d < best then best = d end
    end
    local off = math.sqrt(best)
    if st.phase == 'running' then
      if off > P.maxOff then P.maxOff = off end
      if off > M.OFF_M then
        P.offTime = P.offTime + dt
        if not P.isOff then
          P.isOff, P.offEvents = true, P.offEvents + 1
          if #P.worst < 12 then P.worst[#P.worst + 1] = { along, off } end
        elseif P.worst[#P.worst] and off > P.worst[#P.worst][2] then P.worst[#P.worst][2] = off end
      else P.isOff = false end
    end
  end
  -- (23-nov, el usuario: «si el piloto se queda atascado más de 10 s fuera de la calzada, devuélvelo al centro») atascado =
  -- casi parado o fuera de la línea más de RESCUE_S segundos seguidos en carrera: se coloca en el centro de la calzada, unos
  -- metros por delante, mirando en el sentido de marcha, y se vuelve a planificar. Cada rescate queda en el informe.
  if st.phase == 'running' and P.time > 8 then
    local off = P.pts and (function()
      local best = 1e9
      for i = 2, #P.pts do local d = cp:squaredDistanceToLineSegment(P.pts[i - 1], P.pts[i]) if d < best then best = d end end
      return math.sqrt(best)
    end)() or 0
    if sp < 1.0 or off > M.OFF_M then P.stuckT = (P.stuckT or 0) + dt else P.stuckT = 0 end
    if P.stuckT > M.RESCUE_S then
      P.stuckT = 0
      local ok, al = pcall(function()
        local a = api()
        local la, lo = a.toGeo(cp.x, cp.y, cp.z)
        local lx, ly = geo.toLocal(st.track, la, lo)
        local al = geo.project(st.track, lx, ly, 1, 0, #st.track.pts)
        M.go(math.min(st.track.total, al + 6), 0)
        return al
      end)
      P.rescues = P.rescues or {}
      P.rescues[#P.rescues + 1] = ok and ('%.0f'):format(al) or 'err'
      P.planAt = nil
      return
    end
  end
  pcall(function() local o = map.objects[veh:getID()] if o then P.damage = math.floor(o.damage or 0) end end)
  if not P.planAt or along > P.planAt + M.REPLAN_M then
    if not (P.toEnd and st.phase == 'toStop') then pcall(plan, st, veh, along) end
  end
end

return M

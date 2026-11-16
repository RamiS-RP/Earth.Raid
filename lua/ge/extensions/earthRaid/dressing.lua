-- Raid.Earth: el montaje de un tramo como el rally del juego (medido en Utah NGRC26):
--   control horario antes de la salida (preaviso, cartel, sensores hacia la carretera, carpa, mesa, sillas, conos)
--   salida (2 carteles enfrentados, 2 sensores con el láser hacia el coche, semáforo con reloj delante a la derecha,
--   vallas con publicidad, fin de zona), avisos de peligro (1, 2 o 3 según el peligro), flechas en las curvas,
--   puntos de radio y médicos, público en las curvas lentas, cintas en las calles que salen del tramo,
--   meta (preaviso, 2 carteles, sensores, reloj), tablillas 3-2-1 y STOP con su carpa, y un parque de asistencia en el
--   aparcamiento más cercano a la salida.
local geo = require('earthRaid/geo')
local props = require('earthRaid/props')
local M = {}
local TAG = 'earthRaid'

-- Distancias del reglamento FIA (Anexo I, señalización de controles): control horario y salida = cartel amarillo,
-- >= 25 m, control rojo, 50-200 m, salida, 25 m, fin de zona beige; fin de tramo = aviso amarillo 100 m antes de la
-- meta lanzada y STOP 150-300 m después; radio y médico con preaviso a 100 m
M.STOP_AFTER_M = 150       -- el STOP, tras la meta
M.TC_BEFORE_M = 150        -- el control horario (punto de fichaje), antes de la salida (FIA: 50-200 m). En el mismo
                           -- sitio que el STOP del tramo al revés (FIA: 150-300 m tras la meta): un solo puesto por extremo
M.TC_ENTRY_M = 25          -- cartel amarillo antes del control
M.END_ZONE_M = 25          -- fin de zona beige tras la salida y tras el STOP
M.FINISH_WARN_M = 100      -- aviso amarillo de meta lanzada
M.SNAP_M = 8               -- el eje de la carretera del juego, si está a menos de esto del trazado del KMZ
-- Distribución estándar de la salida (la colocada a mano por el jugador en Córdoba SS1, 16-nov-2026), para todos los
-- tramos y eventos: carteles un poco antes de la línea y a la altura de los sensores (no los tapan), girados al
-- revés que los demás; semáforo con el reloj mirando al coche, 5,5 m por delante, a la derecha.
M.SIGN_BEFORE_M = 0.55     -- carteles de salida / meta / control: esto antes de su línea de sensores
M.SIGN_SIDE_M = 0.4        -- ... y su centro esto por fuera del radio de la carretera del grafo. Medido en Obejo (vista
                           -- cenital, 16-nov): la línea continua de borde está en el radio (BeamNG.Earth la pinta ahí) y el
                           -- asfalto sigue ~0,6 m más; el cartel mide 0,62 m: queda entre la línea y el final del asfalto
M.START_SIGN_YAW = 0
-- Carteles de las líneas con dos sentidos (salida = meta del tramo al revés): como en el rally del juego y como los
-- colocó el usuario (16-nov), uno a cada lado de los sensores: el de nuestro sentido antes de la línea, en el borde; el
-- del otro sentido pasada la línea y un poco más afuera (los dos se ven y ninguno tapa los sensores)
M.PAIR_FWD_M = 0.9          -- cada cartel, a esto de la línea (uno antes y otro después)
M.PAIR_OUT_M = 0.45         -- el del otro sentido, esto más hacia fuera
M.SENSOR_SIDE_M = 0.5       -- sensores en la línea, su centro a radio + esto
M.SIGN_YAW = 0             -- todos los carteles de rally del juego: la cara está en -Y (vista en Córdoba SS1: a 180 se
                           -- veían por detrás desde el coche)
M.TREE_FWD_M = 5.5         -- semáforo: por delante de la línea...
M.TREE_SIDE_M = 1.2        -- ... fuera del borde derecho...
M.TREE_YAW = 15            -- ... con el reloj hacia el coche, un poco abierto hacia la carretera
M.RADIO_EVERY_M = 5000
M.SPECTATOR_MAX = 6
M.TAPE_MAX = 80
M.SIDE_PAD_M = 0.5         -- del radio de la carretera a los demás carteles (al final del asfalto)
M.ARROW_MIN_DEG = 40

local function api() return rawget(_G, 'beamngEarth_api') end

-- media anchura de la carretera en (lat, lon), del grafo de carreteras del juego (por defecto 3.5 m)
local function halfWidth(lat, lon)
  local a = api()
  local ok, hw = pcall(function()
    local x, y, z = props.ground(lat, lon)
    local n1, n2 = map.findClosestRoad(vec3(x, y, z))
    local m = map.getMap()
    local r1 = n1 and m.nodes[n1] and m.nodes[n1].radius
    local r2 = n2 and m.nodes[n2] and m.nodes[n2].radius
    return math.max(r1 or 0, r2 or 0)
  end)
  if not ok or not hw or hw <= 0 then return 3.5 end
  return math.max(2.5, math.min(8, hw))
end

-- ¿Carretera de doble sentido en lat, lon? (grafo del juego; sin saberlo, sí)
local function twoWay(lat, lon)
  local a = api()
  local ok, r = pcall(function()
    local x, y, z = props.ground(lat, lon)
    local n1, n2 = map.findClosestRoad(vec3(x, y, z))
    local m = map.getMap()
    local l = n1 and n2 and m.nodes[n1] and m.nodes[n1].links and m.nodes[n1].links[n2]
    if not l then return nil end
    return not l.oneWay
  end)
  if ok and r ~= nil then return r end
  return true
end

-- lat, lon a `along` + `fwd` metros del tramo (siguiendo sus curvas), `right` metros a la derecha (negativo:
-- izquierda). Antes de la salida, en la prolongación recta; tras la meta, por t.after (la carretera que sigue a la
-- meta, la pone stage.lua) o en recta si no se conoce.
local function at(t, along, right, fwd)
  local d = along + (fwd or 0)
  local tr, x, y, dx, dy = t, nil, nil, nil, nil
  if d < 0 and t.before then
    -- antes de la salida, por la carretera que llega a ella (t.before va hacia atrás desde la salida)
    tr = t.before
    local e = math.min(-d, tr.total)
    x, y = geo.at(tr, e)
    local bx, by = geo.dirAt(tr, e)
    dx, dy = -bx, -by
    local over = -d - e
    x, y = x + bx * over, y + by * over
  elseif d > t.total and t.after then
    tr = t.after
    -- la carretera tras la meta no empieza justo en la línea (en Obejo, ~1 m antes): se mide desde la proyección de la
    -- meta sobre ella, o lo de "pasada la línea" caía encima de la línea
    if not t.afterOff then
      local ok, off = pcall(function()
        local fx, fy = geo.at(t, t.total)
        local fla, flo = geo.toGeo(t, fx, fy)
        local ax, ay = geo.toLocal(tr, fla, flo)
        local along = geo.project(tr, ax, ay, 1, 0, math.min(#tr.pts, 40))
        return along
      end)
      t.afterOff = (ok and type(off) == 'number' and off < 30) and off or 0
    end
    local e = math.min(d - t.total + t.afterOff, tr.total)
    x, y = geo.at(tr, e)
    dx, dy = geo.dirAt(tr, e)
    local over = (d - t.total + t.afterOff) - e
    x, y = x + dx * over, y + dy * over
  elseif d >= 0 and d <= t.total then
    x, y = geo.at(t, d)
    dx, dy = geo.dirAt(t, d)
  else
    local base = d < 0 and 0 or t.total
    x, y = geo.at(t, base)
    dx, dy = geo.dirAt(t, base)
    x, y = x + dx * (d - base), y + dy * (d - base)
  end
  -- todo se apoya en el eje de la carretera del juego (el KMZ va desplazado y girado respecto a ella): el punto del
  -- trazado se lleva al eje y la dirección es la de la carretera
  local blat, blon = geo.toGeo(tr, x, y)
  local cl, co, rx, ry = M.snap(blat, blon, dx, dy)
  if cl and (d < 0 or d > t.total) and d > -12 and d < t.total + 12 then
    -- cerca de la salida o de la meta, por fuera del trazado: la distancia a la línea se mide sobre la carretera (el
    -- camino de antes/después no empieza justo en la línea; en Obejo lo de "1 m pasada la meta" caía en la línea)
    local key = d < 0 and '_snap0' or '_snapT'
    if t[key] == nil then
      local base = d < 0 and 0 or t.total
      local bx, by = geo.at(t, base)
      local ddx, ddy = geo.dirAt(t, base)
      local la0, lo0 = geo.toGeo(t, bx, by)
      local sl, so = M.snap(la0, lo0, ddx, ddy)
      t[key] = sl and { sl, so } or false
    end
    local ref = t[key]
    if ref then
      local k = math.cos(math.rad(cl)) * 111195
      local ex, ny = (co - ref[2]) * k, (cl - ref[1]) * 111195
      local want = d < 0 and d or (d - t.total)
      local delta = want - (ex * rx + ny * ry)
      if math.abs(delta) < 5 then
        cl, co = cl + (ry * delta) / 111195, co + (rx * delta) / k
      end
    end
  end
  if cl then
    local r = right or 0
    local k = math.cos(math.rad(cl)) * 111195
    return cl + (-rx * r) / 111195, co + (ry * r) / k, rx, ry
  end
  x, y = x + dy * (right or 0), y - dx * (right or 0)
  local lat, lon = geo.toGeo(tr, x, y)
  return lat, lon, dx, dy
end

-- El eje de la carretera del juego junto a (lat, lon), con la dirección (dx, dy) del tramo: lat, lon del eje y su
-- dirección (este, norte) en el sentido del tramo; nil si no hay carretera cargada cerca o la cruza
function M.snap(lat, lon, dx, dy)
  if M.dry then return nil end
  local a = api()
  local ok, cl, co, rx, ry = pcall(function()
    local x, y, z = props.ground(lat, lon)
    local n1, n2, d = map.findClosestRoad(vec3(x, y, z))
    if not (n1 and n2 and d and d < M.SNAP_M) then return nil end
    local m = map.getMap()
    local p1, p2 = m.nodes[n1].pos, m.nodes[n2].pos
    local sx, sy = p2.x - p1.x, p2.y - p1.y
    local L2 = sx * sx + sy * sy
    if L2 < 0.01 then return nil end
    local u = math.max(0, math.min(1, ((x - p1.x) * sx + (y - p1.y) * sy) / L2))
    local cx, cy, cz = p1.x + sx * u, p1.y + sy * u, p1.z + (p2.z - p1.z) * u
    local L = math.sqrt(L2)
    local ux, uy = sx / L, sy / L
    local dot = ux * dx + uy * dy
    if math.abs(dot) < 0.5 then return nil end
    if dot < 0 then ux, uy = -ux, -uy end
    local la, lo = a.toGeo(cx, cy, cz)
    return la, lo, ux, uy
  end)
  if ok and cl then return cl, co, rx, ry end
  return nil
end

-- La línea en `along` + `fwd` (salida, meta, control): su centro en el eje de la carretera y su dirección
function M.lineAt(t, along, fwd)
  local lat, lon, dx, dy = at(t, along, 0, fwd)
  return lat, lon, dx, dy
end

-- metros de la meta al STOP (más corto si la carretera tras la meta lo es: el "Stop Control" del organizador)
function M.stopAt(t) return t.stopAt or M.STOP_AFTER_M end
-- metros de la salida al control horario: como el STOP, más cerca si la carretera de antes es más corta (así el TC de un
-- sentido y el STOP del otro caen en el mismo sitio)
function M.tcAt(t)
  if t.before and t.before.total > 1 then return math.max(60, math.min(M.TC_BEFORE_M, t.before.total)) end
  return M.TC_BEFORE_M
end

-- tras el final del trazado, en línea recta
local function beyond(t, extra, right)
  return at(t, t.total, right, extra)
end

-- ---- edificios: nada se pone si hay un edificio o un muro entre la carretera y su sitio --------------------------------
M.AVOID = { fenceNgrc = true, fenceBlastr = true, fenceRotopad = true, fenceApm = true, fenceApmSpecial = true,
  specTarp = true, specTarp2 = true, specTarp3 = true, specTape = true, specGrid = true, gazebo3x3 = true, gazebo3x6 = true,
  gazebo3x6b = true, table = true, chair = true, cushion = true }
M.PULL_IN = { start = true, finish = true, tc = true, tcEntry = true, finishEntry = true, stop = true, endArea = true,
  medical = true, medicalWarn = true, radio = true, radioWarn = true, board1 = true, board2 = true, board3 = true,
  danger = true, sensor = true, tree = true }
M.RAY_H = 1.5
M.dry = false                -- simulación: se cuenta lo que se pondría, sin crear nada (M.simulate)
M.skipped = 0

-- metros libres desde la carretera (`from` m al lado) hacia `right` antes de chocar con algo, o nil si está libre
local function freeTo(t, along, right, fwd, from)
  if M.dry or math.abs(right) < 0.5 then return nil end
  local a = api()
  local ok, hit = pcall(function()
    local la0, lo0 = at(t, along, from or 0, fwd)
    local la1, lo1 = at(t, along, right, fwd)
    local x0, y0, z0 = props.ground(la0, lo0)
    local x1, y1 = a.toGame(la1, lo1, 0)
    if not (x0 and x1) then return nil end
    local dir = vec3(x1 - x0, y1 - y0, 0)
    local d = dir:length()
    if d < 0.3 then return nil end
    local h = castRayStatic(vec3(x0, y0, z0 + M.RAY_H), dir / d, d + 0.6)
    if h and h < d + 0.5 then return h end
    return nil
  end)
  return ok and hit or nil
end

-- Norma (16-nov): en la calzada solo conos en el eje. Distancia mínima del centro de cada objeto a la línea de borde
-- (el radio de la carretera más cercana del juego, sea la del tramo o una que cruce); nil: puede ir en la calzada
M.CLEAR_M = { cone = false, lamp = 2.0, sndCrowd = false, sndCheer = false, sndGenerator = false, gazebo3x3 = 2.0, gazebo3x6 = 2.0, gazebo3x6b = 2.0, table = 0.9, chair = 0.9, tree = 0.8,
  cushion = 0.8, specTape = 1.5, specGrid = 1.5, specGridA = 1.5, specTarp = 2.0, specTarp2 = 2.0, specTarp3 = 2.0 }
local function clearOf(kind)
  local c = M.CLEAR_M[kind]
  if c == false then return nil end
  if c then return c end
  if kind:find('^fence') then return 1.0 end
  return M.SIGN_SIDE_M
end
M.pushed = 0
-- Si (lat, lon) cae en una calzada (o a menos de su margen de la línea de borde), se lleva hacia fuera
local function offRoad(kind, lat, lon)
  local c = clearOf(kind)
  if not c or M.dry or not lat then return lat, lon end
  local a = api()
  local ok, la, lo = pcall(function()
    local x, y, z = props.ground(lat, lon)
    if not x then return nil end
    local n1, n2, dd = map.findClosestRoad(vec3(x, y, z))
    local m = map.getMap()
    if not (n1 and n2 and m.nodes[n1] and m.nodes[n2]) then return nil end
    if dd and dd < 40 then M._seen = true end
    local p1, p2 = m.nodes[n1].pos, m.nodes[n2].pos
    local sx, sy = p2.x - p1.x, p2.y - p1.y
    local L2 = sx * sx + sy * sy
    if L2 < 0.01 then return nil end
    local u = math.max(0, math.min(1, ((x - p1.x) * sx + (y - p1.y) * sy) / L2))
    local cx, cy = p1.x + sx * u, p1.y + sy * u
    local r = (m.nodes[n1].radius or 3) + ((m.nodes[n2].radius or 3) - (m.nodes[n1].radius or 3)) * u
    local ex, ey = x - cx, y - cy
    local d = math.sqrt(ex * ex + ey * ey)
    local need = r + c
    if d >= need - 0.05 or d < 0.05 then return nil end
    local k = need / d
    return a.toGeo(cx + ex * k, cy + ey * k, z)
  end)
  if ok and la then M.pushed = M.pushed + 1 return la, lo end
  return lat, lon
end
M.offRoad = offRoad

-- Repaso continuo (norma del usuario: "en todo momento"): lo colocado antes de que el juego cargara la carretera de
-- ese sitio se comprueba otra vez cuando el jugador se acerca, y si cae en una calzada se saca fuera. Lo que ya se
-- comprobó con la carretera cargada no se vuelve a mirar.
M.RECHECK_M = 300
M.SKIP_RECHECK = { line = true, cone = true, lamp = true, tape = true, tape6 = true, tape10 = true, sndCrowd = true, sndCheer = true,
  sndGenerator = true }
function M.recheck(plat, plon)
  if M.dry or not plat then return 0 end
  local k = math.cos(math.rad(plat))
  local moved = 0
  for _, it in ipairs(props.all()) do
    if not it.roadOk and not M.SKIP_RECHECK[it.kind] and it.lat then
      local ex, ny = (it.lon - plon) * 111195 * k, (it.lat - plat) * 111195
      if ex * ex + ny * ny < M.RECHECK_M * M.RECHECK_M then
        M._seen = false
        local la, lo = offRoad(it.kind, it.lat, it.lon)
        it.checks = (it.checks or 0) + 1
        -- con la carretera cargada, o tras 4 intentos (lejos de toda carretera: nada que comprobar)
        if M._seen or it.checks >= 4 then it.roadOk = true end
        if la and (la ~= it.lat or lo ~= it.lon) then props.move(it, la, lo) moved = moved + 1 end
      end
    end
  end
  if moved > 0 then log('I', TAG, ('recheck: %d objects moved off the road'):format(moved)) end
  return moved
end

-- de noche (19:30-7:30 en el reloj del juego): las luces de las carpas solo entonces
function M.night()
  local ok, tod = pcall(function() return core_environment.getTimeOfDay() end)
  if not ok or type(tod) ~= 'table' or not tod.time then return false end
  local h = ((tod.time + 0.5) % 1) * 24
  return h >= 19.5 or h < 7.5
end
M.SOUND_KINDS = { sndCrowd = true, sndCheer = true, sndGenerator = true }

local function place(kind, t, along, right, yaw, fwd, opts)
  -- sonido de ambiente: solo si el jugador lo activa (por defecto no; el audio se entrecortaba en los tirones)
  if M.SOUND_KINDS[kind] and not M.sounds and not M.dry then return nil end
  if kind == 'lamp' and not M.dry and not M.night() then return nil end
  if right and math.abs(right) > 0.5 and (M.AVOID[kind] or M.PULL_IN[kind]) then
    local from = opts and opts.from or 0
    local hit = freeTo(t, along, right, fwd, from)
    if hit then
      if M.AVOID[kind] then M.skipped = M.skipped + 1 return nil end
      -- un cartel, más cerca de la carretera (nunca dentro de ella)
      local sign = right > 0 and 1 or -1
      local minR = (opts and opts.minRight) or 0.6   -- offRoad lo devuelve fuera de la calzada si hace falta
      local r = math.max(minR, math.abs(from) + hit - 0.6)
      right = sign * math.min(math.abs(right), r)
    end
  end
  local lat, lon, dx, dy = at(t, along, right, fwd)
  M._seen = false
  lat, lon = offRoad(kind, lat, lon)
  local seen = M._seen
  if M.dry then
    M.counts[kind] = (M.counts[kind] or 0) + 1
    return { kind = kind, lat = lat, lon = lon }
  end
  local it = props.add(kind, lat, lon, dx, dy, yaw, opts)
  if it and seen then it.roadOk = true end
  return it
end

-- ---- montaje por delante del coche: lo de más allá de la salida se coloca al acercarse (BeamNG.Earth carga carreteras
-- y terreno alrededor del jugador: así la anchura de la calzada, los edificios y la carretera tras la meta son reales)
local jobs = {}
M.JOB_RADIUS_M = 450       -- se monta cuando el jugador está a menos de esto (el grafo de carreteras ya está cargado)
-- t: el tramo (para saber dónde cae el trabajo); atM: metros del tramo (negativo: antes de la salida)
function M.later(atM, fn, t)
  t = t or M._t
  local j = { at = atM, fn = fn }
  if t then
    local d = math.max(0, math.min(t.total, atM))
    local x, y = geo.at(t, d)
    j.lat, j.lon = geo.toGeo(t, x, y)
  end
  jobs[#jobs + 1] = j
end
function M.resetJobs() jobs = {} end
function M.pendingJobs() return #jobs end
-- runJobs(upTo): por metros del tramo (simulación); runJobsNear(lat, lon): por distancia al jugador
-- maxJobs: como mucho tantos trabajos por llamada (uno: el montaje se reparte en varios fotogramas)
function M.runJobsNear(lat, lon, maxJobs)
  local k = math.cos(math.rad(lat))
  local i, n = 1, 0
  while jobs[i] and (not maxJobs or n < maxJobs) do
    local j = jobs[i]
    local near = not j.lat or ((j.lon - lon) * 111195 * k) ^ 2 + ((j.lat - lat) * 111195) ^ 2 < M.JOB_RADIUS_M ^ 2
    if near then
      table.remove(jobs, i)
      local ok, err = pcall(j.fn)
      if not ok then log('W', TAG, 'dressing job: ' .. tostring(err)) end
      n = n + 1
    else
      i = i + 1
    end
  end
  return n
end
-- El box del parque de asistencia (al empezar el rally desde la primera ronda): una carpa 3x6 junto a la carretera más
-- cercana a (lat, lon), fuera de la calzada, con cajas de herramientas, banco, neumáticos, taburete y luz; el coche
-- aparca debajo. Devuelve el sitio del coche { lat, lon, faceLat, faceLon } o nil (sin carretera cargada).
M.BOX_ROAD_M = 40            -- la asistencia más lejos que esto del asfalto: el box se monta en la propia asistencia
function M.serviceBox(lat, lon, towardLat, towardLon)
  local a = api()
  local x, y = a.toGame(lat, lon, 0)
  if not x then return nil end
  local z = core_terrain and core_terrain.getTerrainHeight and core_terrain.getTerrainHeight(vec3(x, y, 0)) or 0
  -- junto a la carretera si pasa cerca de la asistencia; si no (un aparcamiento, un recinto), en el mismo punto
  local n1, n2, d, px, py = props.nearestRoad(x, y, z, 150)
  local m = map.getMap()
  local hx, hy, cx, cy, rx, ry
  if n1 and d and d < M.BOX_ROAD_M then
    local A, B = m.nodes[n1].pos, m.nodes[n2].pos
    local sx, sy = B.x - A.x, B.y - A.y
    local L = math.sqrt(sx * sx + sy * sy)
    if L < 0.5 then return nil end
    hx, hy = sx / L, sy / L
    if towardLat then
      local tx, ty = a.toGame(towardLat, towardLon, 0)
      if tx and ((tx - x) * hx + (ty - y) * hy) < 0 then hx, hy = -hx, -hy end
    end
    rx, ry = hy, -hx
    -- a la derecha de la carretera, la carpa con su borde a 1,5 m del asfalto
    local r = (m.nodes[n1].radius or 3) + 0.6 + 1.5 + 1.5
    cx, cy = px + rx * r, py + ry * r
  else
    -- mirando a la carretera más cercana (por donde se sale), o hacia el primer tramo
    local fx, fy
    if px then fx, fy = px, py elseif towardLat then fx, fy = a.toGame(towardLat, towardLon, 0) end
    local vx, vy = (fx or x + 1) - x, (fy or y) - y
    local L = math.sqrt(vx * vx + vy * vy)
    if L < 0.5 then vx, vy, L = 1, 0, 1 end
    hx, hy = vx / L, vy / L
    rx, ry = hy, -hx
    cx, cy = x, y
  end
  local function put(kind, fwd, side, yaw, opts)
    local la, lo = a.toGeo(cx + hx * fwd + rx * side, cy + hy * fwd + ry * side, z)
    return props.add(kind, la, lo, hx, hy, yaw or 0, opts)
  end
  put('gazebo3x6d', 0, 0, 180)
  put('lamp', 0, 0, 0, { dz = 2.6 })
  put('bigToolbox', -1.6, 2.1, -90)
  put('bigToolbox2', 0.2, 2.1, -90)
  put('smallToolbox', 1.6, 2.0, -90)
  put('workbench', 3.9, 1.0, 180)
  put('stool', 3.4, -0.4, 0)
  put('tireRack', -3.9, 1.2, 0)
  put('cone', -4.2, -1.6, 0)
  put('cone', 4.2, -1.6, 0)
  local la, lo = a.toGeo(cx, cy, z)
  local fla, flo = a.toGeo(cx + hx * 10, cy + hy * 10, z)
  return { lat = la, lon = lo, faceLat = fla, faceLon = flo }
end

function M.pendingJobsNear(lat, lon)
  local k = math.cos(math.rad(lat))
  local n = 0
  for _, j in ipairs(jobs) do
    if not j.lat or ((j.lon - lon) * 111195 * k) ^ 2 + ((j.lat - lat) * 111195) ^ 2 < M.JOB_RADIUS_M ^ 2 then n = n + 1 end
  end
  return n
end
function M.runJobs(upTo)
  local i, n = 1, 0
  while jobs[i] do
    if jobs[i].at <= upTo then
      local j = table.remove(jobs, i)
      local ok, err = pcall(j.fn)
      if not ok then log('W', TAG, 'dressing job: ' .. tostring(err)) end
      n = n + 1
    else
      i = i + 1
    end
  end
  return n
end
local function hwAt(t, along) return halfWidth(at(t, along, 0, 0)) end
M.hwAt = hwAt

-- un par de carteles enfrentados, a ambos lados
local function pair(kind, t, along, hw, fwd)
  place(kind, t, along, hw + M.SIDE_PAD_M, M.SIGN_YAW, fwd)
  place(kind, t, along, -(hw + M.SIDE_PAD_M), M.SIGN_YAW, fwd)
end

-- sensores de cronometraje a ambos lados con el láser cruzando la carretera
local function sensors(t, along, hw, fwd)
  place('sensor', t, along, hw + M.SENSOR_SIDE_M, 90, fwd)
  place('sensor', t, along, -(hw + M.SENSOR_SIDE_M), -90, fwd)
end

-- los carteles de una línea de los dos sentidos, a ambos lados: `mine` mira a quien llega en nuestro sentido (antes
-- de la línea), `other` a quien llega al revés (pasada la línea, girado 180 y un poco más afuera)
local function lineSigns(t, along, hw, fwd, mine, other)
  local f = fwd or 0
  for _, sg in ipairs({ 1, -1 }) do
    place(mine, t, along, sg * (hw + M.SIGN_SIDE_M), M.SIGN_YAW, f - M.PAIR_FWD_M)
    if other then place(other, t, along, sg * (hw + M.SIGN_SIDE_M + M.PAIR_OUT_M), M.SIGN_YAW + 180, f + M.PAIR_FWD_M) end
  end
end

-- una línea pintada con spray en el suelo, de borde a borde de la calzada
M.PAINT = { start = 'spraypaint_mark_green', finish = 'spraypaint_mark', stop = 'spraypaint_mark_orange',
  tc = 'spraypaint_mark_orange' }
local function paintLine(t, along, hw, fwd, what)
  if M.dry then M.counts['line_' .. what] = (M.counts['line_' .. what] or 0) + 1 return nil end
  local la1, lo1 = at(t, along, -(hw - 0.2), fwd)
  local la2, lo2 = at(t, along, hw - 0.2, fwd)
  return props.addLine(la1, lo1, la2, lo2, M.PAINT[what] or 'spraypaint_mark', 0.3)
end

local function fenceLine(t, along, side, n, fwd)
  local kinds = { 'fenceNgrc', 'fenceBlastr', 'fenceRotopad', 'fenceApm', 'fenceApmSpecial' }
  for i = 0, n - 1 do
    -- las vallas son largas en Y: Y a lo largo de la carretera
    -- la publicidad mira a la carretera: a la izquierda, girada
    place(kinds[i % #kinds + 1], t, along, side, side < 0 and 180 or 0, (fwd or 0) - i * 2.6)
  end
end

-- lonas de público (4 m, largas en -Y desde su origen) detrás de una fila de vallas
local function tarpLine(t, along, side, n, fwd)
  local kinds = { 'specTarp', 'specTarp2', 'specTarp3' }
  local from = side > 0 and side - 2.5 or side + 2.5
  for i = 0, n - 1 do place(kinds[i % 3 + 1], t, along, side, 0, (fwd or 0) - i * 4, { noCollision = true, from = from }) end
end

-- Conos en la calzada: solo en el eje y solo si es de doble sentido (dividen los dos carriles)
local function centreCones(t, along, fwd, from, to, step)
  local la, lo = at(t, along, 0, fwd)
  if not twoWay(la, lo) then return end
  for k = from, to, step do place('cone', t, along, 0, 0, fwd + k) end
end

-- Puesto de control: carpa 3x3 fuera de la calzada (su borde a 1 m del asfalto); debajo, la mesa del lado de la
-- carretera, el comisario detrás mirando a la carretera y el reloj de fichar junto a la mesa. En doble sentido, otro
-- puesto enfrente para los que vienen al revés (FIA: cada control, en los dos sentidos si se recorre en los dos).
-- (Las sillas del juego miran hacia -Y con giro 0: las de antes quedaban de espaldas a la carretera.)
M.CHAIR_YAW = 180
local function controlPoint(t, along, hw, label, fwd, bothSides, gap)
  local f = fwd or 0
  local g = gap or 2.5
  for _, sg in ipairs(bothSides and { 1, -1 } or { 1 }) do
    local side = sg * (hw + g)
    -- adelante/atrás según el sentido de quien llega a ese lado
    local ff = sg > 0 and 1 or -1
    place('gazebo3x3', t, along, side, sg > 0 and 180 or 0, f)
    place('table', t, along, side - sg * 0.5, sg > 0 and 180 or 0, f)
    place('chair', t, along, side + sg * 0.5, (sg > 0 and 0 or 180) + M.CHAIR_YAW, f)
    -- el reloj de fichar (el LED del juego, en su trípode) a la entrada del puesto, mirando a la carretera
    place('tree', t, along, side - sg * 0.6, sg > 0 and 90 or -90, f - ff * 1.9)
  end
  -- el generador de la carpa (sonido) detrás del puesto
  place('sndGenerator', t, along, hw + g + 2.5, 0, f + 1)
  centreCones(t, along, f, -8, 8, 4)
end
M.controlPoint = controlPoint

-- ---- partes ------------------------------------------------------------------------------------------------------------

-- ---- extremos del tramo: el mismo montaje para los dos sentidos ---------------------------------------------------------
-- Cada extremo (la salida o la meta) lleva lo mismo, se recorra el tramo como se recorra (norma del usuario, 16-nov: el
-- inverso usa los mismos objetos): la línea con los carteles de los dos sentidos, y a D m por fuera un puesto de control
-- que es el TC de quien sale y el STOP de quien llega. Solo cambia según el sentido: el semáforo de salida y el reloj de
-- meta, el color de la línea, en qué carpa está el reloj de fichar y por dónde se oyen los ánimos.
-- Marco del extremo: "fuera" = alejándose del tramo; "lado" > 0 = a la derecha mirando hacia fuera (la derecha de quien
-- llega), < 0 = la derecha de quien sale. out = -1 en la salida del trazado t, +1 en la meta.
local function endPlacer(t, endAlong, out)
  -- facing 'out': mira a quien va hacia fuera (llega a la meta); 'in': a quien va hacia dentro (sale)
  local function yawFor(facing, base)
    local toOut = (facing == 'out')
    return (base or M.SIGN_YAW) + ((toOut == (out > 0)) and 0 or 180)
  end
  return function(kind, lado, distOut, facing, yaw, opts)
    local y = yaw
    if facing then y = yawFor(facing, yaw) end
    return place(kind, t, endAlong, out * lado, y, out * distOut, opts)
  end, yawFor
end

M.END_FENCE_IN_M, M.END_FENCE_OUT_M = 30, 25
-- role: 'start' (aquí sale el tramo que se corre) o 'finish' (aquí llega). Devuelve el semáforo / reloj de este extremo.
function M.endKit(t, endAlong, out, hw, D, role)
  local put = endPlacer(t, endAlong, out)
  local S, P = hw + M.SIGN_SIDE_M, hw + M.SIDE_PAD_M
  -- la línea: a cada lado, el cartel de quien llega (meta) por dentro y el de quien sale (salida) por fuera, a los
  -- dos lados de los sensores; el de dentro un poco más afuera, para que desde los dos sentidos se vean los dos
  for _, sg in ipairs({ 1, -1 }) do
    put('finish', sg * (S + M.PAIR_OUT_M), -M.PAIR_FWD_M, 'out')
    put('start', sg * S, M.PAIR_FWD_M, 'in')
    put('sensor', sg * (hw + M.SENSOR_SIDE_M), 0, nil, (out * sg) > 0 and 90 or -90)
    -- fin de zona (beige) 25 m dentro para quien sale; aviso amarillo de meta lanzada 100 m antes para quien llega
    put('endArea', sg * P, -M.END_ZONE_M, 'in')
    put('finishEntry', sg * P, -M.FINISH_WARN_M, 'out')
  end
  paintLine(t, endAlong, hw, 0, role == 'start' and 'start' or 'finish')
  -- vallas publicitarias a los dos lados, de 30 m dentro a 25 m fuera, público detrás (y su murmullo)
  local kinds = { 'fenceNgrc', 'fenceBlastr', 'fenceRotopad', 'fenceApm', 'fenceApmSpecial' }
  local n = math.floor((M.END_FENCE_IN_M + M.END_FENCE_OUT_M) / 2.6)
  for _, sg in ipairs({ 1, -1 }) do
    local side = out * sg * (hw + 3.5)
    for i = 0, n - 1 do
      place(kinds[i % #kinds + 1], t, endAlong, side, side < 0 and 180 or 0, out * (-M.END_FENCE_IN_M + i * 2.6))
    end
    local tside = out * sg * (hw + 6)
    local from = tside > 0 and tside - 2.5 or tside + 2.5
    for i = 0, 5 do
      local tk = ({ 'specTarp', 'specTarp2', 'specTarp3' })[i % 3 + 1]
      -- las lonas son largas en -Y desde su origen: el origen en su extremo "hacia fuera"
      place(tk, t, endAlong, tside, out > 0 and 0 or 180, out * (-22 + i * 4),
        { noCollision = true, from = from })
    end
    put('sndCrowd', sg * (hw + 7), -6, nil, 0)
  end

  -- el puesto de control a D m por fuera: TC de quien sale, STOP de quien llega
  paintLine(t, endAlong, hw, out * D, 'stop')
  put('tcEntry', -P, D + M.TC_ENTRY_M, 'in')
  put('tc', -S, D + M.PAIR_FWD_M, 'in')
  for i, b in ipairs({ 'board3', 'board2', 'board1' }) do
    local d = D * i / 4
    put(b, P, d, 'out')
    put(b, -P, d, 'out')
  end
  put('stop', S, D - M.PAIR_FWD_M, 'out')
  local cla, clo = at(t, endAlong, 0, out * D)
  local both = twoWay(cla, clo)
  -- el reloj de fichar en la carpa de quien ficha en este sentido: el que sale aquí (TC) o el que llega (STOP)
  local clockLado = role == 'start' and -1 or 1
  local lados = both and { 1, -1 } or { clockLado }
  local g = 2.6
  for _, lado in ipairs(lados) do
    local side = out * lado * (hw + g)
    local sgn = side > 0 and 1 or -1
    place('gazebo3x3', t, endAlong, side, sgn > 0 and 180 or 0, out * D)
    place('table', t, endAlong, side - sgn * 0.5, sgn > 0 and 180 or 0, out * D)
    place('chair', t, endAlong, side + sgn * 0.5, (sgn > 0 and 0 or 180) + M.CHAIR_YAW, out * D)
    -- de noche, una luz bajo cada carpa (de día no se nota)
    place('lamp', t, endAlong, side, 0, out * D, { dz = 2.4 })
    if lado == clockLado then
      place('tree', t, endAlong, side - sgn * 1.3, sgn > 0 and 90 or -90, out * D + 0.9)
    end
  end
  put('sndGenerator', hw + g + 2.5, D + 1, nil, 0)
  centreCones(t, endAlong, out * D, -10, 10, 5)
  -- detrás del puesto, el equipo de cronometraje y el médico
  put('gazebo3x6', hw + 5, D + 11, nil, (out > 0) and 180 or 0)
  put('gazebo3x6b', hw + 5, D + 19, nil, (out > 0) and 180 or 0)
  put('lamp', hw + 5, D + 15, nil, 0, { dz = 2.6 })
  put('medical', -P, D + 8, 'out')

  -- según el sentido: el semáforo de salida (5,5 m dentro, a la derecha de quien sale, mirándole) o el reloj de meta
  -- (5,5 m fuera, a la derecha de quien llega); y los ánimos al llegar
  local clock
  if role == 'start' then
    clock = place('tree', t, endAlong, out * -(hw + M.TREE_SIDE_M), M.TREE_YAW + ((out > 0) and 180 or 0), -out * M.TREE_FWD_M)
  else
    clock = place('tree', t, endAlong, out * (hw + M.TREE_SIDE_M), M.TREE_YAW + ((out > 0) and 0 or 180), out * M.TREE_FWD_M)
    M.crowdZones[#M.crowdZones + 1] = { at = endAlong - 40, mid = endAlong - 6 }
  end
  return clock and clock.obj
end

function M.startLine(t, hw)
  return M.endKit(t, 0, -1, hw, M.tcAt(t), 'start')
end

function M.finishLine(t, hw)
  return M.endKit(t, t.total, 1, hw, M.stopAt(t), 'finish')
end

-- radio cada RADIO_EVERY_M y en el parcial; médico a mitad
-- (los puntos se cuentan desde la salida del tramo en su sentido normal: el tramo al revés los tiene en el mismo sitio)
function M.safety(t, hw, splitAt)
  local function canon(d) if M.reversed then return t.total - d end return d end
  local marks = {}
  if splitAt then marks[#marks + 1] = canon(math.floor(t.total / 2 / 100 + 0.5) * 100) end
  for c = M.RADIO_EVERY_M, t.total - 500, M.RADIO_EVERY_M do marks[#marks + 1] = canon(c) end
  for _, d in ipairs(marks) do
    M.later(d - 100, function()
      local hwd = hwAt(t, d)
      place('radioWarn', t, math.max(0, d - 100), hwAt(t, d - 100) + M.SIDE_PAD_M, M.SIGN_YAW)
      place('radio', t, d, hwd + M.SIDE_PAD_M, M.SIGN_YAW)
      -- y para el otro sentido, enfrente
      place('radio', t, d, -(hwd + M.SIDE_PAD_M), M.SIGN_YAW + 180)
      place('radioWarn', t, math.min(t.total, d + 100), -(hwAt(t, d + 100) + M.SIDE_PAD_M), M.SIGN_YAW + 180)
    end)
  end
  if t.total > 3000 then
    local d = canon(t.total * 0.5 + 400)
    M.later(d - 100, function()
      place('medicalWarn', t, d - 100, -(hwAt(t, d - 100) + M.SIDE_PAD_M), M.SIGN_YAW)
      place('medical', t, d, -(hwAt(t, d) + M.SIDE_PAD_M), M.SIGN_YAW)
      place('medical', t, d, hwAt(t, d) + M.SIDE_PAD_M, M.SIGN_YAW + 180)
    end)
  end
end

-- Salidas peligrosas: en las curvas lentas tras una recta (y en las horquillas), vallas publicitarias por el exterior
-- donde un coche se saldría, y un cojín de protección en el vértice de las horquillas (no se sabe dónde hay guardarraíl:
-- se ponen igual; si hay un muro o un edificio, place() no las pone)
M.BARRIER_MIN_STRAIGHT_M = 120
function M.barriers(t, notes)
  local prevEnd = 0
  for _, nt in ipairs(notes) do
    if nt.kind == 'corner' then
      local slow = nt.grade == 'hairpin' or nt.grade == 'square' or (type(nt.grade) == 'number' and nt.grade <= 2)
      local straight = nt.at - prevEnd
      if slow and (straight >= M.BARRIER_MIN_STRAIGHT_M or nt.grade == 'hairpin') and nt.at > 150 and nt.endAt < t.total - 150 then
        local mid = (nt.at + nt.endAt) / 2
        local sideSign = nt.side == 'right' and -1 or 1
        M.later(nt.at, function()
          local hw = hwAt(t, mid)
          fenceLine(t, mid, sideSign * (hw + 2.5), 5, 6)
          if nt.grade == 'hairpin' then place('cushion', t, mid, sideSign * (hw + 1.6), 0, 0) end
        end)
      end
      prevEnd = nt.endAt or nt.at
    end
  end
end

-- flechas antes de las curvas cerradas, en el exterior de la curva
function M.arrows(t, notes, hw)
  local n = 0
  for _, nt in ipairs(notes) do
    local sharp = nt.grade == 'hairpin' or nt.grade == 'square' or (type(nt.grade) == 'number' and nt.grade <= 3)
    if nt.kind == 'corner' and nt.deg >= M.ARROW_MIN_DEG and sharp then
      local right = nt.side == 'right'
      local kind
      if nt.grade == 'hairpin' or nt.deg > 120 then kind = right and 'hairpinR' or 'hairpinL'
      elseif nt.deg < 60 then kind = right and 'corner45R' or 'corner45L'
      else kind = right and 'cornerR' or 'cornerL' end
      -- en el exterior: una curva a la derecha lleva la flecha a la izquierda, y viceversa
      local sideSign = right and -1 or 1
      local along = math.max(0, nt.at + 6)
      M.later(along, function()
        local side = sideSign * (hwAt(t, along) + 1.5)
        -- cara del modelo en -X: hacia el coche que llega y un poco hacia la carretera
        local yaw = side > 0 and -60 or -120
        place(kind, t, along, side, yaw, 0, { noCollision = true })
        -- una segunda flecha más adelante en las horquillas
        if nt.grade == 'hairpin' or nt.deg > 120 then
          place(kind, t, math.min(t.total, along + 12), side, yaw, 0, { noCollision = true })
        end
      end)
      n = n + 1
    end
  end
  return n
end

-- avisos de peligro: 1 cartel (precaución), 2 (doble), 3 (dos pares) antes del peligro
function M.cautions(t, hazards, hw)
  for _, h in ipairs(hazards) do
    local lvl = h.level or 1
    local d = math.max(0, h.at - 120)
    M.later(math.max(0, h.at - 220), function()
      local hw1 = hwAt(t, d)
      place('danger', t, d, hw1 + M.SIDE_PAD_M, 180)
      if lvl >= 2 then place('danger', t, d, -(hw1 + M.SIDE_PAD_M), 180) end
      if lvl >= 3 then
        local d2 = math.max(0, h.at - 220)
        local hw2 = hwAt(t, d2)
        place('danger', t, d2, hw2 + M.SIDE_PAD_M, 180)
        place('danger', t, d2, -(hw2 + M.SIDE_PAD_M), 180)
      end
    end)
  end
end

-- público en las curvas más lentas: cinta y rejillas en el exterior, a 10 m
-- zonas de público: al pasar el coche, ánimos (stage.lua llama a M.cheer)
M.crowdZones = {}
function M.cheer(t, along)
  for _, z in ipairs(M.crowdZones) do
    if not z.done and along >= z.at and along < z.at + 60 then
      z.done = true
      local hw = hwAt(t, z.mid or (z.at + 40))
      place('sndCheer', t, z.mid or (z.at + 40), (z.side or 1) * (hw + 9), 0, 0)
    end
  end
end

function M.spectators(t, notes)
  local slow = {}
  for _, nt in ipairs(notes) do
    if nt.kind == 'corner' and (nt.grade == 'hairpin' or (type(nt.grade) == 'number' and nt.grade <= 2)) and nt.at > 300 and nt.at < t.total - 300 then
      slow[#slow + 1] = nt
    end
  end
  table.sort(slow, function(a, b) return a.deg > b.deg end)
  local used = 0
  for _, nt in ipairs(slow) do
    if used >= M.SPECTATOR_MAX then break end
    local mid = (nt.at + nt.endAt) / 2
    local sideSign = nt.side == 'right' and -1 or 1
    M.crowdZones[#M.crowdZones + 1] = { at = mid - 30, side = sideSign, mid = mid }
    M.later(nt.at, function()
      local hw = hwAt(t, mid)
      for k = -1, 1 do
        place('specTape', t, mid, sideSign * (hw + 6), 0, k * 5 + 2.5, { noCollision = true })
        place('specGrid', t, mid, sideSign * (hw + 8), 0, k * 4)
      end
      -- y unas vallas publicitarias con su público detrás
      fenceLine(t, mid, sideSign * (hw + 10), 4, 6)
      tarpLine(t, mid, sideSign * (hw + 12), 3, 6)
      place('sndCrowd', t, mid, sideSign * (hw + 11), 0, 0)
    end)
    used = used + 1
  end
end

-- Cintas de corte: por cada nodo del grafo de carreteras del juego pegado al trazado, las carreteras que se alejan de
-- él reciben una cinta cruzada a lo ancho, a unos metros del cruce
-- (BeamNG.Earth carga el grafo de carreteras por zonas: stage.lua lo vuelve a llamar en marcha con la ventana por
-- delante del coche; lo ya cortado se recuerda en `doneKeys` hasta el siguiente tramo)
local doneKeys, tapeCount = {}, 0
function M.resetClosures() doneKeys, tapeCount = {}, 0 end
function M.closures(t, from, to)
  local a = api()
  if not (a and map and map.getMap) then return 0 end
  local ok, m = pcall(map.getMap)
  if not ok or not (m and m.nodes) then return 0 end
  from, to = from or 0, to or t.total
  local done, n = doneKeys, 0
  for name, node in pairs(m.nodes) do
    if tapeCount >= M.TAPE_MAX then break end
    local nlat, nlon = a.toGeo(node.pos.x, node.pos.y, node.pos.z)
    if nlat then
      local nx, ny = geo.toLocal(t, nlat, nlon)
      local along, lateral, i = geo.project(t, nx, ny, 1, 0, #t.pts)
      if lateral < 8 and along > 40 and along < t.total - 20 and along >= from and along <= to then
        -- la propia carretera del tramo sale del nodo hacia delante y hacia atrás: esas dos no se cortan nunca (el KMZ va
        -- desplazado de la carretera y en las curvas parecía una calle lateral: cintas en medio del tramo)
        local tdx, tdy = geo.dirAt(t, along)
        local fwdBest, fwdDot, backBest, backDot = nil, 0.5, nil, 0.5
        local fwdXY, backXY = nil, nil
        for other in pairs(node.links or {}) do
          local on = m.nodes[other]
          if on then
            local olat, olon = a.toGeo(on.pos.x, on.pos.y, on.pos.z)
            local ox, oy = geo.toLocal(t, olat, olon)
            local ex, ey = ox - nx, oy - ny
            local l = math.sqrt(ex * ex + ey * ey)
            if l > 0.1 then
              local dt = (ex * tdx + ey * tdy) / l
              if dt > fwdDot then fwdBest, fwdDot, fwdXY = other, dt, { ox, oy } end
              if -dt > backDot then backBest, backDot, backXY = other, -dt, { ox, oy } end
            end
          end
        end
        for other in pairs(node.links or {}) do
          if other == fwdBest or other == backBest then goto nextLink end
          local on = m.nodes[other]
          local key = name < other and (name .. '|' .. other) or (other .. '|' .. name)
          if on and not done[key] then
            done[key] = true
            local olat, olon = a.toGeo(on.pos.x, on.pos.y, on.pos.z)
            local ox, oy = geo.toLocal(t, olat, olon)
            local _, oLat = geo.project(t, ox, oy, i, 20, 20)
            if oLat > 12 then
              -- la calle que sale: dirección (ex, ey) desde el cruce
              local ex, ey = ox - nx, oy - ny
              local l = math.sqrt(ex * ex + ey * ey)
              if l > 4 then
                ex, ey = ex / l, ey / l
                -- la cinta a lo ancho de la lateral (6, 8 o 10 m según su anchura)
                local rw = on.radius or node.radius or 3
                local kind, half = 'tape', 4
                if rw <= 2.6 then kind, half = 'tape6', 3 elseif rw > 3.6 then kind, half = 'tape10', 5 end
                local px, py = ey, -ex
                -- ninguna de sus dos estacas puede quedar en la carretera del tramo (los dos tramos de ella que salen
                -- del cruce): se aleja por la lateral hasta que las dos quedan fuera, o no se pone
                local stageR = (node.radius or 3) + 1.2
                local function clearOfStage(qx, qy)
                  for _, e2 in ipairs({ fwdXY, backXY }) do
                    if e2 then
                      local sx, sy = e2[1] - nx, e2[2] - ny
                      local L2 = sx * sx + sy * sy
                      local u = L2 > 0.01 and math.max(0, math.min(1, ((qx - nx) * sx + (qy - ny) * sy) / L2)) or 0
                      if (qx - nx - sx * u) ^ 2 + (qy - ny - sy * u) ^ 2 < stageR * stageR then return false end
                    end
                  end
                  return (qx - nx) ^ 2 + (qy - ny) ^ 2 >= stageR * stageR
                end
                local d, placed = math.max(rw + 3, lateral + 4), false
                while d <= l * 0.85 and not placed do
                  local cx, cy = nx + ex * d, ny + ey * d
                  if clearOfStage(cx + px * half, cy + py * half) and clearOfStage(cx - px * half, cy - py * half) then
                    -- el origen en un extremo y el largo (-Y) a lo ancho: Y = perpendicular a la calle
                    local lat0, lon0 = geo.toGeo(t, cx + px * half, cy + py * half)
                    -- props.add mide el giro desde (dx, dy): pasamos la perpendicular como dirección y giro 0
                    props.add(kind, lat0, lon0, px, py, 0, { noCollision = false })
                    n, tapeCount, placed = n + 1, tapeCount + 1, true
                  end
                  d = d + 1.5
                end
              end
            end
          end
          ::nextLink::
        end
      end
    end
  end
  if n > 0 then log('I', TAG, ('closures: +%d tapes (%d total)'):format(n, tapeCount)) end
  return n
end

-- El aparcamiento más cercano a (lat, lon) entre 40 m y 1,5 km (Overture, por BeamNG.Earth): el box. cb(lat, lon) o cb()
function M.findBox(lat, lon, cb)
  local a = api()
  if not (a and a.has and a.has('places') and a.places) then cb() return false end
  local done = false
  local ok = a.places(lat, lon, { radius = 1500, categories = { 'parking' }, limit = 12, cachedOnly = true }, function(res)
    if done then return end
    done = true
    local best, bd = nil, math.huge
    for _, p in ipairs(res and res.places or {}) do
      if p.lat and p.lon then
        local k = math.cos(math.rad(lat))
        local d = math.sqrt(((p.lon - lon) * 111195 * k) ^ 2 + ((p.lat - lat) * 111195) ^ 2)
        if d >= 40 and d < bd then best, bd = p, d end
      end
    end
    if best then cb(best.lat, best.lon) else cb() end
  end)
  if not ok then cb() end
  return ok
end

-- Parque de asistencia: carpas 3x6 en el box (el aparcamiento más cercano al control horario); si no hay, junto al TC
function M.service(t, hw)
  local lat0, lon0, dx, dy = at(t, 0, hw + 14, -70)
  local function build(lat, lon)
    local kinds = { 'gazebo3x6', 'gazebo3x6b', 'gazebo3x6r', 'gazebo3x6d' }
    for i = 0, 3 do
      local x, y = geo.toLocal(t, lat, lon)
      local px, py = dy, -dx
      local plat, plon = geo.toGeo(t, x + px * (i * 7), y + py * (i * 7))
      props.add(kinds[i + 1], plat, plon, dx, dy, 90)
    end
  end
  local tcLat, tcLon = at(t, 0, 0, -M.TC_BEFORE_M)
  M.findBox(tcLat, tcLon, function(lat, lon) build(lat or lat0, lon or lon0) end)
end

-- Todo el montaje. Devuelve el reloj de salida y el de meta.
function M.build(t, notes, hazards, splitAt, opts)
  opts = opts or {}
  M.reversed = opts.reversed == true
  M.sounds = opts.sounds == true
  local hw0 = halfWidth(t.lat0, t.lon0)
  local flat, flon = geo.toGeo(t, t.pts[#t.pts][1], t.pts[#t.pts][2])
  local hwF = halfWidth(flat, flon)
  local startClock, finishClock
  M.resetJobs()
  M.crowdZones = {}
  M._t = t
  M.skipped = 0
  local steps = {
    function() M.later(0, function()
      if opts.startLater then pcall(opts.startLater) end
      local obj = M.startLine(t, hwAt(t, 0))
      if opts.onStartClock and obj then pcall(opts.onStartClock, obj) end
    end) end,
    function()
      if opts.finishLater then M.later(t.total, opts.finishLater)
      else finishClock = M.finishLine(t, hwF) end
    end,
    function() M.safety(t, hw0, splitAt) end,
    function() M.arrows(t, notes, hw0) end,
    function() M.cautions(t, hazards, hw0) end,
  }
  if opts.ambience ~= false then
    steps[#steps + 1] = function() M.spectators(t, notes) end
    steps[#steps + 1] = function() M.barriers(t, notes) end
    -- (el parque de asistencia junto al box ya no: no coincidía entre un sentido y otro)
  end
  M.resetClosures()
  if opts.closures ~= false and not M.dry then steps[#steps + 1] = function() M.closures(t) end end
  for _, f in ipairs(steps) do
    local ok, err = pcall(f)
    if not ok then log('W', TAG, 'dressing: ' .. tostring(err)) end
  end
  return startClock, finishClock
end

-- Simulación de un tramo (sin juego para la geometría, sin crear objetos): cuántos objetos de cada clase lleva, con la
-- anchura de calzada por defecto. Sirve para comprobar que todos los tramos tienen la señalización estándar.
function M.simulate(t, notes, hazards, splitAt)
  M.dry, M.counts = true, {}
  local ok, err = pcall(function()
    M.build(t, notes, hazards, splitAt, { ambience = true, closures = false })
    M.runJobs(math.huge)
  end)
  M.dry = false
  local c = M.counts
  M.counts = nil
  if not ok then return nil, err end
  return c
end

return M

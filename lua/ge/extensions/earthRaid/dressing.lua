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
-- NORMA (22-nov, el usuario): los carteles de los dos sentidos van CUADRADOS, espalda con espalda en la misma línea
-- lateral, cada uno mirando hacia el origen de su sentido, con el hueco justo para el sensor entre los dos: el sensor
-- queda tapado desde el tramo en ambos sentidos. Vale para salidas, metas y parciales (siempre con sensor).
M.PAIR_FWD_M = 0.55         -- cada cartel, a esto de la línea (uno antes y otro después): 1,1 m de hueco para el sensor
M.PAIR_OUT_M = 0            -- el del otro sentido, en la misma línea lateral (antes 0,45 m más afuera: descuadrado)
M.SENSOR_SIDE_M = 1.0       -- (22-nov) el sensor, centrado ENTRE los dos carteles (medido: con 0,5 asomaba 0,4 m hacia la calzada)
M.SIGN_YAW = 0             -- todos los carteles de rally del juego: la cara está en -Y (vista en Córdoba SS1: a 180 se
                           -- veían por detrás desde el coche)
M.TREE_FWD_M = 5.5         -- semáforo: por delante de la línea...
M.TREE_SIDE_M = 1.2        -- ... fuera del borde derecho...
M.TREE_YAW = 15            -- ... con el reloj hacia el coche, un poco abierto hacia la carretera
M.RADIO_EVERY_M = 5000
M.SPECTATOR_MAX = 6
M.TAPE_MAX = 120
M.SIDE_PAD_M = 0.5         -- del radio de la carretera a los demás carteles (al final del asfalto)
M.ARROW_MIN_DEG = 40
M.BALES = 3                -- pacas de paja por curva peligrosa
M.SHIFT_TRY = { 4, -4, 8, -8, 12, -12, 18, -18, 25, -25 }

local function api() return rawget(_G, 'beamngEarth_api') end

-- Superficie del tramo (norma FIA: asfalto, tierra/grava, nieve/hielo o mixto). Cambia la anchura supuesta donde el
-- juego no tiene la carretera: una pista de tierra es más estrecha que una carretera asfaltada.
M.surface = 'asphalt'
M.DEFAULT_HW = { asphalt = 3.5, tarmac = 3.5, gravel = 2.75, dirt = 2.75, snow = 3.0, ice = 3.0, mixed = 3.25 }
function M.defaultHalfWidth() return M.DEFAULT_HW[M.surface] or 3.25 end

-- media anchura de la carretera en (lat, lon): del grafo de carreteras del juego si la carretera está ahí mismo (a
-- menos de SNAP_M); si no (un camino que el juego no tiene), la de la superficie del tramo
local function halfWidth(lat, lon)
  local ok, hw = pcall(function()
    local x, y, z = props.ground(lat, lon)
    local n1, n2, d = map.findClosestRoad(vec3(x, y, z))
    if not (d and d < M.SNAP_M) then return nil end
    local m = map.getMap()
    local r1 = n1 and m.nodes[n1] and m.nodes[n1].radius
    local r2 = n2 and m.nodes[n2] and m.nodes[n2].radius
    return math.max(r1 or 0, r2 or 0)
  end)
  if not ok or not hw or hw <= 0 then return M.defaultHalfWidth() end
  return math.max(2.5, math.min(8, hw))
end
M.halfWidth = halfWidth

-- ¿Carretera de doble sentido en lat, lon? (grafo del juego; sin saberlo, sí)
local function twoWay(lat, lon)
  local a = api()
  local ok, r = pcall(function()
    local x, y, z = props.ground(lat, lon)
    local n1, n2 = map.findClosestRoad(vec3(x, y, z))
    local m = map.getMap()
    local l = n1 and n2 and ((m.nodes[n1] and m.nodes[n1].links and m.nodes[n1].links[n2]) or (m.nodes[n2] and m.nodes[n2].links and m.nodes[n2].links[n1]))
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
      -- (sin carretera cargada todavía no se guarda nada: se vuelve a intentar en la siguiente llamada)
      t[key] = sl and { sl, so } or nil
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
  -- 18-nov (Pravia): findClosestRoad daba la carretera de al lado (un cruce, una paralela) y el punto se quedaba en el
  -- trazado del KMZ, desplazado: la línea de salida acababa medio fuera de la calzada. Se busca entre todas las
  -- carreteras cargadas a menos de SNAP_FAR_M la más cercana que vaya en el sentido del tramo
  local ok2, l2, o2, ux2, uy2 = pcall(function()
    local x, y = props.ground(lat, lon)
    if not x then return nil end
    local ix = props.roadIndex()
    if not ix then return nil end
    local C = props.CELL_M
    local best, bd = nil, M.SNAP_FAR_M ^ 2
    local seen = {}
    for gx = math.floor((x - M.SNAP_FAR_M) / C), math.floor((x + M.SNAP_FAR_M) / C) do
      for gy = math.floor((y - M.SNAP_FAR_M) / C), math.floor((y + M.SNAP_FAR_M) / C) do
        for _, sg in ipairs(ix.cells[gx .. ':' .. gy] or {}) do
          if not sg.virtual and not seen[sg] then
            seen[sg] = true
            local sx, sy = sg.bx - sg.ax, sg.by - sg.ay
            local L2 = sx * sx + sy * sy
            if L2 > 0.01 then
              local L = math.sqrt(L2)
              local dot = (sx * dx + sy * dy) / L
              if math.abs(dot) >= 0.5 then
                local u = math.max(0, math.min(1, ((x - sg.ax) * sx + (y - sg.ay) * sy) / L2))
                local cx, cy = sg.ax + sx * u, sg.ay + sy * u
                local dd = (x - cx) ^ 2 + (y - cy) ^ 2
                if dd < bd then
                  local ux, uy = sx / L, sy / L
                  if dot < 0 then ux, uy = -ux, -uy end
                  best, bd = { cx, cy, ux, uy }, dd
                end
              end
            end
          end
        end
      end
    end
    if not best then return nil end
    local la, lo = a.toGeo(best[1], best[2], 0)
    return la, lo, best[3], best[4]
  end)
  if ok2 and l2 then return l2, o2, ux2, uy2 end
  return nil
end
M.SNAP_FAR_M = 22

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
  if t.tcAlong then return t.tcAlong end
  if t.before and t.before.total > 1 then return math.max(60, math.min(M.TC_BEFORE_M, t.before.total)) end
  return M.TC_BEFORE_M
end

-- tras el final del trazado, en línea recta
local function beyond(t, extra, right)
  return at(t, t.total, right, extra)
end

-- ---- edificios: nada se pone si hay un edificio o un muro entre la carretera y su sitio --------------------------------
M.AVOID = { hayBale = true, hayBale2 = true, fenceNgrc = true, fenceBlastr = true, fenceRotopad = true, fenceApm = true, fenceApmSpecial = true,
  specTarp = true, specTarp2 = true, specTarp3 = true, specTape = true, specGrid = true, gazebo3x3 = true, gazebo3x6 = true,
  gazebo3x6b = true, table = true, chair = true, cushion = true, ambulance = true, extinguisher = true }
M.PULL_IN = { start = true, finish = true, tc = true, tcEntry = true, finishEntry = true, stop = true, endArea = true,
  medical = true, medicalWarn = true, radio = true, radioWarn = true, board1 = true, board2 = true, board3 = true,
  danger = true, bendL = true, bendR = true, sensor = true, tree = true }
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
M.CLEAR_M = { hayBale = 1.4, hayBale2 = 1.4, meshBarricade = 0.5, plasticBarrier = 0.8, plasticBarrierW = 0.8, barrel = 0.6, cone = false, coneS = false, coneY = false, tapeY = false, markY = false, lamp = 2.0, sndCrowd = false, sndCheer = false, sndGenerator = false, gazebo3x3 = 2.0, gazebo3x6 = 2.0, gazebo3x6b = 2.0, table = 0.9, chair = 0.9, tree = 0.8,
  cushion = 0.8, ambulance = 1.6, extinguisher = 0.3, laptop = false, specTape = 1.5, specGrid = 1.5, specGridA = 1.5, specGridB = 1.5, specTapeBigA = 1.5, specTapeBigB = 1.5, specTapeBigCenter = 1.5, specTarpAngle = 1.5, meshBarricade = 1.5, specTarp = 2.0, specTarp2 = 2.0, specTarp3 = 2.0 }
local function clearOf(kind)
  local c = M.CLEAR_M[kind]
  if c == false then return nil end
  if c then return c end
  if kind:find('^fence') then return 1.0 end
  return M.SIGN_SIDE_M
end
M.pushed = 0
M.rejected = 0
-- Si (lat, lon) cae en una calzada (o a menos de su margen de la línea de borde de cualquier carretera cargada), se
-- lleva hacia fuera; si al sacarlo de una cae en otra (cruces), se repite; si no hay sitio, nil: no se pone.
-- M._seen: había carreteras cargadas alrededor (la comprobación vale).
local function offRoad(kind, lat, lon)
  local c = clearOf(kind)
  if not c or M.dry or not lat then return lat, lon end
  local a = api()
  local ok, la, lo = pcall(function()
    local x, y, z = props.ground(lat, lon)
    if not x then return lat, lon end
    local ox, oy = x, y
    for _ = 1, 6 do
      local segs = props.roadsAt(x, y)
      if not segs then return lat, lon end
      if #segs > 0 then M._seen = true end
      local worst, wx, wy, wneed, wd = 0, nil, nil, nil, nil
      for _, sg in ipairs(segs) do
        local sx, sy = sg.bx - sg.ax, sg.by - sg.ay
        local L2 = sx * sx + sy * sy
        local u = L2 > 0.01 and math.max(0, math.min(1, ((x - sg.ax) * sx + (y - sg.ay) * sy) / L2)) or 0
        local cx, cy = sg.ax + sx * u, sg.ay + sy * u
        local need = sg.ra + (sg.rb - sg.ra) * u + c
        local d = math.sqrt((x - cx) ^ 2 + (y - cy) ^ 2)
        if need - d > worst + 0.05 then
          worst, wx, wy, wneed, wd = need - d, cx, cy, need, d
          if d < 0.05 then
            -- justo en el eje: hacia la derecha del tramo
            local L = math.sqrt(L2)
            if L > 0.01 then wx, wy, wd = cx - sy / L * 0.05, cy + sx / L * 0.05, 0.05 end
          end
        end
      end
      if not wx then
        if x == ox and y == oy then return lat, lon end
        M.pushed = M.pushed + 1
        return a.toGeo(x, y, z)
      end
      local ex, ey = x - wx, y - wy
      if wd < 0.05 then ex, ey = ex / math.max(wd, 0.01), ey / math.max(wd, 0.01) wd = 1 end
      local k = (wneed + 0.1) / wd
      x, y = wx + ex * k, wy + ey * k
    end
    return false
  end)
  if not ok then return lat, lon end
  if la == false then M.rejected = M.rejected + 1 return nil end
  return la, lo
end
M.offRoad = offRoad

-- Repaso continuo (norma del usuario: "en todo momento"): lo colocado antes de que el juego cargara la carretera de
-- ese sitio se comprueba otra vez cuando el jugador se acerca, y si cae en una calzada se saca fuera. Lo que ya se
-- comprobó con la carretera cargada no se vuelve a mirar.
M.RECHECK_M = 600
M.NEAR_FREEZE_M = 130
-- durante la pantalla de carga sí se recoloca todo (no se ve)
function M.loading()
  -- la auditoría mide con el coche ya junto a la meta: el repaso que al conducir se hace al acercarse se hace ahí
  if M.forceGuard then return true end
  local ok, r = pcall(function() return require('earthRaid/loader').active() end)
  return ok and r == true
end
M.SKIP_RECHECK = { line = true, cone = true, coneS = true, tapeY = true, lamp = true, tape = true, tape6 = true, tape10 = true, sndCrowd = true, sndCheer = true,
  sndGenerator = true }
function M.recheck(plat, plon)
  if M.dry or not plat then return 0 end
  -- el grafo cambió (carreteras nuevas): todo se vuelve a comprobar
  local ix = props.roadIndex()
  if ix and ix.version ~= M._roadVersion then
    M._roadVersion = ix.version
    -- (26-nov, auditoría) también el visto bueno del guardián del borde: con calles nuevas, se vuelve a mirar
    for _, it in ipairs(props.all()) do it.roadOk = nil it.checks = nil it.edgeOk = nil end
  end
  local k = math.cos(math.rad(plat))
  local moved, hidden = 0, 0
  for _, it in ipairs(props.all()) do
    -- (20-nov: lo de un corte —pacas, barreras— va en la calzada a propósito; al cambiar el grafo se borraba su roadOk y
    -- acababan apartadas a los lados, dejando el paso abierto)
    if not it.roadOk and not it.closure and not M.SKIP_RECHECK[it.kind] and it.lat and not it.hidden then
      local ex, ny = (it.lon - plon) * 111195 * k, (it.lat - plat) * 111195
      -- NORMA (22-nov, el usuario: "hay objetos que se mueven mientras me acerco"): nada se recoloca a la vista; lo que
      -- está a menos de NEAR_FREEZE_M del jugador se queda como está
      local d2 = ex * ex + ny * ny
      if d2 < M.RECHECK_M * M.RECHECK_M and (d2 > M.NEAR_FREEZE_M * M.NEAR_FREEZE_M or M.loading()) then
        M._seen = false
        local la, lo = offRoad(it.kind, it.lat, it.lon)
        it.checks = (it.checks or 0) + 1
        if M._seen or it.checks >= 4 then it.roadOk = true end
        if not la then
          -- no cabe fuera de la calzada: se quita
          props.hide(it) hidden = hidden + 1
        elseif la ~= it.lat or lo ~= it.lon then
          props.move(it, la, lo) moved = moved + 1
        end
      end
    end
  end
  -- Última comprobación (21-nov, auditoría): con el grafo ya cargado, lo que haya quedado pisando una calzada medido como
  -- el juego (findClosestRoad: eje y radio del nodo) se aparta; las piezas de una fila (vallas, barreras, pacas) se
  -- quitan, porque desplazadas quedarían encima de sus vecinas. Una vez por objeto y solo cerca. MARK:edge-guard-v1
  local okG, g1, g2 = pcall(M.edgeGuard, plat, plon)
  if okG then moved, hidden = moved + (g1 or 0), hidden + (g2 or 0) end
  if moved + hidden > 0 then log('I', TAG, ('recheck: %d objects moved off the road, %d removed'):format(moved, hidden)) end
  return moved
end
M.EDGE_GUARD_M = 350
M.EDGE_MARGIN_M = 0.45
-- (22-nov, el usuario: «las señales de salida están pegadas a las vallas, deberían estar al borde de la calzada»: el guardián
-- las empujaba de r+0,4 a r+1,05 m.) Los carteles de línea (salida, meta, fin de zona, aviso de meta) se colocan a r+0,4 y
-- ahí se quedan: solo se mueven si de verdad pisan la calzada (r+0,25).
M.EDGE_SIGN = { start = true, finish = true, endArea = true, finishEntry = true }
M.EDGE_SIGN_MARGIN_M, M.EDGE_SIGN_TARGET_M = 0.25, 0.4
M.BOARD_PULL = { start = true, finish = true, stop = true, tc = true, endArea = true, finishEntry = true }
M.BOARD_PULL_MIN_M, M.BOARD_PULL_MAX_M = 2.0, 8.0
-- el puesto de un control o de un médico se coloca con su propia lógica (carpa libre, calle cortada): no se toca
M.POST_KINDS = { gazebo3x3 = true, gazebo3x6 = true, gazebo3x6b = true, table = true, chair = true,
  laptop = true, extinguisher = true, ambulance = true, rallyCar = true, tcEntry = true, tc = true }
M.ROW_KINDS = { plasticBarrier = true, plasticBarrierW = true, hayBale = true, hayBale2 = true,
  fenceNgrc = true, fenceBlastr = true, fenceRotopad = true, fenceApm = true, fenceApmSpecial = true }
function M.edgeGuard(plat, plon)
  local a = api()
  if not (a and map and map.findClosestRoad) then return 0, 0 end
  local m = map.getMap()
  local k = math.cos(math.rad(plat))
  local moved, hidden = 0, 0
  for _, it in ipairs(props.all()) do
    if it.obj and it.lat and not it.edgeOk and not it.hidden and not it.closure and not it.line and not it.park
      and not (it.opts and it.opts.force) and not M.POST_KINDS[it.kind]
      and not M.SKIP_RECHECK[it.kind] and not M.SOUND_KINDS[it.kind] then
      local ex, ny = (it.lon - plon) * 111195 * k, (it.lat - plat) * 111195
      local d2 = ex * ex + ny * ny
      if d2 < M.EDGE_GUARD_M * M.EDGE_GUARD_M and (d2 > M.NEAR_FREEZE_M * M.NEAR_FREEZE_M or M.loading()) then
        local okP, q = pcall(function() return it.obj:getPosition() end)
        if okP and q then
          local n1, n2, dd = map.findClosestRoad(q)
          if n1 and n2 and m.nodes[n1] and m.nodes[n2] then
            -- (se da por bueno solo de cerca, con el grafo de allí ya entero; de lejos se vuelve a mirar)
            if d2 < 300 * 300 then it.edgeOk = true end
            local p1, p2 = m.nodes[n1].pos, m.nodes[n2].pos
            local sx, sy = p2.x - p1.x, p2.y - p1.y
            local L2 = sx * sx + sy * sy
            local u = L2 > 0.01 and math.max(0, math.min(1, ((q.x - p1.x) * sx + (q.y - p1.y) * sy) / L2)) or 0
            local cx, cy = p1.x + sx * u, p1.y + sy * u
            local r1, r2 = m.nodes[n1].radius or 3, m.nodes[n2].radius or 3
            -- (junto a un cruce el radio no baja en línea recta: el del nodo más cercano manda si es mayor)
            local r = math.max(r1 + (r2 - r1) * u, u < 0.5 and r1 or r2)
            local d = math.sqrt((q.x - cx) ^ 2 + (q.y - cy) ^ 2)
            local margin = M.EDGE_SIGN[it.kind] and M.EDGE_SIGN_MARGIN_M or M.EDGE_MARGIN_M
            -- (27-nov, el usuario: «acerca los carteles que están a 4-5 m del borde al límite de la calzada») un cartel de
            -- línea colocado desde un eje del tramo desviado del de la carretera queda lejos del borde: se acerca a r+0,4
            -- (solo entre BOARD_PULL_MIN y BOARD_PULL_MAX m por fuera: más lejos puede ser otra carretera)
            if M.BOARD_PULL[it.kind] and d > r + M.BOARD_PULL_MIN_M and d < r + M.BOARD_PULL_MAX_M then
              local f = (r + M.EDGE_SIGN_TARGET_M) / d
              local nx, ny2 = cx + (q.x - cx) * f, cy + (q.y - cy) * f
              local la, lo = a.toGeo(nx, ny2, q.z)
              if la then
                local la0, lo0 = a.toGeo(q.x, q.y, q.z)
                props.move(it, it.lat + (la - la0), it.lon + (lo - lo0))
                moved = moved + 1
              end
            elseif d < r + margin then
              local row = M.ROW_KINDS[it.kind] or tostring(it.kind):find('^fence')
              if row or d < 0.3 then
                props.hide(it) hidden = hidden + 1
              else
                local f = (r + (M.EDGE_SIGN[it.kind] and M.EDGE_SIGN_TARGET_M or (M.EDGE_MARGIN_M + 0.6))) / d
                local nx, ny2 = cx + (q.x - cx) * f, cy + (q.y - cy) * f
                local la, lo = a.toGeo(nx, ny2, q.z)
                -- (el punto guardado es el del objeto: se desplaza lo mismo que su posición real)
                if la then
                  local la0, lo0 = a.toGeo(q.x, q.y, q.z)
                  props.move(it, it.lat + (la - la0), it.lon + (lo - lo0))
                  moved = moved + 1
                end
              end
            end
          end
        end
      end
    end
  end
  return moved, hidden
end

-- de noche (19:30-7:30 en el reloj del juego): las luces de las carpas solo entonces
function M.night()
  local ok, tod = pcall(function() return core_environment.getTimeOfDay() end)
  if not ok or type(tod) ~= 'table' or not tod.time then return false end
  local h = ((tod.time + 0.5) % 1) * 24
  return h >= 19.5 or h < 7.5
end
M.SOUND_KINDS = { sndCrowd = true, sndCheer = true, sndGenerator = true }

-- Nada grande encima de otra cosa grande (19-nov, norma del usuario: "bien posicionados y con una separación
-- realista"): vallas, carpas y ambulancias guardan una distancia mínima entre sus centros, vengan de la fila que vengan
M.GROUP = { gazebo3x3 = 'tent', gazebo3x6 = 'tent', gazebo3x6b = 'tent', ambulance = 'van', plasticBarrier = 'barrier',
  plasticBarrierW = 'barrier' }
M.MIN_GAP_M = { ['fence|fence'] = 2.45, ['tent|tent'] = 3.3, ['fence|tent'] = 2.2, ['fence|van'] = 3.0, ['tent|van'] = 3.6,
  ['van|van'] = 4.5, ['barrier|barrier'] = 1.1 }
local function groupOf(kind)
  if M.GROUP[kind] then return M.GROUP[kind] end
  if tostring(kind):find('^fence') then return 'fence' end
  return nil
end
function M.tooClose(kind, lat, lon)
  local g = groupOf(kind)
  if not g or M.dry or not lat then return false end
  local k = math.cos(math.rad(lat)) * 111195
  for _, it in ipairs(props.all()) do
    if it.lat and not it.dead and not it.hidden and not it.line then
      local g2 = groupOf(it.kind)
      if g2 then
        local min = M.MIN_GAP_M[g .. '|' .. g2] or M.MIN_GAP_M[g2 .. '|' .. g]
        if min then
          local ex, ny = (it.lon - lon) * k, (it.lat - lat) * 111195
          if ex * ex + ny * ny < min * min then return true end
        end
      end
    end
  end
  return false
end

local function place(kind, t, along, right, yaw, fwd, opts)
  -- sonido de ambiente: solo si el jugador lo activa (por defecto no; el audio se entrecortaba en los tirones)
  -- (22-nov, el usuario: «me he cansado del ruido blanco en la salida») sin sonidos de ambiente propios, nunca
  if M.SOUND_KINDS[kind] then return nil end
  if kind == 'lamp' and not M.dry and not M.night() then return nil end
  local force = opts and opts.force
  if right and math.abs(right) > 0.5 and (M.AVOID[kind] or M.PULL_IN[kind]) and not force then
    local from = opts and opts.from or 0
    local hit = freeTo(t, along, right, fwd, from)
    -- piezas de una fila (vallas, lonas, mallas): si en su sitio hay un árbol o un muro, hueco. Antes se buscaba sitio
    -- unos metros antes o después y caía ENCIMA de sus vecinas (19-nov, Villaviciosa: vallas amontonadas) MARK:rows-v1
    if hit and M.AVOID[kind] and opts and (opts.row or opts.noPush) then M.skipped = M.skipped + 1 return nil end
    if hit and M.AVOID[kind] then
      -- en sitios estrechos (pueblos: casas, muros) se busca hueco unos metros antes o después, y si no, al otro lado,
      -- antes de renunciar (17-nov: las salidas junto a zonas urbanas se quedaban sin carpas ni equipo)
      local moved = false
      for _, sh in ipairs(M.SHIFT_TRY) do
        if not freeTo(t, along + sh, right, fwd, from) then along, hit, moved = along + sh, nil, true break end
      end
      if not moved and not (opts and opts.keepSide) then
        for _, sh in ipairs({ 0, 5, -5, 10, -10 }) do
          if not freeTo(t, along + sh, -right, fwd, from and -from) then
            -- al otro lado, un cartel de frente a la calzada gira 180; el semáforo/reloj (de cara a quien llega por el eje)
            -- se refleja (19-nov: en la meta de Córdoba quedaba de espaldas al coche)
            along, right, yaw, hit, moved = along + sh, -right, (kind == 'tree') and -(yaw or 0) or ((yaw or 0) + 180), nil, true
            break
          end
        end
      end
      if moved then M.shifted = (M.shifted or 0) + 1 end
    end
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
  -- opts.chord (vallas en fila): la pieza se orienta según la fila (la cuerda entre sus vecinas a 1,3 m), no según el eje de
  -- la carretera: en curvas y cruces el eje no es la dirección de la fila (21-nov: vallas de la salida mal orientadas)
  if lat and opts and opts.chord then
    local l1, o1 = at(t, along, right, (fwd or 0) - 1.3)
    local l2, o2 = at(t, along, right, (fwd or 0) + 1.3)
    if l1 and l2 then
      local kk = math.cos(math.rad(lat)) * 111195
      local ex, ny = (o2 - o1) * kk, (l2 - l1) * 111195
      local L = math.sqrt(ex * ex + ny * ny)
      if L > 0.5 then dx, dy = ex / L, ny / L end
    end
  end
  M._seen = false
  local lat0, lon0 = lat, lon
  -- force: se pone donde se pide (el puesto de un control, que siempre tiene que estar: tcPost)
  if not force then lat, lon = offRoad(kind, lat, lon) end
  local seen = M._seen or force
  if not lat then return nil end
  -- piezas de un perímetro (mallas, barreras en fila): si no caben donde toca, no se ponen desplazadas (18-nov, Salas:
  -- junto a un cruce las mallas se iban monte abajo)
  if opts and opts.noPush and lat0 and math.abs(lat - lat0) * 111195 + math.abs(lon - lon0) * 111195 * math.cos(math.rad(lat)) > 0.7 then
    return nil
  end
  if M.dry then
    M.counts[kind] = (M.counts[kind] or 0) + 1
    return { kind = kind, lat = lat, lon = lon }
  end
  if not force and M.tooClose(kind, lat, lon) then M.skipped = M.skipped + 1 return nil end
  local it = props.add(kind, lat, lon, dx, dy, yaw, opts)
  if it and seen then it.roadOk = true end
  return it
end

-- ---- montaje por delante del coche: lo de más allá de la salida se coloca al acercarse (BeamNG.Earth carga carreteras
-- y terreno alrededor del jugador: así la anchura de la calzada, los edificios y la carretera tras la meta son reales)
local jobs = {}
M.JOB_RADIUS_M = 450       -- se monta cuando el jugador está a menos de esto (el grafo de carreteras ya está cargado)
-- t: el tramo (para saber dónde cae el trabajo); atM: metros del tramo (negativo: antes de la salida)
function M.later(atM, fn, t, delayS)
  t = t or M._t
  local j = { at = atM, fn = fn, notBefore = delayS and (os.clockhp() + delayS) or nil }
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
    if near and j.notBefore and os.clockhp() < j.notBefore then near = false end
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

-- Fila de vallas publicitarias a `side` m del eje, de f0 a f1 metros (respecto a `along`). Cada valla mide 2,5 m: van
-- una detrás de otra a FENCE_PITCH_M medidos SOBRE EL TERRENO, no sobre el eje de la carretera (19-nov: por el
-- interior de una curva, 2,6 m de eje son 1,7 m de arcén y se montaban unas sobre otras). Donde no cabe una (un
-- árbol, un muro, una calle que sale), queda el hueco, como en una fila de verdad.
M.FENCE_PITCH_M = 2.75
M.FENCE_KINDS = { 'fenceNgrc', 'fenceBlastr', 'fenceRotopad', 'fenceApm', 'fenceApmSpecial' }
local function fenceRow(t, along, side, f0, f1)
  local step = f1 >= f0 and 0.25 or -0.25
  local yaw = side < 0 and 180 or 0          -- la publicidad mira a la carretera: a la izquierda, girada
  local lx, ly, k, n = nil, nil, nil, 0
  for f = f0, f1, step do
    local la, lo = at(t, along, side, f)
    if la then
      k = k or math.cos(math.rad(la)) * 111195
      local x, y = lo * k, la * 111195
      if not lx or (x - lx) ^ 2 + (y - ly) ^ 2 >= M.FENCE_PITCH_M ^ 2 then
        lx, ly = x, y
        place(M.FENCE_KINDS[n % #M.FENCE_KINDS + 1], t, along, side, yaw, f, { row = true, noPush = true, chord = true })
        n = n + 1
      end
    end
  end
  return n
end

-- lonas de público (4 m, largas en -Y desde su origen) detrás de una fila de vallas
local function tarpLine(t, along, side, n, fwd)
  local kinds = { 'specTarp', 'specTarp2', 'specTarp3' }
  local from = side > 0 and side - 2.5 or side + 2.5
  for i = 0, n - 1 do place(kinds[i % 3 + 1], t, along, side, 0, (fwd or 0) - i * 4, { noCollision = true, from = from, noPush = true }) end
end

-- Conos en la calzada: solo en el eje y solo si es de doble sentido (dividen los dos carriles)
local function centreCones(t, along, fwd, from, to, step)
  local la, lo = at(t, along, 0, fwd)
  if not twoWay(la, lo) then return end
  for k = from, to, step do place('coneS', t, along, 0, 0, fwd + k) end
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

-- El puesto de control horario (TC) a D m por fuera del punto endAlong, en el marco de endPlacer (out = -1: quien
-- ficha viaja en el sentido +fwd del trazado). clockLado: en qué lado va la carpa con el reloj (-1: derecha de quien
-- ficha). full: también el STOP y los carteles de cuenta atrás de quien llega (el extremo de un tramo); sin ello es un
-- TC de enlace (el TC0 a la salida del parque de asistencia).
-- ---- el sitio de la carpa de un control (21-nov, el usuario: "las casetas dentro de los edificios... siempre visibles desde
-- el sentido del tramo"): su planta (3x3) sin ningún edificio, muro ni árbol encima (rayos hacia abajo) y a la vista de
-- quien llega (rayo desde la calzada, 12 m antes, hasta el techo de la carpa). MARK:tent-v1
M.TENT_SEE_M = 12
local function solidAt(x, y, z)
  local ok, d = pcall(castRayStatic, vec3(x, y, z + 25), vec3(0, 0, -1), 40)
  return ok and d ~= nil and d < 24.3
end
-- true: libre; false: ocupado; nil: no hay terreno cargado por ahí (no se puede saber)
local function tentFree(t, along, side, f)
  if M.dry then return true end
  local sgn = side > 0 and 1 or -1
  for _, a0 in ipairs({ -1.7, 0, 1.7 }) do
    for _, l in ipairs({ -1.7, 0, 1.7 }) do
      local la, lo = at(t, along, side + sgn * l, f + a0)
      if not la then return nil end
      local x, y, z = props.ground(la, lo)
      if not x then return nil end
      if solidAt(x, y, z) then return false end
    end
  end
  return true
end
local function tentSeen(t, along, side, f, approachF)
  if M.dry then return true end
  local la0, lo0 = at(t, along, 0, approachF)
  local la1, lo1 = at(t, along, side, f)
  if not (la0 and la1) then return true end
  local x0, y0, z0 = props.ground(la0, lo0)
  local x1, y1, z1 = props.ground(la1, lo1)
  if not (x0 and x1) then return true end
  local dir = vec3(x1 - x0, y1 - y0, (z1 + 1.8) - (z0 + 1.6))
  local d = dir:length()
  if d < 1.5 then return true end
  local ok, h = pcall(castRayStatic, vec3(x0, y0, z0 + 1.6), dir / d, d)
  return not (ok and h and h < d - 1.3)
end

function M.tcPost(t, endAlong, out, hw, D, clockLado, full, forceBooth, twin)
  local put = endPlacer(t, endAlong, out)
  local S, P = hw + M.SIGN_SIDE_M, hw + M.SIDE_PAD_M
  paintLine(t, endAlong, hw, out * D, full and 'stop' or 'tc')
  put('tcEntry', -P, D + M.TC_ENTRY_M, 'in')
  put('tc', -S, D + M.PAIR_FWD_M, 'in')
  if full then
    for i, b in ipairs({ 'board3', 'board2', 'board1' }) do
      local d = D * i / 4
      put(b, P, d, 'out')
      put(b, -P, d, 'out')
    end
    put('stop', S, D - M.PAIR_FWD_M, 'out')
  end
  local cla, clo = at(t, endAlong, 0, out * D)
  local both = twoWay(cla, clo)
  -- el reloj de fichar en la carpa de quien ficha en este sentido: el que sale aquí (TC) o el que llega (STOP)
  -- 18-nov (norma del usuario): UNA sola carpa por control, como en NGRC Rally Utah: dos mesas, la silla del comisario,
  -- el portátil en la mesa y dos extintores (docs/utah_vanilla_scan.json)
  local _ = both
  local g = (type(twin) == 'table' and twin.g) or 2.6
  -- SIEMPRE hay caseta de comisario en un control (19-nov, norma del usuario: el TC0 a la salida de un aparcamiento se
  -- quedaba sin carpa, mesa ni reloj porque no cabían "fuera de toda calzada" entre los pasillos del aparcamiento, y
  -- el control pasaba inadvertido). Se prueba en su lado, en el otro y unos metros antes o después; y si en ningún
  -- sitio cabe, se pone en su lado de todos modos, pegada al borde de la carretera del control. MARK:booth-v1
  local function booth(lado, shift, force)
    local side = out * lado * (hw + g)
    local sgn = side > 0 and 1 or -1
    local ty = sgn > 0 and 180 or 0
    local f = out * D + shift
    local function o(extra)
      if not force then return extra end
      local r = { force = true }
      for k2, v2 in pairs(extra or {}) do r[k2] = v2 end
      return r
    end
    if not place('gazebo3x3', t, endAlong, side, ty, f, o({ keepSide = true })) then return false end
    place('table', t, endAlong, side - sgn * 0.9, ty, f + 0.6, o())
    place('table', t, endAlong, side - sgn * 0.9, ty, f - 0.6, o())
    place('laptop', t, endAlong, side - sgn * 0.9, ty + 180, f + 0.6, o({ dz = 0.75 }))
    place('chair', t, endAlong, side - sgn * 0.3, (sgn > 0 and 0 or 180) + M.CHAIR_YAW, f + 0.6, o())
    -- (26-nov, auditoría: extintores en la calzada cuando la carpa va pegada al borde) los extintores, por detrás de la
    -- carpa, del lado contrario a la carretera
    place('extinguisher', t, endAlong, side + sgn * 1.3, 40, f + 1.2, o())
    place('extinguisher', t, endAlong, side + sgn * 1.3, 250, f - 1.2, o())
    -- de noche, una luz bajo la carpa (de día no se nota)
    place('lamp', t, endAlong, side, 0, f, o({ dz = 2.4 }))
    -- vallas como las de NGRC Rally Utah (mainPrefab, medidas respecto al cartel): una detrás de la carpa junto a la
    -- carretera, otra delante, y una enfrente al otro lado del asfalto. Sin reloj: solo las salidas lo llevan. MARK:tcfence-v1
    local fo = { row = true, noPush = true, chord = true }
    local fy = sgn > 0 and 0 or 180
    place(M.FENCE_KINDS[1], t, endAlong, side - sgn * 0.6, fy, f - 1.9, fo)
    place(M.FENCE_KINDS[2], t, endAlong, side + sgn * 0.7, fy, f + 2.0, fo)
    -- (27-nov) con dos casetas una frente a otra (salida por un lado abierto del aparcamiento) esa valla caería en la otra
    if not (type(twin) == 'table' and twin.noOpposite) then place(M.FENCE_KINDS[3], t, endAlong, -side, fy + 180, f + 2.6, fo) end
    return true
  end
  local done, chosen = false, nil
  -- Los sitios posibles, del más cercano al punto al más lejano (su lado, el otro lado; hasta 23 m a cada lado)
  local cands = {}
  for _, sh in ipairs({ 0, -4, 4, -8, 8, -12, 12, -17, 17, -23, 23 }) do
    cands[#cands + 1] = { clockLado, sh }
    cands[#cands + 1] = { -clockLado, sh }
  end
  -- (22-nov, el usuario marcó las casetas del TC0 de box) escalonadas: la primera antes de la línea de stop a un lado y la
  -- segunda después, al otro (twin = { g, s1, s2 }: separación extra del carril y desplazamientos a lo largo)
  if type(twin) == 'table' and twin.s1 then
    table.insert(cands, 1, { clockLado, twin.s1 })
  end
  local function usable(c, seen)
    local side, f = out * c[1] * (hw + g), out * D + c[2]
    if tentFree(t, endAlong, side, f) == false then return false end
    return not seen or tentSeen(t, endAlong, side, f, out * D - M.TENT_SEE_M)
  end
  -- forceBooth (el TC0 en el pasillo de los boxes): se pone sin las comprobaciones de calzada (dentro de un aparcamiento
  -- los pasillos cuentan como calzada), pero en un sitio libre de edificios y a la vista
  if forceBooth then
    for _, seen in ipairs({ true, false }) do
      for _, c in ipairs(cands) do
        if usable(c, seen) then booth(c[1], c[2], true) done, chosen = true, c[1] break end
      end
      if done then break end
    end
  end
  if not done then
    for _, seen in ipairs({ true, false }) do
      for _, c in ipairs(cands) do
        if usable(c, seen) and booth(c[1], c[2], false) then done, chosen = true, c[1] break end
      end
      if done then break end
    end
  end
  if not done then
    -- ningún sitio libre y a la vista en 23 m: pegada a la calzada en el mejor que no tenga un edificio encima; si ni así,
    -- sin carpa (antes se metía dentro del edificio)
    for _, c in ipairs(cands) do
      if usable(c, false) then booth(c[1], c[2], true) done, chosen = true, c[1] break end
    end
    if not done then log('W', TAG, 'control post: no free place for the tent within 23 m') end
  end
  -- (22-nov, el usuario: el TC0 de los boxes lleva dos casetas, como en NGRC Rally Utah): la segunda, enfrente, al otro lado
  -- de la salida, a la altura de la línea de stop
  if twin and chosen then
    local shs = (type(twin) == 'table' and twin.s2) and { twin.s2, 0, -3, 3, -6, 6 } or { 0, -3, 3, -6, 6 }
    for _, sh in ipairs(shs) do
      if usable({ -chosen, sh }, false) and booth(-chosen, sh, true) then break end
    end
  end
  put('sndGenerator', hw + g + 2.5, D + 1, nil, 0)
  -- (22-nov, el usuario colocó los conos del TC0 con F11) el TC0 lleva 3, juntos, para dejar la salida libre y que ninguno
  -- caiga fuera de la calzada; los demás controles, como antes
  if twin then centreCones(t, endAlong, out * D, -3.5, 3.5, 3.5) else centreCones(t, endAlong, out * D, -10, 10, 5) end
end

M.END_FENCE_IN_M, M.END_FENCE_OUT_M, M.END_FENCE_SIDE_M = 30, 25, 2.2   -- (22-nov) 2,2: los carteles de la línea ya no se meten en las vallas

-- Vallas repetidas (21-nov: "algunas duplicadas"): de cada pareja a menos de minD m, se quita la segunda
function M.dedupeFences(minD)
  minD = minD or 1.6
  local list = {}
  for _, it in ipairs(props.all()) do
    if it.lat and not it.hidden and not it.dead and tostring(it.kind):find('^fence') then list[#list + 1] = it end
  end
  if #list < 2 then return 0 end
  local k = math.cos(math.rad(list[1].lat)) * 111195
  local removed = 0
  for i = 1, #list do
    local a0 = list[i]
    if not a0.hidden then
      for j = i + 1, #list do
        local b = list[j]
        if not b.hidden then
          local ex, ny = (a0.lon - b.lon) * k, (a0.lat - b.lat) * 111195
          if ex * ex + ny * ny < minD * minD then props.hide(b) removed = removed + 1 end
        end
      end
    end
  end
  return removed
end
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
  -- la línea llega hasta el final del asfalto (radio + 0,4 m): ahí, al final de la línea, van los carteles
  paintLine(t, endAlong, hw + 0.6, 0, role == 'start' and 'start' or 'finish')
  -- vallas publicitarias a los dos lados, de 30 m dentro a 25 m fuera, público detrás (y su murmullo)
  -- (21-nov, el usuario: "más pegadas a la calzada, protegiendo la acera de peatones": el borde de la calzada + 1,6 m, no
  -- 3,5 m, que las dejaba contra las fachadas)
  for _, sg in ipairs({ 1, -1 }) do
    local side = out * sg * (hw + M.END_FENCE_SIDE_M)
    -- (26-nov, el usuario: «vallas alineadas, un extremo junto al otro, siguiendo la curva de cruces y aceras, sin cortar
    -- el paso ni cruzarse con objetos o edificios»): por el BORDE REAL de la calzada, como las barreras de las curvas; en
    -- la boca de una calle, hueco. Sin grafo cargado, la fila de antes a partir del eje.
    local a1, a2 = endAlong + math.min(out * -M.END_FENCE_IN_M, out * M.END_FENCE_OUT_M), endAlong + math.max(out * -M.END_FENCE_IN_M, out * M.END_FENCE_OUT_M)
    local okE, done = pcall(M.edgeAdFences, t, a1, a2, side > 0 and 1 or -1, M.END_FENCE_SIDE_M)
    if not (okE and done) then fenceRow(t, endAlong, side, out * -M.END_FENCE_IN_M, out * M.END_FENCE_OUT_M) end
    local tside = out * sg * (hw + M.END_FENCE_SIDE_M + 2.5)
    local from = tside > 0 and tside - 2.5 or tside + 2.5
    for i = 0, 5 do
      local tk = ({ 'specTarp', 'specTarp2', 'specTarp3' })[i % 3 + 1]
      -- las lonas son largas en -Y desde su origen: el origen en su extremo "hacia fuera"
      place(tk, t, endAlong, tside, out > 0 and 0 or 180, out * (-22 + i * 4),
        { noCollision = true, from = from, row = true })
    end
    put('sndCrowd', sg * (hw + 7), -6, nil, 0)
  end

  -- el puesto de control a D m por fuera: TC de quien sale, STOP de quien llega
  if not M.circuit then M.tcPost(t, endAlong, out, hw, D, role == 'start' and -1 or 1, true) end
  -- el médico, con su ambulancia
  put('medical', -P, D + 8, 'out')
  M.medicPost(t, endAlong, -out, out * (D + 16))

  -- según el sentido: el semáforo de salida (5,5 m dentro, a la derecha de quien sale, mirándole) o el reloj de meta
  -- (5,5 m fuera, a la derecha de quien llega); y los ánimos al llegar
  local clock
  if role == 'start' then
    clock = place('tree', t, endAlong, out * -(hw + M.TREE_SIDE_M), M.TREE_YAW + ((out > 0) and 180 or 0), -out * M.TREE_FWD_M)
  else
    -- (sin reloj en la meta ni en los controles: como NGRC Rally Utah, solo las salidas llevan el reloj LED)
    M.crowdZones[#M.crowdZones + 1] = { at = endAlong - 40, mid = endAlong - 6 }
  end
  pcall(M.dedupeFences, 1.6)
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
      -- (22-nov: como los de radio, con lógica en los dos sentidos) cada sentido tiene su preaviso 100 m antes y su
      -- cartel en el punto, a SU derecha y mirándole
      place('medicalWarn', t, math.max(0, d - 100), hwAt(t, d - 100) + M.SIDE_PAD_M, M.SIGN_YAW)
      place('medical', t, d, hwAt(t, d) + M.SIDE_PAD_M, M.SIGN_YAW)
      place('medical', t, d, -(hwAt(t, d) + M.SIDE_PAD_M), M.SIGN_YAW + 180)
      place('medicalWarn', t, math.min(t.total, d + 100), -(hwAt(t, d + 100) + M.SIDE_PAD_M), M.SIGN_YAW + 180)
      -- norma: ambulancia en cada punto médico, aparcada fuera de la calzada pasado el cartel
      M.medicPost(t, d + 15, -1, 0)
    end)
  end
end

-- Perímetro de público con las piezas del juego, puestas una tras otra (18-nov): la central de 4 m (centrada) en medio
-- y a cada lado piezas de 2 m (a y b alternas), hasta cubrir [from, to] metros del tramo; en los extremos, la pieza de
-- esquina (specTarpAngle: 2 m a lo largo y 2 m hacia fuera). kind: 'grid' (malla de 1,15 m) o 'tape' (cinta de 0,7 m).
-- Cada pieza es larga en -Y desde su origen: con giro 0 va hacia atrás, así que se coloca por su extremo delantero.
M.PERIM = {
  grid = { center = 'specGrid', a = 'specGridA', b = 'specGridB' },
  tape = { center = 'specTapeBigCenter', a = 'specTapeBigA', b = 'specTapeBigB' },
}
function M.perimeter(t, from, to, side, kind)
  local P = M.PERIM[kind] or M.PERIM.grid
  from, to = math.max(0, from), math.min(t.total, to)
  if to - from < 2 then return end
  local mid = (from + to) / 2
  local opts = { noCollision = true, noPush = true }
  local n = 0
  if to - from >= 4 then
    place(P.center, t, mid, side, 0, 0, opts) n = n + 1
  end
  local half = (to - from >= 4) and 2 or 0
  -- hacia delante: cada pieza con su extremo trasero en la anterior (origen = extremo delantero, largo en -Y)
  local i = 0
  local a2 = mid + half + 2
  while a2 <= to + 0.01 do
    place(i % 2 == 0 and P.a or P.b, t, a2, side, 0, 0, opts)
    a2, i, n = a2 + 2, i + 1, n + 1
  end
  -- hacia atrás: el origen (extremo delantero) en el extremo trasero de la anterior
  i = 1
  a2 = mid - half
  while a2 - 2 >= from - 0.01 do
    place(i % 2 == 0 and P.a or P.b, t, a2, side, 0, 0, opts)
    a2, i, n = a2 - 2, i + 1, n + 1
  end
  -- esquinas: en los extremos, 2 m hacia fuera (la pieza va 2 m en +X desde el origen: a la derecha con giro 0)
  local out = side > 0 and 1 or -1
  local endF = mid + half + 2 * math.floor((to - mid - half) / 2)
  local endB = mid - half - 2 * math.floor((mid - half - from) / 2)
  place('specTarpAngle', t, endF + 2, side, out > 0 and 0 or 180, 0, opts)
  place('specTarpAngle', t, endB, side, out > 0 and 180 or 0, 0, opts)
  return n
end

-- Salidas peligrosas (18-nov, como NGRC Rally Utah): por el exterior de las curvas lentas tras una recta, de las
-- horquillas y de las que dan a un barranco, una cadena de barreras de plástico rojas (hr_plasticbarrier_red) cada
-- 1,45 m siguiendo el borde; nunca en la calzada (place/offRoad). Las vallas publicitarias quedan solo en salida y meta
-- (pesaban demasiado por el tramo).
M.TAPE_EDGE_M = 0.2           -- la cinta de un corte, a esto por fuera del borde de la carretera del tramo
M.ROW_TRACK_M = 5.5          -- (27-nov) las barreras de detrás de la cinta, a más de esto del eje del trazado
M.TAPE_TRACK_M = 2.0          -- y nunca a menos de esto del eje del trazado (el KML va desplazado 1-2 m de la calzada)
M.BARRIER_MIN_STRAIGHT_M = 120
M.BARRIER_STEP_M = 1.45
M.CLIFF_DROP_M = 3.5          -- el terreno a 6 m por fuera, esto por debajo de la carretera: barranco
local function dropOutside(t, along, side)
  local ok, d = pcall(function()
    local la0, lo0 = at(t, along, 0)
    local la1, lo1 = at(t, along, side)
    local _, _, z0 = props.ground(la0, lo0)
    local _, _, z1 = props.ground(la1, lo1)
    if z0 and z1 then return z0 - z1 end
  end)
  return ok and d or 0
end
M.BARRIER_LEN_M = 1.5          -- hr_plasticbarrier: 1,5 m de largo (eje X) y 0,6 de ancho
M.BARRIER_MAX = 40
M.EDGE_MARCH_M = 20          -- hasta aquí se busca el borde real de la calzada desde el eje del tramo
M.BARRIER_PAD_M = 1.0        -- las barreras, a esto del borde real
M.MESH_PAD_M = 3.0           -- la malla naranja, detrás, a esto del borde real
M.MESH_LEN_M = 10
M.FENCE_NEAR_M = 280        -- las vallas de curva se montan con el jugador a menos de esto (grafo de la zona completo)
-- NORMA (22-nov, el usuario: "las vallas no están rectas ni alineadas, la naranja se cruza con la roja y blanca y no empieza
-- donde termina la anterior; hay vallas bajo la señal del interior de la curva"). El eje del tramo (KML suavizado) corta
-- los cruces en arco y no coincide con la calzada del juego, así que las vallas NO se colocan a partir del eje sino del
-- BORDE REAL de la calzada (grafo de carreteras):
--  1. desde cada punto del eje se avanza hacia el exterior de la curva hasta salir de la calzada: ese es el borde;
--  2. donde no se sale (la boca de una calle que sigue recto: zona de escape o corte) no hay valla: hueco;
--  3. las piezas se encadenan extremo con extremo sobre ese borde desplazado (cuerdas de la longitud de la pieza);
--  4. una pieza que no cabe se omite, nunca se desplaza; y ya colocada no se vuelve a mover (roadOk).
local function onRoadG(x, y, c)
  local segs = props.roadsAt(x, y)
  if not segs then return nil end
  for _, sg in ipairs(segs) do
    local sx, sy = sg.bx - sg.ax, sg.by - sg.ay
    local L2 = sx * sx + sy * sy
    local u = L2 > 0.01 and math.max(0, math.min(1, ((x - sg.ax) * sx + (y - sg.ay) * sy) / L2)) or 0
    local cx, cy = sg.ax + sx * u, sg.ay + sy * u
    local r = math.max(sg.ra + (sg.rb - sg.ra) * u, u < 0.5 and sg.ra or sg.rb)
    if (x - cx) ^ 2 + (y - cy) ^ 2 < (r + c) ^ 2 then return true end
  end
  return false
end
-- tramos continuos del borde real exterior (coordenadas del juego): { {x, y}, ... } por tramo; nil si el grafo de carreteras
-- de la zona aún no está cargado
local function realEdge(t, from, to, sideSign)
  local a = api()
  if not a then return nil end
  local function gp(al)
    local x, y = geo.at(t, al)
    local la, lo = geo.toGeo(t, x, y)
    return a.toGame(la, lo, 0)
  end
  local runs, run, n, seenN = {}, nil, 0, 0
  local a0, a1 = math.max(0, from), math.min(t.total, to)
  local al = a0
  while al <= a1 do
    local x, y = gp(al)
    local x2, y2 = gp(math.min(t.total, al + 1))
    local x1, y1 = gp(math.max(0, al - 1))
    if not (x and x2 and x1) then return nil end
    local dx, dy = x2 - x1, y2 - y1
    local l = math.sqrt(dx * dx + dy * dy)
    n = n + 1
    local e
    if l > 0.1 then
      local nx, ny = sideSign * dy / l, -sideSign * dx / l
      local inside = onRoadG(x, y, 0)
      if inside == nil then return nil end
      local seen = inside
      local s = 0.5
      while s <= M.EDGE_MARCH_M do
        local r = onRoadG(x + nx * s, y + ny * s, 0)
        if r then
          -- con el eje fuera de la calzada (interior de un cruce), la calzada debe empezar cerca
          if not seen and s > 10 then break end
          seen = true
        elseif seen then
          local lo2, hi = s - 0.5, s
          for _ = 1, 6 do
            local mid = (lo2 + hi) / 2
            if onRoadG(x + nx * mid, y + ny * mid, 0) then lo2 = mid else hi = mid end
          end
          e = hi
          break
        end
        s = s + 0.5
      end
      if seen then seenN = seenN + 1 end
      if e then
        local px, py = x + nx * e, y + ny * e
        -- salto entre dos puntos seguidos del borde: el mismo borde si lo que hay entre ellos no es calzada (los rayos se
        -- abren en el ápice); si es calzada (la boca de una calle), el tramo de borde se corta ahí
        if run then
          local lx, ly = run[#run][1], run[#run][2]
          local d2 = (px - lx) ^ 2 + (py - ly) ^ 2
          if d2 > 64 then run = nil
          elseif d2 > 2.25 then
            local mx, my = (px + lx) / 2 + (nx + run[#run][3]) * 0.25, (py + ly) / 2 + (ny + run[#run][4]) * 0.25
            if onRoadG(mx, my, 0) or onRoadG((px + lx) / 2, (py + ly) / 2, -0.3) then run = nil end
          end
        end
        if not run then run = {} runs[#runs + 1] = run end
        -- (puntos casi repetidos fuera: los rayos de un arco convergen)
        if #run == 0 or (px - run[#run][1]) ^ 2 + (py - run[#run][2]) ^ 2 > 0.04 then run[#run + 1] = { px, py, nx, ny } end
      else
        run = nil
      end
    end
    al = al + 1
  end
  if n == 0 or seenN < n * 0.5 then return nil end
  -- los extremos de cada tramo que hacen un quiebro (el rayo rozó una esquina) se recortan
  for _, r in ipairs(runs) do
    for _ = 1, 3 do
      if #r >= 4 then
        local function turn(p, q, s2) local ux, uy, vx, vy = q[1] - p[1], q[2] - p[2], s2[1] - q[1], s2[2] - q[2]
          return (ux * vx + uy * vy) / math.max(0.001, math.sqrt((ux * ux + uy * uy) * (vx * vx + vy * vy))) end
        if turn(r[1], r[2], r[3]) < 0.87 then table.remove(r, 1) end
        if #r >= 4 and turn(r[#r - 2], r[#r - 1], r[#r]) < 0.87 then table.remove(r) end
      end
    end
  end
  return runs
end
-- el tramo de borde desplazado `pad` m hacia fuera, perpendicular a él (no en la dirección del rayo)
local function offsetRun(run, pad)
  local P = {}
  for i, p in ipairs(run) do
    local p0, p1 = run[i - 1] or p, run[i + 1] or p
    local tx, ty = p1[1] - p0[1], p1[2] - p0[2]
    local l = math.sqrt(tx * tx + ty * ty)
    if l > 0.01 then
      local nx, ny = ty / l, -tx / l
      if nx * p[3] + ny * p[4] < 0 then nx, ny = -nx, -ny end
      P[#P + 1] = { p[1] + nx * pad, p[2] + ny * pad }
    end
  end
  return P
end
-- piezas de longitud L encadenadas extremo con extremo a lo largo de la polilínea P: cb(cx, cy, dx, dy) por pieza; si cb
-- devuelve false se acaba
local function chordChain(P, L, cb)
  if #P < 2 then return end
  local ax, ay = P[1][1], P[1][2]
  local px, py = ax, ay
  local i = 2
  -- el punto de la polilínea a `len` m (en línea recta) de (ax, ay), avanzando desde el estado (i, px, py)
  local function reach(len, i0, px0, py0)
    local j, ux, uy = i0, px0, py0
    while j <= #P do
      local qx, qy = P[j][1], P[j][2]
      if (qx - ax) ^ 2 + (qy - ay) ^ 2 < len * len then
        ux, uy = qx, qy
        j = j + 1
      else
        local lo2, hi = 0, 1
        for _ = 1, 14 do
          local mid = (lo2 + hi) / 2
          local mx, my = ux + (qx - ux) * mid, uy + (qy - uy) * mid
          if (mx - ax) ^ 2 + (my - ay) ^ 2 < len * len then lo2 = mid else hi = mid end
        end
        return ux + (qx - ux) * hi, uy + (qy - uy) * hi, j
      end
    end
    return nil
  end
  while true do
    local bx, by, j = reach(L, i, px, py)
    if not bx then return end
    local r = cb((ax + bx) / 2, (ay + by) / 2, (bx - ax) / L, (by - ay) / L)
    if r == false then return end
    if r == 'skip' then
      -- no cabe: la cadena vuelve a empezar 1 m más allá (no un largo entero: el hueco, lo justo)
      bx, by, j = reach(1.0, i, px, py)
      if not bx then return end
    end
    ax, ay, px, py, i = bx, by, bx, by, j
  end
end
-- barreras rojas y blancas + malla naranja por el borde real exterior. Devuelve false si el grafo aún no está (reintentar).
local function edgeFences(t, from, to, sideSign)
  if M.dry then
    M.counts.plasticBarrier = (M.counts.plasticBarrier or 0) + math.min(M.BARRIER_MAX, math.floor((to - from) / 1.52))
    M.counts.meshBarricade = (M.counts.meshBarricade or 0) + math.floor((to - from) / M.MESH_LEN_M)
    return true
  end
  local runs = realEdge(t, from, to, sideSign)
  if not runs then return false end
  local a = api()
  local nB = 0
  local function put(kind, cx, cy, dx, dy, yaw, opts, clear)
    -- la pieza entera fuera de toda calzada: el centro y los dos extremos
    local h = (kind == 'meshBarricade' and M.MESH_LEN_M or M.BARRIER_LEN_M) / 2
    if onRoadG(cx, cy, clear) or onRoadG(cx + dx * h, cy + dy * h, clear * 0.5) or onRoadG(cx - dx * h, cy - dy * h, clear * 0.5) then
      M.skipped = M.skipped + 1
      return 'skip'
    end
    local z = core_terrain and core_terrain.getTerrainHeight and core_terrain.getTerrainHeight(vec3(cx, cy, 0)) or 0
    local la, lo = a.toGeo(cx, cy, z)
    if not la then return nil end
    local it = props.add(kind, la, lo, dx, dy, yaw, opts)
    if it then it.roadOk = true end
    return it
  end
  for _, run in ipairs(runs) do
    if #run >= 2 then
      chordChain(offsetRun(run, M.BARRIER_PAD_M), M.BARRIER_LEN_M + 0.02, function(cx, cy, dx, dy)
        if nB >= M.BARRIER_MAX then return false end
        if put((nB + 1) % 2 == 1 and 'plasticBarrier' or 'plasticBarrierW', cx, cy, dx, dy, 90, nil, 0.35) == 'skip' then return 'skip' end
        nB = nB + 1
      end)
      chordChain(offsetRun(run, M.MESH_PAD_M), M.MESH_LEN_M, function(cx, cy, dx, dy)
        if put('meshBarricade', cx, cy, dx, dy, 0, { noCollision = true }, 0.3) == 'skip' then return 'skip' end
      end)
    end
  end
  return true
end
M.edgeFences = edgeFences

-- Vallas publicitarias de salida/meta por el borde real (26-nov, MARK:ad-fences-edge-v1): piezas de FENCE_PITCH_M
-- encadenadas extremo con extremo a `pad` m del borde; una pieza que pisaría calzada, un edificio u otro objeto se omite
-- (nunca se desplaza) y la cadena sigue 1 m más allá. Devuelve false si el grafo no está (se usa la fila de siempre).
M.AD_FENCE_CLEAR_M = 1.1
function M.edgeAdFences(t, from, to, sideSign, pad)
  if M.dry then return false end
  local runs = realEdge(t, from, to, sideSign)
  if not runs or #runs == 0 then return false end
  local a = api()
  local others = {}
  for _, it in ipairs(props.all()) do
    if it.lat and not tostring(it.kind):find('^fence') and not tostring(it.kind):find('^snd') and it.kind ~= 'line' then
      local x, y = a.toGame(it.lat, it.lon, 0)
      if x then others[#others + 1] = { x, y } end
    end
  end
  local function blocked(x, y)
    if onRoadG(x, y, 0.3) then return true end
    for _, o in ipairs(others) do
      if (o[1] - x) ^ 2 + (o[2] - y) ^ 2 < M.AD_FENCE_CLEAR_M ^ 2 then return true end
    end
    -- un edificio o un muro: algo sólido por encima del suelo
    local g = props.trueGround and props.trueGround(x, y) or nil
    if g then
      local okR, d = pcall(castRayStatic, vec3(x, y, g + 25), vec3(0, 0, -1), 30)
      if okR and type(d) == 'number' and d < 24.2 then return true end
    end
    return false
  end
  local n, yaw = 0, sideSign > 0 and 0 or 180
  local half = M.FENCE_PITCH_M / 2
  for _, run in ipairs(runs) do
    if #run >= 2 then
      chordChain(offsetRun(run, pad), M.FENCE_PITCH_M, function(cx, cy, dx, dy)
        if blocked(cx, cy) or blocked(cx + dx * half, cy + dy * half) or blocked(cx - dx * half, cy - dy * half) then
          M.skipped = M.skipped + 1
          return 'skip'
        end
        local la, lo = a.toGeo(cx, cy, 0)
        if not la then return 'skip' end
        local it = props.add(M.FENCE_KINDS[n % #M.FENCE_KINDS + 1], la, lo, dx, dy, yaw, { row = true, noPush = true })
        if it then it.roadOk = true n = n + 1 end
      end)
    end
  end
  return n > 0
end
function M.barriers(t, notes)
  local prevEnd = 0
  for _, nt in ipairs(notes) do
    if nt.kind == 'corner' then
      local slow = nt.grade == 'hairpin' or nt.grade == 'square' or (type(nt.grade) == 'number' and nt.grade <= 2)
      local fast = type(nt.grade) == 'number' and nt.grade >= 3
      local straight = nt.at - prevEnd
      if nt.at > 150 and nt.endAt < t.total - 150 then
        local mid = (nt.at + nt.endAt) / 2
        local sideSign = nt.side == 'right' and -1 or 1
        local byStraight = slow and (straight >= M.BARRIER_MIN_STRAIGHT_M or nt.grade == 'hairpin')
        M.later(nt.at, function()
          local hw = hwAt(t, mid)
          local cliff = dropOutside(t, mid, sideSign * (hw + 6)) > M.CLIFF_DROP_M
          if byStraight or (cliff and (slow or fast)) then
            -- por el borde REAL de la calzada; si el grafo de la zona aún no está cargado, se reintenta (hasta 90 s)
            -- NORMA (22-nov): el grafo llega por partes; a 400 m aún está incompleto y el borde salía mal (vallas en el
            -- interior del cruce). Las vallas se montan con el jugador a menos de FENCE_NEAR_M y con el grafo estable
            -- (misma versión que 2 s antes); mientras tanto se reintenta.
            local tries, lastV = 0, nil
            local function fences()
              local ready = M.dry
              if not ready then
                local a = api()
                local pl, po = a.position()
                local la, lo = at(t, nt.at, 0, 0)
                local ix = props.roadIndex()
                local near = pl and la and ((po - lo) * 111195 * math.cos(math.rad(la))) ^ 2 + ((pl - la) * 111195) ^ 2 < M.FENCE_NEAR_M ^ 2
                local v = ix and ix.version
                ready = near and v ~= nil and v == lastV
                lastV = near and v or nil
              end
              if not ready then M.later(nt.at, fences, t, 2.0) return end
              if not edgeFences(t, nt.at - 4, (nt.endAt or nt.at) + 8, sideSign) then
                tries = tries + 1
                if tries < 45 then M.later(nt.at, fences, t, 2.0) end
              end
            end
            fences()
            -- y por el lado interior (la idea del usuario, 22-nov: vallas a ambos lados de la curva de cruce)
            -- señal de curva peligrosa antes de la curva, en el exterior del lado de llegada
            if slow then
              -- (22-nov, el usuario: la señal debe estar ANTES de la curva y de las vallas, con antelación para frenar desde
              -- una recta larga): 60-110 m antes del inicio de la curva según la recta, en su propio trabajo
              local lead = math.min(110, math.max(60, straight - 15))
              local sa = math.max(0, nt.at - 4 - lead)
              M.later(sa, function()
                place(nt.side == 'right' and 'bendR' or 'bendL', t, sa, sideSign * (hwAt(t, sa) + M.SIDE_PAD_M), 180)
              end)
            end
            -- y detrás, el perímetro blando: la malla naranja de 10 m del juego siguiendo el borde (una pieza cada
            -- 10 m, centrada; si no cabe sin moverla, no se pone)
          end
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
        -- (22-nov, el usuario: un poste/señal en el ápice de la curva de cruce): ni flecha ni colchones donde hay un cruce
        if not M.dry then
          local la0, lo0 = at(t, along, side, 0)
          local a0 = api()
          local okJ, junc = pcall(function()
            local gx, gy = a0.toGame(la0, lo0, 0)
            local m = map.getMap()
            for name, node in pairs(m.nodes) do
              if (node.pos.x - gx) ^ 2 + (node.pos.y - gy) ^ 2 < 22 * 22 then
                local d = 0
                for _ in pairs(props.neighbors(name)) do d = d + 1 end
                if d >= 3 then return true end
              end
            end
            return false
          end)
          if okJ and junc then return end
        end
        -- cara del modelo en -X: hacia el coche que llega y un poco hacia la carretera
        local yaw = side > 0 and -60 or -120
        place(kind, t, along, side, yaw, 0)
        -- una segunda flecha más adelante en las horquillas
        if nt.grade == 'hairpin' or nt.deg > 120 then
          place(kind, t, math.min(t.total, along + 12), side, yaw, 0)
        end
        -- en las curvas más peligrosas (horquillas, escuadras, 1 y 2), protección donde se saldría el coche: colchones
        -- a la salida, por fuera, como en los rallies del juego; nunca en la calzada (offRoad las aparta)
        local danger = nt.grade == 'hairpin' or nt.grade == 'square' or (type(nt.grade) == 'number' and nt.grade <= 2)
        if danger and M.protection ~= false then
          for k = 0, M.BALES - 1 do
            local a2 = math.min(t.total, along + 4 + k * 2.6)
            local s2 = sideSign * (hwAt(t, a2) + 2.2)
            -- colchones de seguridad del rally del juego (las pacas de paja salían sin textura: 18-nov)
            place('cushion', t, a2, s2, 90, 0)
          end
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
      -- el peligro en sí (carretera abrupta, mal generada): conos grandes amarillos a rayas y cinta amarilla en las dos
      -- cunetas (el amarillo es de peligros y obras; el naranja, del trazado). Nunca sobre la calzada
      for _, sd in ipairs({ 1, -1 }) do
        local hwh = hwAt(t, h.at) + 1.0
        for _, off in ipairs({ -12, -6, 0 }) do place('coneY', t, math.max(0, h.at + off), sd * hwh, 0) end
        place('markY', t, math.max(0, h.at - 10), sd * (hwh + 0.8), 90)
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

M.SPECTATOR_FENCES = false
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
      -- NORMA (22-nov, el usuario: "vallas mal colocadas en la calzada y confundiendo; todos los objetos alineados y con un
      -- mismo patrón, no formatos diferentes"): el perímetro de público (cinta, mallas, lonas y esquinas, otro formato y
      -- medido desde el eje) queda fuera; en las curvas solo va el patrón único de M.barriers (barreras + malla naranja
      -- sobre el borde real). Se conserva el sonido de público.
      if not M.SPECTATOR_FENCES then place('sndCrowd', t, mid, sideSign * (hwAt(t, mid) + 11), 0, 0) return end
      local hw = hwAt(t, mid)
      -- pegadas al borde para que se vean (18-nov): la cinta a 2,5 m, el perímetro de mallas a 3,5 m y las lonas detrás
      for k = -1, 1 do
        place('specTape', t, mid, sideSign * (hw + 2.5), 0, k * 5 + 2.5, { noCollision = true })
      end
      M.perimeter(t, mid - 7, mid + 7, sideSign * (hw + 3.5), 'grid')
      M.perimeter(t, mid - 15, mid - 7, sideSign * (hw + 3.5), 'tape')
      M.perimeter(t, mid + 7, mid + 15, sideSign * (hw + 3.5), 'tape')
      tarpLine(t, mid, sideSign * (hw + 5.5), 3, 6)
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
function M.resetClosures() doneKeys, tapeCount = {}, 0 M.medicQueue = nil end
-- Calles que salen de un nodo contando como uno solo los nodos a menos de 3 m (cruces partidos): { nombre = true }, y el
-- nombre canónico del grupo (el menor)
local function farNb(name)
  local ok, mp = pcall(map.getMap)
  local nodes = ok and mp and mp.nodes or {}
  local group, queue, canon = { [name] = true }, { name }, name
  local out = {}
  local qi = 1
  while qi <= #queue and qi < 12 do
    local cur = queue[qi]
    qi = qi + 1
    local cn = nodes[cur]
    for o in pairs(props.neighbors(cur)) do
      local on = nodes[o]
      if on and cn then
        local d = math.sqrt((on.pos.x - cn.pos.x) ^ 2 + (on.pos.y - cn.pos.y) ^ 2)
        if d < 3 then
          if not group[o] then group[o] = true queue[#queue + 1] = o if o < canon then canon = o end end
        else out[o] = true end
      end
    end
  end
  for g in pairs(group) do out[g] = nil end
  return out, canon
end
function M.closures(t, from, to)
  local a = api()
  if not (a and map and map.getMap) then return 0 end
  local ok, m = pcall(map.getMap)
  if not ok or not (m and m.nodes) then return 0 end
  from, to = from or 0, to or t.total
  local done, n = doneKeys, 0
  for name, node in pairs(m.nodes) do
    local nlat, nlon = a.toGeo(node.pos.x, node.pos.y, node.pos.z)
    if nlat then
      local nx, ny = geo.toLocal(t, nlat, nlon)
      local along, lateral, i = geo.project(t, nx, ny, 1, 0, #t.pts)
      if lateral < 8 and along > 40 and along < t.total - 20 and along >= from and along <= to then
        -- la propia carretera del tramo sale del nodo hacia delante y hacia atrás: esas dos no se cortan nunca (el KMZ va
        -- desplazado de la carretera y en las curvas parecía una calle lateral: cintas en medio del tramo)
        -- la dirección del tramo justo antes y justo después del nodo (en una horquilla la de "en el nodo" ya apunta a la
        -- salida y la calle de atrás se confundía con la que sigue recto: Salas, 18-nov)
        local tdx, tdy = geo.dirAt(t, math.min(t.total, along + 12))
        local bdx, bdy = geo.dirAt(t, math.max(0, along - 12))
        -- 18-nov (Pravia: cortes en mitad del tramo): solo los cruces de verdad (3 o más calles) llevan corte, y la
        -- carretera del tramo es siempre la mejor alineada hacia delante y hacia atrás, por cerrada que sea la curva
        -- un cruce suele venir partido en varios nodos a ~1 m (Umeå, 22-nov): se agrupan y se miran solo las calles que
        -- salen del grupo (a más de 3 m), con un único nombre para todo el grupo (canon)
        local NB, canon = farNb(name)
        local degree = 0
        for _ in pairs(NB) do degree = degree + 1 end
        if degree < 3 then goto nextNode end
        local fwdBest, fwdDot, backBest, backDot = nil, -2, nil, -2
        local fwdXY, backXY = nil, nil
        for other in pairs(NB) do
          local on = m.nodes[other]
          if on then
            local olat, olon = a.toGeo(on.pos.x, on.pos.y, on.pos.z)
            local ox, oy = geo.toLocal(t, olat, olon)
            local ex, ey = ox - nx, oy - ny
            local l = math.sqrt(ex * ex + ey * ey)
            if l > 0.1 then
              local dt = (ex * tdx + ey * tdy) / l
              local db = -(ex * bdx + ey * bdy) / l
              if dt > fwdDot then fwdBest, fwdDot, fwdXY = other, dt, { ox, oy } end
              if db > backDot then backBest, backDot, backXY = other, db, { ox, oy } end
            end
          end
        end
        -- cruce donde el tramo gira y otra calle sigue recto (zona que confunde, 18-nov): flecha de dirección en la boca
        -- de la que sigue recto, mirando a quien llega
        if fwdXY and backXY and not doneKeys['arrow|' .. canon] then
          local ix, iy = nx - backXY[1], ny - backXY[2]
          local il = math.sqrt(ix * ix + iy * iy)
          local fx, fy = fwdXY[1] - nx, fwdXY[2] - ny
          local fl = math.sqrt(fx * fx + fy * fy)
          if il > 0.5 and fl > 0.5 then
            ix, iy, fx, fy = ix / il, iy / il, fx / fl, fy / fl
            local turn = ix * fx + iy * fy                 -- < 0.8: el tramo gira más de ~37 grados en el cruce
            if turn < 0.8 then
              for other in pairs(NB) do
                local on = m.nodes[other]
                if on and other ~= fwdBest and other ~= backBest then
                  local olat, olon = a.toGeo(on.pos.x, on.pos.y, on.pos.z)
                  local ox, oy = geo.toLocal(t, olat, olon)
                  local sx, sy = ox - nx, oy - ny
                  local sl = math.sqrt(sx * sx + sy * sy)
                  if sl > 0.5 and (sx * ix + sy * iy) / sl > 0.85 then
                    doneKeys['arrow|' .. canon] = true
                    local right = (ix * fy - iy * fx) < 0
                    -- en la esquina entre la calle que sigue recto y la salida del tramo (fuera de las dos calzadas)
                    local bx2, by2 = sx / sl + fx, sy / sl + fy
                    local bl2 = math.sqrt(bx2 * bx2 + by2 * by2)
                    if bl2 < 0.1 then break end
                    local rw2 = ((node.radius or 3) + 2.5) * 1.5
                    local ax, ay = nx + bx2 / bl2 * rw2, ny + by2 / bl2 * rw2
                    local al, ao = offRoad('cornerR', geo.toGeo(t, ax, ay))
                    if al then props.add(right and 'cornerR' or 'cornerL', al, ao, ix, iy, -90) end
                    -- zona de escape (18-nov, Salas: curva muy cerrada tras un salto y el coche acababa por la calle
                    -- que sigue recto): pacas redondas y cuadradas cruzando la boca de esa calle y detrás una fila
                    -- de barreras de plástico rojas y blancas
                    if turn < 0.8 then
                      -- esta calle ya queda cerrada por la zona de escape: sin cinta de corte encima
                      doneKeys[canon < other and (canon .. '|' .. other) or (other .. '|' .. canon)] = true
                      local ux, uy = sx / sl, sy / sl
                      local qx, qy = -uy, ux
                      local w = (on.radius or 3)
                      local d0 = (node.radius or 3) + 5
                      -- pacas cuadradas (1,8 x 2,5 m) cruzadas: el lado largo a lo ancho de la calle (20-nov, el usuario:
                      -- estaban a lo largo, giradas 90°), y una segunda fila encima a tresbolillo. MARK:bales-across-v1
                      local kinds = {}
                      -- 0,8 m más a cada lado que el radio de la calle: sin hueco por el que quepa un coche junto al bordillo
                      local wb = w + 0.8
                      local nb = math.max(2, math.floor((2 * wb) / 2.6 + 0.5))
                      local stepB = (2 * wb - 2.6) / math.max(1, nb - 1)
                      for i = 0, nb - 1 do
                        local off = -wb + 1.3 + i * stepB
                        kinds[#kinds + 1] = { 'hayBale2', off, 0, 0 }
                        if i < nb - 1 then kinds[#kinds + 1] = { 'hayBale', off + stepB / 2, 0, 1.15 } end
                      end
                      for _, k in ipairs(kinds) do
                        local bx, by = nx + ux * (d0 + k[3]) + qx * k[2], ny + uy * (d0 + k[3]) + qy * k[2]
                        local bl, bo = geo.toGeo(t, bx, by)
                        -- la paca con su lado largo (Y, 2,5 m) a lo ancho de la calle y el corto (1,8 m) en su sentido
                        local it3 = props.add(k[1], bl, bo, ux, uy, 90, k[4] > 0 and { dz = k[4] } or nil)
                        if it3 then it3.roadOk = true it3.closure = true end
                      end
                      local nB = 0
                      for off = -w + 0.8, w - 0.8, 1.58 do
                        local bx, by = nx + ux * (d0 + 2.7) + qx * off, ny + uy * (d0 + 2.7) + qy * off
                        local bl, bo = geo.toGeo(t, bx, by)
                        local it3 = props.add(nB % 2 == 0 and 'plasticBarrier' or 'plasticBarrierW', bl, bo, qx, qy, 90)
                        if it3 then it3.roadOk = true it3.closure = true end
                        nB = nB + 1
                      end
                    end
                    break
                  end
                end
              end
            end
          end
        end
        -- (los cortes con cinta tienen un tope por tramo; las flechas y zonas de escape de arriba, no)
        if tapeCount >= M.TAPE_MAX then goto nextNode end
        for other in pairs(NB) do
          if other == fwdBest or other == backBest then goto nextLink end
          local on = m.nodes[other]
          local key = canon < other and (canon .. '|' .. other) or (other .. '|' .. canon)
          if on and not done[key] then
            done[key] = true
            local olat, olon = a.toGeo(on.pos.x, on.pos.y, on.pos.z)
            local ox, oy = geo.toLocal(t, olat, olon)
            local _, oLat = geo.project(t, ox, oy, i, 20, 20)
            -- (22-nov, el usuario: "el acceso a la línea de salida está cortado con una cinta"): la calle de llegada al
            -- tramo (el enlace t.before hasta el TC1) nunca se corta
            local onApproach = false
            if t.before and t.before.pts and #t.before.pts > 1 then
              local bx, by = geo.toLocal(t.before, olat, olon)
              local _, dB = geo.project(t.before, bx, by, 1, 0, #t.before.pts)
              onApproach = dB < 10
            end
            if oLat > 12 and not onApproach then
              -- la calle que sale: dirección (ex, ey) desde el cruce
              local ex, ey = ox - nx, oy - ny
              local l = math.sqrt(ex * ex + ey * ey)
              if l > 4 then
                ex, ey = ex / l, ey / l
                -- la cinta a lo ancho de la lateral (6, 8 o 10 m según su anchura)
                local rw = on.radius or node.radius or 3
                -- NORMA (22-nov, el usuario: "la cinta no corta la calle; ponla en la boca, horizontal, y justo detrás las vallas
                -- rojas y blancas"): la calzada que se ve es más ancha que el radio del grafo y su eje va algo desplazado, así
                -- que la cinta sobra ~1 m por cada lado (6 m solo para sendas), va en la BOCA de la calle (pegada al borde de
                -- la carretera del tramo) y detrás lleva una fila de barreras de lado a lado con el bidón.
                local kind, half = 'tape10', 5
                if rw <= 1.9 then kind, half = 'tape6', 3 elseif rw <= 2.6 then kind, half = 'tape', 4 end
                local px, py = ey, -ex
                -- ninguna de sus dos estacas puede quedar en la carretera del tramo (los dos tramos de ella que salen
                -- del cruce): se aleja por la lateral hasta que las dos quedan fuera, o no se pone
                -- ESTÁNDAR de corte (22-nov, colocado a mano por el usuario): la cinta pegada al borde de la carretera del tramo
                -- (M.TAPE_EDGE_M por fuera del radio del cruce), no calle adentro
                local stageR = (node.radius or 3) + M.TAPE_EDGE_M
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
                -- en la boca de la calle (18-nov, Pravia: aparecía decenas de metros calle arriba): como mucho 12 m más
                local d, placed = stageR, false
                local dMax = math.min(l * 0.85, d + 14)
                while d <= dMax and not placed do
                  local cx, cy = nx + ex * d, ny + ey * d
                  -- y lejos del trazado del tramo (estacas y centro): nunca una cinta cruzando el tramo
                  local function farFromTrack(qx, qy)
                    -- (22-nov: el tramo pasa dos veces por la misma calle: se mira contra TODO el trazado, no solo cerca de este punto)
                    local _, lat2 = geo.project(t, qx, qy, 1, 0, #t.pts)
                    return lat2 > M.TAPE_TRACK_M
                  end
                  -- centrada en el eje real de la calle (el cruce son varios nodos juntos y la dirección desde su centro
                  -- deja la cinta 1-2 m a un lado)
                  pcall(function()
                    local la, lo = geo.toGeo(t, cx, cy)
                    local gx, gy, gz = a.toGame(la, lo, 0)
                    local n1, n2 = map.findClosestRoad(vec3(gx, gy, on.pos.z))
                    local A, B = n1 and m.nodes[n1], n2 and m.nodes[n2]
                    if not (A and B) then return end
                    local sx, sy = B.pos.x - A.pos.x, B.pos.y - A.pos.y
                    local L2 = sx * sx + sy * sy
                    if L2 < 1 or math.abs(sx * ex + sy * ey) / math.sqrt(L2) < 0.85 then return end
                    local u = ((gx - A.pos.x) * sx + (gy - A.pos.y) * sy) / L2
                    local la2, lo2 = a.toGeo(A.pos.x + sx * u, A.pos.y + sy * u, on.pos.z)
                    if la2 then cx, cy = geo.toLocal(t, la2, lo2) end
                  end)
                  if clearOfStage(cx + px * half, cy + py * half) and clearOfStage(cx - px * half, cy - py * half)
                    and farFromTrack(cx + px * half, cy + py * half) and farFromTrack(cx - px * half, cy - py * half)
                    and farFromTrack(cx, cy) then
                    -- el origen en un extremo y el largo (-Y) a lo ancho: Y = perpendicular a la calle
                    local lat0, lon0 = geo.toGeo(t, cx + px * half, cy + py * half)
                    -- props.add mide el giro desde (dx, dy): pasamos la perpendicular como dirección y giro 0
                    local itT = props.add(kind, lat0, lon0, px, py, 0, { noCollision = false })
                    if itT then itT.closure = true end
                    -- y detrás, el corte como en los rallies del juego: dos barreras de plástico rojas y un bidón
                    if M.protection ~= false then
                      -- a lo ancho de la calle (el largo de la barrera, eje X, en la dirección de la cinta)
                      local row = {}
                      local nb = math.max(2, math.floor((2 * rw + 3) / 1.52 + 0.5))
                      for i = 1, nb do row[#row + 1] = { (i - (nb + 1) / 2) * 1.52, i % 2 == 1 and 'plasticBarrier' or 'plasticBarrierW', 1.3 } end
                      row[#row + 1] = { 0, 'barrel', 2.4 }
                      for _, b in ipairs(row) do
                        local bx, by = cx + ex * b[3] + px * b[1], cy + ey * b[3] + py * b[1]
                        -- (27-nov, pasada de la IA en el shakedown: a 104 km/h se llevó la fila de un corte cuyas barreras
                        -- de los extremos quedaban a 3,5 m del eje del tramo) la fila es más ancha que la cinta: una pieza
                        -- que caiga cerca del trazado no se pone (la misma distancia que exige la cinta)
                        local _, latB = geo.project(t, bx, by, 1, 0, #t.pts)
                        if latB > M.ROW_TRACK_M then
                          local bl, bo = geo.toGeo(t, bx, by)
                          -- en la calle cortada a propósito: no se vuelve a comprobar contra la calzada
                          local it2 = props.add(b[2], bl, bo, px, py, b[2] == 'barrel' and 0 or 90)
                          if it2 then it2.roadOk = true it2.closure = true end
                        end
                      end
                    end
                    n, tapeCount, placed = n + 1, tapeCount + 1, true
                  end
                  d = d + 0.5
                end
              end
            end
          end
          ::nextLink::
        end
      end
    end
    ::nextNode::
  end
  if n > 0 then log('I', TAG, ('closures: +%d tapes (%d total)'):format(n, tapeCount)) end
  return n
end

-- ---- puesto médico -------------------------------------------------------------------------------------------------------
-- Norma (19-nov, el usuario): la ambulancia no puede ser un estorbo. Si junto al punto médico sale una calle (un cruce a
-- menos de MEDIC_SEARCH_M), el puesto va DENTRO de esa calle, que se corta: cinta en la boca, la ambulancia detrás
-- mirando al tramo (lista para salir) y, más adentro, la carpa con la mesa, la silla y los extintores del comisario.
-- Si no hay calle, la ambulancia va fuera de la calzada con toda su planta (6,2 x 2,4 m) libre de cualquier carretera;
-- y si no cabe en ningún lado, no se pone. MARK:medic-v1
M.MEDIC_SEARCH_M = 160   -- (21-nov: el puesto médico siempre en la calle lateral más cercana si la hay, también un callejón sin salida)
M.VAN_HALF_LEN_M, M.VAN_HALF_WID_M = 3.1, 1.2

-- ¿la planta de un vehículo (centro x, y; dirección ux, uy; medias medidas) queda fuera de todas las calzadas?
-- true / false; nil si no hay carreteras cargadas por ahí (no se puede saber)
local function footprintClear(x, y, ux, uy, halfLen, halfWid, margin)
  local px, py = uy, -ux
  local any = false
  for _, c in ipairs({ { 0, 0 }, { 1, 1 }, { 1, -1 }, { -1, 1 }, { -1, -1 }, { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
    local qx, qy = x + ux * halfLen * c[1] + px * halfWid * c[2], y + uy * halfLen * c[1] + py * halfWid * c[2]
    local segs = props.roadsAt(qx, qy)
    if not segs then return nil end
    for _, sg in ipairs(segs) do
      any = true
      local sx, sy = sg.bx - sg.ax, sg.by - sg.ay
      local L2 = sx * sx + sy * sy
      local u = L2 > 0.01 and math.max(0, math.min(1, ((qx - sg.ax) * sx + (qy - sg.ay) * sy) / L2)) or 0
      local d = math.sqrt((qx - sg.ax - sx * u) ^ 2 + (qy - sg.ay - sy * u) ^ 2)
      if d < sg.ra + (sg.rb - sg.ra) * u + (margin or 0.4) then return false end
    end
  end
  if not any then
    local ix = props.roadIndex()
    if not (ix and #ix.segs > 0) then return nil end
  end
  return true
end
M.footprintClear = footprintClear

-- dirección del juego (ux, uy) en (x, y) -> dirección este/norte (la que usa props.add)
local function geoDirOf(a, x, y, z, ux, uy)
  local la0, lo0 = a.toGeo(x, y, z)
  local la1, lo1 = a.toGeo(x + ux * 10, y + uy * 10, z)
  local k = math.cos(math.rad(la0)) * 111195
  local ex, ny = (lo1 - lo0) * k, (la1 - la0) * 111195
  local l = math.sqrt(ex * ex + ny * ny)
  if l < 0.01 then return 0, 1 end
  return ex / l, ny / l
end

-- una calle desde el cruce `from` por el vecino `to`: polilínea { {x, y, z, r, d} } hasta maxM metros
local function walkStreet(m, from, to, maxM)
  local p0 = m.nodes[from].pos
  local pts = { { p0.x, p0.y, p0.z, m.nodes[from].radius or 3, 0 } }
  local seen, prev, cur, L = { [from] = true }, from, to, 0
  while cur and m.nodes[cur] and L < maxM do
    local q, pp = m.nodes[cur].pos, m.nodes[prev].pos
    local hx, hy = q.x - pp.x, q.y - pp.y
    local hl = math.sqrt(hx * hx + hy * hy)
    L = L + hl
    pts[#pts + 1] = { q.x, q.y, q.z, m.nodes[cur].radius or 3, L }
    seen[cur] = true
    if hl < 0.1 then break end
    local best, bd = nil, 0.6
    for nb in pairs(props.neighbors(cur)) do
      if not seen[nb] and m.nodes[nb] then
        local r = m.nodes[nb].pos
        local vx, vy = r.x - q.x, r.y - q.y
        local vl = math.sqrt(vx * vx + vy * vy)
        if vl > 0.1 then
          local dot = (vx * hx + vy * hy) / (vl * hl)
          if dot > bd then best, bd = nb, dot end
        end
      end
    end
    prev, cur = cur, best
  end
  return pts, L
end
local function streetAt(pts, d)
  for i = 2, #pts do
    if pts[i][5] >= d or i == #pts then
      local a0, b0 = pts[i - 1], pts[i]
      local l = b0[5] - a0[5]
      local u = l > 0.01 and math.max(0, math.min(1, (d - a0[5]) / l)) or 0
      local ux, uy = b0[1] - a0[1], b0[2] - a0[2]
      local ul = math.sqrt(ux * ux + uy * uy)
      if ul < 0.01 then return nil end
      return a0[1] + (b0[1] - a0[1]) * u, a0[2] + (b0[2] - a0[2]) * u, a0[3] + (b0[3] - a0[3]) * u, ux / ul, uy / ul,
        a0[4] + (b0[4] - a0[4]) * u
    end
  end
  return nil
end

-- ¿(lat, lon) está lejos del tramo y de sus accesos? (una "calle lateral" que es el propio tramo no vale)
local function farFromStage(t, lat, lon, minM)
  for _, tr in ipairs({ t, t.after, t.before }) do
    if tr and tr.pts and #tr.pts >= 2 then
      local x, y = geo.toLocal(tr, lat, lon)
      local _, lateral = geo.project(tr, x, y, 1, 0, #tr.pts)
      if lateral and lateral < minM then return false end
    end
  end
  return true
end

-- side: +1 a la derecha del sentido del trazado, -1 a la izquierda (lado preferido si no hay calle)
function M.medicPost(t, along, side, fwd)
  if M.dry then M.counts.ambulance = (M.counts.ambulance or 0) + 1 return true end
  local a = api()
  local la, lo, dx, dy = at(t, along, 0, fwd)
  if not la then return false end
  -- (26-nov, MARK:user-medic-v1) la ambulancia donde la puso el usuario en el paquete (medicPoint = {lat, lon, latHacia,
  -- lonHacia}: el sitio y hacia dónde mira), si este punto médico está cerca (Trans Sierra Nevada SS1: en el callejón)
  local mp = t.medicPoint
  if type(mp) == 'table' and mp[1] and not t._medicUsed then
    local kk0 = math.cos(math.rad(mp[1])) * 111195
    local dd = math.sqrt(((mp[1] - la) * 111195) ^ 2 + ((mp[2] - lo) * kk0) ^ 2)
    if dd < 300 then
      t._medicUsed = true
      local hx, hy = 0, 1
      if mp[3] then
        hx, hy = (mp[4] - mp[2]) * kk0, (mp[3] - mp[1]) * 111195
        local hl = math.sqrt(hx * hx + hy * hy)
        if hl > 0.01 then hx, hy = hx / hl, hy / hl else hx, hy = 0, 1 end
      end
      local it = props.add('ambulance', mp[1], mp[2], hx, hy, 0)
      -- en una calle que el usuario eligió para ella (cortada a propósito, como las del puesto médico)
      if it then it.roadOk = true it.closure = true end
      log('I', TAG, 'medical post: the ambulance where the user set it')
      return it ~= nil
    end
  end
  local x, y, z = props.ground(la, lo)
  if not x then return false end
  -- (22-nov, el usuario: "la ambulancia no está donde estaba, me corta el paso"): si las carreteras de alrededor aún no están
  -- cargadas, no se busca calle ni hueco (acababa en medio de la calzada): se aplaza hasta que haya grafo (M.pumpMedic)
  if not M._medicRetry then
    local near = false
    pcall(function()
      for _, n in pairs(map.getMap().nodes) do
        if (n.pos.x - x) ^ 2 + (n.pos.y - y) ^ 2 < 120 * 120 then near = true break end
      end
    end)
    if not near then
      M.medicQueue = M.medicQueue or {}
      M.medicQueue[#M.medicQueue + 1] = { t = t, along = along, side = side, fwd = fwd, at = os.clock() }
      return true
    end
  end
  -- la dirección del tramo en coordenadas del juego
  local kk = math.cos(math.rad(la)) * 111195
  local x2, y2 = a.toGame(la + dy * 10 / 111195, lo + dx * 10 / kk, 0)
  local gx, gy = x2 - x, y2 - y
  local gl = math.sqrt(gx * gx + gy * gy)
  if gl < 0.01 then return false end
  gx, gy = gx / gl, gy / gl

  -- 1) una calle que salga cerca: el puesto dentro de ella, cortada
  local okS, placed = pcall(function()
    local m = map.getMap()
    if not (m and m.nodes) then return false end
    local best, bs = nil, 1e9
    for name, node in pairs(m.nodes) do
      local ex, ey = node.pos.x - x, node.pos.y - y
      local al, lt = ex * gx + ey * gy, math.abs(ex * gy - ey * gx)
      if math.abs(al) <= M.MEDIC_SEARCH_M and lt < 8 and math.abs(al) < bs then
        local deg = 0
        for _ in pairs(props.neighbors(name)) do deg = deg + 1 end
        if deg >= 3 then
          for other in pairs(props.neighbors(name)) do
            local pts, L = walkStreet(m, name, other, 45)
            if L >= 30 then
              local qx, qy, qz, ux, uy = streetAt(pts, 6)
              local fx, fy, fz = streetAt(pts, 24)
              if qx and fx and math.abs(ux * gx + uy * gy) < 0.5 then
                local fla, flo = a.toGeo(fx, fy, fz)
                -- (22-nov, el usuario: el acceso a la línea de salida cortado con cinta): nunca la calle del enlace de llegada
                local onAppr = false
                if t.before and t.before.pts and #t.before.pts > 1 then
                  for _, d in ipairs({ 20, 30 }) do
                    local ax, ay, az = streetAt(pts, d)
                    if ax then
                      local al, ao = a.toGeo(ax, ay, az)
                      local lx, ly = geo.toLocal(t.before, al, ao)
                      local _, dB = geo.project(t.before, lx, ly, 1, 0, #t.before.pts)
                      if dB < 6 then onAppr = true end   -- la calle va POR el enlace (no solo nace junto a él)
                    end
                  end
                end
                if farFromStage(t, fla, flo, 28) and not onAppr then
                  best, bs = { name = name, other = other, pts = pts, node = node }, math.abs(al)
                end
              end
            end
          end
        end
      end
    end
    if not best then return false end
    local pts, node = best.pts, best.node
    local function add(kind, d, across, yaw, flip, opts)
      local px, py, pz, ux, uy = streetAt(pts, d)
      if not px then return nil end
      local qx, qy = px + uy * across, py - ux * across
      local pl, po = a.toGeo(qx, qy, pz)
      local ex, ny = geoDirOf(a, qx, qy, pz, flip and -ux or ux, flip and -uy or uy)
      local it = props.add(kind, pl, po, ex, ny, yaw or 0, opts)
      if it then it.roadOk = true it.closure = true end
      return it
    end
    local rw = select(6, streetAt(pts, 8)) or 3
    local d0 = math.max(rw + 3, (node.radius or 3) + 3.5)
    -- la cinta en la boca (si los cortes del tramo no la han puesto ya), con sus barreras y su bidón
    local key = best.name < best.other and (best.name .. '|' .. best.other) or (best.other .. '|' .. best.name)
    if not doneKeys[key] then
      doneKeys[key] = true
      local kind, half = 'tape', 4
      if rw <= 2.6 then kind, half = 'tape6', 3 elseif rw > 3.6 then kind, half = 'tape10', 5 end
      local px, py, pz, ux, uy = streetAt(pts, d0)
      -- el origen de la cinta en un extremo y su largo a lo ancho de la calle (como en M.closures)
      local ox, oy = px + uy * half, py - ux * half
      local pl, po = a.toGeo(ox, oy, pz)
      local ex, ny = geoDirOf(a, ox, oy, pz, uy, -ux)
      local itT = props.add(kind, pl, po, ex, ny, 0, { noCollision = false })
      if itT then itT.closure = true end
      add('plasticBarrier', d0 + 2.2, -1.9, 90)
      add('plasticBarrierW', d0 + 2.2, 1.9, 90)
      add('barrel', d0 + 2.2, 0, 0)
    end
    -- la ambulancia en el centro de la calle, mirando al tramo
    if not add('ambulance', d0 + 8.5, 0, 0, true) then return false end
    -- la carpa del comisario más adentro, a un lado de la calle, con su mesa, silla y extintores
    local off = math.max(0, rw - 1.7)
    add('gazebo3x3', d0 + 17, off, 0)
    add('table', d0 + 17, off - 0.6, 0)
    add('chair', d0 + 17, off + 0.3, M.CHAIR_YAW)
    add('extinguisher', d0 + 15.6, off - 1.2, 40)
    add('extinguisher', d0 + 15.4, off - 0.8, 250)
    add('coneS', d0 + 4.4, -1.4, 0)
    add('coneS', d0 + 4.4, 1.4, 0)
    log('I', TAG, ('medical post in a closed side street, %.0f m from the point'):format(bs))
    return true
  end)
  if not okS then log('W', TAG, 'medicPost: ' .. tostring(placed)) end
  if okS and placed then return true end

  -- 2) sin calle: fuera de la calzada, con toda la planta libre; si no cabe, no se pone
  local hw = halfWidth(la, lo)
  local unknown = false
  for _, sgn in ipairs({ side or -1, -(side or -1) }) do
    for _, extra in ipairs({ 3.0, 3.8, 4.6, 5.6 }) do
      local r = sgn * (hw + extra)
      if not freeTo(t, along, r + sgn * M.VAN_HALF_WID_M, fwd, sgn * (hw + 0.3)) then
        local pla, plo, pdx, pdy = at(t, along, r, fwd)
        local px, py, pz = props.ground(pla, plo)
        if px then
          local x3, y3 = a.toGame(pla + pdy * 10 / 111195, plo + pdx * 10 / kk, 0)
          local ux, uy = x3 - px, y3 - py
          local ul = math.sqrt(ux * ux + uy * uy)
          if ul > 0.01 then
            local clear = footprintClear(px, py, ux / ul, uy / ul, M.VAN_HALF_LEN_M, M.VAN_HALF_WID_M, 0.5)
            if clear == nil then unknown = true end
            if clear and not M.tooClose('ambulance', pla, plo) then
              local it = props.add('ambulance', pla, plo, pdx, pdy, 0)
              if it then it.roadOk = true end
              return it ~= nil
            end
          end
        end
      end
    end
  end
  if unknown then
    -- sin carreteras cargadas todavía: en su sitio de siempre; el repaso continuo la saca de la calzada al acercarse
    return place('ambulance', t, along, (side or -1) * (hw + 3.2), 0, fwd, { keepSide = true }) ~= nil
  end
  log('I', TAG, 'medical post: no room for the ambulance off the road, not placed')
  return false
end

-- los puestos médicos aplazados por falta de grafo: se montan en cuanto hay carreteras cargadas cerca (o a los 90 s, como estén)
function M.pumpMedic()
  local q = M.medicQueue
  if not q or #q == 0 then return end
  local keep = {}
  for _, e in ipairs(q) do
    local la, lo = at(e.t, e.along, 0, 0)
    local x, y = props.ground(la, lo)
    local near = false
    if x then
      pcall(function()
        for _, n in pairs(map.getMap().nodes) do
          if (n.pos.x - x) ^ 2 + (n.pos.y - y) ^ 2 < 120 * 120 then near = true break end
        end
      end)
    end
    if near or os.clock() - e.at > 90 then
      M._medicRetry = true
      pcall(M.medicPost, e.t, e.along, e.side, e.fwd)
      M._medicRetry = nil
    else
      keep[#keep + 1] = e
    end
  end
  M.medicQueue = keep
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
-- superficie a una de las categorías FIA (asphalt, gravel, snow, mixed)
function M.normSurface(sf)
  sf = tostring(sf or ''):lower()
  if sf:find('mix') or sf:find('mixto') then return 'mixed' end
  if sf:find('snow') or sf:find('nieve') or sf:find('ice') or sf:find('hielo') then return 'snow' end
  if sf:find('grav') or sf:find('tierra') or sf:find('dirt') or sf:find('terra') or sf:find('off') or sf:find('track') then return 'gravel' end
  return 'asphalt'
end

function M.build(t, notes, hazards, splitAt, opts)
  opts = opts or {}
  M.surface = M.normSurface(opts.surface)
  M.reversed = opts.reversed == true
  M.sounds = false
  M.circuit = opts.circuit == true   -- circuito cerrado: parrilla y bandera, sin control horario ni STOP
  local hw0 = halfWidth(t.lat0, t.lon0)
  local flat, flon = geo.toGeo(t, t.pts[#t.pts][1], t.pts[#t.pts][2])
  local hwF = halfWidth(flat, flon)
  local startClock, finishClock
  M.resetJobs()
  M.crowdZones = {}
  M._t = t
  M.skipped = 0
  local steps = {
    function()
      -- (21-nov) el control y la salida esperan a que el grafo de carreteras de allí esté cargado (hasta 20 s): con el
      -- coche recién llegado al sitio el TC caía en la rama equivocada (una calle sin salida) y ya no se movía. MARK:start-wait-v1
      local tries = 0
      local function startJob()
        if opts.startReady and not M.dry and tries < 40 then
          local okR, ready = pcall(opts.startReady)
          if okR and not ready then tries = tries + 1 M.later(0, startJob, t, 1.0) return end
        end
        if opts.startLater then pcall(opts.startLater) end
        local obj = M.startLine(t, hwAt(t, 0))
        if opts.onStartClock and obj then pcall(opts.onStartClock, obj) end
      end
      M.later(0, startJob)
    end,
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

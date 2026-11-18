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
M.CLEAR_M = { hayBale = 2.3, hayBale2 = 1.4, meshBarricade = 0.5, plasticBarrier = 0.8, plasticBarrierW = 0.8, barrel = 0.6, cone = false, lamp = 2.0, sndCrowd = false, sndCheer = false, sndGenerator = false, gazebo3x3 = 2.0, gazebo3x6 = 2.0, gazebo3x6b = 2.0, table = 0.9, chair = 0.9, tree = 0.8,
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
M.RECHECK_M = 300
M.SKIP_RECHECK = { line = true, cone = true, lamp = true, tape = true, tape6 = true, tape10 = true, sndCrowd = true, sndCheer = true,
  sndGenerator = true }
function M.recheck(plat, plon)
  if M.dry or not plat then return 0 end
  -- el grafo cambió (carreteras nuevas): todo se vuelve a comprobar
  local ix = props.roadIndex()
  if ix and ix.version ~= M._roadVersion then
    M._roadVersion = ix.version
    for _, it in ipairs(props.all()) do it.roadOk = nil it.checks = nil end
  end
  local k = math.cos(math.rad(plat))
  local moved, hidden = 0, 0
  for _, it in ipairs(props.all()) do
    if not it.roadOk and not M.SKIP_RECHECK[it.kind] and it.lat and not it.hidden then
      local ex, ny = (it.lon - plon) * 111195 * k, (it.lat - plat) * 111195
      if ex * ex + ny * ny < M.RECHECK_M * M.RECHECK_M then
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
  if moved + hidden > 0 then log('I', TAG, ('recheck: %d objects moved off the road, %d removed'):format(moved, hidden)) end
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
            along, right, yaw, hit, moved = along + sh, -right, (yaw or 0) + 180, nil, true
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
  M._seen = false
  local lat0, lon0 = lat, lon
  lat, lon = offRoad(kind, lat, lon)
  local seen = M._seen
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
  for i = 0, n - 1 do place(kinds[i % 3 + 1], t, along, side, 0, (fwd or 0) - i * 4, { noCollision = true, from = from, noPush = true }) end
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
  -- 18-nov (norma del usuario): UNA sola carpa por control, como en NGRC Rally Utah: dos mesas, la silla del comisario,
  -- el portátil en la mesa y dos extintores (docs/utah_vanilla_scan.json)
  local _ = both
  local lados = { clockLado }
  local g = 2.6
  for _, lado in ipairs(lados) do
    local side = out * lado * (hw + g)
    local sgn = side > 0 and 1 or -1
    local ty = sgn > 0 and 180 or 0
    place('gazebo3x3', t, endAlong, side, ty, out * D)
    place('table', t, endAlong, side - sgn * 0.9, ty, out * D + 0.6)
    place('table', t, endAlong, side - sgn * 0.9, ty, out * D - 0.6)
    place('laptop', t, endAlong, side - sgn * 0.9, ty + 180, out * D + 0.6, { dz = 0.75 })
    place('chair', t, endAlong, side - sgn * 0.3, (sgn > 0 and 0 or 180) + M.CHAIR_YAW, out * D + 0.6)
    place('extinguisher', t, endAlong, side - sgn * 1.2, 40, out * D + 1.5)
    place('extinguisher', t, endAlong, side - sgn * 1.5, 250, out * D + 1.6)
    -- de noche, una luz bajo la carpa (de día no se nota)
    place('lamp', t, endAlong, side, 0, out * D, { dz = 2.4 })
    place('tree', t, endAlong, side - sgn * 1.3, sgn > 0 and 90 or -90, out * D - 1.4)
  end
  put('sndGenerator', hw + g + 2.5, D + 1, nil, 0)
  centreCones(t, endAlong, out * D, -10, 10, 5)
  -- el médico, con su ambulancia
  put('medical', -P, D + 8, 'out')
  put('ambulance', -(P + 2.6), D + 16, 'out')

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
      -- norma: ambulancia en cada punto médico, aparcada fuera de la calzada pasado el cartel
      place('ambulance', t, d + 15, -(hwAt(t, d + 15) + 3.0), 0)
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
M.BARRIER_MIN_STRAIGHT_M = 120
M.BARRIER_STEP_M = 1.45
M.BARRIER_MAX = 24
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
local function barrierChain(t, from, to, sideSign)
  -- el largo de la barrera (eje X) a lo largo del borde: giro 90; rojas y blancas alternas; cada pieza a
  -- BARRIER_LEN + 0,08 m de la anterior medido sobre la curva del borde (en el interior de una curva los puntos se
  -- juntan y se solapaban, 18-nov)
  local n, lx, ly = 0, nil, nil
  local a2, aEnd = math.max(0, from), math.min(t.total, to)
  while a2 <= aEnd and n < M.BARRIER_MAX do
    local r = sideSign * (hwAt(t, a2) + 1.0)
    local x, y = geo.at(t, a2)
    local dx, dy = geo.dirAt(t, a2)
    local px, py = x + dy * r, y - dx * r
    if not lx or (px - lx) ^ 2 + (py - ly) ^ 2 >= (M.BARRIER_LEN_M + 0.08) ^ 2 then
      if place(n % 2 == 0 and 'plasticBarrier' or 'plasticBarrierW', t, a2, r, 90, 0, { noPush = true }) then
        lx, ly, n = px, py, n + 1
      end
    end
    a2 = a2 + 0.25
  end
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
            barrierChain(t, nt.at - 4, (nt.endAt or nt.at) + 8, sideSign)
            -- y detrás, el perímetro blando: la malla naranja de 10 m del juego siguiendo el borde (una pieza cada
            -- 10 m, centrada; si no cabe sin moverla, no se pone)
            local from, to = nt.at - 4, (nt.endAt or nt.at) + 8
            for a3 = from + 5, to - 5, 10 do
              place('meshBarricade', t, a3, sideSign * (hwAt(t, a3) + 3.0), 0, 0, { noCollision = true, noPush = true })
            end
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
        -- 18-nov (Pravia: cortes en mitad del tramo): solo los cruces de verdad (3 o más calles) llevan corte, y la
        -- carretera del tramo es siempre la mejor alineada hacia delante y hacia atrás, por cerrada que sea la curva
        local degree = 0
        for _ in pairs(props.neighbors(name)) do degree = degree + 1 end
        if degree < 3 then goto nextNode end
        local fwdBest, fwdDot, backBest, backDot = nil, -2, nil, -2
        local fwdXY, backXY = nil, nil
        for other in pairs(props.neighbors(name)) do
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
        -- cruce donde el tramo gira y otra calle sigue recto (zona que confunde, 18-nov): flecha de dirección en la boca
        -- de la que sigue recto, mirando a quien llega
        if fwdXY and backXY and not doneKeys['arrow|' .. name] then
          local ix, iy = nx - backXY[1], ny - backXY[2]
          local il = math.sqrt(ix * ix + iy * iy)
          local fx, fy = fwdXY[1] - nx, fwdXY[2] - ny
          local fl = math.sqrt(fx * fx + fy * fy)
          if il > 0.5 and fl > 0.5 then
            ix, iy, fx, fy = ix / il, iy / il, fx / fl, fy / fl
            local turn = ix * fx + iy * fy                 -- < 0.8: el tramo gira más de ~37 grados en el cruce
            if turn < 0.8 then
              for other in pairs(props.neighbors(name)) do
                local on = m.nodes[other]
                if on and other ~= fwdBest and other ~= backBest then
                  local olat, olon = a.toGeo(on.pos.x, on.pos.y, on.pos.z)
                  local ox, oy = geo.toLocal(t, olat, olon)
                  local sx, sy = ox - nx, oy - ny
                  local sl = math.sqrt(sx * sx + sy * sy)
                  if sl > 0.5 and (sx * ix + sy * iy) / sl > 0.85 then
                    doneKeys['arrow|' .. name] = true
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
                    if turn < 0.55 then
                      local ux, uy = sx / sl, sy / sl
                      local qx, qy = -uy, ux
                      local w = (on.radius or 3)
                      local d0 = (node.radius or 3) + 5
                      local kinds = { { 'hayBale', -w + 0.3, 0 }, { 'hayBale2', w - 1.2, 0 }, { 'hayBale2', w - 1.2, 1.3 } }
                      for _, k in ipairs(kinds) do
                        local bx, by = nx + ux * (d0 + k[3]) + qx * k[2], ny + uy * (d0 + k[3]) + qy * k[2]
                        local bl, bo = geo.toGeo(t, bx, by)
                        local it3 = props.add(k[1], bl, bo, ux, uy, 90)
                        if it3 then it3.roadOk = true it3.closure = true end
                      end
                      local nB = 0
                      for off = -w + 0.8, w - 0.8, 1.58 do
                        local bx, by = nx + ux * (d0 + 3.2) + qx * off, ny + uy * (d0 + 3.2) + qy * off
                        local bl, bo = geo.toGeo(t, bx, by)
                        local it3 = props.add(nB % 2 == 0 and 'plasticBarrier' or 'plasticBarrierW', bl, bo, ux, uy, 90)
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
        for other in pairs(props.neighbors(name)) do
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
                -- en la boca de la calle (18-nov, Pravia: aparecía decenas de metros calle arriba): como mucho 12 m más
                local d, placed = math.max(rw + 3, lateral + 4), false
                local dMax = math.min(l * 0.85, d + 12)
                while d <= dMax and not placed do
                  local cx, cy = nx + ex * d, ny + ey * d
                  -- y lejos del trazado del tramo (estacas y centro): nunca una cinta cruzando el tramo
                  local function farFromTrack(qx, qy)
                    local _, lat2 = geo.project(t, qx, qy, i, 30, 30)
                    return lat2 > stageR + 2
                  end
                  if clearOfStage(cx + px * half, cy + py * half) and clearOfStage(cx - px * half, cy - py * half)
                    and farFromTrack(cx + px * half, cy + py * half) and farFromTrack(cx - px * half, cy - py * half)
                    and farFromTrack(cx, cy) then
                    -- el origen en un extremo y el largo (-Y) a lo ancho: Y = perpendicular a la calle
                    local lat0, lon0 = geo.toGeo(t, cx + px * half, cy + py * half)
                    -- props.add mide el giro desde (dx, dy): pasamos la perpendicular como dirección y giro 0
                    props.add(kind, lat0, lon0, px, py, 0, { noCollision = false })
                    -- y detrás, el corte como en los rallies del juego: dos barreras de plástico rojas y un bidón
                    if M.protection ~= false then
                      -- a lo ancho de la calle (el largo de la barrera, eje X, en la dirección de la cinta)
                      for _, b in ipairs({ { -1.9, 'plasticBarrier' }, { 1.9, 'plasticBarrierW' }, { 0, 'barrel' } }) do
                        local bx, by = cx + ex * 2.2 + px * b[1], cy + ey * 2.2 + py * b[1]
                        local bl, bo = geo.toGeo(t, bx, by)
                        -- en la calle cortada a propósito: no se vuelve a comprobar contra la calzada
                        local it2 = props.add(b[2], bl, bo, px, py, b[2] == 'barrel' and 0 or 90)
                        if it2 then it2.roadOk = true it2.closure = true end
                      end
                    end
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
    ::nextNode::
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

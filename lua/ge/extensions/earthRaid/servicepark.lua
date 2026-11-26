-- Raid.Earth: el parque de asistencia en el mejor sitio posible. Petición del usuario, 19-nov: "cuando se den estos
-- casos [el box dentro de un edificio] hay que utilizar la mejor zona posible: aparcamientos, descampados con acceso a
-- la calzada, zonas donde puedan habilitarse los boxes sin problema de colisiones, que puedan maniobrar los vehículos y
-- esté lo más plano posible". Y como en el rally del juego: boxes de carpas 3x6 con separación, y un control horario
-- (TC0) a la salida del parque, en la carretera.
--
-- Cómo: alrededor del punto de asistencia del organizador (radio R) se muestrea el suelo en una rejilla; una celda vale
-- si no está dentro de un edificio (ni a 3 m), no está en una carretera del grafo (ni a 2,5 m del borde) y hay terreno.
-- Con una transformada de distancia se busca la celda con más espacio libre alrededor (la plaza más ancha), cerca de la
-- asistencia y con una carretera a mano para salir; el eje largo del sitio es el de mayor alcance libre; se comprueba
-- que sea llano. La búsqueda es incremental (M.step con presupuesto de ms) para no dar tirones en la carga.
local M = {}
local props = require('earthRaid/props')
local geo = require('earthRaid/geo')
local TAG = 'earthRaid.servicepark'
local function api() return rawget(_G, 'beamngEarth_api') end

M.R = 240            -- radio de búsqueda (m)
M.STEP = 4           -- paso de la rejilla (m)
M.MIN_CLEAR = 10     -- espacio libre mínimo alrededor del centro (m)
M.MAX_CLEAR = 30     -- más libre que esto no cuenta más
M.ROAD_PAD = 2.5     -- del borde de la calzada
M.BLD_PAD = 3        -- de un edificio
M.SLOPE_MAX = 0.08   -- pendiente máxima (desnivel / distancia)
M.EXIT_ROAD_M = 70   -- la carretera de salida, como mucho a esta distancia del sitio
M.BUILDINGS_WAIT_S = 5
M.PAIR_M = 6.2       -- entre boxes (una carpa 3x6 por coche, girada 90°: el coche queda a lo largo)
M.MAX_BOXES = 4      -- (a futuro: según los jugadores inscritos en el evento)
M.BOX_LEVELS = { 1, 2, 4, 8 }   -- boxes según el sitio (22-nov): 1 mínimo obligatorio, 2 recomendable, 4 de norma, 8 máximo
M.ROW_GAP_M = 15     -- entre dos filas de boxes: 6 m de fondo de carpa + pasillo de maniobra
M.BIG_EXTRA = 4      -- en un aparcamiento grande (caben todos), estos boxes más, para llenar (19-nov)
M.NO_PARK_M = 45     -- sin coches de tráfico aparcados a menos de esto de un box (19-nov: solo los de rally)
-- El box, como en los rallies del juego (19-nov, colocado a mano por el usuario con el editor): el coche entra de
-- morro y sale marcha atrás; los extintores al fondo de la carpa, no delante cortando el paso
M.EXT_BACK_M = 2.0
M.BUDGET_MS = 6

local function terrainZ(x, y)
  if core_terrain and core_terrain.getTerrainHeight then
    local z = core_terrain.getTerrainHeight(vec3(x, y, 0))
    if z and z > -1000 then
      -- (26-nov) con un parche de BeamNG.Earth encima (Córdoba), su altura: el TerrainBlock queda debajo
      local okG, g = pcall(props.trueGround, x, y)
      if okG and g and g > z + 1.0 then return g end
      return z
    end
  end
  return nil
end

-- distancia de (x, y) al contorno del polígono y si está dentro
local function polyDist(poly, x, y)
  local inside, best = false, math.huge
  local n = #poly
  for i = 1, n do
    local a, b = poly[i], poly[i % n + 1]
    if (a[2] > y) ~= (b[2] > y) then
      local xi = a[1] + (y - a[2]) * (b[1] - a[1]) / (b[2] - a[2])
      if x < xi then inside = not inside end
    end
    local vx, vy, wx, wy = b[1] - a[1], b[2] - a[2], x - a[1], y - a[2]
    local L = vx * vx + vy * vy
    local u = L > 0 and math.max(0, math.min(1, (wx * vx + wy * vy) / L)) or 0
    local dx, dy = wx - u * vx, wy - u * vy
    local d = dx * dx + dy * dy
    if d < best then best = d end
  end
  return math.sqrt(best), inside
end


-- Parques colocados a mano por el usuario (20-nov): donde la búsqueda automática no da con un sitio como quiere, sus
-- cruces sobre una captura. lat/lon (no coordenadas del juego: valen en cualquier zona cargada).
--   boxes: un box (carpa + coche + extintores) en cada punto; los coches salen marcha atrás hacia 'aisle' (grados, 0 = N, 90 = E)
--   (el usuario colocó su caseta con F11: eje largo norte-sur, coche de morro al sur; los demás igual, 20-nov)
--   tc0: el puesto del TC0 (en el centro de la calzada de salida); out = hacia dónde se sale (grados), face = hacia dónde
--   miran los boxes desde él, hw = semiancho de la calzada (la línea cruza perpendicular a 'out')
M.MANUAL = {
  { name = 'cristian-lopez', lat = 43.31945, lon = -3.85400, radius = 500, aisle = 0,
    boxes = { { 43.3195578, -3.8542240 }, { 43.3194210, -3.8541920 }, { 43.3193697, -3.8540132 }, { 43.3193634, -3.8539023 } },
    tc0 = { lat = 43.3196299, lon = -3.8536290, out = 90, face = 180, hw = 3.0 } },
}
local function manualFor(lat, lon)
  for _, m in ipairs(M.MANUAL) do
    local dy = (lat - m.lat) * 111320
    local dx = (lon - m.lon) * 111320 * math.cos(math.rad(lat))
    if dx * dx + dy * dy <= m.radius * m.radius then return m end
  end
end
M.manualFor = manualFor

-- Empieza la búsqueda. toward: hacia dónde se sale (el primer control), para orientar la salida.
function M.search(lat, lon, towardLat, towardLon)
  local a = api()
  if not (a and a.toGame) then return nil end
  local x0, y0 = a.toGame(lat, lon, 0)
  if not x0 then return nil end
  local man = manualFor(lat, lon)
  if man then
    local cx, cy = a.toGame(man.tc0.lat, man.tc0.lon, 0)
    return { x0 = x0, y0 = y0, lat = lat, lon = lon, t0 = os.clock(), phase = 'done',
      site = { manual = man, x = cx, y = cy, z = terrainZ(cx, cy) or 0, exitX = cx, exitY = cy, hx = 0, hy = 1, len = 40, wid = 40 } }
  end
  -- un aparcamiento elegido por el usuario a menos de 3 km: la búsqueda se centra en él
  for _, pf in ipairs(M.PREFER) do
    local dy = (lat - pf.lat) * 111320
    local dx = (lon - pf.lon) * 111320 * math.cos(math.rad(lat))
    if dx * dx + dy * dy < 3000 * 3000 then
      lat, lon = pf.lat, pf.lon
      x0, y0 = a.toGame(lat, lon, 0)
      break
    end
  end
  local h = { x0 = x0, y0 = y0, lat = lat, lon = lon, t0 = os.clock(), n = math.floor(2 * M.R / M.STEP) + 1,
    grid = {}, z = {}, i = 1, phase = 'buildings', polys = nil, site = nil, tx = nil, ty = nil }
  if towardLat then h.tx, h.ty = a.toGame(towardLat, towardLon, 0) end
  if a.has and a.has('buildings') and a.buildings then
    a.buildings(lat, lon, { radius = M.R + 60, limit = 100 }, function(r)
      if h.polys then return end
      local polys = {}
      for _, b in ipairs(r and r.buildings or {}) do
        local poly, minx, miny, maxx, maxy = {}, math.huge, math.huge, -math.huge, -math.huge
        for _, p in ipairs(b.outline or {}) do
          local px, py = a.toGame(p[1] or p.lat, p[2] or p.lon, 0)
          if px then
            poly[#poly + 1] = { px, py }
            minx, miny, maxx, maxy = math.min(minx, px), math.min(miny, py), math.max(maxx, px), math.max(maxy, py)
          end
        end
        if #poly >= 3 then poly.box = { minx - M.BLD_PAD, miny - M.BLD_PAD, maxx + M.BLD_PAD, maxy + M.BLD_PAD } polys[#polys + 1] = poly end
      end
      h.polys = polys
    end)
  else
    h.polys = {}
  end
  return h
end

local function cellXY(h, i)
  local n = h.n
  local gx, gy = (i - 1) % n, math.floor((i - 1) / n)
  return h.x0 + (gx - (n - 1) / 2) * M.STEP, h.y0 + (gy - (n - 1) / 2) * M.STEP, gx, gy
end

-- (26-nov, Asturias: el parque salió dentro del río Nalón, en San Esteban: «el motor se está inundando») el agua de
-- BeamNG.Earth (mar y ríos) no la ve el rayo ni el material del suelo: una celda cuyo suelo queda por debajo de la
-- superficie de un agua que la cubre no vale. MARK:park-water-v1
local function waterBodies()
  local out = {}
  for _, c in ipairs({ 'River', 'WaterBlock' }) do
    for _, n in ipairs(scenetree.findClassObjects(c) or {}) do
      local ob = scenetree.findObject(n)
      if ob then
        local ok, b = pcall(function() return ob:getWorldBox() end)
        if ok and b then
          local w = { b.minExtents.x, b.minExtents.y, b.maxExtents.x, b.maxExtents.y, ob:getPosition().z }
          if c == 'River' then
            -- un río: por sus nodos (posición, ancho), no por su caja, que en un valle abarca mucha tierra más baja
            local nodes = {}
            pcall(function()
              for i = 0, ob:getNodeCount() - 1 do
                local p = ob:getNodePosition(i)
                nodes[#nodes + 1] = { p.x, p.y, p.z, ob:getNodeWidth(i) / 2 }
              end
            end)
            w.nodes = nodes
          end
          out[#out + 1] = w
        end
      end
    end
  end
  return out
end
M.waterBodies = waterBodies
local function underWater(list, x, y, z)
  for _, w in ipairs(list or {}) do
    if x >= w[1] - 10 and x <= w[3] + 10 and y >= w[2] - 10 and y <= w[4] + 10 then
      if w.nodes then
        for i = 1, #w.nodes - 1 do
          local a, b = w.nodes[i], w.nodes[i + 1]
          local vx, vy = b[1] - a[1], b[2] - a[2]
          local L2 = vx * vx + vy * vy
          local t = L2 > 0 and math.max(0, math.min(1, ((x - a[1]) * vx + (y - a[2]) * vy) / L2)) or 0
          local d2 = (x - a[1] - vx * t) ^ 2 + (y - a[2] - vy * t) ^ 2
          local hw = a[4] + (b[4] - a[4]) * t
          local sz = a[3] + (b[3] - a[3]) * t
          if d2 < (hw + 2) ^ 2 and z < sz - 0.2 then return true end
        end
      elseif z < w[5] - 0.2 then
        return true
      end
    end
  end
  return false
end
M.underWater = underWater

local function blocked(h, x, y)
  local z = terrainZ(x, y)
  if not z then return true, nil end
  h.water = h.water or waterBodies()
  if underWater(h.water, x, y, z) then return true, z end
  for _, poly in ipairs(h.polys) do
    local b = poly.box
    if x >= b[1] and x <= b[3] and y >= b[2] and y <= b[4] then
      local d, inside = polyDist(poly, x, y)
      if inside or d < M.BLD_PAD then return true, z end
    end
  end
  local n1, _, d = props.nearestRoad(x, y, z, 30)
  if n1 and d then
    local m = map.getMap()
    local r = (m.nodes[n1] and m.nodes[n1].radius) or 3
    if d < r + M.ROAD_PAD then return true, z end
  end
  return false, z
end

-- la transformada de distancia (chamfer 3-4) en celdas: cuántas celdas libres hay alrededor
local function distanceTransform(h)
  local n, g = h.n, h.grid
  local INF = 1e6
  local d = {}
  for i = 1, n * n do d[i] = g[i] and 0 or INF end
  local function at(gx, gy) if gx < 0 or gy < 0 or gx >= n or gy >= n then return 0 end return d[gy * n + gx + 1] end
  for gy = 0, n - 1 do for gx = 0, n - 1 do
    local i = gy * n + gx + 1
    if d[i] > 0 then
      d[i] = math.min(d[i], at(gx - 1, gy) + 3, at(gx, gy - 1) + 3, at(gx - 1, gy - 1) + 4, at(gx + 1, gy - 1) + 4)
    end
  end end
  for gy = n - 1, 0, -1 do for gx = n - 1, 0, -1 do
    local i = gy * n + gx + 1
    if d[i] > 0 then
      d[i] = math.min(d[i], at(gx + 1, gy) + 3, at(gx, gy + 1) + 3, at(gx + 1, gy + 1) + 4, at(gx - 1, gy + 1) + 4)
    end
  end end
  h.dist = d
end

-- alcance libre desde (x, y) en la dirección (ux, uy), hasta maxM
local function reach(h, x, y, ux, uy, maxM)
  local n = h.n
  local s = 0
  while s < maxM do
    s = s + M.STEP * 0.5
    local px, py = x + ux * s, y + uy * s
    local gx = math.floor((px - h.x0) / M.STEP + (n - 1) / 2 + 0.5)
    local gy = math.floor((py - h.y0) / M.STEP + (n - 1) / 2 + 0.5)
    if gx < 0 or gy < 0 or gx >= n or gy >= n or h.grid[gy * n + gx + 1] then return s - M.STEP * 0.5 end
  end
  return maxM
end

-- La carretera de verdad más cercana a (x, y) hasta maxD: una calle (drivability >= 0.9 y radio >= 2,5 m en el grafo),
-- no un pasillo de aparcamiento ni un camino. n1, n2, d, px, py (el punto de la carretera) o nil.
M.ROAD_DRIV = 0.9
M.ROAD_R = 2.4
local function nearestStreet(x, y, maxD)
  local m = map.getMap()
  if not (m and m.nodes) then return nil end
  local best, bn1, bn2, bpx, bpy = maxD * maxD, nil, nil, nil, nil
  local seen = {}
  for id, nd in pairs(m.nodes) do
    local p = nd.pos
    if math.abs(p.x - x) < maxD + 60 and math.abs(p.y - y) < maxD + 60 then
      for nb, l in pairs(nd.links or {}) do
        local key = id < nb and (id .. '|' .. nb) or (nb .. '|' .. id)
        local o = m.nodes[nb]
        if o and not seen[key] and (l.drivability or 1) >= M.ROAD_DRIV and math.min(nd.radius or 3, o.radius or 3) >= M.ROAD_R then
          seen[key] = true
          local ax, ay, bx, by = p.x, p.y, o.pos.x, o.pos.y
          local vx, vy, wx, wy = bx - ax, by - ay, x - ax, y - ay
          local L = vx * vx + vy * vy
          local u = L > 0 and math.max(0, math.min(1, (wx * vx + wy * vy) / L)) or 0
          local qx, qy = ax + u * vx, ay + u * vy
          local d2 = (x - qx) ^ 2 + (y - qy) ^ 2
          if d2 < best then best, bn1, bn2, bpx, bpy = d2, id, nb, qx, qy end
        end
      end
    end
  end
  if not bn1 then return nil end
  return bn1, bn2, math.sqrt(best), bpx, bpy
end
M.nearestStreet = nearestStreet

-- ---- los aparcamientos de BeamNG.Earth ---------------------------------------------------------------------------------
-- El servidor de BeamNG.Earth manda con cada tesela de carretera sus plazas de aparcamiento (beamngEarth/parking.lua:
-- filas { x, y, z, rumbo, 1 = plaza de aparcamiento (no de calle) }). Un aparcamiento es un racimo de esas plazas:
-- el sitio ideal para el parque. Se leen de la tabla interna del módulo (debug.getupvalue: solo lectura).
local function lotRows()
  local ok, pk = pcall(require, 'beamngEarth/parking')
  if not (ok and pk and pk.onRows) then return {} end
  local spots
  for i = 1, 40 do
    local nm, v = debug.getupvalue(pk.onRows, i)
    if not nm then break end
    if nm == 'spots' then spots = v break end
  end
  local out = {}
  for _, t in pairs(spots or {}) do
    for _, r in ipairs(t.rows or {}) do if r[5] == 1 then out[#out + 1] = r end end
  end
  return out
end
M.LOT_LINK_M = 19      -- plazas a menos de esto son del mismo aparcamiento (las filas de un aparcamiento van a ~17 m)
M.LOT_MIN = 16         -- plazas mínimas para que sirva
M.LOT_PAD = 3          -- margen alrededor de las plazas
M.LOT_R = 600          -- el aparcamiento más cercano, hasta a esta distancia del punto del organizador (20-nov)
M.LOTS_WAIT_S = 3      -- las plazas llegan de BeamNG.Earth poco a poco: espera a que dejen de aumentar...
M.LOTS_WAIT_MAX_S = 10 -- ...como mucho esto

-- Los aparcamientos cerca del punto (racimos de plazas), del mejor al peor: { cx, cy, z, ux, uy, len, wid, n, far }
local function lots(h)
  local rows = lotRows()
  local pts = {}
  for _, r in ipairs(rows) do
    if math.abs(r[1] - h.x0) <= M.LOT_R and math.abs(r[2] - h.y0) <= M.LOT_R then pts[#pts + 1] = r end
  end
  if #pts < M.LOT_MIN then return {} end
  -- racimos por enlace simple con una rejilla
  local cell = M.LOT_LINK_M
  local hash = {}
  for i, p in ipairs(pts) do
    local k = math.floor(p[1] / cell) .. ':' .. math.floor(p[2] / cell)
    hash[k] = hash[k] or {}
    hash[k][#hash[k] + 1] = i
  end
  local parent = {}
  for i = 1, #pts do parent[i] = i end
  local function find(i) while parent[i] ~= i do parent[i] = parent[parent[i]] i = parent[i] end return i end
  for i, p in ipairs(pts) do
    local gx, gy = math.floor(p[1] / cell), math.floor(p[2] / cell)
    for dx = -1, 1 do for dy = -1, 1 do
      for _, j in ipairs(hash[(gx + dx) .. ':' .. (gy + dy)] or {}) do
        if j > i and (p[1] - pts[j][1]) ^ 2 + (p[2] - pts[j][2]) ^ 2 <= cell * cell then
          local a, b = find(i), find(j)
          if a ~= b then parent[a] = b end
        end
      end
    end end
  end
  local groups = {}
  for i = 1, #pts do local r = find(i) groups[r] = groups[r] or {} groups[r][#groups[r] + 1] = pts[i] end
  local out = {}
  for _, g in pairs(groups) do
    if #g >= M.LOT_MIN then
      local cx, cy, cz = 0, 0, 0
      for _, p in ipairs(g) do cx, cy, cz = cx + p[1], cy + p[2], cz + p[3] end
      cx, cy, cz = cx / #g, cy / #g, cz / #g
      -- el eje largo: componente principal
      local sxx, sxy, syy = 0, 0, 0
      for _, p in ipairs(g) do local dx, dy = p[1] - cx, p[2] - cy sxx, sxy, syy = sxx + dx * dx, sxy + dx * dy, syy + dy * dy end
      local ang = 0.5 * math.atan2(2 * sxy, sxx - syy)
      local ux, uy = math.cos(ang), math.sin(ang)
      local a0, a1, b0, b1 = math.huge, -math.huge, math.huge, -math.huge
      for _, p in ipairs(g) do
        local dx, dy = p[1] - cx, p[2] - cy
        local a, b = dx * ux + dy * uy, -dx * uy + dy * ux
        a0, a1, b0, b1 = math.min(a0, a), math.max(a1, a), math.min(b0, b), math.max(b1, b)
      end
      local len, wid = a1 - a0 + 2 * M.LOT_PAD + 3, b1 - b0 + 2 * M.LOT_PAD + 3
      local ccx, ccy = cx + ux * (a0 + a1) / 2 - uy * (b0 + b1) / 2, cy + uy * (a0 + a1) / 2 + ux * (b0 + b1) / 2
      local far = math.sqrt((ccx - h.x0) ^ 2 + (ccy - h.y0) ^ 2)
      out[#out + 1] = { cx = ccx, cy = ccy, z = cz, ux = ux, uy = uy, len = len, wid = wid, n = #g, far = far, pts = g,
        score = math.sqrt(math.min(len, 100) * math.min(wid, 60)) - far / 25 }
    end
  end
  table.sort(out, function(p, q) return p.score > q.score end)
  return out
end

-- ¿el perímetro del rectángulo (centro, ejes, largo, ancho) está libre?
local function rectFree(h, cx, cy, ux, uy, len, wid)
  local n = h.n
  local function free(px, py)
    local gx = math.floor((px - h.x0) / M.STEP + (n - 1) / 2 + 0.5)
    local gy = math.floor((py - h.y0) / M.STEP + (n - 1) / 2 + 0.5)
    return not (gx < 0 or gy < 0 or gx >= n or gy >= n or h.grid[gy * n + gx + 1])
  end
  local hl, hw = len / 2, wid / 2
  local steps = math.max(2, math.floor(math.max(len, wid) / (M.STEP * 0.5)))
  for i = 0, steps do
    local f = -1 + 2 * i / steps
    -- los dos lados largos y los dos cortos
    if not free(cx + ux * hl * f + uy * hw, cy + uy * hl * f - ux * hw) then return false end
    if not free(cx + ux * hl * f - uy * hw, cy + uy * hl * f + ux * hw) then return false end
    if not free(cx + ux * hl + uy * hw * f, cy + uy * hl - ux * hw * f) then return false end
    if not free(cx - ux * hl + uy * hw * f, cy - uy * hl - ux * hw * f) then return false end
  end
  return true
end

-- El rectángulo libre más grande alrededor de la celda: eje largo por el mayor alcance, centro en medio, y se
-- encoge hasta que su perímetro esté libre. { cx, cy, ux, uy, len, wid } o nil.
local function rectAt(h, x, y)
  local best, bu, bv = -1, 1, 0
  for k = 0, 15 do
    local ang = k * math.pi / 16
    local ux, uy = math.cos(ang), math.sin(ang)
    local L = reach(h, x, y, ux, uy, 90) + reach(h, x, y, -ux, -uy, 90)
    if L > best then best, bu, bv = L, ux, uy end
  end
  local cx, cy = x, y
  local len, wid = 0, 0
  for _ = 1, 3 do
    local fwd, back = reach(h, cx, cy, bu, bv, 90), reach(h, cx, cy, -bu, -bv, 90)
    cx, cy = cx + bu * (fwd - back) / 2, cy + bv * (fwd - back) / 2
    len = fwd + back
    local left, right = reach(h, cx, cy, -bv, bu, 60), reach(h, cx, cy, bv, -bu, 60)
    cx, cy = cx - bv * (left - right) / 2, cy + bu * (left - right) / 2
    wid = left + right
  end
  len, wid = len - 2, wid - 2
  for _ = 1, 8 do
    if len < 20 or wid < 16 then return nil end
    if rectFree(h, cx, cy, bu, bv, len, wid) then return { cx = cx, cy = cy, ux = bu, uy = bv, len = len, wid = wid } end
    len, wid = len * 0.88, wid * 0.88
  end
  return nil
end

-- Aparcamientos elegidos por el usuario (26-nov): si uno de los aparcamientos encontrados tiene plazas a menos de r m de
-- este punto, es el parque de asistencia, aunque haya otro mayor o más cerca del punto del organizador. El resto (boxes,
-- vallado, TC0 en la salida asfaltada) es el automático, igual que en todos los rallies.
M.PREFER = {
  -- Sierra Morena 2026: aparcamiento de la plaza de toros de Córdoba (el coche del usuario aparcado allí)
  -- gate: el acceso que marcó (el paso de la acera a la avenida curva del norte); allí van el hueco del vallado y el TC0
  { name = 'sierra-morena-plaza-toros', lat = 37.8811398, lon = -4.7942082, r = 60, gate = { 37.8813468, -4.7945695 } },
}
local function preferredFirst(list)
  local a = api()
  if not (a and a.toGame) then return list end
  for _, pf in ipairs(M.PREFER) do
    local px, py = a.toGame(pf.lat, pf.lon, 0)
    if px then
      for i, L in ipairs(list) do
        local hit = false
        for _, st in ipairs(L.pts or {}) do
          if (st[1] - px) ^ 2 + (st[2] - py) ^ 2 < pf.r * pf.r then hit = true break end
        end
        if hit then
          if i > 1 then table.remove(list, i) table.insert(list, 1, L) end
          L.preferred, L.gate = pf.name, pf.gate
          log('I', TAG, 'parking lot chosen by the user: ' .. pf.name)
          return list
        end
      end
    end
  end
  return list
end

local function tryLots(h)
  -- primero los aparcamientos de BeamNG.Earth (plazas del servidor): el más grande y cercano con carretera para salir
  for _, L in ipairs(preferredFirst(lots(h))) do
    -- (26-nov, Suecia: «aparcamiento» de 78 plazas en medio de un bosque, todo hierba) un aparcamiento de verdad no es
    -- hierba: si casi todo el recinto es hierba, se descarta (salvo el elegido por el usuario)
    local grassy, n = 0, 0
    local tb = scenetree.findObject('bngEarthTerrain')
    if tb and not L.preferred then
      for _, fa in ipairs({ -0.35, 0, 0.35 }) do
        for _, fs in ipairs({ -0.35, 0, 0.35 }) do
          local x = L.cx + L.ux * fa * L.len - L.uy * fs * L.wid
          local y = L.cy + L.uy * fa * L.len + L.ux * fs * L.wid
          local z = terrainZ(x, y)
          if z then
            local okM, mn = pcall(function() return tb:getMaterialName(tb:getMaterialIdxWs(vec3(x, y, z))) end)
            n = n + 1
            if okM and tostring(mn):find('Grass') then grassy = grassy + 1 end
          end
        end
      end
    end
    if n >= 5 and grassy / n > 0.7 then
      log('I', TAG, ('parking lot of %d stalls skipped: grass, not a car park'):format(L.n or 0))
      goto nextLot
    end
    do
    -- la carretera de salida: la más cercana FUERA del aparcamiento (dentro suele haber pasillos en el grafo), buscada
    -- desde fuera de cada lado del rectángulo
    local function inside(x, y, pad)
      local dx, dy = x - L.cx, y - L.cy
      local al, sd = dx * L.ux + dy * L.uy, -dx * L.uy + dy * L.ux
      return math.abs(al) < L.len / 2 + pad and math.abs(sd) < L.wid / 2 + pad
    end
    local n1, n2, rd, px, py
    local best = math.huge
    for _, q in ipairs({ { L.ux, L.uy, L.len / 2, L.wid / 2 }, { -L.ux, -L.uy, L.len / 2, L.wid / 2 }, { -L.uy, L.ux, L.wid / 2, L.len / 2 }, { L.uy, -L.ux, L.wid / 2, L.len / 2 } }) do
      for _, k in ipairs({ 0.5, 1 }) do
        for _, f in ipairs({ -0.8, 0, 0.8 }) do
          local ox, oy = L.cx + q[1] * (q[3] + 6) + (-q[2]) * f * q[4] * k, L.cy + q[2] * (q[3] + 6) + q[1] * f * q[4] * k
          local a1, a2, d, ax, ay = nearestStreet(ox, oy, M.EXIT_ROAD_M)
          if a1 and d and ax and not inside(ax, ay, 2) then
            local dc = math.sqrt((ax - L.cx) ^ 2 + (ay - L.cy) ^ 2)
            if dc < best then best, n1, n2, rd, px, py = dc, a1, a2, d, ax, ay end
          end
        end
      end
    end
    -- (26-nov) el aparcamiento elegido por el usuario con su acceso marcado: la salida es ese acceso, aunque la calle
    -- quede dentro del rectángulo de las plazas (Sierra Morena: con 213 plazas el rectángulo tapaba la calle)
    if not n1 and L.preferred and type(L.gate) == 'table' and L.gate[1] then
      local a = api()
      local gx, gy = a.toGame(L.gate[1], L.gate[2], 0)
      if gx then
        local a1, a2, d, ax, ay = nearestStreet(gx, gy, 80)
        if a1 then n1, n2, rd, px, py = a1, a2, d, ax, ay end
      end
    end
    if n1 and rd and L.wid >= 14 and L.len >= 20 then
      h.site = { x = L.cx, y = L.cy, z = terrainZ(L.cx, L.cy) or L.z, hx = L.ux, hy = L.uy, len = L.len, wid = L.wid,
        exitX = px, exitY = py, n1 = n1, n2 = n2, roadD = rd, far = L.far, clear = 0, lot = L.n, stalls = L.pts, tx = h.tx, ty = h.ty,
        gate = L.gate }
      h.phase = 'done'
      log('I', TAG, ('parking lot: %d stalls, %.0f x %.0f m, %.0f m from the service point, road at %.0f m (%.1f s)'):format(
        L.n, L.len, L.wid, L.far, rd, os.clock() - h.t0))
      return true
    end
    end
    ::nextLot::
  end
  return false
end

-- Los segmentos de calle del grafo cerca de la zona (una vez): { ax, ay, bx, by, n1, n2 }
local function streetSegs(h)
  local m = map.getMap()
  local segs = {}
  if not (m and m.nodes) then return segs end
  local box = M.R + M.EXIT_ROAD_M + 60
  local seen = {}
  for id, nd in pairs(m.nodes) do
    local p = nd.pos
    if math.abs(p.x - h.x0) < box and math.abs(p.y - h.y0) < box then
      for nb, l in pairs(nd.links or {}) do
        local o = m.nodes[nb]
        local key = tostring(id) < tostring(nb) and (id .. '|' .. nb) or (nb .. '|' .. id)
        if o and not seen[key] and (l.drivability or 1) >= M.ROAD_DRIV and math.min(nd.radius or 3, o.radius or 3) >= M.ROAD_R then
          seen[key] = true
          segs[#segs + 1] = { p.x, p.y, o.pos.x, o.pos.y, id, nb }
        end
      end
    end
  end
  return segs
end

-- la calle más cercana a (x, y) hasta maxD entre los segmentos: n1, n2, distancia, punto
local function segDist(segs, x, y, maxD)
  local best, bi, bpx, bpy = maxD * maxD, nil, nil, nil
  for i = 1, #segs do
    local sg = segs[i]
    local vx, vy, wx, wy = sg[3] - sg[1], sg[4] - sg[2], x - sg[1], y - sg[2]
    local L = vx * vx + vy * vy
    local u = L > 0 and math.max(0, math.min(1, (wx * vx + wy * vy) / L)) or 0
    local qx, qy = sg[1] + u * vx, sg[2] + u * vy
    local d2 = (x - qx) ^ 2 + (y - qy) ^ 2
    if d2 < best then best, bi, bpx, bpy = d2, i, qx, qy end
  end
  if not bi then return nil end
  return segs[bi][5], segs[bi][6], math.sqrt(best), bpx, bpy
end

M.MAX_TRIES = 150
local function finish(h)
  local n, d = h.n, h.dist
  h.segs = h.segs or streetSegs(h)
  -- candidatas: celdas con espacio libre (cada 8 m) y una calle a mano para salir; el sitio ideal es amplio, llano,
  -- cerca de la asistencia del organizador y pegado a una carretera (no la duna más grande del mapa)
  local cands = {}
  for gy = 0, n - 1, 2 do
    for gx = 0, n - 1, 2 do
      local i = gy * n + gx + 1
      if not h.grid[i] then
        local clear = d[i] / 3 * M.STEP
        if clear >= M.MIN_CLEAR then
          local x, y = cellXY(h, i)
          local _, _, rd = segDist(h.segs, x, y, M.EXIT_ROAD_M + 30)
          if rd then
            local far = math.sqrt((x - h.x0) ^ 2 + (y - h.y0) ^ 2)
            cands[#cands + 1] = { x = x, y = y, clear = clear, score = math.min(clear, M.MAX_CLEAR) * 2 - far / 20 - rd / 8 }
          end
        end
      end
    end
  end
  table.sort(cands, function(p, q) return p.score > q.score end)
  local z0 = h.z[math.floor(n * n / 2) + 1]
  -- de las mejores celdas, el rectángulo libre más grande (llano, con carretera para salir): gana el de más superficie
  -- útil, con una pequeña preferencia por lo cercano a la asistencia
  local bestSite, bestScore = nil, -math.huge
  local tries, done = 0, {}
  local st = { rects = 0, noRoad = 0, steep = 0 }
  h.stats = st
  for ci = 1, #cands do
    if tries >= M.MAX_TRIES then break end
    local c = cands[ci]
    local r = rectAt(h, c.x, c.y)
    tries = tries + 1
    if r then
      local key = math.floor(r.cx / 10) .. ':' .. math.floor(r.cy / 10)
      if not done[key] then
        done[key] = true
        st.rects = st.rects + 1
        local z = terrainZ(r.cx, r.cy) or z0
        local n1, n2, rd, px, py = segDist(h.segs, r.cx, r.cy, M.EXIT_ROAD_M + r.len / 2)
        if not (n1 and rd) then st.noRoad = st.noRoad + 1 end
        if n1 and rd then
          local ok = true
          for _, p in ipairs({ { r.ux, r.uy, r.len / 2 - 2 }, { -r.ux, -r.uy, r.len / 2 - 2 }, { -r.uy, r.ux, r.wid / 2 - 2 }, { r.uy, -r.ux, r.wid / 2 - 2 } }) do
            local pz = terrainZ(r.cx + p[1] * p[3], r.cy + p[2] * p[3])
            if not pz or math.abs(pz - z) / math.max(p[3], 1) > M.SLOPE_MAX then ok = false break end
          end
          if not ok then st.steep = st.steep + 1 end
          if ok then
            local far = math.sqrt((r.cx - h.x0) ^ 2 + (r.cy - h.y0) ^ 2)
            local score = math.sqrt(math.min(r.len, 100) * math.min(r.wid, 60)) - far / 40 - rd / 6
            if score > bestScore then
              bestScore = score
              bestSite = { x = r.cx, y = r.cy, z = z, hx = r.ux, hy = r.uy, len = r.len, wid = r.wid, exitX = px, exitY = py,
                n1 = n1, n2 = n2, roadD = rd, far = far, clear = c.clear, key = key }
            end
          end
        end
      end
    end
  end
  h.site = bestSite
  if h.site then h.site.tx, h.site.ty = h.tx, h.ty end
  h.phase = 'done'
  -- (26-nov, Canarias: «no site found» con el aparcamiento de 600 plazas allí) las plazas de BeamNG.Earth pueden llegar
  -- después de la espera: sin sitio, al terminar se prueba otra vez con los aparcamientos que haya ya
  -- (solo sin sitio: en Suecia, con sitio en tierra, el «aparcamiento» que llegaba después estaba en un bosque)
  if not h.site and not h.lotsRetried then
    h.lotsRetried = true
    local okL, found = pcall(tryLots, h)
    if okL and found then log('I', TAG, 'no free ground, but a parking lot is now loaded: using it') return end
    h.site, h.phase = nil, 'done'
  end
  log('I', TAG, h.site and ('site: %.0f x %.0f m, %.0f m from the service point, road at %.0f m (%d cands, %d tries, %d rects, %.1f s)'):format(
    h.site.len, h.site.wid, h.site.far, h.site.roadD, #cands, tries, st.rects, os.clock() - h.t0) or ('no site found (%d cands, %d tries, %d rects, %d no road, %d steep, %.1f s)'):format(#cands, tries, st.rects, st.noRoad, st.steep, os.clock() - h.t0))
end

-- Avanza la búsqueda como mucho ms milisegundos. true cuando ha terminado (h.site, o nil si no hay sitio).
function M.step(h, ms)
  if not h or h.phase == 'done' then return true end
  local until_ = os.clock() + (ms or M.BUDGET_MS) / 1000
  if h.phase == 'buildings' then
    -- un aparcamiento de BeamNG.Earth cerca: no hace falta más búsqueda
    -- (20-nov) las plazas de BeamNG.Earth llegan después de cargar la zona: antes se miraba una sola vez nada más
    -- empezar y, sin plazas todavía, se caía al descampado (Canarias: casas y solar en vez del aparcamiento de 600 plazas).
    -- Ahora se espera a que el número de plazas cercanas deje de crecer (M.LOTS_WAIT_S) y entonces se busca.
    if not h.lotsTried then
      local n = 0
      for _, r in ipairs(lotRows()) do
        if math.abs(r[1] - h.x0) <= M.LOT_R and math.abs(r[2] - h.y0) <= M.LOT_R then n = n + 1 end
      end
      local now = os.clock()
      if n ~= h.lotN then h.lotN, h.lotChange = n, now end
      local waited = now - h.t0
      local stable = h.lotN and h.lotN >= M.LOT_MIN and now - (h.lotChange or now) >= 1.5 and waited >= M.LOTS_WAIT_S
      local empty = (h.lotN or 0) < M.LOT_MIN and now - (h.lotChange or now) >= 3.5 and waited >= 5   -- sin plazas en la zona
      if stable or empty or waited >= M.LOTS_WAIT_MAX_S then
        h.lotsTried = true
        if tryLots(h) then return true end
      else
        return false
      end
    end
    if not h.polys then
      if os.clock() - h.t0 > M.BUILDINGS_WAIT_S then h.polys = {} log('W', TAG, 'buildings: no answer, going on without them') else return false end
    end
    h.phase = 'grid'
  end
  if h.phase == 'grid' then
    local N = h.n * h.n
    while h.i <= N do
      local x, y = cellXY(h, h.i)
      local b, z = blocked(h, x, y)
      h.grid[h.i], h.z[h.i] = b, z
      h.i = h.i + 1
      if os.clock() > until_ then return false end
    end
    h.phase = 'dist'
    return false
  end
  if h.phase == 'dist' then distanceTransform(h) h.phase = 'pick' return false end
  if h.phase == 'pick' then finish(h) end
  return true
end

function M.active(h) return h ~= nil and h.phase ~= 'done' end

-- El montaje: boxes (dos carpas 3x6 juntas, cada una con sus dos extintores) en fila a lo largo del eje largo, pegados a
-- un lado del sitio, con el pasillo de maniobra por delante; el del jugador en medio. Devuelve el box del jugador
-- { lat, lon, faceLat, faceLon } (el coche bajo la carpa, mirando al pasillo).
-- En un aparcamiento de verdad: los boxes sobre las plazas de la fila más alejada de la salida (así quedan en el
-- asfalto pintado, nunca en el talud del borde), orientados como las plazas
-- Coches de rally aparcados en los boxes vecinos al del jugador (19-nov, ambiente): { [índice de box] = {modelo, config} }
-- Son vehículos de verdad solo cerca del coche (phys.lua): como mucho M.PARK_CARS.
M.PARK_CARS = 3       -- coches de rally aparcados en los boxes vecinos (22-nov, el usuario: 3)
M.surface = 'asphalt'
-- El TC0 en el pasillo de los boxes (19-nov, el usuario lo colocó a mano con F11 y lo quiere así): al final de la fila, del
-- lado de la salida del recinto, 18 m más allá del último box y a 5,5 m de ellos (en el pasillo), de modo que desde el
-- box no se sale del recinto sin pasar por él. build() guarda aquí el sitio { x, y, z, ux, uy } (ux,uy: hacia la salida).
M.TC0_BEYOND_M, M.TC0_AISLE_M = 18, 5.5
M.tcSpot = nil
-- ¿cuál de los dos extremos de la fila queda más cerca de una carretera de verdad (nodos del grafo con paso, 2+ enlaces)?
-- Las calles del propio aparcamiento son nodos sueltos (1 enlace) y no cuentan. Sin grafo, la salida que encontró la
-- búsqueda. Devuelve true si gana el primero.
local function firstEndIsNearer(x1, y1, x2, y2, exitX, exitY)
  local okM, m = pcall(map.getMap)
  if okM and m and m.nodes then
    local d1, d2 = 1e9, 1e9
    for _, nd in pairs(m.nodes) do
      local n = 0
      for _ in pairs(nd.links or {}) do n = n + 1 if n >= 2 then break end end
      if n >= 2 then
        local a1 = (nd.pos.x - x1) ^ 2 + (nd.pos.y - y1) ^ 2
        local a2 = (nd.pos.x - x2) ^ 2 + (nd.pos.y - y2) ^ 2
        if a1 < d1 then d1 = a1 end
        if a2 < d2 then d2 = a2 end
      end
    end
    if d1 < 1e9 or d2 < 1e9 then return d1 <= d2 end
  end
  return (x1 - exitX) ^ 2 + (y1 - exitY) ^ 2 <= (x2 - exitX) ^ 2 + (y2 - exitY) ^ 2
end
-- La salida del recinto según el grafo de carreteras: la calle del aparcamiento (vía de servicio, drivability <= 0,5)
-- que desemboca en una carretera de verdad. El TC0 va en esa calle, unos metros antes de la incorporación: quien sale
-- del recinto pasa por él y para ahí (19-nov, el usuario: "la línea donde están las ruedas delanteras... fichar a la
-- salida"). Devuelve el sitio { x, y, z, ux, uy (hacia la carretera), bx, by (hacia los boxes), hw } o nil (sin calle
-- de salida en el grafo: vale el extremo de la fila). MARK:gate-v1
M.GATE_SEARCH_M, M.GATE_BACK_M, M.LOT_DRIV = 220, 7, 0.5
local function exitGate(cx, cy, z)
  local okM, m = pcall(map.getMap)
  if not (okM and m and m.nodes) then return nil end
  local adj, R2 = {}, M.GATE_SEARCH_M ^ 2
  local function near(nd) return (nd.pos.x - cx) ^ 2 + (nd.pos.y - cy) ^ 2 <= R2 end
  for k, nd in pairs(m.nodes) do
    for nb, ed in pairs(nd.links or {}) do
      local o = m.nodes[nb]
      if o and (near(nd) or near(o)) then
        local dr = type(ed) == 'table' and tonumber(ed.drivability) or 1
        adj[k] = adj[k] or {}
        adj[nb] = adj[nb] or {}
        adj[k][nb], adj[nb][k] = dr, dr
      end
    end
  end
  local function class(k)
    local hi = 0
    for _, d in pairs(adj[k] or {}) do if d > hi then hi = d end end
    return hi
  end
  local bp, bj, bd
  for p, links in pairs(adj) do
    if class(p) <= M.LOT_DRIV then
      for j, d in pairs(links) do
        if d <= M.LOT_DRIV and class(j) > M.LOT_DRIV then
          local P, J = m.nodes[p].pos, m.nodes[j].pos
          local dP = math.sqrt((P.x - cx) ^ 2 + (P.y - cy) ^ 2)
          local dJ = math.sqrt((J.x - cx) ^ 2 + (J.y - cy) ^ 2)
          -- la calle sale desde nuestro lado (no la de un aparcamiento al otro lado de la carretera)
          if dP < dJ + 5 and (not bd or dJ < bd) then bp, bj, bd = p, j, dJ end
        end
      end
    end
  end
  if not bp then return nil end
  local P, J = m.nodes[bp], m.nodes[bj]
  local dx, dy = J.pos.x - P.pos.x, J.pos.y - P.pos.y
  local L = math.sqrt(dx * dx + dy * dy)
  if L < 6 then return nil end
  dx, dy = dx / L, dy / L
  local back = math.min(L * 0.75, (J.radius or 3) + M.GATE_BACK_M)
  local x, y = J.pos.x - dx * back, J.pos.y - dy * back
  local bx, by = cx - x, cy - y
  local bl = math.sqrt(bx * bx + by * by)
  if bl < 0.5 then bx, by, bl = -dy, dx, 1 end
  log('I', TAG, string.format('TC0 at the lot exit: %.0f m before the road, %.0f m from the boxes', back, bl))
  return { x = x, y = y, z = z or P.pos.z, ux = dx, uy = dy, bx = bx / bl, by = by / bl,
    hw = math.max(2.5, math.min(3.5, (P.radius or 2) + 1)), gate = true, bp = bp, bj = bj }
end
function M.parkedCars(n, mine, cands)
  local out = {}
  local okS, st = pcall(function() return require('earthRaid/settings').get() end)
  if not okS or st.ambience == false or st.parkCars == false then return out end
  local slots, seen = {}, {}
  for _, i in ipairs(cands or { mine - 1, mine + 1, mine - 2, mine + 2 }) do
    if i >= 1 and i <= n and i ~= mine and not seen[i] and #slots < M.PARK_CARS then slots[#slots + 1] = i seen[i] = true end
  end
  -- el ajuste de rendimiento limita cuántos (un coche de rally es un vehículo entero): bajo 0, medio 1, alto todos
  local okL, lim = pcall(function() return require('earthRaid/phys').level().rallyCars end)
  if okL and lim then while #slots > lim do table.remove(slots) end end
  if #slots == 0 then return out end
  local okP, list = pcall(function() return require('earthRaid/phys').pickRallyCars(#slots, M.surface) end)
  if not okP then return out end
  for j, i in ipairs(slots) do out[i] = list[j] end
  return out
end

-- Vallas publicitarias alrededor del aparcamiento (21-nov, el usuario: "perimetrar el parking con ballas publicitarias"):
-- la envolvente convexa de las plazas, 4 m hacia fuera (la carpa sobresale 3 m del centro de su plaza), con la publicidad
-- mirando adentro y un hueco de GAP m a cada lado de la salida del recinto (por donde se sale y está el TC0). Una pieza
-- no se pone si cae contra un edificio o en una pendiente (el borde del aparcamiento). MARK:lotfence-v1
M.LOT_FENCE_OFF_M, M.LOT_FENCE_GAP_M, M.LOT_FENCE_MAX, M.LOT_FENCE_PITCH_M = 4.0, 13, 90, 2.75
M.LOT_FENCE_KINDS = { 'fenceNgrc', 'fenceBlastr', 'fenceRotopad', 'fenceApm', 'fenceApmSpecial' }
local function hullOf(pts)
  local p = {}
  for _, s in ipairs(pts) do p[#p + 1] = { s[1], s[2] } end
  table.sort(p, function(u, v) return u[1] < v[1] or (u[1] == v[1] and u[2] < v[2]) end)
  local function cross(o, u, v) return (u[1] - o[1]) * (v[2] - o[2]) - (u[2] - o[2]) * (v[1] - o[1]) end
  local lo, up = {}, {}
  for _, q in ipairs(p) do
    while #lo >= 2 and cross(lo[#lo - 1], lo[#lo], q) <= 0 do lo[#lo] = nil end
    lo[#lo + 1] = q
  end
  for i = #p, 1, -1 do
    local q = p[i]
    while #up >= 2 and cross(up[#up - 1], up[#up], q) <= 0 do up[#up] = nil end
    up[#up + 1] = q
  end
  lo[#lo] = nil
  up[#up] = nil
  for _, q in ipairs(up) do lo[#lo + 1] = q end
  return lo              -- antihorario: el interior queda a la izquierda de cada lado
end

-- ---- (22-nov) la boca del recinto, los boxes por niveles y el tráfico fuera del aparcamiento ----------------------------
-- ¿(x, y) dentro de la envolvente h (antihoraria) ensanchada off metros?
local function inHull(h, x, y, off)
  for i = 1, #h do
    local A, B = h[i], h[i % #h + 1]
    local ex, ey = B[1] - A[1], B[2] - A[2]
    local L = math.sqrt(ex * ex + ey * ey)
    if L > 0.01 and (ex * (y - A[2]) - ey * (x - A[1])) / L < -off then return false end
  end
  return true
end
M.inHull = inHull

-- La ruta de servicio (las calles del aparcamiento, drivability <= LOT_DRIV) desde el nodo más cercano a (cx, cy) hasta
-- la incorporación a la carretera (gate.bp -> gate.bj): lista de { x, y }; nil si el grafo no la une.
local function serviceRoute(m, cx, cy, gate)
  if not (gate and gate.bp and gate.bj) then return nil end
  local R2 = (M.GATE_SEARCH_M + 40) ^ 2
  local adj = {}
  for k, nd in pairs(m.nodes) do
    if (nd.pos.x - cx) ^ 2 + (nd.pos.y - cy) ^ 2 <= R2 then
      for nb, ed in pairs(nd.links or {}) do
        local dr = type(ed) == 'table' and tonumber(ed.drivability) or 1
        if dr <= M.LOT_DRIV and m.nodes[nb] then
          adj[k] = adj[k] or {}
          adj[nb] = adj[nb] or {}
          adj[k][nb], adj[nb][k] = true, true
        end
      end
    end
  end
  if not adj[gate.bp] then return nil end
  local start, sd
  for k in pairs(adj) do
    local q = m.nodes[k].pos
    local d = (q.x - cx) ^ 2 + (q.y - cy) ^ 2
    if not sd or d < sd then start, sd = k, d end
  end
  if not start then return nil end
  local dist, prev, done = { [start] = 0 }, {}, {}
  while true do
    local u, ud
    for k, d in pairs(dist) do if not done[k] and (not ud or d < ud) then u, ud = k, d end end
    if not u or u == gate.bp then break end
    done[u] = true
    local pu = m.nodes[u].pos
    for nb in pairs(adj[u] or {}) do
      local pn = m.nodes[nb].pos
      local d2 = ud + math.sqrt((pn.x - pu.x) ^ 2 + (pn.y - pu.y) ^ 2)
      if not dist[nb] or d2 < dist[nb] then dist[nb], prev[nb] = d2, u end
    end
  end
  if not dist[gate.bp] then return nil end
  local rev, k = {}, gate.bp
  while k do local q = m.nodes[k].pos rev[#rev + 1] = { q.x, q.y } k = prev[k] end
  local out = {}
  for i = #rev, 1, -1 do out[#out + 1] = rev[i] end
  local J = m.nodes[gate.bj].pos
  out[#out + 1] = { J.x, J.y }
  return out
end

-- La boca del recinto: el punto donde la ruta de salida (la que sigue el GPS) cruza el vallado del aparcamiento (la
-- envolvente de las plazas + LOT_FENCE_OFF_M). Ahí van el hueco del vallado, la línea del TC0 y sus dos casetas.
-- La ruta: la más corta por el grafo de carreteras (todas las calles) desde el nodo más cercano al centro de los boxes hasta
-- el nodo de carretera de verdad (drivability > LOT_DRIV) más cercano fuera del recinto (22-nov: antes solo calles de
-- servicio y salía por otra calle que la del GPS). Sin ruta, la recta a la incorporación; si ni así sale de la envolvente,
-- la salida de siempre (exitGate). MARK:mouth-v1
-- (22-nov) el grafo de carreteras se completa tras viajar al sitio: la boca se calcula cuando ya está la calle junto al
-- aparcamiento (una calle a menos de 45 m del centro; como mucho 20 s de espera)
local graphWait
function M.graphReady(site)
  -- (26-nov) y el suelo afinado: en Sierra Morena el parque se montaba con el terreno grueso (z = 72 m, el suelo de verdad a
  -- 101 m): carpas enterradas y las comprobaciones de árboles y edificios (rayos desde z + 25) no veían nada
  local a = api()
  local grounded = true
  if a and a.ready then
    local okR, r = pcall(a.ready)
    if okR and r == false then grounded = false end
  end
  if not grounded then
    graphWait = graphWait or os.clock()
    if os.clock() - graphWait > 20 then graphWait = nil return true end
    return false
  end
  local okM, m = pcall(map.getMap)
  if okM and m and m.nodes then
    for _, nd in pairs(m.nodes) do
      if (nd.pos.x - site.x) ^ 2 + (nd.pos.y - site.y) ^ 2 < 45 ^ 2 then
        for _, ed in pairs(nd.links or {}) do
          if (type(ed) == 'table' and tonumber(ed.drivability) or 1) > M.LOT_DRIV then graphWait = nil return true end
        end
      end
    end
  end
  graphWait = graphWait or os.clock()
  if os.clock() - graphWait > 20 then graphWait = nil return true end
  return false
end

local function mouthRoute(m, h, cx, cy)
  -- (26-nov) acceso marcado por el usuario (M.PREFER.gate): la salida es esa, hasta la carretera de verdad más cercana
  if M.gateHint then
    local gx, gy = M.gateHint[1], M.gateHint[2]
    local best, bx, by, br
    for _, nd in pairs(m.nodes) do
      if (nd.pos.x - gx) ^ 2 + (nd.pos.y - gy) ^ 2 < 60 ^ 2 then
        for nb, ed in pairs(nd.links or {}) do
          local o = m.nodes[nb]
          local dr = type(ed) == 'table' and tonumber(ed.drivability) or 1
          if o and dr > M.LOT_DRIV then
            local vx, vy = o.pos.x - nd.pos.x, o.pos.y - nd.pos.y
            local L2 = vx * vx + vy * vy
            local u = L2 > 0 and math.max(0, math.min(1, ((gx - nd.pos.x) * vx + (gy - nd.pos.y) * vy) / L2)) or 0
            local qx, qy = nd.pos.x + vx * u, nd.pos.y + vy * u
            local d2 = (qx - gx) ^ 2 + (qy - gy) ^ 2
            if not inHull(h, qx, qy, 1) and (not best or d2 < best) then best, bx, by, br = d2, qx, qy, nd.radius or 3 end
          end
        end
      end
    end
    if bx then
      log('I', TAG, string.format('lot exit at the user\'s gate (%.1f, %.1f) -> road (%.1f, %.1f)', gx, gy, bx, by))
      -- la ruta cruza el borde del recinto justo en el acceso y en perpendicular (si no, el hueco y el TC0 quedaban 10 m
      -- más allá, donde la diagonal del centro al acceso cortaba el borde)
      if M.hullEdgePoint then
        local ex, ey = M.hullEdgePoint(h, gx, gy)
        local nx, ny = bx - ex, by - ey
        local nl = math.sqrt(nx * nx + ny * ny)
        if ex and nl > 0.5 then
          nx, ny = nx / nl, ny / nl
          return { { cx, cy, br }, { ex - nx * 6, ey - ny * 6, br }, { ex + nx * 2, ey + ny * 2, br }, { bx, by, br } }
        end
      end
      return { { cx, cy, br }, { gx, gy, br }, { bx, by, br } }
    end
  end
  local R2 = (M.GATE_SEARCH_M + 40) ^ 2
  local adj, cls = {}, {}
  for k, nd in pairs(m.nodes) do
    if (nd.pos.x - cx) ^ 2 + (nd.pos.y - cy) ^ 2 <= R2 then
      for nb, ed in pairs(nd.links or {}) do
        if m.nodes[nb] then
          local dr = type(ed) == 'table' and tonumber(ed.drivability) or 1
          adj[k] = adj[k] or {}
          adj[nb] = adj[nb] or {}
          adj[k][nb], adj[nb][k] = true, true
          if dr > (cls[k] or 0) then cls[k] = dr end
          if dr > (cls[nb] or 0) then cls[nb] = dr end
        end
      end
    end
  end
  local start, sd, goal, gd
  for k in pairs(adj) do
    local q = m.nodes[k].pos
    local d = (q.x - cx) ^ 2 + (q.y - cy) ^ 2
    if not sd or d < sd then start, sd = k, d end
    if (cls[k] or 0) > M.LOT_DRIV and not inHull(h, q.x, q.y, M.RUN_OFF_M + 2) and (not gd or d < gd) then goal, gd = k, d end
  end
  -- (26-nov) ¿tiene el aparcamiento calles propias en el grafo? Antes la recta de abajo se usaba SIEMPRE (el `if start`
  -- era cierto en todos los casos) y la ruta por el grafo nunca se calculaba.
  local lotStreets = false
  for k in pairs(adj) do
    local q = m.nodes[k].pos
    if (cls[k] or 0) <= M.LOT_DRIV and inHull(h, q.x, q.y, 2) then lotStreets = true break end
  end
  -- NORMA (26-nov, el usuario: "el TC0 ha de estar en la salida asfaltada siempre que sea posible"; Canarias lo ponía en
  -- la esquina de tierra): sin calles del aparcamiento en el grafo, la boca es la unión ASFALTADA del recinto con una
  -- carretera de verdad, leída del material del terreno de BeamNG.Earth (bngEarthGroundAsphalt)
  if not lotStreets then
    local okP, paved = pcall(M.pavedMouthRoute, m, h, cx, cy)
    if okP and paved then return paved end
  end
  -- sin unión asfaltada: la recta del box al punto más cercano de una carretera de verdad, como la línea que pinta el GPS
  if start and not lotStreets then
    local bx, by, bd, brad
    for _, nd in pairs(m.nodes) do
      for nb, ed in pairs(nd.links or {}) do
        local o = m.nodes[nb]
        local dr = type(ed) == 'table' and tonumber(ed.drivability) or 1
        if o and dr > M.LOT_DRIV and (nd.pos.x - cx) ^ 2 + (nd.pos.y - cy) ^ 2 <= R2 then
          local ax, ay = nd.pos.x, nd.pos.y
          local vx, vy = o.pos.x - ax, o.pos.y - ay
          local L2 = vx * vx + vy * vy
          local tt = L2 > 0 and math.max(0, math.min(1, ((cx - ax) * vx + (cy - ay) * vy) / L2)) or 0
          local px, py = ax + vx * tt, ay + vy * tt
          if not inHull(h, px, py, M.RUN_OFF_M + 2) then
            local d = (px - cx) ^ 2 + (py - cy) ^ 2
            if not bd or d < bd then bd, bx, by, brad = d, px, py, nd.radius end
          end
        end
      end
    end
    if bx then return { { cx, cy, brad or 2.5 }, { bx, by, brad or 2.5 } } end
    return nil
  end
  if not (start and goal) then return nil end
  local dist, prev, done = { [start] = 0 }, {}, {}
  while true do
    local u, ud
    for k, d in pairs(dist) do if not done[k] and (not ud or d < ud) then u, ud = k, d end end
    if not u or u == goal then break end
    done[u] = true
    local pu = m.nodes[u].pos
    for nb in pairs(adj[u] or {}) do
      local pn = m.nodes[nb].pos
      local d2 = ud + math.sqrt((pn.x - pu.x) ^ 2 + (pn.y - pu.y) ^ 2)
      if not dist[nb] or d2 < dist[nb] then dist[nb], prev[nb] = d2, u end
    end
  end
  if not dist[goal] then return nil end
  local rev, k = {}, goal
  while k do local q = m.nodes[k].pos rev[#rev + 1] = { q.x, q.y, m.nodes[k].radius } k = prev[k] end
  local out = {}
  for i = #rev, 1, -1 do out[#out + 1] = rev[i] end
  return out
end

-- ---- la salida asfaltada del recinto (26-nov) ---------------------------------------------------------------------------
-- El terreno de BeamNG.Earth pinta el asfalto de los aparcamientos y sus accesos (material bngEarthGroundAsphalt), aunque el
-- grafo no tenga esas calles. Se buscan pasillos asfaltados de al menos PAVED_W_M de ancho que unan el borde del recinto con
-- una carretera de verdad (drivability > LOT_DRIV) a menos de PAVED_MAX_M; gana el más corto (a igualdad, el que queda hacia
-- el primer control). Devuelve la ruta { centro, borde, carretera } o nil.
M.PAVED_MAX_M, M.PAVED_W_M, M.PAVED_STEP_M = 45, 5, 1
local terrainBlock
local pavedCache = {}
function M.isPaved(x, y)
  terrainBlock = terrainBlock or scenetree.findObject('bngEarthTerrain')
  if not terrainBlock then return nil end
  local okI, idx = pcall(function() return terrainBlock:getMaterialIdxWs(vec3(x, y, 0)) end)
  if not okI or idx == nil or idx < 0 then return nil end
  local nm = pavedCache[idx]
  if nm == nil then
    local okN, name = pcall(function() return terrainBlock:getMaterialName(idx) end)
    name = tostring(okN and name or ''):lower()
    nm = (name:find('asphalt') or name:find('concrete') or name:find('paved')) and true or false
    pavedCache[idx] = nm
  end
  return nm
end
local function hullEdgePoint(h, x, y)
  local bd, bx, by
  for i = 1, #h do
    local A, B = h[i], h[i % #h + 1]
    local ex, ey = B[1] - A[1], B[2] - A[2]
    local L2 = ex * ex + ey * ey
    local t = L2 > 0 and math.max(0, math.min(1, ((x - A[1]) * ex + (y - A[2]) * ey) / L2)) or 0
    local px, py = A[1] + ex * t, A[2] + ey * t
    local d = (px - x) ^ 2 + (py - y) ^ 2
    if not bd or d < bd then bd, bx, by = d, px, py end
  end
  return bx, by, bd and math.sqrt(bd) or 1e9
end
M.hullEdgePoint = hullEdgePoint
function M.pavedMouthRoute(m, h, cx, cy, tx, ty)
  if M.isPaved(cx, cy) == nil then return nil end
  local R2 = (M.GATE_SEARCH_M + 40) ^ 2
  local best
  for _, nd in pairs(m.nodes) do
    if (nd.pos.x - cx) ^ 2 + (nd.pos.y - cy) ^ 2 <= R2 then
      for nb, ed in pairs(nd.links or {}) do
        local o = m.nodes[nb]
        local dr = type(ed) == 'table' and tonumber(ed.drivability) or 1
        if o and dr > M.LOT_DRIV then
          local ax, ay = nd.pos.x, nd.pos.y
          local vx, vy = o.pos.x - ax, o.pos.y - ay
          local L = math.sqrt(vx * vx + vy * vy)
          for d = 0, L, 3 do
            local qx, qy = ax + vx * d / math.max(L, 0.01), ay + vy * d / math.max(L, 0.01)
            if not inHull(h, qx, qy, 2) then
              local ex, ey, de = hullEdgePoint(h, qx, qy)
              local rad = math.max(nd.radius or 2.5, o.radius or 2.5)
              local gap = de - rad
              if gap <= M.PAVED_MAX_M and (not best or de < best.score + 6) then
                -- el pasillo: del borde del recinto al borde de la calzada, asfalto en el eje y a ± media anchura
                local ux, uy = (qx - ex) / math.max(de, 0.01), (qy - ey) / math.max(de, 0.01)
                local nx, ny = -uy, ux
                -- el eje, asfalto entero; los lados, al menos el 80 % (bordillos, farolas). El último 1,5 m antes de la calzada
                -- no cuenta: bajo la malla de la carretera el terreno puede ser de otro material
                local ok, sides, n = true, 0, 0
                local hw = M.PAVED_W_M / 2
                for t = 0, math.max(0, gap - 1.5), M.PAVED_STEP_M do
                  local px, py = ex + ux * t, ey + uy * t
                  if not M.isPaved(px, py) then ok = false break end
                  n = n + 2
                  if M.isPaved(px + nx * hw, py + ny * hw) then sides = sides + 1 end
                  if M.isPaved(px - nx * hw, py - ny * hw) then sides = sides + 1 end
                end
                if ok and n > 0 and sides < n * 0.8 then ok = false end
                if ok then
                  local toward = (tx and ((qx - tx) ^ 2 + (qy - ty) ^ 2) ^ 0.5 or 0) * 0.02
                  local score = de + toward
                  if not best or score < best.score then best = { score = score, ex = ex, ey = ey, qx = qx, qy = qy, rad = rad } end
                end
              end
            end
          end
        end
      end
    end
  end
  if not best then return nil end
  log('I', TAG, string.format('paved lot exit at (%.1f, %.1f) -> road (%.1f, %.1f)', best.ex, best.ey, best.qx, best.qy))
  -- un paso hacia dentro del recinto en la misma dirección, para que la ruta cruce el borde por el pasillo asfaltado
  local ix, iy = best.ex - (best.qx - best.ex) * 0.2, best.ey - (best.qy - best.ey) * 0.2
  return { { cx, cy, best.rad }, { ix, iy, best.rad }, { best.qx, best.qy, best.rad } }
end

local function exitMouth(h, cx, cy, z)
  local okM, m = pcall(map.getMap)
  local route = okM and m and m.nodes and mouthRoute(m, h, cx, cy) or nil
  M.dbg = { hull = h, cx = cx, cy = cy, route = route }
  local gate
  if not route then
    gate = exitGate(cx, cy, z)
    if not gate then return nil end
    route = { { cx, cy }, { gate.x, gate.y } }
  end
  for i = 1, #route - 1 do
    local A, B = route[i], route[i + 1]
    local L = math.sqrt((B[1] - A[1]) ^ 2 + (B[2] - A[2]) ^ 2)
    if L > 0.5 then
      local ux, uy = (B[1] - A[1]) / L, (B[2] - A[2]) / L
      for d = 0, L, 1 do
        local x, y = A[1] + ux * d, A[2] + uy * d
        if not inHull(h, x, y, M.RUN_OFF_M) then
          local rad = A[3] or B[3] or 2
          log('I', TAG, string.format('lot mouth at (%.1f, %.1f), route of %d nodes', x, y, #route))
          do   -- la línea de stop paralela al vallado: la salida es la normal exterior del lado del recinto por el que cruza
            local bd2, bnx, bny
            for i2 = 1, #h do
              local A2, B2 = h[i2], h[i2 % #h + 1]
              local ex2, ey2 = B2[1] - A2[1], B2[2] - A2[2]
              local L2 = math.sqrt(ex2 * ex2 + ey2 * ey2)
              if L2 > 0.5 then
                local t2 = math.max(0, math.min(1, ((x - A2[1]) * ex2 + (y - A2[2]) * ey2) / (L2 * L2)))
                local d2 = (x - A2[1] - ex2 * t2) ^ 2 + (y - A2[2] - ey2 * t2) ^ 2
                if not bd2 or d2 < bd2 then bd2, bnx, bny = d2, ey2 / L2, -ex2 / L2 end
              end
            end
            if bnx and bnx * ux + bny * uy > 0.2 then ux, uy = bnx, bny end
          end
          return { x = x, y = y, z = terrainZ(x, y) or z, ux = ux, uy = uy, bx = -ux, by = -uy,
            hw = math.max(2.5, math.min(3.5, rad + 1)), gate = true, mouth = true }
        end
      end
    end
  end
  return gate or exitGate(cx, cy, z)
end
M.exitMouth = exitMouth   -- (26-nov) para la auditoría de boxes

-- Árboles de BeamNG.Earth (objetos Forest: castRayStatic no los ve) cerca del parque, una vez por montaje (26-nov: en el
-- aparcamiento de la plaza de toros salía un árbol dentro de una carpa)
M.TREE_CLEAR_M = 2.2
local treeCache = nil
function M.cacheTrees(cx, cy, r)
  treeCache = {}
  local z = terrainZ(cx, cy) or 0
  for _, name in ipairs(scenetree.findClassObjects('Forest') or {}) do
    local f = scenetree.findObject(name)
    local ok, items = pcall(function() return f:getData():getItemsCircle(vec3(cx, cy, z), r) end)
    if ok and items then
      for _, it in ipairs(items) do
        local okP, p = pcall(function() return it:getPosition() end)
        if okP and p then treeCache[#treeCache + 1] = { p.x, p.y } end
      end
    end
  end
  return #treeCache
end
local function treeAt(x, y, r)
  if not treeCache then return false end
  for _, t in ipairs(treeCache) do
    if (t[1] - x) ^ 2 + (t[2] - y) ^ 2 < r * r then return true end
  end
  return false
end
M.treeAt = treeAt
-- ¿cabe la carpa 3x6 de una plaza (girada como la plaza) sin tocar un edificio, un muro o un árbol?
local function boxFree(p)
  local hdg = math.rad(p[4] or 0)
  local fx, fy = math.cos(hdg), math.sin(hdg)
  local sx, sy = fy, -fx
  for _, f in ipairs({ -3, 0, 3 }) do
    for _, sd in ipairs({ -1.7, 0, 1.7 }) do
      if treeAt(p[1] + fx * f + sx * sd, p[2] + fy * f + sy * sd, M.TREE_CLEAR_M) then return false end
    end
  end
  for _, f in ipairs({ -3, 0, 3 }) do
    for _, sd in ipairs({ -1.7, 0, 1.7 }) do
      local ok, d = pcall(castRayStatic, vec3(p[1] + fx * f + sx * sd, p[2] + fy * f + sy * sd, (p[3] or 0) + 25), vec3(0, 0, -1), 40)
      if ok and d and d < 24.3 then return false end
    end
  end
  return true
end

-- distancia con signo al recinto (negativa dentro)
local function sdHull(h, x, y)
  local best, ins = math.huge, true
  for i = 1, #h do
    local A, B = h[i], h[i % #h + 1]
    local ex, ey = B[1] - A[1], B[2] - A[2]
    local L = math.sqrt(ex * ex + ey * ey)
    if L > 0 then
      if (ex * (y - A[2]) - ey * (x - A[1])) / L < 0 then ins = false end
      local t = math.max(0, math.min(1, ((x - A[1]) * ex + (y - A[2]) * ey) / (L * L)))
      local d = math.sqrt((x - A[1] - ex * t) ^ 2 + (y - A[2] - ey * t) ^ 2)
      if d < best then best = d end
    end
  end
  return ins and -best or best
end

local function centered(list, k)
  local l = {}
  for i, v in ipairs(list) do l[i] = v end
  while #l > k do table.remove(l, #l % 2 == 0 and 1 or #l) end
  return l
end

-- (22-nov, el usuario colocó a mano los boxes en fila contra el muro SO) El tramo recto más largo del recinto: aristas
-- consecutivas casi alineadas. Los boxes van en fila a lo largo de él, centrados, y la segunda fila es una copia trasladada
-- hacia dentro ROW_GAP_M (alineada y cuadrada con la primera, con pasillo para maniobrar).
M.BOX_PITCH_M = 7.8
M.TWIN_S1, M.TWIN_S2 = -2.7, 3.6      -- casetas del TC0 de box: antes y después de la línea de stop (medidas de la marca del usuario)
M.STREET_W_M, M.RUN_OFF_M = 9.2, 0.3 -- calle junto al aparcamiento: ancho entre vallas, y valla del lado del aparcamiento pegada al recinto
local function wallPicks(site, h)
  local n = #h
  local edges = {}
  for i = 1, n do
    local A, B = h[i], h[i % n + 1]
    local ex, ey = B[1] - A[1], B[2] - A[2]
    local L = math.sqrt(ex * ex + ey * ey)
    if L > 0.5 then edges[#edges + 1] = { A = A, B = B, L = L, a = math.atan2(ey, ex) } end
  end
  local best
  for s0 = 1, #edges do
    local len, last = edges[s0].L, edges[s0]
    for k = 1, #edges - 1 do
      local e = edges[(s0 + k - 1) % #edges + 1]
      local da = math.abs(((e.a - edges[s0].a + math.pi) % (2 * math.pi)) - math.pi)
      if da > math.rad(10) then break end
      len, last = len + e.L, e
    end
    if not best or len > best.len then best = { len = len, A = edges[s0].A, B = last.B } end
  end
  if not best or best.len < 2 * M.BOX_PITCH_M then return nil end
  local ex, ey = best.B[1] - best.A[1], best.B[2] - best.A[2]
  local L = math.sqrt(ex * ex + ey * ey)
  ex, ey = ex / L, ey / L
  local nx, ny = -ey, ex                       -- hacia dentro (el recinto es antihorario)
  local mx, my = (best.A[1] + best.B[1]) / 2, (best.A[2] + best.B[2]) / 2
  local cnt = math.floor((L - 2) / M.BOX_PITCH_M) + 1
  local function row(off)
    local r = {}
    for i = 1, cnt do
      local t = (i - (cnt + 1) / 2) * M.BOX_PITCH_M
      local x, y = mx + ex * t + nx * off, my + ey * t + ny * off
      local z = terrainZ(x, y)
      local pk = { x, y, z or site.z or 0, math.deg(math.atan2(ny, nx)), face = true, fx = nx, fy = ny }
      if z and boxFree(pk) and (off == 0 or sdHull(h, x, y) < -3.5) then r[#r + 1] = pk end
    end
    return r
  end
  local A = row(0)
  local B = row(M.ROW_GAP_M)
  return A, B
end

-- NORMA (26-nov, el usuario: "ningún objeto en la calzada, y menos en un acceso o salida de boxes; nunca, aunque no tengan
-- colisión"): una valla del recinto no va sobre una carretera del grafo (su radio + 1 m) ni sobre el pasillo de salida (la
-- ruta de la boca a la carretera, 4,5 m a cada lado del eje). MARK:fence-clear-v1
local function fenceClearance(cx, cy, h)
  local segs, corridor = {}, {}
  local okM, m = pcall(map.getMap)
  if okM and m and m.nodes then
    local R2 = 420 ^ 2
    for _, nd in pairs(m.nodes) do
      if (nd.pos.x - cx) ^ 2 + (nd.pos.y - cy) ^ 2 < R2 then
        for nb, ed in pairs(nd.links or {}) do
          local o = m.nodes[nb]
          local dr = type(ed) == 'table' and tonumber(ed.drivability) or 1
          -- los pasillos del propio aparcamiento (dentro del recinto) no cuentan: el vallado va por fuera de ellos
          -- (26-nov, el usuario: «una valla en el centro del camino de tierra de la salida de boxes»): un pasillo que SALE
          -- del recinto (un extremo dentro y otro fuera) es el acceso, no un pasillo interior: cuenta y se deja libre
          local inner = dr <= M.LOT_DRIV and h and (inHull(h, nd.pos.x, nd.pos.y, 3) and inHull(h, o and o.pos.x or 0, o and o.pos.y or 0, 3))
          -- junto al TC0 (la boca por la que sale el coche) ningún pasillo es interior: se deja libre
          local ts = M.tcSpot
          if inner and ts and ts.x and o and ((nd.pos.x - ts.x) ^ 2 + (nd.pos.y - ts.y) ^ 2 < 25 * 25 or (o.pos.x - ts.x) ^ 2 + (o.pos.y - ts.y) ^ 2 < 25 * 25) then inner = false end
          if o and not inner then segs[#segs + 1] = { nd.pos.x, nd.pos.y, o.pos.x, o.pos.y, math.max(nd.radius or 2.5, o.radius or 2.5) + 1.0 } end
        end
      end
    end
  end
  local r = M.dbg and M.dbg.route
  if r then
    for i = 1, #r - 1 do corridor[#corridor + 1] = { r[i][1], r[i][2], r[i + 1][1], r[i + 1][2], 4.5 } end
  end
  -- y del TC0 a la carretera más cercana (por donde sale el coche, el GPS empieza ahí)
  local ts = M.tcSpot
  if ts and ts.x and okM and m and m.nodes then
    local bx, by, bd
    for _, nd in pairs(m.nodes) do
      local d = (nd.pos.x - ts.x) ^ 2 + (nd.pos.y - ts.y) ^ 2
      if d > 4 and d < 60 * 60 and (not bd or d < bd) and not (h and inHull(h, nd.pos.x, nd.pos.y, 0)) then bx, by, bd = nd.pos.x, nd.pos.y, d end
    end
    if bx then corridor[#corridor + 1] = { ts.x, ts.y, bx, by, 4.5 } end
  end
  local function near(list, x, y)
    for _, sg in ipairs(list) do
      local vx, vy = sg[3] - sg[1], sg[4] - sg[2]
      local L2 = vx * vx + vy * vy
      local t = L2 > 0 and math.max(0, math.min(1, ((x - sg[1]) * vx + (y - sg[2]) * vy) / L2)) or 0
      local px, py = sg[1] + vx * t, sg[2] + vy * t
      if (x - px) ^ 2 + (y - py) ^ 2 < sg[5] * sg[5] then return true end
    end
    return false
  end
  return function(x, y)
    -- la valla mide ~2,5 m: se miran su centro y sus extremos
    return not near(segs, x, y) and not near(corridor, x, y)
  end, segs
end

local function lotFence(site)
  local a = api()
  if not (a and site and site.stalls and #site.stalls >= 6) then return 0 end
  local h = hullOf(site.stalls)
  if #h < 3 then return 0 end
  -- el hueco del vallado: en la boca de salida (por donde va el GPS y está el TC0), con sitio para las dos casetas
  local gates, gap = {}, M.LOT_FENCE_GAP_M
  if M.tcSpot then gates[#gates + 1] = { M.tcSpot.x, M.tcSpot.y } end
  if M.tcSpot and M.tcSpot.mouth then gap = (M.tcSpot.hw or 3) + 0.1     -- hueco = el ancho del carril (7 m en la marca del usuario)
  elseif site.exitX then gates[#gates + 1] = { site.exitX, site.exitY } end
  local z0 = site.z or terrainZ(site.x, site.y) or 0
  local n, skipped = 0, 0
  local clear, roadSegs = fenceClearance(site.x, site.y, h)
  local cands = {}
  -- el tramo recto del recinto por el que sale la ruta (la calle va pegada): su valla va junto al borde y la del otro lado de
  -- la calle, paralela a STREET_W_M
  local runSet, runA, runB = {}, nil, nil
  if M.tcSpot and M.tcSpot.mouth then
    local bi, bd
    for i = 1, #h do
      local A, B = h[i], h[i % #h + 1]
      local ex, ey = B[1] - A[1], B[2] - A[2]
      local L = math.sqrt(ex * ex + ey * ey)
      if L > 0.5 then
        local t = math.max(0, math.min(1, ((M.tcSpot.x - A[1]) * ex + (M.tcSpot.y - A[2]) * ey) / (L * L)))
        local d = (M.tcSpot.x - A[1] - ex * t) ^ 2 + (M.tcSpot.y - A[2] - ey * t) ^ 2
        if not bd or d < bd then bi, bd = i, d end
      end
    end
    if bi then
      local function ang(i) local A, B = h[i], h[i % #h + 1] return math.atan2(B[2] - A[2], B[1] - A[1]) end
      local a0 = ang(bi)
      local function same(i) return math.abs(((ang(i) - a0 + math.pi) % (2 * math.pi)) - math.pi) < math.rad(18) end
      local lo, hi = bi, bi
      runSet[bi] = true
      for _ = 1, #h - 1 do local j = (lo - 2) % #h + 1 if runSet[j] or not same(j) then break end lo = j runSet[j] = true end
      for _ = 1, #h - 1 do local j = hi % #h + 1 if runSet[j] or not same(j) then break end hi = j runSet[j] = true end
      runA, runB = h[lo], h[hi % #h + 1]
    end
  end
  for i = 1, #h do
    local A, B = h[i], h[i % #h + 1]
    local ex, ey = B[1] - A[1], B[2] - A[2]
    local L = math.sqrt(ex * ex + ey * ey)
    if L > 1 then
      ex, ey = ex / L, ey / L
      local OFF = runSet[i] and M.RUN_OFF_M or M.LOT_FENCE_OFF_M
      local ox, oy = ey * OFF, -ex * OFF       -- hacia fuera (derecha del lado)
      local la0, lo0 = a.toGeo(A[1], A[2], z0)
      local la1, lo1 = a.toGeo(A[1] + ex * 10, A[2] + ey * 10, z0)
      local kk = math.cos(math.rad(la0)) * 111195
      local gx, gy = (lo1 - lo0) * kk, (la1 - la0) * 111195
      local gl = math.sqrt(gx * gx + gy * gy)
      if gl > 0.01 then gx, gy = gx / gl, gy / gl else gx, gy = 0, 1 end
      for d = 0, L, M.LOT_FENCE_PITCH_M do
        local x, y = A[1] + ex * d + ox, A[2] + ey * d + oy
        local z = terrainZ(x, y)
        -- en un talud (la valla caía 2-5 m por encima del suelo del aparcamiento), se acerca al recinto hasta que el suelo coincide
        if z and math.abs(z - z0) >= 2.5 then
          for _, off in ipairs({ 3, 2, 1, 0.3 }) do
            local x2, y2 = A[1] + ex * d + ey * off, A[2] + ey * d - ex * off
            local z2 = terrainZ(x2, y2)
            if z2 and math.abs(z2 - z0) < 2.5 then x, y, z = x2, y2, z2 break end
          end
        end
        local ok = z ~= nil and math.abs(z - z0) < 2.5
        if ok then
          for _, g in ipairs(gates) do
            if (x - g[1]) ^ 2 + (y - g[2]) ^ 2 < gap ^ 2 then ok = false break end
          end
        end
        if ok and not clear(x, y) then ok = false end
        if ok then
          local hitOk, hd = pcall(castRayStatic, vec3(x, y, z + 25), vec3(0, 0, -1), 40)
          if hitOk and hd and hd < 24.3 then ok = false end
        end
        if ok then
          cands[#cands + 1] = { x = x, y = y, z = z, gx = gx, gy = gy }
        else skipped = skipped + 1 end
      end
    end
  end
  -- (26-nov) con el tope de piezas, primero las más cercanas a la salida (TC0) y a los boxes: antes se cortaba según por qué
  -- esquina empezaba la vuelta y el lado de la salida podía quedar sin vallar
  local fx, fy = M.tcSpot and M.tcSpot.x or site.x, M.tcSpot and M.tcSpot.y or site.y
  table.sort(cands, function(p1, p2)
    return math.min((p1.x - fx) ^ 2 + (p1.y - fy) ^ 2, (p1.x - site.x) ^ 2 + (p1.y - site.y) ^ 2)
      < math.min((p2.x - fx) ^ 2 + (p2.y - fy) ^ 2, (p2.x - site.x) ^ 2 + (p2.y - site.y) ^ 2)
  end)
  for _, c in ipairs(cands) do
    if n >= M.LOT_FENCE_MAX then skipped = skipped + 1
    else
      local la, lo = a.toGeo(c.x, c.y, c.z)
      if props.add(M.LOT_FENCE_KINDS[n % #M.LOT_FENCE_KINDS + 1], la, lo, c.gx, c.gy, 0, { row = true, noPush = true }) then n = n + 1 end
    end
  end
  -- la valla del otro lado de la calle, solo si de verdad hay una calle pegada y paralela al recinto (en Canarias la salida
  -- es un acceso perpendicular y esta fila cortaba el acceso asfaltado)
  local streetAlong = false
  if runA and runB then
    local ex, ey = runB[1] - runA[1], runB[2] - runA[2]
    local L = math.sqrt(ex * ex + ey * ey)
    if L > 3 then
      ex, ey = ex / L, ey / L
      local mx, my = (runA[1] + runB[1]) / 2 + ey * (M.RUN_OFF_M + M.STREET_W_M / 2), (runA[2] + runB[2]) / 2 - ex * (M.RUN_OFF_M + M.STREET_W_M / 2)
      for _, sg in ipairs(roadSegs) do
        local vx, vy = sg[3] - sg[1], sg[4] - sg[2]
        local l = math.sqrt(vx * vx + vy * vy)
        if l > 1 and math.abs((vx * ex + vy * ey) / l) > 0.9 then
          local t = math.max(0, math.min(1, ((mx - sg[1]) * vx + (my - sg[2]) * vy) / (l * l)))
          if (mx - sg[1] - vx * t) ^ 2 + (my - sg[2] - vy * t) ^ 2 < (M.STREET_W_M / 2 + 2) ^ 2 then streetAlong = true break end
        end
      end
    end
  end
  if runA and runB and streetAlong then
    local ex, ey = runB[1] - runA[1], runB[2] - runA[2]
    local L = math.sqrt(ex * ex + ey * ey)
    if L > 3 then
      ex, ey = ex / L, ey / L
      local off = M.RUN_OFF_M + M.STREET_W_M
      local la0, lo0 = a.toGeo(runA[1], runA[2], z0)
      local la1, lo1 = a.toGeo(runA[1] + ex * 10, runA[2] + ey * 10, z0)
      local kk = math.cos(math.rad(la0)) * 111195
      local gx, gy = (lo1 - lo0) * kk, (la1 - la0) * 111195
      local gl = math.sqrt(gx * gx + gy * gy)
      if gl > 0.01 then gx, gy = gx / gl, gy / gl else gx, gy = 0, 1 end
      local far = 0
      for d = -8, L + 8, M.LOT_FENCE_PITCH_M do
        local x, y = runA[1] + ex * d + ey * off, runA[2] + ey * d - ex * off
        local z = terrainZ(x, y)
        local ok = z ~= nil and math.abs(z - z0) < 2.5 and clear(x, y)
        if ok then
          local hitOk, hd = pcall(castRayStatic, vec3(x, y, z + 25), vec3(0, 0, -1), 40)
          if hitOk and hd and hd < 24.3 then ok = false end
        end
        if ok then
          local la, lo = a.toGeo(x, y, z)
          if props.add(M.LOT_FENCE_KINDS[(n + far) % #M.LOT_FENCE_KINDS + 1], la, lo, gx, gy, 0, { row = true, noPush = true }) then far = far + 1 end
        end
      end
      n = n + far
      log('I', TAG, ('street fence: %d pieces on the far side'):format(far))
    end
  end
  log('I', TAG, ('lot fence: %d pieces, %d spots skipped'):format(n, skipped))
  return n
end
M.lotFence = lotFence

-- (26-nov) quita las vallas del parque que, con el grafo de carreteras ya completo, quedan sobre un camino o en la salida
function M.recheckFences()
  local d = M.dbg
  if not (d and d.hull and d.cx) then return 0 end
  local a = api()
  if not a then return 0 end
  local clear = fenceClearance(d.cx, d.cy, d.hull)
  local n = 0
  for _, it in ipairs(props.all()) do
    if it.park and not it.hidden and it.lat and tostring(it.kind):find('^fence') then
      local x, y = a.toGame(it.lat, it.lon)
      if x and not clear(x, y) then props.hide(it) n = n + 1 end
    end
  end
  if n > 0 then log('I', TAG, ('lot fence: %d pieces removed from a path now loaded'):format(n)) end
  return n
end

local function buildOnStalls(site)
  local a = api()
  -- los ejes son los de las plazas (su rumbo = el largo de la plaza; una fila de plazas, a lo ancho), no los del rectángulo
  -- del sitio: si el aparcamiento está girado respecto a él, las bandas cortaban las filas en trozos (solo salían 2 boxes)
  local hdg0 = math.rad((site.stalls[1] and site.stalls[1][4]) or 0)
  local rx, ry = math.cos(hdg0), math.sin(hdg0)      -- profundidad de la plaza
  local hx, hy = ry, -rx                              -- a lo largo de la fila
  -- el lado de la salida = hacia la boca real (donde la ruta del GPS cruza el vallado); site.exit cambiaba entre arranques
  local exX, exY = site.exitX, site.exitY
  do
    local okE, g0 = pcall(exitMouth, hullOf(site.stalls), site.x, site.y, site.z or 0)
    if okE and g0 and g0.x then exX, exY = g0.x, g0.y end
  end
  local ex, ey = exX - site.x, exY - site.y
  local sideSign = (ex * rx + ey * ry) > 0 and -1 or 1
  -- las plazas por su coordenada de profundidad (bandas de 3 m = una fila)
  local bands = {}
  for _, p in ipairs(site.stalls) do
    local dx, dy = p[1] - site.x, p[2] - site.y
    local b = dx * rx + dy * ry
    local k = math.floor(b / 3 + 0.5)
    bands[k] = bands[k] or {}
    bands[k][#bands[k] + 1] = p
  end
  -- (22-nov) los boxes por niveles según el sitio: 1 (mínimo obligatorio), 2 (recomendable), 4 (de norma) y 8 (máximo, si el
  -- aparcamiento es grande), siempre sin tocar edificios ni muros. La primera fila es la más alejada de la salida; si
  -- hay otra a >= ROW_GAP_M hacia la salida, los boxes se reparten entre las dos.
  local function rowPicks(row)
    table.sort(row, function(p, q) return (p[1] - site.x) * hx + (p[2] - site.y) * hy < (q[1] - site.x) * hx + (q[2] - site.y) * hy end)
    local picks, last = {}, -math.huge
    for _, p in ipairs(row) do
      local al = (p[1] - site.x) * hx + (p[2] - site.y) * hy
      if al - last >= M.PAIR_M and boxFree(p) then picks[#picks + 1] = p last = al end
    end
    return picks
  end
  local bestK
  for _, need in ipairs({ 6, 2, 1 }) do
    for k, g in pairs(bands) do
      if #g >= need and (not bestK or k * sideSign > bestK * sideSign) then bestK = k end
    end
    if bestK then break end
  end
  if not bestK then return nil end
  local picksA = rowPicks(bands[bestK])
  local bestB
  for k, g in pairs(bands) do
    if k * sideSign < bestK * sideSign and math.abs(k - bestK) * 3 >= M.ROW_GAP_M and #g >= 5
        and (not bestB or math.abs(k - bestK) < math.abs(bestB - bestK)) then bestB = k end
  end
  local picksB = bestB and rowPicks(bands[bestB]) or {}
  -- (22-nov, el usuario: la fila de detrás "alineada y cuadrada" con la de delante, a distancia para maniobrar): una copia
  -- trasladada de la primera (mismas posiciones a lo largo, misma orientación) a la profundidad de la fila B
  if bestB and #picksA > 0 then
    local dk = (bestB - bestK) * 3
    local hl = hullOf(site.stalls)
    local copy = {}
    for _, q in ipairs(picksA) do
      local x, y = q[1] + rx * dk, q[2] + ry * dk
      local z = terrainZ(x, y) or q[3]
      local pk = { x, y, z, q[4], face = true }
      local fx, fy = math.cos(math.rad(q[4] or 0)), math.sin(math.rad(q[4] or 0))
      if (site.x - q[1]) * fx + (site.y - q[2]) * fy < 0 then fx, fy = -fx, -fy end
      pk.fx, pk.fy = fx, fy
      if (not q[3] or math.abs(z - q[3]) < 2) and sdHull(hl, x, y) < -3.5 and boxFree(pk) then copy[#copy + 1] = pk end
    end
    if #copy > 0 then picksB = copy end
  end
  do
    local okW, wa, wb = pcall(wallPicks, site, hullOf(site.stalls))
    if okW and wa and #wa >= 2 then picksA, picksB = wa, wb or {} end
  end
  if #picksA == 0 and #picksB > 0 then picksA, picksB = picksB, {} end
  if #picksA == 0 then return nil end
  local total = #picksA + #picksB
  local level = 1
  for _, L in ipairs(M.BOX_LEVELS) do if total >= L then level = L end end
  local nA, nB = math.min(#picksA, level), 0
  if level >= 4 and #picksB >= 2 then
    nA = math.min(#picksA, math.ceil(level / 2))
    nB = math.min(#picksB, level - nA)
    nA = math.min(#picksA, level - nB)
  end
  local picks = centered(picksA, nA)
  local mine = math.floor((#picks + 1) / 2)
  for _, p in ipairs(centered(picksB, nB)) do picks[#picks + 1] = p end
  log('I', TAG, ('boxes: %d (level %d; row A %d free, row B %d free)'):format(#picks, level, #picksA, #picksB))
  M.lvl = { ex = exX, ey = exY, sideSign = sideSign, n = #picks, level = level, a = #picksA, b = #picksB, bestK = bestK, bestB = bestB, bands = (function() local t = {} for k, g in pairs(bands) do t[#t + 1] = k .. ':' .. #g end return table.concat(t, ' ') end)() }
  local hull = hullOf(site.stalls)
  -- las plazas de los boxes y las de todo el aparcamiento dejan de ser plazas de aparcamiento (22-nov, el usuario: "coches
  -- de tráfico en el parking de box: no puede pasar, solo coches de rally en su box"): se vuelven a registrar las filas de la
  -- tesela sin ellas (parking.onRows, la entrada pública del módulo)
  pcall(function()
    local pk = require('beamngEarth/parking')
    local spots
    for i = 1, 40 do local nm, v = debug.getupvalue(pk.onRows, i) if not nm then break end if nm == 'spots' then spots = v break end end
    for key, t in pairs(spots or {}) do
      local keep, dropped = {}, 0
      for _, r in ipairs(t.rows or {}) do
        local near = #hull >= 3 and inHull(hull, r[1], r[2], 8)
        if not near then
          for _, p in ipairs(picks) do if (r[1] - p[1]) ^ 2 + (r[2] - p[2]) ^ 2 < M.NO_PARK_M ^ 2 then near = true break end end
        end
        if near then dropped = dropped + 1 else keep[#keep + 1] = r end
      end
      if dropped > 0 then pk.onRows(t.anchor, key, keep) end
    end
  end)
  local box
  local kinds = { 'gazebo3x6', 'gazebo3x6b', 'gazebo3x6r' }
  -- los coches de rally, repartidos: junto al del jugador y en la otra fila
  local cands = { mine - 1, mine + 1 }
  if #picks > #picksA or nB > 0 then cands[#cands + 1] = nA + math.ceil(nB / 2) end
  for _, i in ipairs({ mine + 2, mine - 2, nA + 1, nA + nB }) do cands[#cands + 1] = i end
  local cars = M.parkedCars(#picks, mine, cands)
  do
    -- la boca del recinto (por donde cruza la ruta de salida el vallado) y, de reserva, el extremo de la fila más cercano
    local cx, cy = 0, 0
    for _, p in ipairs(picks) do cx, cy = cx + p[1] / #picks, cy + p[2] / #picks end
    local e1, e2 = picks[1], picks[#picks]
    local e = firstEndIsNearer(e1[1], e1[2], e2[1], e2[2], site.exitX, site.exitY) and e1 or e2
    local hdg = math.rad(e[4] or 0)
    local fx, fy = math.cos(hdg), math.sin(hdg)
    if (site.x - e[1]) * fx + (site.y - e[2]) * fy < 0 then fx, fy = -fx, -fy end
    local ux, uy = fy, -fx
    if (e[1] - cx) * ux + (e[2] - cy) * uy < 0 then ux, uy = -ux, -uy end
    if #picks == 1 then
      local dx, dy = site.exitX - e[1], site.exitY - e[2]
      local dl = math.sqrt(dx * dx + dy * dy)
      if dl > 1 then ux, uy = dx / dl, dy / dl end
    end
    M.tcSpot = { x = e[1] + ux * M.TC0_BEYOND_M + fx * M.TC0_AISLE_M, y = e[2] + uy * M.TC0_BEYOND_M + fy * M.TC0_AISLE_M, z = e[3], ux = ux, uy = uy, fx = fx, fy = fy }
    -- la boca se calcula desde el centro de los boxes (no desde el del jugador: así no depende de cuál le toque)
    local mp = { 0, 0 }
    for _, q in ipairs(picks) do mp[1], mp[2] = mp[1] + q[1] / #picks, mp[2] + q[2] / #picks end
    local okG, gate = pcall(exitMouth, hull, mp[1], mp[2], e[3])
    if okG and gate then M.tcSpot = gate elseif not okG then log('W', TAG, 'mouth: ' .. tostring(gate)) end
  end
  for i, p in ipairs(picks) do
    local hdg = math.rad(p[4] or 0)
    local fx, fy = math.cos(hdg), math.sin(hdg)
    if (site.x - p[1]) * fx + (site.y - p[2]) * fy < 0 then fx, fy = -fx, -fy end
    if p.fx then fx, fy = p.fx, p.fy end
    local sx, sy = fy, -fx      -- a lo largo de la fila
    local k = kinds[(i - 1) % #kinds + 1]
    local function put(kind, fwd, side, yaw, opts)
      local la, lo = a.toGeo(p[1] + fx * fwd + sx * side, p[2] + fy * fwd + sy * side, p[3])
      return props.add(kind, la, lo, fx, fy, yaw or 0, opts)
    end
    -- una sola carpa 3x6 por coche, girada 90° (su lado largo, el del coche) y con los objetos del box de NGRC Rally Utah:
    -- dos extintores delante y un cono pequeño a rayas
    put(k, 0, 0, 90)
    -- en los boxes de al lado del tuyo, un coche de rally aparcado (ambiente)
    if cars[i] then put('rallyCar', 0, 0, 180, { vehicle = cars[i] }) end
    put('extinguisher', -M.EXT_BACK_M - 0.05, -0.7, 40)
    put('extinguisher', -M.EXT_BACK_M, -0.95, 250)
    -- (20-nov, norma del usuario: sin conos en los boxes; cada cono cerca del coche es un objeto con física)
    if i == mine then
      local la, lo = a.toGeo(p[1], p[2], p[3])
      local fla, flo = a.toGeo(p[1] - fx * 12, p[2] - fy * 12, p[3])       -- de morro: mirando al fondo
      box = { lat = la, lon = lo, faceLat = fla, faceLon = flo }
    end
  end
  local okF, errF = pcall(lotFence, site)
  if not okF then log('W', TAG, 'lot fence: ' .. tostring(errF)) end
  return box
end


-- Boxes en los puntos de M.MANUAL: la misma pieza que en la fila (carpa girada 90°, coche de morro, extintores atrás)
local function buildManual(site)
  local a = api()
  local man = site.manual
  local rad = math.rad(man.aisle)
  local mx, my = math.sin(rad), math.cos(rad)       -- "marcha": hacia donde sale el coche (el pasillo)
  local kinds = { 'gazebo3x6', 'gazebo3x6b', 'gazebo3x6r' }
  local n = #man.boxes
  local mine = n                                      -- el coche del jugador, en el box más cercano al camino
  local cars = M.parkedCars(n, mine)
  local box
  local function put(kind, la, lo, back, along, yaw, opts)
    local x, y = a.toGame(la, lo, 0)
    x, y = x - mx * back - my * along, y - my * back + mx * along
    local pla, plo = a.toGeo(x, y, terrainZ(x, y) or site.z)
    return props.add(kind, pla, plo, mx, my, yaw or 0, opts)
  end
  for i, b in ipairs(man.boxes) do
    put(kinds[(i - 1) % #kinds + 1], b[1], b[2], 0, 0, 90)
    if cars[i] then put('rallyCar', b[1], b[2], 0, 0, 180, { vehicle = cars[i] }) end
    put('extinguisher', b[1], b[2], M.EXT_BACK_M + 0.05, 0.7, 40)
    put('extinguisher', b[1], b[2], M.EXT_BACK_M, 0.95, 250)
    if i == mine then
      local x, y = a.toGame(b[1], b[2], 0)
      local fla, flo = a.toGeo(x - mx * 12, y - my * 12, site.z)
      box = { lat = b[1], lon = b[2], faceLat = fla, faceLon = flo }
    end
  end
  local o, f = math.rad(man.tc0.out), math.rad(man.tc0.face)
  M.tcSpot = { x = site.x, y = site.y, z = site.z, ux = math.sin(o), uy = math.cos(o), fx = math.sin(f), fy = math.cos(f), hw = man.tc0.hw }
  return box
end

function M.build(site)
  local a = api()
  M.tcSpot = nil
  if not (a and site) then return nil end
  -- los árboles del recinto, para no poner carpas encima
  pcall(M.cacheTrees, site.x, site.y, math.max(60, (site.len or 60) / 2 + (site.wid or 60) / 2 + 20))
  M.gateHint = nil
  if site.gate then
    local gx, gy = a.toGame(site.gate[1], site.gate[2], 0)
    if gx then M.gateHint = { gx, gy } end
  end
  -- (26-nov) la altura del sitio, otra vez ahora (la de la búsqueda podía ser del terreno aún sin afinar)
  do
    local z = terrainZ(site.x, site.y)
    if z then site.z = z end
    for _, st in ipairs(site.stalls or {}) do
      local sz = terrainZ(st[1], st[2])
      if sz then st[3] = sz end
    end
  end
  if site.manual then
    local ok, box = pcall(buildManual, site)
    if ok then return box end
    log('W', TAG, 'manual: ' .. tostring(box))
  end
  if site.stalls then
    local ok, box = pcall(buildOnStalls, site)
    if ok and box then return box end
    if not ok then log('W', TAG, 'stalls: ' .. tostring(box)) end
  end
  local hx, hy, rx, ry = site.hx, site.hy, site.hy, -site.hx
  -- la fila en el lado más alejado de la carretera de salida (el pasillo queda hacia la salida)
  local ex, ey = site.exitX - site.x, site.exitY - site.y
  local sideSign = (ex * rx + ey * ry) > 0 and -1 or 1
  -- (la fila entera dentro de las plazas: el fondo de las carpas a 1,5 m del borde de las plazas, no en el talud)
  local rowSide = sideSign * (site.wid / 2 - 8)
  local fit = math.floor((site.len - 4) / M.PAIR_M)
  local n = math.max(1, math.min(fit >= M.MAX_BOXES + M.BIG_EXTRA and M.MAX_BOXES + M.BIG_EXTRA or M.MAX_BOXES, fit))
  local along0 = -(n - 1) * M.PAIR_M / 2
  -- el pasillo: ¿hacia dónde se sale? el extremo de la fila más cercano a la salida
  local exitAlong = ex * hx + ey * hy
  local z = site.z
  local function put(kind, along, side, yaw, opts)
    local la, lo = a.toGeo(site.x + hx * along + rx * side, site.y + hy * along + ry * side, z)
    -- "marcha" del objeto: hacia el pasillo (desde la fila hacia el centro)
    return props.add(kind, la, lo, -sideSign * rx, -sideSign * ry, yaw or 0, opts)
  end
  local kinds = { 'gazebo3x6', 'gazebo3x6b', 'gazebo3x6r' }
  local mine = math.floor((n + 1) / 2)
  local box
  local cars = M.parkedCars(n, mine)
  do
    local hl = (n - 1) * M.PAIR_M / 2
    local sg = firstEndIsNearer(site.x + hx * hl + rx * rowSide, site.y + hy * hl + ry * rowSide,
      site.x - hx * hl + rx * rowSide, site.y - hy * hl + ry * rowSide, site.exitX, site.exitY) and 1 or -1
    local al = sg * ((n - 1) * M.PAIR_M / 2 + M.TC0_BEYOND_M)
    local sd = rowSide - sideSign * M.TC0_AISLE_M
    M.tcSpot = { x = site.x + hx * al + rx * sd, y = site.y + hy * al + ry * sd, z = z, ux = hx * sg, uy = hy * sg, fx = -sideSign * rx, fy = -sideSign * ry }
    local okG, gate = pcall(exitGate, site.x + rx * rowSide, site.y + ry * rowSide, z)
    if okG and gate then M.tcSpot = gate end
  end
  for i = 1, n do
    local along = along0 + (i - 1) * M.PAIR_M
    local k = kinds[(i - 1) % #kinds + 1]
    put(k, along, rowSide, 90)
    if cars[i] then put('rallyCar', along, rowSide, 180, { vehicle = cars[i] }) end
    put('extinguisher', along + 0.7, rowSide + sideSign * (M.EXT_BACK_M + 0.05), 40)
    put('extinguisher', along + 0.95, rowSide + sideSign * M.EXT_BACK_M, 250)
    if i == mine then
      local la, lo = a.toGeo(site.x + hx * along + rx * rowSide, site.y + hy * along + ry * rowSide, z)
      local fla, flo = a.toGeo(site.x + hx * along + rx * (rowSide + sideSign * 12), site.y + hy * along + ry * (rowSide + sideSign * 12), z)
      box = { lat = la, lon = lo, faceLat = fla, faceLon = flo }
    end
  end
  local _ = exitAlong
  return box
end

-- El TC0 a la salida del parque: en la carretera de salida, en el sentido hacia el primer control. Un trazado corto por
-- la carretera (40 m antes y 100 m después del punto de salida) para montar el puesto con las mismas piezas que el TC
-- de un tramo (dressing.tcPost). Devuelve { lat, lon } del punto de fichaje.
function M.tc0(site, dressing)
  local a = api()
  local sp = M.tcSpot
  if a and sp and not (site and site.byRoad) then
    -- el puesto en el pasillo de los boxes: un trazado recto hacia la salida del recinto (20 m antes y 40 después)
    local gpath = {}
    for d = -20, 40, 10 do
      local la, lo = a.toGeo(sp.x + sp.ux * d, sp.y + sp.uy * d, sp.z or 0)
      gpath[#gpath + 1] = { la, lo }
    end
    local t = geo.track(gpath)
    -- la caseta al lado del pasillo que mira a los boxes (como la puso el usuario): a la derecha de quien sale si la
    -- "delantera" de los boxes cae a su derecha
    local lado = -1
    if sp.bx then
      -- en la calle de salida: la caseta en el lado de los boxes
      -- (tcPost: lateral = out * lado, con out = -1; los boxes a la derecha de quien sale -> lado -1)
      lado = (sp.ux * sp.by - sp.uy * sp.bx) < 0 and -1 or 1
    elseif sp.fx and (sp.uy * sp.fx - sp.ux * sp.fy) < 0 then lado = 1 end
    local ok = pcall(dressing.tcPost, t, 20, -1, sp.hw or 3.5, 0, lado, false, true, { g = 1.9, s1 = M.TWIN_S1, s2 = M.TWIN_S2 })
    if ok then
      local la, lo = geo.toGeo(t, geo.at(t, 20))
      return { lat = la, lon = lo }
    end
  end
  if not (a and site and site.n1) then return nil end
  local m = map.getMap()
  local A, B = m.nodes[site.n1], m.nodes[site.n2]
  if not (A and B) then return nil end
  -- sentido: hacia el objetivo si lo hay; si no, hacia B
  local dx, dy = B.pos.x - A.pos.x, B.pos.y - A.pos.y
  local L = math.sqrt(dx * dx + dy * dy)
  if L < 0.5 then return nil end
  dx, dy = dx / L, dy / L
  if site.tx and ((site.tx - site.exitX) * dx + (site.ty - site.exitY) * dy) < 0 then dx, dy = -dx, -dy end
  -- la polilínea por el grafo: desde 40 m antes de la salida hasta 100 m después
  local function walk(fromN, toN, maxM)
    local pts, cur, prev, acc = {}, toN, fromN, 0
    while cur and acc < maxM do
      local p = m.nodes[cur].pos
      pts[#pts + 1] = { p.x, p.y }
      local nxt, bestDot = nil, -1
      local pp = m.nodes[prev].pos
      local ux, uy = p.x - pp.x, p.y - pp.y
      local ul = math.sqrt(ux * ux + uy * uy)
      if ul < 0.1 then break end
      ux, uy = ux / ul, uy / ul
      for nb, _ in pairs(m.nodes[cur].links or {}) do
        if nb ~= prev then
          local q = m.nodes[nb].pos
          local vx, vy = q.x - p.x, q.y - p.y
          local vl = math.sqrt(vx * vx + vy * vy)
          local dot = vl > 0 and (vx * ux + vy * uy) / vl or -1
          if dot > bestDot then bestDot, nxt = dot, nb end
        end
      end
      if not nxt or bestDot < 0.3 then break end
      acc = acc + math.sqrt((m.nodes[nxt].pos.x - p.x) ^ 2 + (m.nodes[nxt].pos.y - p.y) ^ 2)
      prev, cur = cur, nxt
    end
    return pts
  end
  local fwdN, backN = site.n2, site.n1
  if ((B.pos.x - A.pos.x) * dx + (B.pos.y - A.pos.y) * dy) < 0 then fwdN, backN = site.n1, site.n2 end
  local ahead = walk(backN, fwdN, 100)
  local behind = walk(fwdN, backN, 40)
  local pts = {}
  for i = #behind, 1, -1 do pts[#pts + 1] = behind[i] end
  -- el punto de salida en medio
  pts[#pts + 1] = { site.exitX, site.exitY }
  for _, p in ipairs(ahead) do pts[#pts + 1] = p end
  -- quitar repetidos / retrocesos
  local path = {}
  for _, p in ipairs(pts) do
    local q = path[#path]
    if not q or math.sqrt((p[1] - q[1]) ^ 2 + (p[2] - q[2]) ^ 2) > 1 then path[#path + 1] = p end
  end
  if #path < 2 then return nil end
  local gpath = {}
  for _, p in ipairs(path) do local la, lo = a.toGeo(p[1], p[2], site.z) gpath[#gpath + 1] = { la, lo } end
  local t = geo.track(gpath)
  -- el fichaje 30 m después de la salida del parque (sitio para el preaviso antes); si en la cuneta de ahí hay algo del
  -- mundo (una marquesina, una farola), un poco más adelante
  local exitAlong = 0
  for i = 1, #path do if path[i][1] == site.exitX and path[i][2] == site.exitY then exitAlong = t.cum[i] break end end
  local hw = (A.radius or 3)
  local statics = {}
  pcall(function()
    for _, nm in ipairs(scenetree.findClassObjects('TSStatic') or {}) do
      local o = scenetree.findObject(nm)
      if o then
        local p = o:getPosition()
        if math.abs(p.x - site.exitX) < 160 and math.abs(p.y - site.exitY) < 160 then statics[#statics + 1] = { p.x, p.y } end
      end
    end
  end)
  local function clearAt(al)
    local x, y = geo.at(t, al)
    local dx, dy = geo.dirAt(t, al)
    -- la carpa a la derecha, a hw + 2,6 m (del marco del trazado al del juego)
    local la, lo = geo.toGeo(t, x + dy * (hw + 2.6), y - dx * (hw + 2.6))
    local gx, gy = a.toGame(la, lo, 0)
    if not gx then return true end
    for _, q in ipairs(statics) do if (q[1] - gx) ^ 2 + (q[2] - gy) ^ 2 < 5 ^ 2 then return false end end
    return true
  end
  -- el fichaje EN la boca de salida del parque (19-nov, el usuario: la caseta TC0 donde se para el coche al salir del
  -- aparcamiento, desde ahí corre el tiempo del enlace); si el sitio no está libre, un poco más adelante
  local along = math.min(t.total - 10, math.max(12, exitAlong))
  for _, extra in ipairs({ 0, 5, 10, 18, 28 }) do
    local al = math.min(t.total - 10, math.max(12, exitAlong) + extra)
    if al > 12 and clearAt(al) then along = al break end
  end
  dressing.tcPost(t, along, -1, hw, 0, -1, false, false, { g = 1.9, s1 = M.TWIN_S1, s2 = M.TWIN_S2 })
  local la, lo = geo.toGeo(t, geo.at(t, along))
  return { lat = la, lon = lo }
end

-- Sin salida de aparcamiento a la vista (el parque cae en un descampado o el box de siempre): la salida se "crea" en la
-- carretera del juego más cercana (hasta ROAD_SITE_M), eligiendo la zona más llana (pendiente a lo largo del tramo de
-- calle que cuenta el doble que la distancia). Devuelve un sitio como el de la búsqueda, para M.tc0.
M.ROAD_SITE_M = 300
function M.roadSite(lat, lon, towardLat, towardLon)
  local a = api()
  if not (a and lat) then return nil end
  local okM, m = pcall(map.getMap)
  if not (okM and m and m.nodes) then return nil end
  local bx, by = a.toGame(lat, lon, 0)
  if not bx then return nil end
  local tx, ty
  if towardLat then tx, ty = a.toGame(towardLat, towardLon, 0) end
  local best, bs = nil, 1e9
  for n1, A in pairs(m.nodes) do
    local ax, ay = A.pos.x - bx, A.pos.y - by
    if ax * ax + ay * ay < (M.ROAD_SITE_M + 60) ^ 2 and (A.radius or 3) >= 2 then
      for n2 in pairs(A.links or {}) do
        local B = m.nodes[n2]
        if B and n1 < n2 then
          local ex, ey = B.pos.x - A.pos.x, B.pos.y - A.pos.y
          local el = math.sqrt(ex * ex + ey * ey)
          if el > 5 then
            local u = math.max(0, math.min(1, ((bx - A.pos.x) * ex + (by - A.pos.y) * ey) / (el * el)))
            local px, py = A.pos.x + ex * u, A.pos.y + ey * u
            local d = math.sqrt((px - bx) ^ 2 + (py - by) ^ 2)
            if d <= M.ROAD_SITE_M then
              local slope = math.abs(B.pos.z - A.pos.z) / el
              local score = d + slope * 600
              if score < bs then
                bs = score
                best = { n1 = n1, n2 = n2, exitX = px, exitY = py, z = A.pos.z + (B.pos.z - A.pos.z) * u, tx = tx, ty = ty, roadD = d, byRoad = true }
              end
            end
          end
        end
      end
    end
  end
  return best
end

M._lots = lots   -- (pruebas)
return M

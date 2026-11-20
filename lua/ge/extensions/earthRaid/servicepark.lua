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
M.BIG_EXTRA = 4      -- en un aparcamiento grande (caben todos), estos boxes más, para llenar (19-nov)
M.NO_PARK_M = 45     -- sin coches de tráfico aparcados a menos de esto de un box (19-nov: solo los de rally)
-- El box, como en los rallies del juego (19-nov, colocado a mano por el usuario con el editor): el coche entra de
-- morro y sale marcha atrás; los extintores al fondo de la carpa, no delante cortando el paso
M.EXT_BACK_M = 2.0
M.BUDGET_MS = 6

local function terrainZ(x, y)
  if core_terrain and core_terrain.getTerrainHeight then
    local z = core_terrain.getTerrainHeight(vec3(x, y, 0))
    if z and z > -1000 then return z end
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

-- Empieza la búsqueda. toward: hacia dónde se sale (el primer control), para orientar la salida.
function M.search(lat, lon, towardLat, towardLon)
  local a = api()
  if not (a and a.toGame) then return nil end
  local x0, y0 = a.toGame(lat, lon, 0)
  if not x0 then return nil end
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

local function blocked(h, x, y)
  local z = terrainZ(x, y)
  if not z then return true, nil end
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

local function tryLots(h)
  -- primero los aparcamientos de BeamNG.Earth (plazas del servidor): el más grande y cercano con carretera para salir
  for _, L in ipairs(lots(h)) do
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
    if n1 and rd and L.wid >= 14 and L.len >= 20 then
      h.site = { x = L.cx, y = L.cy, z = terrainZ(L.cx, L.cy) or L.z, hx = L.ux, hy = L.uy, len = L.len, wid = L.wid,
        exitX = px, exitY = py, n1 = n1, n2 = n2, roadD = rd, far = L.far, clear = 0, lot = L.n, stalls = L.pts, tx = h.tx, ty = h.ty }
      h.phase = 'done'
      log('I', TAG, ('parking lot: %d stalls, %.0f x %.0f m, %.0f m from the service point, road at %.0f m (%.1f s)'):format(
        L.n, L.len, L.wid, L.far, rd, os.clock() - h.t0))
      return true
    end
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
M.PARK_CARS = 2       -- (3 con la fila grande)
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
    hw = math.max(2.5, math.min(3.5, (P.radius or 2) + 1)), gate = true }
end
function M.parkedCars(n, mine)
  local out = {}
  local okS, st = pcall(function() return require('earthRaid/settings').get() end)
  if not okS or st.ambience == false or st.parkCars == false then return out end
  local slots = {}
  for _, i in ipairs({ mine - 1, mine + 1, mine - 2, mine + 2 }) do
    if i >= 1 and i <= n and #slots < (n > M.MAX_BOXES and M.PARK_CARS + 1 or M.PARK_CARS) then slots[#slots + 1] = i end
  end
  local okP, list = pcall(function() return require('earthRaid/phys').pickRallyCars(#slots, M.surface) end)
  if not okP then return out end
  for j, i in ipairs(slots) do out[i] = list[j] end
  return out
end

local function buildOnStalls(site)
  local a = api()
  -- los ejes son los de las plazas (su rumbo = el largo de la plaza; una fila de plazas, a lo ancho), no los del rectángulo
  -- del sitio: si el aparcamiento está girado respecto a él, las bandas cortaban las filas en trozos (solo salían 2 boxes)
  local hdg0 = math.rad((site.stalls[1] and site.stalls[1][4]) or 0)
  local rx, ry = math.cos(hdg0), math.sin(hdg0)      -- profundidad de la plaza
  local hx, hy = ry, -rx                              -- a lo largo de la fila
  local ex, ey = site.exitX - site.x, site.exitY - site.y
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
  -- la banda más alejada de la salida con plazas suficientes
  local bestK
  for k, g in pairs(bands) do
    if #g >= 6 and (not bestK or k * sideSign > bestK * sideSign) then bestK = k end
  end
  if not bestK then return nil end
  local row = bands[bestK]
  table.sort(row, function(p, q) return (p[1] - site.x) * hx + (p[2] - site.y) * hy < (q[1] - site.x) * hx + (q[2] - site.y) * hy end)
  -- plazas cada PAIR_M a lo largo de la fila, de un extremo al otro
  local picks, lastAlong = {}, -math.huge
  for _, p in ipairs(row) do
    local al = (p[1] - site.x) * hx + (p[2] - site.y) * hy
    if al - lastAlong >= M.PAIR_M then picks[#picks + 1] = p lastAlong = al end
  end
  local maxBoxes = #picks >= M.MAX_BOXES + M.BIG_EXTRA and M.MAX_BOXES + M.BIG_EXTRA or M.MAX_BOXES
  while #picks > maxBoxes do table.remove(picks, #picks % 2 == 0 and 1 or #picks) end
  if #picks == 0 then return nil end
  -- las plazas de los boxes dejan de ser plazas de aparcamiento (si no, el juego aparca coches dentro de las carpas):
  -- se vuelven a registrar las filas de la tesela sin ellas (parking.onRows, la entrada pública del módulo)
  pcall(function()
    local pk = require('beamngEarth/parking')
    local spots
    for i = 1, 40 do local nm, v = debug.getupvalue(pk.onRows, i) if not nm then break end if nm == 'spots' then spots = v break end end
    for key, t in pairs(spots or {}) do
      local keep, dropped = {}, 0
      for _, r in ipairs(t.rows or {}) do
        local near = false
        for _, p in ipairs(picks) do if (r[1] - p[1]) ^ 2 + (r[2] - p[2]) ^ 2 < M.NO_PARK_M ^ 2 then near = true break end end
        if near then dropped = dropped + 1 else keep[#keep + 1] = r end
      end
      if dropped > 0 then pk.onRows(t.anchor, key, keep) end
    end
  end)
  -- hacia el pasillo: la dirección de la plaza (su rumbo) que mira al centro del aparcamiento
  local mine = math.floor((#picks + 1) / 2)
  local box
  local kinds = { 'gazebo3x6', 'gazebo3x6b', 'gazebo3x6r' }
  local cars = M.parkedCars(#picks, mine)
  do
    -- el extremo de la fila más cercano a la salida del recinto, y el sitio del TC0 más allá
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
      -- una sola plaza: hacia la salida
      local dx, dy = site.exitX - e[1], site.exitY - e[2]
      local dl = math.sqrt(dx * dx + dy * dy)
      if dl > 1 then ux, uy = dx / dl, dy / dl end
    end
    M.tcSpot = { x = e[1] + ux * M.TC0_BEYOND_M + fx * M.TC0_AISLE_M, y = e[2] + uy * M.TC0_BEYOND_M + fy * M.TC0_AISLE_M, z = e[3], ux = ux, uy = uy, fx = fx, fy = fy }
    local okG, gate = pcall(exitGate, cx, cy, e[3])
    if okG and gate then M.tcSpot = gate end
  end
  for i, p in ipairs(picks) do
    local hdg = math.rad(p[4] or 0)
    local fx, fy = math.cos(hdg), math.sin(hdg)
    if (site.x - p[1]) * fx + (site.y - p[2]) * fy < 0 then fx, fy = -fx, -fy end
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
    put('coneS', 4.6, 1.3, 0)
    if i == mine then
      local la, lo = a.toGeo(p[1], p[2], p[3])
      local fla, flo = a.toGeo(p[1] - fx * 12, p[2] - fy * 12, p[3])       -- de morro: mirando al fondo
      box = { lat = la, lon = lo, faceLat = fla, faceLon = flo }
    end
    if i == 1 then put('coneS', 4.6, -3.4, 0) end
    if i == #picks then put('coneS', 4.6, 3.4, 0) end
  end
  return box
end

function M.build(site)
  local a = api()
  M.tcSpot = nil
  if not (a and site) then return nil end
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
  -- conos en los extremos de la fila
  put('coneS', along0 - 3.4, rowSide - sideSign * 4.6, 0)
  put('coneS', along0 + (n - 1) * M.PAIR_M + 3.4, rowSide - sideSign * 4.6, 0)
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
    local ok = pcall(dressing.tcPost, t, 20, -1, sp.hw or 3.5, 0, lado, false, true)
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
  dressing.tcPost(t, along, -1, hw, 0, -1, false)
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

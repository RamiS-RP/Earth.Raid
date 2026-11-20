-- Raid.Earth: geometría de un tramo en metros locales (este, norte) alrededor de su salida. Puro.
local M = {}
local rad, cos, sqrt, max, min = math.rad, math.cos, math.sqrt, math.max, math.min
M.M_PER_DEG = 111195

-- path { {lat, lon}... } -> track { lat0, lon0, k, pts = { {x, y} }, cum = { m }, total }
function M.track(path)
  local lat0, lon0 = path[1][1], path[1][2]
  local k = cos(rad(lat0))
  local t = { lat0 = lat0, lon0 = lon0, k = k, pts = {}, cum = { 0 }, total = 0 }
  for i, p in ipairs(path) do
    t.pts[i] = { (p[2] - lon0) * M.M_PER_DEG * k, (p[1] - lat0) * M.M_PER_DEG }
    if i > 1 then
      local a, b = t.pts[i - 1], t.pts[i]
      t.cum[i] = t.cum[i - 1] + sqrt((b[1] - a[1]) ^ 2 + (b[2] - a[2]) ^ 2)
    end
  end
  t.total = t.cum[#t.cum]
  return t
end

-- quita el principio del trazado hasta `along` (la salida pasa a estar ahí); devuelve el trozo quitado como path
-- { {lat, lon}... } (con el punto de corte al final). Mismo origen local (lat0, lon0): toLocal/toGeo siguen valiendo
function M.cutStart(t, along)
  if along <= 0 or along >= t.total then return nil end
  local x, y = M.at(t, along)
  local removed = {}
  local i = 1
  while t.cum[i + 1] and t.cum[i + 1] <= along do i = i + 1 end
  for k = 1, i do removed[#removed + 1] = { M.toGeo(t, t.pts[k][1], t.pts[k][2]) } end
  removed[#removed + 1] = { M.toGeo(t, x, y) }
  local pts, cum = { { x, y } }, { 0 }
  for k = i + 1, #t.pts do
    pts[#pts + 1] = t.pts[k]
    cum[#cum + 1] = t.cum[k] - along
  end
  if #pts >= 2 and cum[2] < 0.01 then table.remove(pts, 2) table.remove(cum, 2) end
  t.pts, t.cum = pts, cum
  t.total = cum[#cum]
  return removed
end

-- corta el trazado en `along` (la meta pasa a estar ahí)
function M.truncate(t, along)
  if along >= t.total or along <= 0 then return end
  local x, y = M.at(t, along)
  local i = 1
  while t.cum[i + 1] and t.cum[i + 1] < along do i = i + 1 end
  for k = #t.pts, i + 1, -1 do t.pts[k], t.cum[k] = nil, nil end
  t.pts[i + 1], t.cum[i + 1] = { x, y }, along
  t.total = along
end

function M.toLocal(t, lat, lon) return (lon - t.lon0) * M.M_PER_DEG * t.k, (lat - t.lat0) * M.M_PER_DEG end
function M.toGeo(t, x, y) return t.lat0 + y / M.M_PER_DEG, t.lon0 + x / (M.M_PER_DEG * t.k) end

-- El punto a `along` metros de la salida y la dirección de marcha allí: x, y, dx, dy (unitario)
function M.at(t, along)
  local n = #t.pts
  along = max(0, min(t.total, along))
  local i = 1
  while i < n - 1 and t.cum[i + 1] < along do i = i + 1 end
  local a, b = t.pts[i], t.pts[i + 1]
  local len = t.cum[i + 1] - t.cum[i]
  local f = len > 0 and (along - t.cum[i]) / len or 0
  local dx, dy = b[1] - a[1], b[2] - a[2]
  local l = sqrt(dx * dx + dy * dy)
  if l < 1e-6 then dx, dy, l = 0, 1, 1 end
  return a[1] + (b[1] - a[1]) * f, a[2] + (b[2] - a[2]) * f, dx / l, dy / l
end

-- La dirección de marcha suavizada en `along` (entre along-back y along+fwd)
function M.dirAt(t, along, span)
  span = span or 12
  local x1, y1 = M.at(t, max(0, along - span))
  local x2, y2 = M.at(t, min(t.total, along + span))
  local dx, dy = x2 - x1, y2 - y1
  local l = sqrt(dx * dx + dy * dy)
  if l < 1e-6 then local _, _, ax, ay = M.at(t, along) return ax, ay end
  return dx / l, dy / l
end

-- Proyección de (x, y) sobre el trazado cerca del tramo `hint` (índice): along, lateral (m), índice
function M.project(t, x, y, hint, back, fwd)
  local n = #t.pts
  local i0 = max(1, (hint or 1) - (back or 6))
  local i1 = min(n - 1, (hint or 1) + (fwd or 40))
  local best, bAlong, bi = 1e18, 0, i0
  for i = i0, i1 do
    local a, b = t.pts[i], t.pts[i + 1]
    local dx, dy = b[1] - a[1], b[2] - a[2]
    local l2 = dx * dx + dy * dy
    local f = l2 > 0 and ((x - a[1]) * dx + (y - a[2]) * dy) / l2 or 0
    f = max(0, min(1, f))
    local px, py = a[1] + dx * f, a[2] + dy * f
    local d2 = (x - px) ^ 2 + (y - py) ^ 2
    if d2 < best then best, bAlong, bi = d2, t.cum[i] + sqrt(l2) * f, i end
  end
  return bAlong, sqrt(best), bi
end

-- El reloj del rally es la hora del mapa (scenetree.tod: 0 = mediodía, 0.5 = medianoche), no la del ordenador
-- (19-nov: el reloj marcaba las 19:36 con el sol de las 9 de la mañana). Sin escena de hora, la del ordenador.
function M.dayClock()
  local ok, v = pcall(function() local t = scenetree.tod return t and t.time end)
  if ok and type(v) == 'number' then return math.floor(((v + 0.5) % 1) * 86400 + 0.5) % 86400 end
  local tm = os.date('*t')
  return tm.hour * 3600 + tm.min * 60 + tm.sec
end
function M.setDayClock(secs)
  pcall(function() local t = scenetree.tod if t then t.time = ((secs % 86400) / 86400 + 0.5) % 1 end end)
end

return M

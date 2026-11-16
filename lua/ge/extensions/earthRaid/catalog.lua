-- Raid.Earth: el catálogo de eventos y la búsqueda por zona. Puro (sin juego): todo en lat/lon.
-- index.json: { events = { { id, file, name, type, surface, dates, centre = {lat, lon}, bbox = {latMin, lonMin, latMax,
-- lonMax}, radiusKm, stageCount, stageKm, stages = { { id, title, km, start = {lat, lon} } } } } }
local M = {}

local R = 6371008.8
local rad, sin, cos, asin, sqrt, min, max = math.rad, math.sin, math.cos, math.asin, math.sqrt, math.min, math.max

-- metros entre dos puntos (haversine)
function M.dist(lat1, lon1, lat2, lon2)
  local a1, a2 = rad(lat1), rad(lat2)
  local dla, dlo = a2 - a1, rad(lon2 - lon1)
  local h = sin(dla / 2) ^ 2 + cos(a1) * cos(a2) * sin(dlo / 2) ^ 2
  return 2 * R * asin(min(1, sqrt(h)))
end

-- metros de un punto a la caja de un evento (0 dentro)
function M.distToBox(lat, lon, b)
  local cl = max(b[1], min(lat, b[3]))
  local co = max(b[2], min(lon, b[4]))
  return M.dist(lat, lon, cl, co)
end

-- el tramo de un evento cuya salida está más cerca: stage, metros
function M.nearestStage(ev, lat, lon)
  local best, bd
  for _, s in ipairs(ev.stages or {}) do
    if s.start then
      local d = M.dist(lat, lon, s.start[1], s.start[2])
      if not bd or d < bd then best, bd = s, d end
    end
  end
  return best, bd
end

-- Los eventos a menos de radiusM de (lat, lon), el más cercano primero:
-- { { event, boxM (a su zona), stage (el tramo más cercano), stageM } }
function M.nearby(index, lat, lon, radiusM)
  local out = {}
  for _, ev in ipairs(index and index.events or {}) do
    if type(ev.bbox) == 'table' and #ev.bbox == 4 then
      local d = M.distToBox(lat, lon, ev.bbox)
      if d <= radiusM then
        local st, sd = M.nearestStage(ev, lat, lon)
        out[#out + 1] = { event = ev, boxM = d, stage = st, stageM = sd }
      end
    end
  end
  table.sort(out, function(a, b)
    if a.boxM ~= b.boxM then return a.boxM < b.boxM end
    return (a.stageM or 1e12) < (b.stageM or 1e12)
  end)
  return out
end

return M

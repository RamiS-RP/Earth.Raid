-- Earth.Raid: el catálogo de eventos y la búsqueda por zona. Puro (sin juego): todo en lat/lon.
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

-- El mismo tramo en sentido contrario (trazado al revés, salida y meta cambiadas, id + 'R')
local revCache = setmetatable({}, { __mode = 'k' })
function M.reversed(s, es)
  if not s then return nil end
  if revCache[s] then return revCache[s] end
  local r = {}
  for k, v in pairs(s) do if k ~= '_clean' and k ~= '_cleanRemovedM' then r[k] = v end end
  local p = {}
  for k = #s.path, 1, -1 do p[#p + 1] = s.path[k] end
  r.path, r.start, r.finish = p, s.finish or p[1], s.start or p[#p]
  r.id, r.reverse = s.id .. 'R', true
  -- avisos y radios: su distancia se cuenta ahora desde la otra punta
  local total = s.lengthM or s.length or (s.km and s.km * 1000)
  local function flip(list)
    if type(list) ~= 'table' or not total then return list end
    local out = {}
    for i = #list, 1, -1 do
      local h = list[i]
      if type(h) == 'number' then out[#out + 1] = math.max(0, total - h)
      elseif type(h) == 'table' then
        local c = {} for k, v in pairs(h) do c[k] = v end
        if h.atM then c.atM = math.max(0, total - h.atM) end
        if h.at then c.at = math.max(0, total - h.at) end
        out[#out + 1] = c
      end
    end
    return out
  end
  r.hazards, r.radios = flip(s.hazards), flip(s.radios)
  r.title = (s.title or s.id) .. (es and ' (inverso)' or ' (reverse)')
  revCache[s] = r
  return r
end

return M

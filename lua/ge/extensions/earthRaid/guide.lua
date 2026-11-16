-- Raid.Earth: el GPS de BeamNG.Earth para llevar al jugador a la salida y, en el tramo, por el trazado hasta la meta.
local geo = require('earthRaid/geo')
local M = {}
local TAG = 'earthRaid'

M.GPS_POINTS = 11          -- lo que admite gpsSetRoute (10 waypoints + destino)

local function api() return rawget(_G, 'beamngEarth_api') end

function M.toStart(t, name)
  local a = api()
  if not (a and a.gpsSet) then return false end
  local ok = a.gpsSet(t.lat0, t.lon0, name)
  return ok
end

-- por el trazado: puntos repartidos y la meta como destino
function M.along(t, name)
  local a = api()
  if not (a and a.gpsSetRoute) then return false end
  local pts = {}
  for i = 1, M.GPS_POINTS do
    local along = t.total * i / M.GPS_POINTS
    local lat, lon = geo.toGeo(t, geo.at(t, along))
    pts[#pts + 1] = { lat = lat, lon = lon, name = i == M.GPS_POINTS and name or nil }
  end
  local ok, err = a.gpsSetRoute(pts)
  if not ok then log('W', TAG, 'gps: ' .. tostring(err)) end
  return ok
end

function M.clear() local a = api() if a and a.gpsClear then pcall(a.gpsClear) end end

return M

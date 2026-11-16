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

-- La línea de carrera del mod "Racing Line" (racingline_v122, si está instalado): en el tramo sustituye a la línea azul
-- del GPS. Sigue la ruta del GPS (el trazado), así que se oculta la azul del suelo y se le pide su línea de velocidad;
-- al acabar se devuelve todo como estaba.
M.RL_DELAY_S = 1.0          -- el planificador de rutas tarda un poco en tener la ruta nueva
local rl = { on = false, wait = nil, saved = nil }

function M.racingLineAvailable()
  return FS:fileExists('/lua/ge/extensions/racingline.lua') == true
end

local function rlExt()
  if rawget(_G, 'racingline') then return racingline end
  if not M.racingLineAvailable() then return nil end
  pcall(extensions.load, 'racingline')
  return rawget(_G, 'racingline')
end

local function blueLine(show)
  pcall(function()
    if not show and not rl.saved then
      rl.saved = { gm = settings.getValue('showNavigationGroundmarkers'), ar = settings.getValue('showNavigationArrows') }
    end
    if show and rl.saved then
      settings.setValue('showNavigationGroundmarkers', rl.saved.gm ~= false)
      settings.setValue('showNavigationArrows', rl.saved.ar ~= false)
      rl.saved = nil
    elseif not show then
      settings.setValue('showNavigationGroundmarkers', false)
      settings.setValue('showNavigationArrows', false)
    end
    local gm = core_groundMarkers or rawget(_G, 'core_groundmarkers')
    if gm and gm.onSettingsChanged then gm.onSettingsChanged() end
  end)
end

-- en la salida del tramo (tras poner la ruta del GPS): on = ajuste del jugador
function M.racingLine(on)
  if not on then return false end
  local ext = rlExt()
  if not (ext and ext.uiAction) then return false end
  rl.on, rl.wait = true, M.RL_DELAY_S
  blueLine(false)
  return true
end

function M.tick(dt)
  if rl.wait then
    rl.wait = rl.wait - (dt or 0)
    if rl.wait <= 0 then
      rl.wait = nil
      local ext = rawget(_G, 'racingline')
      if ext and ext.uiAction then pcall(ext.uiAction, 'navline') end
    end
  end
end

local function racingLineOff()
  if not rl.on then return end
  rl.on, rl.wait = false, nil
  local ext = rawget(_G, 'racingline')
  if ext and ext.uiAction then pcall(ext.uiAction, 'clear') end
  blueLine(true)
end

function M.clear()
  racingLineOff()
  local a = api() if a and a.gpsClear then pcall(a.gpsClear) end
end

return M

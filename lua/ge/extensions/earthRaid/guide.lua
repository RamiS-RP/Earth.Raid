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
local racingLineOffForce
local rl = { on = false, wait = nil, saved = nil }
local function rlAction(name, v)
  local ext = rawget(_G, 'racingline')
  if ext and ext.uiAction then pcall(ext.uiAction, name, v) end
end

function M.racingLineAvailable()
  return FS:fileExists('/lua/ge/extensions/racingline.lua') == true
end

local function rlExt()
  if rawget(_G, 'racingline') then return racingline end
  if not M.racingLineAvailable() then return nil end
  pcall(extensions.load, 'racingline')
  return rawget(_G, 'racingline')
end

-- si el juego se cierra en mitad de un tramo, lo guardado aquí permite devolver la línea azul al volver a cargar
M.RL_FILE = '/settings/earthRaid/blueline.json'

local function blueLine(show)
  pcall(function()
    -- lo guardado en disco (un cierre a mitad de tramo, o una recarga del módulo) vale más que lo que hay ahora: si ya
    -- estaba oculta por nosotros, lo "actual" es false y se perdería para siempre la preferencia del jugador (19-nov:
    -- el GPS azul desaparecido)
    if not rl.saved and FS:fileExists(M.RL_FILE) then
      local ok, d = pcall(jsonReadFile, M.RL_FILE)
      if ok and type(d) == 'table' then rl.saved = d end
    end
    if not show and not rl.saved then
      rl.saved = { gm = settings.getValue('showNavigationGroundmarkers'), ar = settings.getValue('showNavigationArrows') }
      pcall(jsonWriteFile, M.RL_FILE, rl.saved)
    end
    if show then pcall(function() FS:removeFile(M.RL_FILE) end) end
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

-- modo hardcore: ni la línea azul ni las flechas del GPS mientras dure el tramo o el rally
function M.hideNav(on) blueLine(not on) end

-- en la salida del tramo (tras poner la ruta del GPS): on = ajuste del jugador
function M.racingLine(on)
  if not on then return false end
  local ext = rlExt()
  if not (ext and ext.uiAction) then return false end
  rl.on, rl.wait = true, M.RL_DELAY_S
  rlAction('tg_navFollow', true)
  -- la línea azul del GPS fuera mientras dure el tramo: el propio mod la oculta (17-nov: se veían las dos)
  rlAction('tg_hideNav', true)
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

-- al cargar el addon: la línea azul que quedó oculta por un cierre a mitad de tramo
function M.restoreBlueLine()
  if FS:fileExists(M.RL_FILE) then blueLine(true) end
end

-- Fuera del tramo (hacia el TC y del TC a la salida) solo la línea azul del GPS: el mod Racing Line sigue por su cuenta
-- cualquier ruta del GPS ("seguir navegación"), así que mientras Raid.Earth tiene un tramo se le apaga eso y se borra
-- su línea; al terminar con Raid.Earth se le devuelve.
function M.hold()
  rl.held = true
  rlAction('tg_navFollow', false)
  rlAction('clear')
  rlAction('tg_navFollow', false)
end
-- en un mapa normal (rally vanilla, etc.): el mod Racing Line, tal como estaba sin Raid.Earth
function M.restoreAll()
  rl.held = true
  M.release()
  pcall(racingLineOffForce)
end
function M.release()
  if not rl.held then return end
  rl.held = false
  rlAction('tg_navFollow', true)
end

local function racingLineOff()
  if not rl.on then return end
  racingLineOffForce()
end
racingLineOffForce = function()
  rl.on, rl.wait = false, nil
  rlAction('clear')
  rlAction('tg_hideNav', false)
  if rl.held then rlAction('tg_navFollow', false) end
  blueLine(true)
end

function M.clear()
  racingLineOff()
  local a = api() if a and a.gpsClear then pcall(a.gpsClear) end
end

return M

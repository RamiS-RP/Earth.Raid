-- Raid.Earth: sin trampas (18-nov, el usuario). Durante un tramo no se puede cambiar de coche ni teletransportarse
-- (F7 = dropPlayerAtCameraNoReset, volver a casa, cambiar de vehículo, selector de vehículos y piezas). Se puede
-- recuperar el coche (R, o mantenerlo para volver atrás en el tiempo) con su penalización.
--  - Tramo suelto: el coche se puede cambiar hasta fichar en el TC.
--  - Rally completo: solo en la asistencia.
-- Si el coche cambia de todos modos (p. ej. desde el menú), el tramo o el rally se anula.
local M = {}

M.GROUP = 'earthRaidNoCheat'
M.ACTIONS = { 'loadHome', 'switch_previous_vehicle', 'switch_next_vehicle', 'dropPlayerAtCamera',
  'dropPlayerAtCameraNoReset', 'vehicle_selector', 'parts_selector', 'reload_vehicle', 'reload_all_vehicles',
  'recover_to_last_road' }

local blocked = false
local vid = nil

local function filter() return rawget(_G, 'core_input_actionFilter') end

local function setBlocked(on)
  if on == blocked then return end
  local f = filter()
  if f and f.setGroup and f.addAction then
    pcall(f.setGroup, M.GROUP, M.ACTIONS)
    pcall(f.addAction, 0, M.GROUP, on)
  end
  blocked = on
end

local function playerId()
  local v = getPlayerVehicle and getPlayerVehicle(0)
  return v and v:getID() or nil
end

-- ¿está permitido cambiar de coche ahora?
local function allowed(stage, rally)
  if rally.active() then
    local R = rally.state()
    return R and R.phase == 'service'
  end
  local S = stage.state()
  if not S then return true end
  if S.phase == 'grid' then return true end   -- circuito: en la parrilla, hasta pulsar Iniciar
  return S.phase == 'approach' and S.tcTime == nil
end

-- cada fotograma (main.onUpdate); onCheat(msg) anula el tramo o el rally
function M.update(stage, rally, onCheat)
  local active = stage.state() ~= nil or rally.active()
  if not active then
    setBlocked(false)
    vid = nil
    return
  end
  local ok = allowed(stage, rally)
  setBlocked(not ok)
  local id = playerId()
  if ok or not vid then vid = id return end
  if id and id ~= vid then
    vid = nil
    setBlocked(false)
    if onCheat then onCheat() end
  end
end

function M.release() setBlocked(false) vid = nil end

return M

-- Raid.Earth: objetos con física de verdad cerca del coche.
-- Los carteles de rally, los conos y las cintas de corte del juego existen también como "vehículos" ligeros con
-- física (vehicles/rallysigns, cones, rallytape): un cartel es papel en un palo y se cae al tocarlo, un cono sale
-- rodando y una cinta se rompe. Mantener decenas de ellos todo el tramo cuesta, así que:
--   - lejos, el objeto es un modelo estático sin colisión (props.lua);
--   - a menos de M.ON_M del coche se cambia por su versión con física (se crean de uno en uno, sin tirones);
--   - a más de M.OFF_M se quita la física y vuelve el estático (de pie otra vez, como lo recolocaría la organización).
local M = {}
local TAG = 'earthRaid'

M.ON_M = 180
M.OFF_M = 280
M.MAX = 24                    -- como mucho a la vez
M.SPAWN_EVERY_S = 0.45        -- uno cada tanto: crear un vehículo cuesta de 100 a 800 ms (18-nov, medido: era la causa
                              -- de los tirones; en la pantalla de carga se crean los de la salida de golpe)
M.SCAN_EVERY_S = 0.25         -- la búsqueda del más cercano, no en cada fotograma
-- con física solo lo que el coche puede tocar de verdad: conos en la calzada, cintas, lo del puesto de control y la
-- meta (zona lenta) y la ambulancia; el resto de carteles del tramo queda estático (18-nov, rendimiento)
M.PHYS_KINDS = { cone = true, coneS = true, coneY = true, tapeY = true, markY = true, tape = true, tape6 = true, tape10 = true, ambulance = true, start = true, finish = true,
  stop = true, tc = true, tcEntry = true, finishEntry = true, endArea = true }
M.enabled = true

-- tipo de props.lua -> modelo y configuración del juego
M.MAP = {
  start = { 'rallysigns', 'start' }, finish = { 'rallysigns', 'finish' }, finishEntry = { 'rallysigns', 'finishentry' },
  stop = { 'rallysigns', 'stop' }, endArea = { 'rallysigns', 'endofarea' },
  radio = { 'rallysigns', 'radio_point' }, radioWarn = { 'rallysigns', 'radio_warning' },
  medical = { 'rallysigns', 'medical_point' }, medicalWarn = { 'rallysigns', 'medical_warning' },
  board1 = { 'rallysigns', 'cooldown_1' }, board2 = { 'rallysigns', 'cooldown_2' }, board3 = { 'rallysigns', 'cooldown_3' },
  cone = { 'cones', 'large' },
  coneS = { 'cones', 'small_orange_white_single' }, coneY = { 'cones', 'large_yellow_black_double' },
  tapeY = { 'rallytape', 'hazardtape' }, markY = { 'rallytape', 'coursemarker_4m' },
  -- en cada punto médico, una ambulancia aparcada (la de tráfico simple: ligera, sin motor que simular)
  ambulance = { 'simple_traffic', 'van_ambulance_parked' },
  tape = { 'rallytape', 'roadclosed_8m' }, tape6 = { 'rallytape', 'roadclosed_6m' }, tape10 = { 'rallytape', 'roadclosed_10m' },
}
-- giro extra (grados) entre la orientación del modelo estático y la del vehículo
M.YAW_FIX = { rallysigns = 0, cones = 0, rallytape = 0, simple_traffic = 0 }
-- sin modelo estático visible: solo existen como vehículo
M.PHYS_ONLY = { ambulance = true, tapeY = true, markY = true }

local live = {}               -- item -> { vid }
local count = 0
local spawnT = 0

function M.handles(kind) return M.enabled and M.MAP[kind] ~= nil and M.PHYS_KINDS[kind] == true end

local function exists(kind)
  local m = M.MAP[kind]
  return m and FS:fileExists('/vehicles/' .. m[1] .. '/' .. m[2] .. '.pc')
end

local function hideStatic(it, hide)
  if it.obj then pcall(function() it.obj:setHidden(hide) end) end
end

local function despawn(it)
  local l = live[it]
  if not l then return end
  live[it] = nil
  count = count - 1
  pcall(function()
    local v = be:getObjectByID(l.vid)
    if v then v:delete() end
  end)
  if not M.PHYS_ONLY[it.kind] then hideStatic(it, false) end
end

local function spawn(it)
  local m = M.MAP[it.kind]
  if not (it.obj and m and exists(it.kind)) then return false end
  local ok, vid = pcall(function()
    local pos = it.obj:getPosition()
    local rot = quat(it.obj:getRotation())
    local fix = M.YAW_FIX[m[1]] or 0
    if fix ~= 0 then rot = quatFromEuler(0, 0, math.rad(fix)) * rot end
    local v = core_vehicles.spawnNewVehicle(m[1], {
      config = 'vehicles/' .. m[1] .. '/' .. m[2] .. '.pc', pos = vec3(pos.x, pos.y, pos.z + 0.02), rot = rot,
      cling = true, autoEnterVehicle = false, centeredPosition = false, spawnOptions = { autoEnterVehicle = false } })
    if not v then return nil end
    pcall(function() v.playerUsable = false end)
    pcall(function() v:setDynDataFieldbyName('earthRaidProp', 0, '1') end)
    return v:getID()
  end)
  if not ok or not vid then
    if not ok then log('W', TAG, 'phys spawn ' .. tostring(it.kind) .. ': ' .. tostring(vid)) end
    it.noPhys = true
    return false
  end
  live[it] = { vid = vid }
  count = count + 1
  hideStatic(it, true)
  return true
end

-- cada fotograma: x, y del coche (coordenadas del juego); items = props.all()
local scanT = 0
function M.update(dt, px, py, items, burst)
  if not M.enabled then return end
  spawnT = spawnT + (dt or 0)
  scanT = scanT + (dt or 0)
  if scanT < M.SCAN_EVERY_S and not burst then return end
  scanT = 0
  -- fuera lo que queda lejos (o cuyo objeto ya no existe)
  for it in pairs(live) do
    local gone = not it.obj or it.hidden or it.dead
    if not gone then
      local p = it.obj:getPosition()
      gone = (p.x - px) ^ 2 + (p.y - py) ^ 2 > M.OFF_M * M.OFF_M
    end
    if gone then despawn(it) end
  end
  if count >= M.MAX or (spawnT < M.SPAWN_EVERY_S and not burst) then return end
  -- el más cercano sin física
  local best, bd = nil, M.ON_M * M.ON_M
  for _, it in ipairs(items) do
    if it.obj and not live[it] and not it.noPhys and not it.hidden and M.MAP[it.kind] and M.PHYS_KINDS[it.kind] then
      local p = it.obj:getPosition()
      local d = (p.x - px) ^ 2 + (p.y - py) ^ 2
      if d < bd then best, bd = it, d end
    end
  end
  if best then
    spawnT = 0
    spawn(best)
  end
end

-- todos fuera (al acabar o limpiar el tramo)
function M.clear()
  for it in pairs(live) do despawn(it) end
  live, count = {}, 0
end

function M.forget(it) despawn(it) end
function M.isLive(it) return live[it] ~= nil end
function M.count() return count end

-- restos de una recarga del addon: vehículos marcados como nuestros
function M.purgeOrphans()
  local n = 0
  pcall(function()
    for _, name in ipairs(scenetree.findClassObjects('BeamNGVehicle') or {}) do
      local o = scenetree.findObject(name)
      if o and o:getDynDataFieldbyName('earthRaidProp', 0) == '1' then
        local mine = false
        for _, l in pairs(live) do if l.vid == o:getID() then mine = true end end
        if not mine then o:delete() n = n + 1 end
      end
    end
  end)
  return n
end

return M

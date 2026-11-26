-- Raid.Earth: objetos con física de verdad cerca del coche.
-- Los carteles de rally, los conos y las cintas de corte del juego existen también como "vehículos" ligeros con
-- física (vehicles/rallysigns, cones, rallytape): un cartel es papel en un palo y se cae al tocarlo, un cono sale
-- rodando y una cinta se rompe. Mantener decenas de ellos todo el tramo cuesta, así que:
--   - lejos, el objeto es un modelo estático sin colisión (props.lua);
--   - a menos de M.ON_M del coche se cambia por su versión con física (de uno en uno; ver MARK:phys-pool-v1);
--   - a más de M.OFF_M se quita la física y vuelve el estático (de pie otra vez, como lo recolocaría la organización).
local M = {}
local TAG = 'earthRaid'

M.ON_M = 70                   -- (20-nov, el usuario: física solo a una distancia prudente; eran 180 / 280)
M.OFF_M = 120
-- (22-nov, el usuario: «la ambulancia aparece de la nada») la ambulancia es solo vehículo (no tiene modelo estático): se crea
-- desde lejos, de la reserva, y se retira cuando el coche se aleja (libera carga)
M.ON_KIND = { ambulance = 280 }
M.OFF_KIND = { ambulance = 360 }
M.MAX = 24                    -- como mucho a la vez
M.SPAWN_EVERY_S = 0.45        -- uno cada tanto: crear un vehículo cuesta de 100 a 800 ms (18-nov, medido: era la causa
                              -- de los tirones; en la pantalla de carga se crean los de la salida de golpe)
M.SCAN_EVERY_S = 0.25         -- la búsqueda del más cercano, no en cada fotograma
-- con física solo lo que el coche puede tocar de verdad: conos en la calzada, cintas, lo del puesto de control y la
-- meta (zona lenta) y la ambulancia; el resto de carteles del tramo queda estático (18-nov, rendimiento)
M.PHYS_KINDS = { cone = true, coneS = true, coneY = true, tapeY = true, markY = true, tape = true, tape6 = true, tape10 = true, ambulance = true, start = true, finish = true,
  stop = true, tc = true, tcEntry = true, finishEntry = true, endArea = true, rallyCar = true }
M.enabled = true

-- MARK:phys-pool-v1 (20-nov) Rendimiento. Crear un vehículo es lo único caro del mod (100-800 ms: un tirón), así que:
--   - los que quedan lejos no se borran: se desactivan (setActive(0), no cuestan) y se guardan por modelo; el siguiente
--     cono o cartel igual reutiliza uno (moverlo y reiniciarlo no da tirón);
--   - crear uno nuevo solo con el coche lento (o en la pantalla de carga, donde además se dejan repuestos hechos);
--   - el ajuste «Rendimiento» (settings.performance) limita cuántos hay a la vez. En «bajo» no hay ninguno: todo queda
--     como modelo estático, sin ambulancias ni coches en los boxes.
M.LEVELS = {
  low    = { max = 0,  createKmh = 0,  rallyCars = 0, prewarm = 0 },
  medium = { max = 12, createKmh = 20, rallyCars = 1, prewarm = 14 },
  high   = { max = 24, createKmh = 35, rallyCars = 3, prewarm = 20 },
}
-- (20-nov, medido en Ourense con el nivel alto y el tope en 110 km/h: 15 creados a 60 km/h, tirones de hasta 958 ms.
-- Por eso el tope es bajo: a más velocidad solo se usan los repuestos; lo que no tenga repuesto se queda estático.)
-- (20-nov, conduciendo en Ourense: una cinta de corte creada en mitad del tramo con el coche casi parado = parón de
-- 1,5 s.) Durante el tramo cronometrado NO se crea nada: solo se reutilizan los de la reserva, que se llena antes (en
-- el control horario, en la línea de salida y en la carga), incluidas la ambulancia y las cintas de los cortes.
M.quiet = false               -- lo pone stage.lua en la cuenta atrás y en el tramo: ni crear ni hacer repuestos
M.ALWAYS_WARM = { 'tape6', 'tape', 'tape10' }   -- cintas de corte: se montan por el camino, no están en la lista al empezar
-- «auto»: según la calidad elegida en BeamNG.Earth (él ya mira el equipo la primera vez)
M.AUTO = { low = 'low', medium = 'low', high = 'medium', ultra = 'high', extreme = 'high' }
M.POOL_MAX = 24               -- desactivados en reserva, como mucho
M.PREWARM_PER = { cones = 6, rallysigns = 2, rallytape = 2, simple_traffic = 3 }   -- repuestos por configuración (solo estos modelos)
local levelT, levelName = -1, 'medium'
function M.levelName()
  local now = os.clock()
  if now - levelT < 2 and levelT >= 0 then return levelName end
  levelT = now
  local name = 'auto'
  pcall(function() name = tostring(require('earthRaid/settings').get().performance or 'auto') end)
  if not M.LEVELS[name] then
    local q
    pcall(function() q = beamngEarth_settings and beamngEarth_settings.get('quality') end)
    name = M.AUTO[tostring(q)] or 'medium'
  end
  levelName = name
  return name
end
function M.level() return M.LEVELS[M.levelName()] or M.LEVELS.medium end

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
  -- coches de rally aparcados en los boxes (19-nov): el modelo y la configuración van en el objeto (it.opts.vehicle)
  rallyCar = { 'covet', 'rally_asphalt' },
  tape = { 'rallytape', 'roadclosed_8m' }, tape6 = { 'rallytape', 'roadclosed_6m' }, tape10 = { 'rallytape', 'roadclosed_10m' },
}
-- giro extra (grados) entre la orientación del modelo estático y la del vehículo
M.TAPE_LEN = { tape = 8, tape6 = 6, tape10 = 10 }
M.YAW_FIX = { rallysigns = 0, cones = 0, rallytape = 0, simple_traffic = 0 }
-- sin modelo estático visible: solo existen como vehículo
M.PHYS_ONLY = { ambulance = true, tapeY = true, markY = true, rallyCar = true }
-- los de los boxes, según la superficie del rally (los que existan en el juego)
M.RALLY_CARS = {
  asphalt = { { 'sunburst2', 'rally_pro_asphalt' }, { 'vivace', 'ardente_rally_asphalt' }, { 'covet', 'rally_asphalt' },
    { 'bolide', 'rally_asphalt' }, { 'etki', 'rally_am_asphalt' }, { 'sbr', 'rally_am_asphalt' }, { 'legran', 'rally_asphalt' },
    { 'bx', '240bx_coupe_rally_asp' } },
  gravel = { { 'sunburst2', 'rally_pro_gravel' }, { 'vivace', 'ardente_rally' }, { 'covet', 'rally_gravel' },
    { 'bolide', 'rally_gravel' }, { 'etki', 'rally_am_gravel' }, { 'pessima', 'rallyspec1_dirty' }, { 'wendover', 'rally' },
    { 'bx', '240bx_coupe_rally_gravel' } },
}
-- n coches distintos para los boxes: { {modelo, configuración}... }
function M.pickRallyCars(n, surface)
  local list = M.RALLY_CARS[(surface == 'gravel' or surface == 'dirt' or surface == 'snow') and 'gravel' or 'asphalt']
  local ok = {}
  for _, c in ipairs(list) do if FS:fileExists('/vehicles/' .. c[1] .. '/' .. c[2] .. '.pc') then ok[#ok + 1] = c end end
  local out = {}
  while #out < n and #ok > 0 do out[#out + 1] = table.remove(ok, math.random(#ok)) end
  return out
end
local function mapOf(it) return (it.opts and it.opts.vehicle) or M.MAP[it.kind] end

local live = {}               -- item -> { vid, key, c, off, rot0 }
local count = 0
local spawnT = 0
local pool, poolN = {}, 0     -- 'modelo/config' -> { { vid, c, off, rot0 }... } desactivados
local warmed = 0              -- repuestos creados en esta pantalla de carga
M.stats = { created = 0, reused = 0, pooled = 0, deleted = 0, waitSpeed = 0 }

function M.handles(kind) return M.enabled and M.MAP[kind] ~= nil and M.PHYS_KINDS[kind] == true end
local function keyOf(m) return m[1] .. '/' .. m[2] end

local function exists(it)
  local m = mapOf(it)
  return m and FS:fileExists('/vehicles/' .. m[1] .. '/' .. m[2] .. '.pc')
end

local function hideStatic(it, hide)
  if it.obj then pcall(function() it.obj:setHidden(hide) end) end
end

-- a la reserva (desactivado) si cabe; si no, borrado
local function retire(l, keep)
  pcall(function()
    local v = be:getObjectByID(l.vid)
    if not v then return end
    if keep and l.key and l.c and poolN < M.POOL_MAX then
      v:setActive(0)
      pool[l.key] = pool[l.key] or {}
      table.insert(pool[l.key], l)
      poolN = poolN + 1
      M.stats.pooled = M.stats.pooled + 1
    else
      v:delete()
      M.stats.deleted = M.stats.deleted + 1
    end
  end)
end

local function despawn(it, keep)
  local l = live[it]
  if not l then return end
  live[it] = nil
  count = count - 1
  retire(l, keep)
  if not M.PHYS_ONLY[it.kind] then hideStatic(it, false) end
end

local function takePooled(key)
  local list = pool[key]
  while list and #list > 0 do
    local l = table.remove(list)
    poolN = poolN - 1
    if be:getObjectByID(l.vid) then return l end
  end
  return nil
end

-- crea el vehículo (lo caro). Devuelve la ficha { vid, key, c, off, rot0 }: c y off son lo que el juego añade al giro y
-- a la posición pedidos (medidos en el recién creado), para poder recolocar luego el mismo vehículo en otro sitio
local function create(m, pos, rot, kind)
  local v = core_vehicles.spawnNewVehicle(m[1], {
    config = 'vehicles/' .. m[1] .. '/' .. m[2] .. '.pc', pos = vec3(pos.x, pos.y, pos.z + 0.02), rot = rot,
    cling = true, autoEnterVehicle = false, centeredPosition = false, spawnOptions = { autoEnterVehicle = false } })
  if not v then return nil end
  pcall(function() v.playerUsable = false end)
  pcall(function() v:setDynDataFieldbyName('earthRaidProp', 0, '1') end)
  if kind == 'rallyCar' then
    -- aparcado: sin contacto y con el freno de mano
    pcall(function() v:queueLuaCommand("if electrics and electrics.setIgnitionLevel then electrics.setIgnitionLevel(0) end input.event('parkingbrake', 1, 1)") end)
  end
  if kind == 'ambulance' then
    -- las luces de la ambulancia encendidas (barra de emergencia y warning): el puesto médico se ve de lejos y avisa del corte
    pcall(function() v:queueLuaCommand("if electrics then if electrics.set_lightbar_signal then electrics.set_lightbar_signal(2) end if electrics.set_warn_signal then electrics.set_warn_signal(true) end end") end)
  end
  local l = { vid = v:getID(), key = keyOf(m) }
  pcall(function()
    local vp = v:getPosition()
    l.c = quat(v:getRotation()) * rot:inversed()
    l.off = vec3(vp.x - pos.x, vp.y - pos.y, vp.z - pos.z)
    l.rot0 = rot
  end)
  M.stats.created = M.stats.created + 1
  return l
end

-- recoloca uno de la reserva: activarlo, llevarlo al sitio (setPositionRotation reinicia su física: de pie y entero)
local function place(l, pos, rot)
  local v = be:getObjectByID(l.vid)
  if not v then return false end
  v:setActive(1)
  local q = l.c * rot
  local off = (rot * l.rot0:inversed()) * l.off
  v:setPositionRotation(pos.x + off.x, pos.y + off.y, pos.z + off.z, q.x, q.y, q.z, q.w)
  pcall(function() v:resetBrokenFlexMesh() end)
  M.stats.reused = M.stats.reused + 1
  return true
end

local function spawn(it, pooledOnly)
  local m = mapOf(it)
  if not (it.obj and m and exists(it)) then return false end
  local ok, l = pcall(function()
    local pos = it.obj:getPosition()
    local rot = quat(it.obj:getRotation())
    local fix = M.YAW_FIX[m[1]] or 0
    if fix ~= 0 then rot = quatFromEuler(0, 0, math.rad(fix)) * rot end
    -- (22-nov, el usuario: "una cinta mal colocada", medido en el juego): la cinta de corte estática tiene el origen en un
    -- extremo y el largo en -Y; la versión con física (rallytape) está centrada y con el largo en su eje X. Sin esto, al
    -- acercarse el coche la cinta giraba 90° y dejaba de cruzar la calle.
    local tl = M.TAPE_LEN[it.kind]
    if tl then
      local Y = it.obj:getTransform():getColumn(1)
      pos = vec3(pos.x - Y.x * tl / 2, pos.y - Y.y * tl / 2, pos.z)
      rot = quatFromEuler(0, 0, math.rad(90)) * rot
    end
    local p = takePooled(keyOf(m))
    if p then
      local okP, done = pcall(place, p, pos, rot)
      if okP and done then return p end
      pcall(function() local v = be:getObjectByID(p.vid) if v then v:delete() end end)
    end
    if pooledOnly then return false end
    return create(m, pos, rot, it.kind)
  end)
  if ok and l == false then return false end      -- sin repuesto y ahora no toca crear: se intentará luego
  if not ok or not l then
    if not ok then log('W', TAG, 'phys spawn ' .. tostring(it.kind) .. ': ' .. tostring(l)) end
    it.noPhys = true
    return false
  end
  live[it] = l
  count = count + 1
  hideStatic(it, true)
  return true
end

-- en la pantalla de carga o con el coche casi parado, con lo de cerca ya creado: repuestos de lo que el tramo tiene más
-- adelante (así el primer cartel de meta o el primer cono lejano no dan tirón). Uno por llamada.
local function prewarm(items, L)
  if warmed >= L.prewarm or poolN >= M.POOL_MAX then return end
  local want, any = {}, nil
  for _, it in ipairs(items) do
    if it.obj and not live[it] and not it.noPhys and not it.hidden and M.PHYS_KINDS[it.kind] and not (it.opts and it.opts.vehicle) then
      any = any or it
      local m = M.MAP[it.kind]
      if m and M.PREWARM_PER[m[1]] then
        local k = keyOf(m)
        want[k] = want[k] or { m = m, n = 0, it = it }
        want[k].n = want[k].n + 1
      end
    end
  end
  if any then
    for _, kind in ipairs(M.ALWAYS_WARM) do
      local m = M.MAP[kind]
      local k = m and keyOf(m)
      if k and not want[k] then want[k] = { m = m, n = 2, it = any } end
    end
  end
  -- primero lo que más cuesta crear y más se echa en falta: ambulancia, cintas, carteles y, al final, conos
  local order = {}
  for k, w in pairs(want) do
    w.k = k
    w.prio = w.m[1] == 'simple_traffic' and 0 or w.m[1] == 'rallytape' and 1 or w.m[1] == 'rallysigns' and 2 or 3
    order[#order + 1] = w
  end
  table.sort(order, function(a, b) if a.prio ~= b.prio then return a.prio < b.prio end return a.k < b.k end)
  for _, w in ipairs(order) do
    local k = w.k
    local have = pool[k] and #pool[k] or 0
    if have < math.min(w.n, M.PREWARM_PER[w.m[1]]) and FS:fileExists('/vehicles/' .. w.m[1] .. '/' .. w.m[2] .. '.pc') then
      local ok, l = pcall(function()
        local pos = w.it.obj:getPosition()
        return create(w.m, pos, quat(w.it.obj:getRotation()), w.it.kind)
      end)
      warmed = warmed + 1
      if ok and l then retire(l, true) end
      return
    end
  end
end

-- cada fotograma: x, y del coche (coordenadas del juego); items = props.all()
local scanT = 0
local lastX, lastY
function M.update(dt, px, py, items, burst)
  if not M.enabled then return end
  spawnT = spawnT + (dt or 0)
  scanT = scanT + (dt or 0)
  if scanT < M.SCAN_EVERY_S and not burst then return end
  -- velocidad del coche, de lo que se ha movido desde la última pasada
  local kmh = 0
  if lastX and scanT > 0 then kmh = math.sqrt((px - lastX) ^ 2 + (py - lastY) ^ 2) / scanT * 3.6 end
  lastX, lastY = px, py
  scanT = 0
  local L = M.level()
  -- fuera lo que queda lejos (o cuyo objeto ya no existe): a la reserva
  for it in pairs(live) do
    local gone = not it.obj or it.hidden or it.dead or L.max == 0
    if not gone then
      local p = it.obj:getPosition()
      local off = M.OFF_KIND[it.kind] or M.OFF_M
      gone = (p.x - px) ^ 2 + (p.y - py) ^ 2 > off * off
    end
    if gone then despawn(it, L.max > 0) end
  end
  if L.max == 0 then
    if poolN > 0 then M.clearPool() end
    return
  end
  if count >= L.max then return end
  -- el más cercano sin física, y el más cercano que tiene repuesto hecho
  local best, bd = nil, math.huge
  local bestP, bdP = nil, math.huge
  for _, it in ipairs(items) do
    if it.obj and not live[it] and not it.noPhys and not it.hidden and M.MAP[it.kind] and M.PHYS_KINDS[it.kind] then
      local p = it.obj:getPosition()
      local d = (p.x - px) ^ 2 + (p.y - py) ^ 2
      local on = M.ON_KIND[it.kind] or M.ON_M
      if d < on * on then
        local m = mapOf(it)
        local list = m and pool[keyOf(m)]
        local spare = list and #list > 0
        -- la ambulancia, a más distancia, solo si hay repuesto o se puede crear sin tirón
        if on == M.ON_M or d < M.ON_M * M.ON_M or spare or (not M.quiet and kmh <= L.createKmh) then
          if d < bd then best, bd = it, d end
          if spare and d < bdP then bestP, bdP = it, d end
        end
      end
    end
  end
  local slow = not M.quiet and spawnT >= M.SPAWN_EVERY_S and kmh <= L.createKmh
  if not best then
    if burst or (slow and kmh <= 5) then
      spawnT = 0
      prewarm(items, L)
    end
    return
  end
  local mayCreate = burst or slow
  if mayCreate then
    spawnT = 0
    spawn(best)
  elseif bestP then
    spawn(bestP, true)
  elseif kmh > L.createKmh then
    M.stats.waitSpeed = M.stats.waitSpeed + 1
  end
end

function M.clearPool()
  for _, list in pairs(pool) do
    for _, l in ipairs(list) do
      pcall(function() local v = be:getObjectByID(l.vid) if v then v:delete() end end)
    end
  end
  pool, poolN = {}, 0
end

-- todos fuera (al acabar o limpiar el tramo)
function M.clear()
  for it in pairs(live) do despawn(it) end
  live, count = {}, 0
  M.clearPool()
  warmed, lastX, lastY = 0, nil, nil
end

function M.forget(it) despawn(it) end
function M.isLive(it) return live[it] ~= nil end
function M.count() return count end
function M.pooled() return poolN end

-- restos de una recarga del addon: vehículos marcados como nuestros
function M.purgeOrphans()
  local n = 0
  pcall(function()
    for _, name in ipairs(scenetree.findClassObjects('BeamNGVehicle') or {}) do
      local o = scenetree.findObject(name)
      if o and o:getDynDataFieldbyName('earthRaidProp', 0) == '1' then
        local mine = false
        for _, l in pairs(live) do if l.vid == o:getID() then mine = true end end
        for _, list in pairs(pool) do for _, l in ipairs(list) do if l.vid == o:getID() then mine = true end end end
        if not mine then o:delete() n = n + 1 end
      end
    end
  end)
  return n
end

return M

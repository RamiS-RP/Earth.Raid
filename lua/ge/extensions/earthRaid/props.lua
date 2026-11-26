-- Raid.Earth: los objetos de un tramo con los modelos del rally del juego.
-- Cada objeto se guarda en lat/lon + dirección de marcha + giro: tras un cambio de origen de BeamNG.Earth se recoloca
-- (M.replace). El giro (yaw) se mide en grados, en sentido horario desde la dirección de marcha, sobre el eje Y del
-- modelo: 0 = el eje Y del objeto mira hacia donde va el coche, 180 = mira al coche que llega, 90 = a la derecha.
-- Medido en el rally del juego (Utah, NGRC26) y en las cajas de los modelos:
--   carteles (cara en -Y)           0, al coche que llega (comprobado en Córdoba SS1)
--   sensores de cronometraje        Y hacia fuera de la carretera: el láser sale por -Y, hacia el coche
--   flechas de curva (cara en -X)   -60 en el lado derecho, -120 en el izquierdo
--   cintas de corte (largo en -Y)   origen en un extremo, Y a lo ancho de la calle que se corta
local M = {}
local phys = require('earthRaid/phys')
local TAG = 'earthRaid'
local A = '/art/shapes/race/rally/rally_assets/'

M.SHAPES = {
  start = A .. 's_rally_signboard_start.dae', finish = A .. 's_rally_signboard_finish.dae',
  finishEntry = A .. 's_rally_signboard_finish_entry.dae', stop = A .. 's_rally_signboard_stop.dae',
  tc = A .. 's_rally_signboard_time_control.dae', tcEntry = A .. 's_rally_signboard_time_control_entry.dae',
  radio = A .. 's_rally_signboard_radio_point.dae', radioWarn = A .. 's_rally_signboard_radio_point_warning.dae',
  medical = A .. 's_rally_signboard_medical_point.dae', medicalWarn = A .. 's_rally_signboard_medical_warning.dae',
  -- ambulancia: solo existe como vehículo cerca del coche (phys.lua); de lejos, un marcador oculto
  ambulance = A .. 's_rally_signboard_medical_point.dae',
  rallyCar = A .. 's_rally_signboard_medical_point.dae',     -- coche de rally aparcado en un box: igual, solo vehículo
  endArea = A .. 's_rally_signboard_end_of_area.dae',
  board1 = A .. 's_cooldown_board_01.dae', board2 = A .. 's_cooldown_board_02.dae', board3 = A .. 's_cooldown_board_03.dae',
  sensor = A .. 's_rally_start_sensor.dae', tree = A .. 's_rally_start_tree.dae',
  gazeboFrame = A .. 's_rally_gazebo_mod_frame_3x3.dae', gazeboCover = A .. 's_rally_gazebo_mod_cover_ngrc_3x3.dae',
  table = A .. 's_rally_fold_table_01.dae',
  -- el puesto de control vanilla (NGRC Rally Utah): portátil en la mesa y dos extintores
  laptop = '/art/shapes/garage_and_dealership/garage/s_laptop.dae',
  extinguisher = '/art/shapes/garage_and_dealership/Clutter/clutter_workshop_fire_extinguisher.dae', chair = A .. 's_rally_fold_chair_01.dae', cone = '/art/shapes/race/cone.dae',
  -- cono pequeño naranja a rayas (casetas, tráfico) y cono grande amarillo a rayas (peligros): estáticos de lejos, con su
  -- configuración de vehículo (cones/small_orange_white_single, large_yellow_black_double) cerca; cinta amarilla solo vehículo
  coneS = '/art/shapes/race/cone.dae', coneY = '/art/shapes/race/cone.dae', tapeY = A .. 's_spectator_tape_5m.dae', markY = A .. 's_spectator_tape_5m.dae',
  cornerR = A .. 's_corner_dir_right.dae', cornerL = A .. 's_corner_dir_left.dae',
  corner45R = A .. 's_corner_dir45_right.dae', corner45L = A .. 's_corner_dir45_left.dae',
  hairpinR = A .. 's_corner_dir135_right.dae', hairpinL = A .. 's_corner_dir225_left.dae',
  tape = A .. 's_tape_road_closure_8m.dae', tape6 = A .. 's_tape_road_closure_6m.dae', tape10 = A .. 's_tape_road_closure_10m.dae',
  specTape = A .. 's_spectator_tape_5m.dae', specGrid = A .. 's_spectator_grid_center.dae',
  fenceNgrc = A .. 's_metal_fence_branding_ngrc.dae', fenceBlastr = A .. 's_metal_fence_branding_blastr.dae',
  fenceRotopad = A .. 's_metal_fence_branding_rotopad.dae', cushion = A .. 's_safety_cushion_01.dae',
  fenceApm = A .. 's_metal_fence_branding_apm.dae', fenceApmSpecial = A .. 's_metal_fence_branding_apm_special.dae',
  specTarp = A .. 's_spectator_tarp_4m.dae', specTarp2 = A .. 's_spectator_tarp_4m_02.dae', specTarp3 = A .. 's_spectator_tarp_4m_03.dae',
  specGridA = A .. 's_spectator_grid_a_2m.dae', specGridB = A .. 's_spectator_grid_b_2m.dae',
  specTapeBigA = A .. 's_spectator_tape_big_a.dae', specTapeBigB = A .. 's_spectator_tape_big_b.dae', specTapeBigCenter = A .. 's_spectator_tape_big_center.dae', specTarpAngle = A .. 's_spectator_tarp_angle.dae', cornerMarker = A .. 's_corner_marker.dae',
  danger = '/art/shapes/garage_and_dealership/Clutter/italy_traf_sign_warn_other_danger.dae',
  bendL = '/art/shapes/garage_and_dealership/Clutter/italy_traf_sign_warn_bend_l.dae',
  bendR = '/art/shapes/garage_and_dealership/Clutter/italy_traf_sign_warn_bend_r.dae',
  -- el box del parque de asistencia
  bigToolbox = '/art/shapes/garage_and_dealership/garage/s_big_toolbox_01.dae',
  bigToolbox2 = '/art/shapes/garage_and_dealership/garage/s_big_toolbox_02.dae',
  smallToolbox = '/art/shapes/garage_and_dealership/garage/s_small_toolbox_01.dae',
  tireRack = '/art/shapes/garage_and_dealership/garage/s_tire_rack.dae',
  -- protecciones en curvas peligrosas y cortes de calles (lo que usan los rallies del juego)
  -- pacas del juego (las de carga de vehículos; sus materiales se cargan aparte, ver create): redondas (un grupo de
  -- 4,4 m de ancho en X) y cuadradas (1,8 x 2,5 m)
  -- (la redonda, haybale_round.dae, usa un material que no existe fuera del vehículo: sale naranja; se usa la cuadrada)
  hayBale = '/vehicles/common/loads/haybale/haybale.dae',
  hayBale2 = '/vehicles/common/loads/haybale/haybale.dae',
  meshBarricade = '/art/shapes/race/ut_race_mesh_barricade_.DAE',   -- malla naranja de 10 m (Utah), larga en Y
  barrel = '/assets/meshes/props/race_event/equipment/s_trafficbarrel_01.dae',
  plasticBarrier = '/art/shapes/garage_and_dealership/Clutter/hr_plasticbarrier_red.DAE',
  plasticBarrierW = '/art/shapes/garage_and_dealership/Clutter/hr_plasticbarrier.DAE',
  workbench = '/art/shapes/garage_and_dealership/garage/s_garage_workbench_medium.dae',
  stool = '/art/shapes/garage_and_dealership/garage/s_metal_stool.dae',
}
-- sonidos de ambiente (SFXEmitter 3D; los .ogg están en el mod: art/sound/earthRaid, se pueden cambiar por grabaciones
-- reales con el mismo nombre)
local SND = '/art/sound/earthRaid/'
M.SOUNDS = {
  sndCrowd = { file = SND .. 'crowd_murmur.ogg', loop = true, volume = 0.8, ref = 8, max = 90 },
  sndCheer = { file = SND .. 'crowd_cheer.ogg', loop = false, volume = 1.0, ref = 15, max = 160 },
  sndGenerator = { file = SND .. 'generator.ogg', loop = true, volume = 0.45, ref = 3, max = 35 },
}
-- prefabs del juego (carpas montadas)
M.PREFABS = {
  gazebo3x3 = '/art/prefabs/p_rally_gazebo_mod_ngrc_3x3.prefab.json',
  gazebo3x6 = '/art/prefabs/p_rally_gazebo_mod_ngrc_3x6.prefab.json',
  gazebo3x6b = '/art/prefabs/p_rally_gazebo_mod_blastr_3x6.prefab.json',
  gazebo3x6r = '/art/prefabs/p_rally_gazebo_mod_rotopad_3x6.prefab.json',
  gazebo3x6d = '/art/prefabs/p_rally_gazebo_mod_dkblue_3x6.prefab.json',
  -- las vallas publicitarias con su valla metálica detrás, como en los rallies del juego (17-nov: salían solo las lonas)
  fenceNgrc = A .. 'p_metal_fence_branding_ngrc.prefab.json',
  fenceBlastr = A .. 'p_metal_fence_branding_blastr.prefab.json',
  fenceRotopad = A .. 'p_metal_fence_branding_rotopad.prefab.json',
  fenceApm = '/art/earthRaid/prefabs/p_metal_fence_branding_apm.prefab.json',
  fenceApmSpecial = '/art/earthRaid/prefabs/p_metal_fence_branding_apm_special.prefab.json',
}

local items = {}           -- { obj, kind, lat, lon, dx, dy, yaw, prefab }
local serial = 0

local function api() return rawget(_G, 'beamngEarth_api') end

-- x, y, z del suelo en lat, lon y si el suelo estaba cargado (BeamNG.Earth carga el terreno alrededor del jugador: más
-- lejos el rayo no encuentra nada, o da 0, y el objeto se recoloca cuando llega su terreno: M.reground)
function M.ground(lat, lon)
  local a = api()
  local x, y, z = a.toGame(lat, lon, 0)
  if not x then return nil end
  -- desde el terreno y como mucho 2,5 m por encima (la calzada de BeamNG.Earth va sobre él): un rayo desde muy alto
  -- choca con copas de árboles, toldos o tejados y deja el objeto flotando
  local th = core_terrain and core_terrain.getTerrainHeight and core_terrain.getTerrainHeight(vec3(x, y, 0))
  local ok = type(th) == 'number' and th > -1e5 and th ~= 0
  -- el terreno del juego puede no cubrir el punto (da otra altura): se contrasta con un rayo desde arriba
  local hTop = be:getSurfaceHeightBelow(vec3(x, y, 9000))
  if ok and type(hTop) == 'number' and hTop > -1e5 and hTop ~= 0 and math.abs(hTop - th) > 60 then
    return x, y, hTop, true
  end
  if ok then
    z = th
    -- un poco por encima del terreno (la calzada); más arriba serían nuestras vallas o carpas: los objetos se
    -- quedaban subidos encima de ellas al recolocarlos (meta de Obejo, 16-nov)
    local h = be:getSurfaceHeightBelow(vec3(x, y, th + 0.45))
    if type(h) == 'number' and h > th - 1 and h < th + 0.45 then z = h end
  else
    local h = be:getSurfaceHeightBelow(vec3(x, y, 9000))
    ok = type(h) == 'number' and h > -1e5 and h ~= 0
    if ok then z = h end
    ok = false               -- sin terreno a la vista: se volverá a mirar
  end
  return x, y, z or 0, ok
end

-- Objetos del addon que siguen en la escena sin que este módulo los lleve (de una recarga del addon con un tramo
-- montado): fuera, o se duplican al montar de nuevo
function M.purgeOrphans()
  local mine = {}
  for _, it in ipairs(items) do if it.obj then pcall(function() mine[it.obj:getName()] = true end) end end
  for _, l in pairs(M._spare or {}) do
    for _, it in ipairs(l) do if it.obj then pcall(function() mine[it.obj:getName()] = true end) end end
  end
  local n = 0
  for _, cls in ipairs({ 'TSStatic', 'Prefab', 'DecalRoad', 'SFXEmitter', 'PointLight' }) do
    for _, name in ipairs(scenetree.findClassObjects(cls) or {}) do
      if tostring(name):find('^earthRaid_') and not mine[name] then
        local o = scenetree.findObject(name)
        if o then pcall(function() if o.unload then o:unload() end o:delete() end) n = n + 1 end
      end
    end
  end
  return n
end

-- las líneas pintadas (spray) son DecalRoad: se rehacen en cada colocación
local function applyLine(it)
  local x1, y1, z1, ok1 = M.ground(it.lat, it.lon)
  local x2, y2, z2, ok2 = M.ground(it.lat2, it.lon2)
  if not (x1 and x2) then return false end
  if it.obj then pcall(function() it.obj:delete() end) it.obj = nil end
  local r = createObject('DecalRoad')
  r:setField('material', 0, it.material)
  r:setField('textureLength', 0, '4')
  r:setField('renderPriority', 0, '10')
  r.canSave = false
  serial = serial + 1
  r:registerObject(('earthRaid_line_%d_%d'):format(serial, os.time()))
  if scenetree.MissionGroup then scenetree.MissionGroup:addObject(r) end
  r:insertNode(vec3(x1, y1, z1), it.width, 0)
  r:insertNode(vec3(x2, y2, z2), it.width, 1)
  it.obj, it.pending, it.z = r, not (ok1 and ok2), z1
  return true
end

-- la dirección (dx, dy) girada `yaw` grados en sentido horario
local function rot(dx, dy, yaw)
  local r = math.rad(yaw or 0)
  local c, s = math.cos(r), math.sin(r)
  return dx * c + dy * s, -dx * s + dy * c
end

local function apply(it)
  if it.line then return applyLine(it) end
  local x, y, z, ok = M.ground(it.lat, it.lon)
  if not x then return false end
  it.pending, it.z = not ok, z
  local fx, fy = rot(it.dx, it.dy, it.yaw)
  local q = quatFromDir(vec3(fx, fy, 0), vec3(0, 0, 1))
  it.obj:setPosRot(x, y, z + (it.dz or 0), q.x, q.y, q.z, q.w)
  return true
end

local function register(o, kind)
  o:setField('canSave', 0, '0')
  o.canSave = false
  serial = serial + 1
  o:registerObject(('earthRaid_%s_%d_%d'):format(kind, serial, os.time()))
  if scenetree.MissionGroup then scenetree.MissionGroup:addObject(o) end
end

M.SOLID = { hayBale = true, hayBale2 = true, plasticBarrier = true, plasticBarrierW = true, table = true, chair = true, cushion = true, bigToolbox = true, bigToolbox2 = true, smallToolbox = true,
  tireRack = true, workbench = true, stool = true, gazeboFrame = true }
-- (20-nov, norma del usuario: las vallas que delimitan el circuito NO chocan, para ahorrar; lo que cierra una calle o una
-- zona de escape —pacas y barreras de plástico— sí, con la malla visible, para que el coche no se salga del tramo)
M.HARD = { hayBale = true, hayBale2 = true, plasticBarrier = true, plasticBarrierW = true }
function M.isSolid(kind) return M.SOLID[kind] == true end

-- Coloca un objeto: kind (clave de SHAPES o PREFABS), lat, lon, dx, dy (dirección de marcha), yaw (grados, horario)
local baleMats = false
local function create(kind, opts)
  local shape, prefab, snd = M.SHAPES[kind], M.PREFABS[kind], M.SOUNDS[kind]
  if (kind == 'hayBale' or kind == 'hayBale2') and not baleMats then
    -- los materiales de las pacas solo existen como carga de vehículo: se cargan a mano (18-nov: salían naranjas)
    baleMats = true
    pcall(loadJsonMaterialsFile, '/vehicles/common/loads/haybale/main.materials.json')
  end
  local o
  if kind == 'lamp' then
    -- luz cálida bajo las carpas (se ve de noche)
    o = createObject('PointLight')
    o:setField('radius', 0, '10')
    o:setField('brightness', 0, '1.4')
    o:setField('color', 0, '1 0.82 0.55 1')
    o:setField('castShadows', 0, '0')
    o:setPosition(vec3(0, 0, 0))
  elseif snd then
    o = createObject('SFXEmitter')
    o:setField('fileName', 0, snd.file)
    o:setField('isLooping', 0, snd.loop and '1' or '0')
    o:setField('is3D', 0, '1')
    o:setField('isStreaming', 0, '0')
    o:setField('volume', 0, tostring(snd.volume))
    o:setField('referenceDistance', 0, tostring(snd.ref))
    o:setField('maxDistance', 0, tostring(snd.max))
    o:setField('playOnAdd', 0, '1')
    o:setPosition(vec3(0, 0, 0))
  elseif prefab then
    o = createObject('Prefab')
    o:setField('filename', 0, prefab)
    o:setPosition(vec3(0, 0, 0))
  else
    o = createObject('TSStatic')
    o:setField('shapeName', 0, shape)
    o:setPosition(vec3(0, 0, 0))
    o.scale = vec3(1, 1, 1)
    -- Colisión (17-nov): solo lo sólido (vallas, colchones, mesas, cajas de herramientas...) choca, con su propia
    -- malla de colisión. Carteles, conos y cintas no: son papel en un palo o plástico, y cerca del coche se cambian
    -- por su versión con física (phys.lua), que se cae o se rompe al tocarla.
    if (opts and opts.noCollision) or not M.isSolid(kind) then o:setField('collisionType', 0, 'None')
    else
      if M.HARD[kind] then o:setField('collisionType', 0, 'Visible Mesh') end
      M.collisionDirty = true
    end
  end
  if kind == 'ambulance' or phys.PHYS_ONLY[kind] then pcall(function() o:setHidden(true) end) end
  register(o, kind)
  -- las vallas son prefabs (armazón + lona) y sus piezas traen colisión propia: fuera (20-nov, norma del usuario: lo que
  -- delimita el circuito no choca). Las piezas existen desde que el prefab se registra. MARK:fence-nocol-v1
  if prefab and (tostring(kind):find('^fence') or (opts and opts.noCollision)) then
    pcall(function()
      local g = o:getChildGroup()
      for i = 0, g:getCount() - 1 do
        local c = Sim.upcast(g:getObject(i))
        if c and c:getClassName() == 'TSStatic' then c:setField('collisionType', 0, 'None') pcall(function() c:postApply() end) end
      end
      M.collisionDirty = true
    end)
  end
  if prefab and o.load then pcall(function() o:load() end) end
  return o
end

-- Los objetos no se crean todos de golpe (un montaje de salida son ~100 y se notaba un tirón de 0,25 s con el sonido
-- entrecortado): se encolan y M.pump los crea poco a poco, con un presupuesto de tiempo por fotograma. El semáforo y
-- los relojes se crean al momento (el reloj del juego los busca enseguida).
M.PUMP_MS = 2.5
M.IMMEDIATE = { tree = true }
local queue = {}
-- Reciclaje entre tramos: al empezar otro tramo lo del anterior no se borra, queda de repuesto; si el nuevo pone el
-- mismo objeto (tipo, opciones, dirección) en el mismo sitio (ida y vuelta, salida donde acabó el otro), se reutiliza
-- en vez de crear uno nuevo. Lo que no se aprovecha se borra cuando su zona ya está montada.
M.REUSE_M = 1.2
M.reused = 0
local spare = {}             -- tipo -> { item... }
M._spare = spare

local function optsKey(o)
  if type(o) ~= 'table' then return '' end
  local ks = {}
  for k, v in pairs(o) do if type(v) ~= 'table' and type(v) ~= 'function' then ks[#ks + 1] = tostring(k) .. '=' .. tostring(v) end end
  table.sort(ks)
  return table.concat(ks, ';')
end

local function dropObj(it)
  pcall(function()
    if it.obj then
      if it.obj.unload then pcall(function() it.obj:unload() end) end
      it.obj:delete()
    end
  end)
  it.obj = nil
end

local function takeSpare(it)
  local l = spare[it.kind]
  if not l or #l == 0 then return false end
  local k = math.cos(math.rad(it.lat))
  local key = optsKey(it.opts)
  local fx, fy = rot(it.dx or 0, it.dy or 1, it.yaw or 0)
  for i, sp in ipairs(l) do
    local ex = (sp.lon - it.lon) * 111195 * k
    local ny = (sp.lat - it.lat) * 111195
    if ex * ex + ny * ny < M.REUSE_M * M.REUSE_M and (sp.key or optsKey(sp.opts)) == key then
      local gx, gy = rot(sp.dx or 0, sp.dy or 1, sp.yaw or 0)
      if fx * gx + fy * gy > 0.97 then
        table.remove(l, i)
        it.obj = sp.obj
        pcall(apply, it)
        M.reused = M.reused + 1
        return true
      end
    end
  end
  return false
end

-- lo de este tramo pasa a ser de repuesto para el siguiente (las luces, sonidos y líneas pintadas no: se borran)
-- el parque de asistencia (boxes, casetas, vallas, TC0) se queda hasta que arranca el tramo (M.releasePark)
M.group = nil
local function parkKeep(it) return it.park == true end

function M.retire()
  phys.clear()
  local kept = {}
  for _, it in ipairs(queue) do if parkKeep(it) then kept[#kept + 1] = it else it.dead = true end end
  local keepQ = {}
  for _, it in ipairs(queue) do if parkKeep(it) then keepQ[#keepQ + 1] = it end end
  queue = keepQ
  kept = {}
  for _, it in ipairs(items) do
    if parkKeep(it) then kept[#kept + 1] = it
    elseif it.obj and not it.line and it.kind ~= 'lamp' and not M.SOUNDS[it.kind] then
      it.key = optsKey(it.opts)
      local l = spare[it.kind] or {}
      spare[it.kind] = l
      l[#l + 1] = it
    else
      dropObj(it)
    end
  end
  items = kept
  M.reused = 0
end

-- el tramo empieza: el parque de asistencia se libera (memoria)
function M.releasePark()
  local rest, n = {}, 0
  for _, it in ipairs(items) do
    if it.park then dropObj(it) n = n + 1 else rest[#rest + 1] = it end
  end
  local q = {}
  for _, it in ipairs(queue) do if it.park then it.dead = true else q[#q + 1] = it end end
  queue, items = q, rest
  if n > 0 then M.collisionDirty = true end
  return n
end

-- borra los de repuesto que no pasen keep(item) (sin keep: todos)
function M.flushSpare(keep)
  local n = 0
  for kind, l in pairs(spare) do
    local rest = {}
    for _, it in ipairs(l) do
      if keep and keep(it) then rest[#rest + 1] = it else dropObj(it) n = n + 1 end
    end
    spare[kind] = rest
  end
  if n > 0 then M.collisionDirty = true end
  return n
end

function M.spareCount()
  local n = 0
  for _, l in pairs(spare) do n = n + #l end
  return n
end

function M.add(kind, lat, lon, dx, dy, yaw, opts)
  local shape, prefab, snd = M.SHAPES[kind], M.PREFABS[kind], M.SOUNDS[kind]
  if not (shape or prefab or snd or kind == 'lamp') then return nil end
  local it = { kind = kind, lat = lat, lon = lon, dx = dx, dy = dy, yaw = yaw or 180, dz = opts and opts.dz, opts = opts, park = M.group == 'park' or nil }
  items[#items + 1] = it
  if takeSpare(it) then return it end
  if M.IMMEDIATE[kind] or M.sync then
    local ok, obj = pcall(create, kind, opts)
    if not ok or not obj then log('W', TAG, 'props ' .. kind .. ': ' .. tostring(obj)) return it end
    it.obj = obj
    pcall(apply, it)
  else
    queue[#queue + 1] = it
  end
  return it
end

-- crea lo encolado hasta gastar budgetMs (o M.PUMP_MS); devuelve cuántos quedan
function M.pump(budgetMs)
  if #queue == 0 then return 0 end
  local t0 = os.clock()
  local limit = (budgetMs or M.PUMP_MS) / 1000
  local i = 1
  while i <= #queue do
    local it = queue[i]
    if not it.dead and not it.hidden then
      local ok, obj = pcall(create, it.kind, it.opts)
      if ok and obj then it.obj = obj pcall(apply, it) else log('W', TAG, 'props ' .. it.kind .. ': ' .. tostring(obj)) end
    end
    i = i + 1
    if os.clock() - t0 > limit then break end
  end
  for _ = 1, i - 1 do table.remove(queue, 1) end
  return #queue
end
function M.pending() return #queue end

-- Una línea pintada en el suelo de (lat, lon) a (lat2, lon2): material de spray del juego, ancho en metros
function M.addLine(lat, lon, lat2, lon2, material, width)
  local it = { line = true, kind = 'line', lat = lat, lon = lon, lat2 = lat2, lon2 = lon2,
    material = material or 'spraypaint_mark', width = width or 0.35 }
  items[#items + 1] = it
  pcall(apply, it)
  return it
end

function M.replace() for _, it in ipairs(items) do pcall(apply, it) end end

-- lleva un objeto a otro sitio (lat, lon), con la misma dirección
function M.move(it, lat, lon)
  it.lat, it.lon = lat, lon
  return pcall(apply, it)
end

-- Recoloca en altura lo que está a menos de radiusM de (lat, lon): lo que se puso sin terreno cargado y lo que ha
-- quedado por encima o por debajo del suelo (el terreno de BeamNG.Earth se afina al acercarse)
-- NORMA (22-nov): nada se mueve a la vista. A menos de M.NEAR_FREEZE_M del jugador solo se corrige lo que nunca tuvo suelo
-- o ha quedado a más de 1 m de él (flotando o enterrado se ve peor); `free` = pantalla de carga, se corrige todo.
M.NEAR_FREEZE_M = 130
function M.reground(lat, lon, radiusM, free)
  local k = math.cos(math.rad(lat))
  local n, trees = 0, 0
  for _, it in ipairs(items) do
    local dx = (it.lon - lon) * 111195 * k
    local dy = (it.lat - lat) * 111195
    local d2 = dx * dx + dy * dy
    if (it.obj or it.line) and d2 < radiusM * radiusM then
      local _, _, z, ok = M.ground(it.lat, it.lon)
      local tol = (free or d2 > M.NEAR_FREEZE_M * M.NEAR_FREEZE_M) and 0.25 or 1.0
      if ok and (it.pending or math.abs((it.z or 0) - z) > tol) then
        pcall(apply, it)
        n = n + 1
        if it.kind == 'tree' then trees = trees + 1 end
      end
    end
  end
  return n, trees
end

function M.clear()
  phys.clear()
  M.flushSpare()
  for _, it in ipairs(queue) do it.dead = true end
  queue = {}
  for _, it in ipairs(items) do
    pcall(function()
      if it.obj then
        if it.obj.unload then pcall(function() it.obj:unload() end) end
        it.obj:delete()
      end
    end)
  end
  items = {}
end

-- quita un objeto de la escena sin romper la lista (offRoad no le encontró sitio fuera de la calzada)
function M.hide(it)
  it.hidden = true
  phys.forget(it)
  if it.obj then
    pcall(function() if it.obj.unload then it.obj:unload() end it.obj:delete() end)
    it.obj = nil
    M.collisionDirty = true
  end
end

function M.count() return #items end
function M.find(kind) for _, it in ipairs(items) do if it.kind == kind then return it.obj end end end
function M.all() return items end


-- La carretera más cercana a (x, y) en planta: n1, n2, distancia, punto más cercano (cx, cy). map.findClosestRoad solo
-- mira unos 100 m (más allá devuelve 128): si no hay nada ahí, se recorre el grafo entero (son pocos cientos de nodos)
function M.nearestRoad(x, y, z, maxD)
  maxD = maxD or 300
  local ok, n1, n2, d = pcall(map.findClosestRoad, vec3(x, y, z or 0))
  local m = map.getMap()
  if not (m and m.nodes) then return nil end
  local function seg(a, b)
    local A, B = m.nodes[a].pos, m.nodes[b].pos
    local sx, sy = B.x - A.x, B.y - A.y
    local L2 = sx * sx + sy * sy
    local u = L2 > 0.01 and math.max(0, math.min(1, ((x - A.x) * sx + (y - A.y) * sy) / L2)) or 0
    local cx, cy = A.x + sx * u, A.y + sy * u
    return math.sqrt((x - cx) ^ 2 + (y - cy) ^ 2), cx, cy
  end
  if ok and n1 and n2 and d and d < 100 and m.nodes[n1] and m.nodes[n2] then
    local dd, cx, cy = seg(n1, n2)
    return n1, n2, dd, cx, cy
  end
  local bd, b1, b2, bx, by = maxD, nil, nil, nil, nil
  for id, nd in pairs(m.nodes) do
    local p = nd.pos
    if math.abs(p.x - x) < maxD + 200 and math.abs(p.y - y) < maxD + 200 then
      for nb in pairs(nd.links or {}) do
        if m.nodes[nb] then
          local dd, cx, cy = seg(id, nb)
          if dd < bd then bd, b1, b2, bx, by = dd, id, nb, cx, cy end
        end
      end
    end
  end
  if b1 then return b1, b2, bd, bx, by end
  return nil
end


-- Índice de todas las carreteras cargadas (tramos entre nodos del grafo), en celdas de 32 m. Se rehace cuando el grafo
-- cambia (BeamNG.Earth carga carreteras nuevas al moverse). Lo usa dressing.offRoad: un objeto no puede quedar en
-- ninguna calzada, ni la del tramo ni las que cruzan.
M.CELL_M = 32
local roadIdx = { n = -1, cells = {}, segs = {}, t = -1e9 }
function M.roadIndex()
  local m = map.getMap()
  if not (m and m.nodes) then return nil end
  -- contar los nodos cuesta: como mucho cada medio segundo
  local now = os.clock()
  if roadIdx.map == m and now - (roadIdx.checked or 0) < 0.5 then return roadIdx end
  local count = 0
  for _ in pairs(m.nodes) do count = count + 1 end
  roadIdx.checked = now
  if count == roadIdx.n and roadIdx.map == m then return roadIdx end
  local cells, segs, C = {}, {}, M.CELL_M
  local seen = {}
  for id, nd in pairs(m.nodes) do
    for nb in pairs(nd.links or {}) do
      local o = m.nodes[nb]
      if o and not seen[tostring(nb) .. '|' .. tostring(id)] then
        seen[tostring(id) .. '|' .. tostring(nb)] = true
        local A, B = nd.pos, o.pos
        local sg = { ax = A.x, ay = A.y, bx = B.x, by = B.y, ra = nd.radius or 3, rb = o.radius or 3 }
        segs[#segs + 1] = sg
        local pad = math.max(sg.ra, sg.rb) + 4
        local x0, x1 = math.floor((math.min(A.x, B.x) - pad) / C), math.floor((math.max(A.x, B.x) + pad) / C)
        local y0, y1 = math.floor((math.min(A.y, B.y) - pad) / C), math.floor((math.max(A.y, B.y) + pad) / C)
        if (x1 - x0 + 1) * (y1 - y0 + 1) <= 400 then
          for cx = x0, x1 do
            for cy = y0, y1 do
              local k = cx .. ':' .. cy
              local l = cells[k]
              if not l then l = {} cells[k] = l end
              l[#l + 1] = sg
            end
          end
        end
      end
    end
  end
  -- el trazado del tramo donde el juego no tiene carretera (pistas de tierra, caminos): también cuenta como calzada,
  -- con la anchura de su superficie, para que nada se quede encima (17-nov: una ruta de tierra importada por un amigo
  -- del usuario se montó mal porque el grafo no tenía ese camino)
  local virt = 0
  for _, sg in ipairs(M._virtual or {}) do
    local mx, my = (sg.ax + sg.bx) / 2, (sg.ay + sg.by) / 2
    local covered = false
    for _, g in ipairs(cells[math.floor(mx / C) .. ':' .. math.floor(my / C)] or {}) do
      local gx, gy = g.bx - g.ax, g.by - g.ay
      local L2 = gx * gx + gy * gy
      local u = L2 > 0.01 and math.max(0, math.min(1, ((mx - g.ax) * gx + (my - g.ay) * gy) / L2)) or 0
      if (mx - g.ax - gx * u) ^ 2 + (my - g.ay - gy * u) ^ 2 < M.VIRTUAL_COVER_M ^ 2 then covered = true break end
    end
    if not covered then
      virt = virt + 1
      segs[#segs + 1] = sg
      local pad = sg.ra + 4
      for cx = math.floor((math.min(sg.ax, sg.bx) - pad) / C), math.floor((math.max(sg.ax, sg.bx) + pad) / C) do
        for cy = math.floor((math.min(sg.ay, sg.by) - pad) / C), math.floor((math.max(sg.ay, sg.by) + pad) / C) do
          local k = cx .. ':' .. cy
          local l = cells[k]
          if not l then l = {} cells[k] = l end
          l[#l + 1] = sg
        end
      end
    end
  end
  roadIdx = { n = count, map = m, cells = cells, segs = segs, version = (roadIdx.version or 0) + 1, checked = now, virtual = virt }
  return roadIdx
end

M.VIRTUAL_COVER_M = 15   -- solo donde no hay ninguna carretera del juego a menos de esto (el KMZ suele ir desplazado unos metros)
-- trazados que cuentan como calzada aunque el grafo no los tenga: lista de puntos {x, y} del juego y media anchura
function M.setVirtualRoad(pts, halfW)
  local v = {}
  for i = 2, #(pts or {}) do
    local a, b = pts[i - 1], pts[i]
    v[#v + 1] = { ax = a[1], ay = a[2], bx = b[1], by = b[2], ra = halfW, rb = halfW, virtual = true }
  end
  M._virtual = v
  roadIdx.n = -1
  roadIdx.checked = 0
end

-- los tramos de carretera cerca de (x, y)
function M.roadsAt(x, y)
  local ix = M.roadIndex()
  if not ix then return nil end
  return ix.cells[math.floor(x / M.CELL_M) .. ':' .. math.floor(y / M.CELL_M)] or {}, ix
end

-- Vecinos de cada nodo del grafo en los dos sentidos: BeamNG.Earth guarda cada enlace en uno solo de sus extremos
-- (17-nov: por eso la carretera de antes de la salida no se encontraba y el TC caía en un prado)
local adj = { map = nil, n = -1 }
function M.neighbors(id)
  local m = map.getMap()
  if not (m and m.nodes) then return {} end
  local count = 0
  if adj.map == m and os.clock() - (adj.t or 0) < 0.5 then
    return adj.list[id] or {}
  end
  for _ in pairs(m.nodes) do count = count + 1 end
  if adj.map ~= m or adj.n ~= count then
    local list = {}
    for a, nd in pairs(m.nodes) do
      for b in pairs(nd.links or {}) do
        if m.nodes[b] then
          list[a] = list[a] or {}
          list[b] = list[b] or {}
          list[a][b] = true
          list[b][a] = true
        end
      end
    end
    adj = { map = m, n = count, list = list }
  end
  adj.t = os.clock()
  return adj.list[id] or {}
end

return M

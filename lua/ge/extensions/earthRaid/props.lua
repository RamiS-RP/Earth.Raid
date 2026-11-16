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
local TAG = 'earthRaid'
local A = '/art/shapes/race/rally/rally_assets/'

M.SHAPES = {
  start = A .. 's_rally_signboard_start.dae', finish = A .. 's_rally_signboard_finish.dae',
  finishEntry = A .. 's_rally_signboard_finish_entry.dae', stop = A .. 's_rally_signboard_stop.dae',
  tc = A .. 's_rally_signboard_time_control.dae', tcEntry = A .. 's_rally_signboard_time_control_entry.dae',
  radio = A .. 's_rally_signboard_radio_point.dae', radioWarn = A .. 's_rally_signboard_radio_point_warning.dae',
  medical = A .. 's_rally_signboard_medical_point.dae', medicalWarn = A .. 's_rally_signboard_medical_warning.dae',
  endArea = A .. 's_rally_signboard_end_of_area.dae',
  board1 = A .. 's_cooldown_board_01.dae', board2 = A .. 's_cooldown_board_02.dae', board3 = A .. 's_cooldown_board_03.dae',
  sensor = A .. 's_rally_start_sensor.dae', tree = A .. 's_rally_start_tree.dae',
  gazeboFrame = A .. 's_rally_gazebo_mod_frame_3x3.dae', gazeboCover = A .. 's_rally_gazebo_mod_cover_ngrc_3x3.dae',
  table = A .. 's_rally_fold_table_01.dae', chair = A .. 's_rally_fold_chair_01.dae', cone = '/art/shapes/race/cone.dae',
  cornerR = A .. 's_corner_dir_right.dae', cornerL = A .. 's_corner_dir_left.dae',
  corner45R = A .. 's_corner_dir45_right.dae', corner45L = A .. 's_corner_dir45_left.dae',
  hairpinR = A .. 's_corner_dir135_right.dae', hairpinL = A .. 's_corner_dir225_left.dae',
  tape = A .. 's_tape_road_closure_8m.dae', tape6 = A .. 's_tape_road_closure_6m.dae', tape10 = A .. 's_tape_road_closure_10m.dae',
  specTape = A .. 's_spectator_tape_5m.dae', specGrid = A .. 's_spectator_grid_center.dae',
  fenceNgrc = A .. 's_metal_fence_branding_ngrc.dae', fenceBlastr = A .. 's_metal_fence_branding_blastr.dae',
  fenceRotopad = A .. 's_metal_fence_branding_rotopad.dae', cushion = A .. 's_safety_cushion_01.dae',
  fenceApm = A .. 's_metal_fence_branding_apm.dae', fenceApmSpecial = A .. 's_metal_fence_branding_apm_special.dae',
  specTarp = A .. 's_spectator_tarp_4m.dae', specTarp2 = A .. 's_spectator_tarp_4m_02.dae', specTarp3 = A .. 's_spectator_tarp_4m_03.dae',
  specGridA = A .. 's_spectator_grid_a_2m.dae', cornerMarker = A .. 's_corner_marker.dae',
  danger = '/art/shapes/garage_and_dealership/Clutter/italy_traf_sign_warn_other_danger.dae',
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
    local h = be:getSurfaceHeightBelow(vec3(x, y, th + 0.6))
    if type(h) == 'number' and h > th - 1 and h < th + 0.6 then z = h end
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

-- Coloca un objeto: kind (clave de SHAPES o PREFABS), lat, lon, dx, dy (dirección de marcha), yaw (grados, horario)
function M.add(kind, lat, lon, dx, dy, yaw, opts)
  local shape, prefab, snd = M.SHAPES[kind], M.PREFABS[kind], M.SOUNDS[kind]
  if not (shape or prefab or snd or kind == 'lamp') then return nil end
  local ok, obj = pcall(function()
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
      if opts and opts.noCollision then o:setField('collisionType', 0, 'None') end
    end
    register(o, kind)
    if prefab and o.load then pcall(function() o:load() end) end
    return o
  end)
  if not ok or not obj then log('W', TAG, 'props ' .. kind .. ': ' .. tostring(obj)) return nil end
  local it = { obj = obj, kind = kind, lat = lat, lon = lon, dx = dx, dy = dy, yaw = yaw or 180, dz = opts and opts.dz }
  items[#items + 1] = it
  pcall(apply, it)
  return it
end

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
function M.reground(lat, lon, radiusM)
  local k = math.cos(math.rad(lat))
  local n, trees = 0, 0
  for _, it in ipairs(items) do
    local dx = (it.lon - lon) * 111195 * k
    local dy = (it.lat - lat) * 111195
    if dx * dx + dy * dy < radiusM * radiusM then
      local _, _, z, ok = M.ground(it.lat, it.lon)
      if ok and (it.pending or math.abs((it.z or 0) - z) > 0.25) then
        pcall(apply, it)
        n = n + 1
        if it.kind == 'tree' then trees = trees + 1 end
      end
    end
  end
  return n, trees
end

function M.clear()
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

function M.count() return #items end
function M.find(kind) for _, it in ipairs(items) do if it.kind == kind then return it.obj end end end
function M.all() return items end

return M

-- Raid.Earth: puentes de madera sobre cruces sin tablero (27-nov, el usuario: «arreglar la entrada al puente del
-- shakedown; probar un puente de madera encima y si no, aplanar el montículo»).
--
-- El paquete marca cada cruce en el tramo con `woodBridges = { { la1, lo1, la2, lo2 }, ... }`: los dos puntos de la
-- orilla, a la altura del camino. Se pone un tablero de madera (36 x 5 m, 4,4 m libres entre bordillos) entre los dos,
-- con la cara superior un poco por debajo de la orilla más baja: los extremos quedan enterrados en el talud y no hay
-- escalón. Material con groundType WOOD (suena y agarra como madera). Se quita al terminar el tramo.
local M = {}
local TAG = 'earthRaid.bridges'

M.SHAPE = '/art/earthRaid/bridge/wood_bridge.dae'
M.MATERIALS = '/art/earthRaid/bridge/main.materials.json'
M.LEN = 36          -- largo del tablero (m)
M.MAX_SPAN = 33     -- distancia máxima entre orillas: los extremos tienen que entrar en el talud
M.CLEAR_HALF = 2.2  -- media anchura libre (bordillos)
M.APPROACH = 14     -- m antes y después del tablero en los que nada se pone dentro de la anchura del puente
M.SINK = 0.08       -- el tablero, por debajo de la orilla más baja
M.UNLOADED_Z = -15.9

-- Los cruces conocidos (evento/tramo), por si el paquete importado se vuelve a generar sin el campo
M.KNOWN = {
  -- Rally Sweden: shakedown de Umeå, el arroyo a 1,6 km (estribo de hormigón sin tablero, montículo en la entrada)
  ['imp-rally-sweden-2027/shakedown-umea-city'] = { { 63.8273566, 20.2122283, 63.8272733, 20.2128527 } },
}

local list, objs, matsLoaded = {}, {}, false

local function api() return rawget(_G, 'beamngEarth_api') end

-- `defs`: la lista del paquete. Calcula ya el centro y la dirección (no hace falta terreno), para que el resto del
-- montaje (bidones de pathgen) sepa dónde va el puente aunque aún no esté puesto
function M.set(defs)
  M.clear()
  local a = api()
  if type(defs) ~= 'table' or not a then return end
  for i, d in ipairs(defs) do
    local x1, y1 = a.toGame(d[1], d[2])
    local x2, y2 = a.toGame(d[3], d[4])
    if x1 and x2 then
      local span = math.sqrt((x2 - x1) ^ 2 + (y2 - y1) ^ 2)
      if span > M.MAX_SPAN then log('W', TAG, ('bridge %d: %.0f m between the banks, longer than the deck'):format(i, span)) end
      list[#list + 1] = { i = i, a = vec3(x1, y1, 0), b = vec3(x2, y2, 0), c = vec3((x1 + x2) / 2, (y1 + y2) / 2, 0),
        dir = vec3(x2 - x1, y2 - y1, 0):normalized(), span = span }
    end
  end
end

-- posición respecto a un puente: (a lo largo desde el centro, de lado) o nil si no hay ninguno cerca
function M.near(x, y, extra)
  for _, b in ipairs(list) do
    local dx, dy = x - b.c.x, y - b.c.y
    local s = dx * b.dir.x + dy * b.dir.y
    local l = -dx * b.dir.y + dy * b.dir.x
    if math.abs(s) <= M.LEN / 2 + (extra or M.APPROACH) and math.abs(l) <= M.CLEAR_HALF + 1.5 then return b, s, l end
  end
end

-- un objeto que iba a quedar dentro del paso del puente (o de su entrada), fuera de él: a 0,7 m del bordillo
function M.pushOut(x, y)
  local b, _, l = M.near(x, y)
  if not b then return x, y, false end
  local side = vec3(-b.dir.y, b.dir.x, 0)
  local want = (l >= 0 and 1 or -1) * (M.CLEAR_HALF + 0.7)
  return x + side.x * (want - l), y + side.y * (want - l), true
end

local function place(b)
  local th = core_terrain and core_terrain.getTerrainHeight
  if not th then return false end
  local za, zb = th(b.a), th(b.b)
  if not za or not zb or za <= M.UNLOADED_Z or zb <= M.UNLOADED_Z then return false end   -- orillas aún sin cargar
  if not matsLoaded then matsLoaded = true pcall(loadJsonMaterialsFile, M.MATERIALS) end
  local z = math.min(za, zb) - M.SINK
  local ok, o = pcall(function()
    local s = createObject('TSStatic')
    s:setField('shapeName', 0, M.SHAPE)
    s:setField('collisionType', 0, 'Visible Mesh')
    s:setField('decalType', 0, 'Visible Mesh')
    s:setField('canSave', 0, '0')
    s.canSave = false
    local q = quatFromDir(b.dir, vec3(0, 0, 1))
    local m = QuatF(q.x, q.y, q.z, q.w):getMatrix()
    m:setPosition(vec3(b.c.x, b.c.y, z))
    s:setTransform(m)
    s.scale = vec3(1, 1, 1)
    s:registerObject(('earthRaid_bridge_%d_%d'):format(b.i, os.time()))
    if scenetree.MissionGroup then scenetree.MissionGroup:addObject(s) end
    return s
  end)
  if not ok or not o then log('W', TAG, 'bridge: ' .. tostring(o)) b.failed = true return false end
  objs[#objs + 1] = o
  b.z, b.placed = z, true
  log('I', TAG, ('wooden bridge %d: %.0f m between the banks, deck at %.2f'):format(b.i, b.span, z))
  return true
end

-- (27-nov, prueba en Umeå) BeamNG.Earth tiene allí su propio puente: pretiles de hormigón sin tablero, desplazados del eje
-- del tramo, y uno de ellos cruza el tablero de madera en diagonal. Mientras está el puente de madera, las mallas de Earth
-- que se meten en su paso (sobre el tablero) se ocultan y pierden la colisión; al quitarlo se devuelven como estaban.
local hiddenEarth = {}
local function hideEarth(b)
  local n = 0
  local ok, names = pcall(scenetree.findClassObjects, 'TSStatic')
  if not ok then return 0 end
  for _, nm in ipairs(names or {}) do
    local o = scenetree.findObject(nm)
    if o and not hiddenEarth[nm] and not tostring(nm):find('^bngEarthFar') then
      local okS, shape = pcall(function() return o:getField('shapeName', 0) end)
      if okS and tostring(shape):find('beamngEarth', 1, true) then
        local okB, box = pcall(function() return o:getWorldBox() end)
        if okB and box and box.maxExtents.z > b.z + 0.1 and box.minExtents.z < b.z + 3
          and box.maxExtents.x - box.minExtents.x < 80 and box.maxExtents.y - box.minExtents.y < 80 then
          -- ¿alguna esquina o el centro de la caja dentro del paso del tablero?
          local hit = false
          local mn, mx = box.minExtents, box.maxExtents
          for _, q in ipairs({ { mn.x, mn.y }, { mx.x, mn.y }, { mx.x, mx.y }, { mn.x, mx.y }, { (mn.x + mx.x) / 2, (mn.y + mx.y) / 2 } }) do
            local dx, dy = q[1] - b.c.x, q[2] - b.c.y
            if math.abs(dx * b.dir.x + dy * b.dir.y) <= M.LEN / 2 and math.abs(-dx * b.dir.y + dy * b.dir.x) <= M.CLEAR_HALF + 0.5 then hit = true break end
          end
          -- (una caja grande en diagonal puede no tener ninguna esquina en el paso: se mira también el eje del tablero)
          if not hit then
            for s = -M.LEN / 2, M.LEN / 2, 2 do
              local x, y = b.c.x + b.dir.x * s, b.c.y + b.dir.y * s
              if x >= mn.x and x <= mx.x and y >= mn.y and y <= mx.y then hit = true break end
            end
          end
          if hit then
            local coll = o:getField('collisionType', 0)
            hiddenEarth[nm] = { o = o, coll = coll, hidden = o:isHidden() }
            pcall(function() o:setField('collisionType', 0, 'None') end)
            pcall(function() o:setHidden(true) end)
            n = n + 1
          end
        end
      end
    end
  end
  if n > 0 then log('I', TAG, ('wooden bridge %d: %d BeamNG.Earth meshes in its way hidden'):format(b.i, n)) end
  return n
end

local function clockS() return os.clock() end
local acc = 0
function M.update(dt)
  if #list == 0 then return end
  acc = acc + (dt or 0)
  if acc < 1 then return end
  acc = 0
  local changed = false
  for _, b in ipairs(list) do
    if not b.placed and not b.failed and place(b) then changed = true end
    -- (las teselas de Earth llegan poco a poco: se mira cada segundo mientras el puente está puesto)
    -- (recorrer todos los TSStatic cuesta: al ponerlo y luego cada 5 s, ocho veces)
    if b.placed and (b.scans or 0) < 8 and clockS() >= (b.nextScan or 0) then
      b.scans, b.nextScan = (b.scans or 0) + 1, clockS() + 5
      if hideEarth(b) > 0 then changed = true end
    end
  end
  if changed then pcall(function() be:reloadStaticCollision(false) end) end
end

function M.clear()
  local had = #objs > 0 or next(hiddenEarth) ~= nil
  for _, o in ipairs(objs) do pcall(function() o:delete() end) end
  for _, h in pairs(hiddenEarth) do
    pcall(function() h.o:setField('collisionType', 0, h.coll or 'Collision Mesh') h.o:setHidden(h.hidden == true) end)
  end
  objs, list, hiddenEarth = {}, {}, {}
  if had then pcall(function() be:reloadStaticCollision(false) end) end
end

function M.count() return #objs end

return M

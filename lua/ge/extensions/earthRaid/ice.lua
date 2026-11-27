-- Raid.Earth: río y mar helados en los tramos de nieve (27-nov, el usuario: «quiero que quede el suelo del río congelado a la
-- altura que se ve el barco, para no caer al agua; la capa de hielo ha de tener al menos un metro y comportarse como tal»).
--
-- Sin tocar el terreno (las ediciones de terreno siguen en alpha): losas de hielo de 20 x 20 x 1 m (art/earthRaid/ice) con
-- colisión y modelo de suelo ICE, con la cara de arriba 6 cm por encima de la superficie del agua (río por sus nodos, mar
-- por su bloque). Se ponen en cuadrícula en las casillas de agua a menos de ICE_R m del tramo, de su camino de antes y de
-- después; las que faltan (agua que carga tarde) se vuelven a buscar cada pocos segundos. Al terminar se borran todas.
local M = {}
local TAG = 'earthRaid.ice'

M.SHAPE = '/art/earthRaid/ice/ice_slab.dae'
M.MATERIALS = '/art/earthRaid/ice/main.materials.json'
M.TILE = 20          -- lado de la losa (m)
M.ICE_R = 45         -- distancia al tramo hasta la que se hiela el agua (m)
M.STEP = 8           -- cada cuántos metros del tramo se mira
M.TOP = 0.06         -- la cara de arriba, sobre la superficie del agua (m)
M.MAX = 600          -- tope de losas
M.RECHECK_S = 3
M.LEVEL_R = M.TILE * 1.5   -- losas vecinas (también en diagonal)
M.LEVEL_MAX = 1.5         -- diferencia máxima que se iguala (más: son aguas distintas, p. ej. un río que baja)
M.UNLOADED_Z = -15.9   -- altura que devuelve el terreno de Earth donde aún no ha cargado

local road = nil     -- { {x, y}, ... } en coordenadas del juego
local slabs = {}     -- [key] = obj
local count = 0
local t = 0
local matsLoaded = false

-- superficie del agua que cubre (x, y) si el suelo z queda por debajo; nil si no hay agua
local function surfaceAt(list, x, y, z)
  local best
  for _, w in ipairs(list or {}) do
    if x >= w[1] - 10 and x <= w[3] + 10 and y >= w[2] - 10 and y <= w[4] + 10 then
      if w.nodes then
        for i = 1, #w.nodes - 1 do
          local a, b = w.nodes[i], w.nodes[i + 1]
          local vx, vy = b[1] - a[1], b[2] - a[2]
          local L2 = vx * vx + vy * vy
          local tt = L2 > 0 and math.max(0, math.min(1, ((x - a[1]) * vx + (y - a[2]) * vy) / L2)) or 0
          local d2 = (x - a[1] - vx * tt) ^ 2 + (y - a[2] - vy * tt) ^ 2
          local hw = a[4] + (b[4] - a[4]) * tt
          local sz = a[3] + (b[3] - a[3]) * tt
          if d2 < (hw + 2) ^ 2 and z < sz - 0.2 and (not best or sz > best) then best = sz end
        end
      elseif z < w[5] - 0.2 and (not best or w[5] > best) then
        best = w[5]
      end
    end
  end
  return best
end
M.surfaceAt = surfaceAt

local function addSlab(key, x, y, z)
  if slabs[key] or count >= M.MAX then return false end
  if not matsLoaded then matsLoaded = true pcall(loadJsonMaterialsFile, M.MATERIALS) end
  local ok, o = pcall(function()
    local s = createObject('TSStatic')
    s:setField('shapeName', 0, M.SHAPE)
    s:setField('collisionType', 0, 'Visible Mesh')
    s:setField('decalType', 0, 'Visible Mesh')
    s:setField('canSave', 0, '0')
    s.canSave = false
    s:setPosition(vec3(x, y, z))
    s.scale = vec3(1, 1, 1)
    s:registerObject(('earthRaid_ice_%s_%d'):format(key, os.time()))
    if scenetree.MissionGroup then scenetree.MissionGroup:addObject(s) end
    return s
  end)
  if not ok or not o then log('W', TAG, 'ice slab: ' .. tostring(o)) return false end
  slabs[key], count = o, count + 1
  return true
end

-- busca agua junto al tramo y pone las losas que falten; devuelve cuántas puso
local function build()
  if not road then return 0 end
  local okS, sp = pcall(require, 'earthRaid/servicepark')
  if not okS or not sp.waterBodies then return 0 end
  local W = sp.waterBodies()
  if #W == 0 then return 0 end
  local T, R = M.TILE, M.ICE_R
  local added, seen = 0, {}
  local last
  for _, p in ipairs(road) do
    if not last or (p[1] - last[1]) ^ 2 + (p[2] - last[2]) ^ 2 >= M.STEP * M.STEP then
      last = p
      local i0, i1 = math.floor((p[1] - R) / T), math.floor((p[1] + R) / T)
      local j0, j1 = math.floor((p[2] - R) / T), math.floor((p[2] + R) / T)
      for i = i0, i1 do
        for j = j0, j1 do
          local key = i .. '_' .. j
          if not slabs[key] and not seen[key] then
            seen[key] = true
            local cx, cy = (i + 0.5) * T, (j + 0.5) * T
            if (cx - p[1]) ^ 2 + (cy - p[2]) ^ 2 <= (R + T * 0.7) ^ 2 then
              -- la casilla se hiela si su centro o alguna esquina está bajo el agua
              local surf
              for _, o in ipairs({ { 0, 0 }, { -0.4, -0.4 }, { 0.4, -0.4 }, { 0.4, 0.4 }, { -0.4, 0.4 } }) do
                local x, y = cx + o[1] * T, cy + o[2] * T
                local z = core_terrain.getTerrainHeight(vec3(x, y, 0))
                -- -16 = terreno aún sin cargar ahí (no es agua): se mira otra vez más tarde
                if z and z <= M.UNLOADED_Z then seen[key] = nil z = nil end
                local s = z and surfaceAt(W, x, y, z)
                if s and (not surf or s > surf) then surf = s end
              end
              if surf and addSlab(key, cx, cy, surf + M.TOP) then added = added + 1 end
            end
          end
        end
      end
    end
  end
  -- y las ya puestas que, con el terreno ya cargado, resultan no estar sobre agua (orilla alta): fuera
  local removed = 0
  for key, o in pairs(slabs) do
    local okP, pos = pcall(function() return o:getPosition() end)
    if okP and pos then
      local water, unknown = false, false
      for _, of in ipairs({ { 0, 0 }, { -0.4, -0.4 }, { 0.4, -0.4 }, { 0.4, 0.4 }, { -0.4, 0.4 } }) do
        local x, y = pos.x + of[1] * T, pos.y + of[2] * T
        local z = core_terrain.getTerrainHeight(vec3(x, y, 0))
        if not z or z <= M.UNLOADED_Z then unknown = true elseif surfaceAt(W, x, y, z) then water = true end
      end
      if not water and not unknown then pcall(function() o:delete() end) slabs[key] = nil count = count - 1 removed = removed + 1 end
    end
  end
  -- (27-nov, visto en Umeå: el río a 0,68 m y la bahía a 1,0 m dejaban escalones de 30 cm entre losas) todas las losas que
  -- se tocan (a menos de LEVEL_R m) quedan a la misma altura: la más alta del grupo
  if added > 0 or removed > 0 then
    local list = {}
    for _, o in pairs(slabs) do local okP, pos = pcall(function() return o:getPosition() end) if okP then list[#list + 1] = { o = o, p = pos, z = pos.z } end end
    for _ = 1, 6 do
      local changed = false
      for _, a in ipairs(list) do
        for _, b in ipairs(list) do
          if b.z > a.z + 0.001 and (a.p.x - b.p.x) ^ 2 + (a.p.y - b.p.y) ^ 2 <= M.LEVEL_R ^ 2 and b.z - a.z <= M.LEVEL_MAX then a.z, changed = b.z, true end
        end
      end
      if not changed then break end
    end
    for _, a in ipairs(list) do
      if math.abs(a.z - a.p.z) > 0.001 then pcall(function() a.o:setPosition(vec3(a.p.x, a.p.y, a.z)) end) end
    end
    pcall(function() be:reloadStaticCollision(false) end)
    if removed > 0 then log('I', TAG, ('frozen water: %d ice slabs on dry land removed'):format(removed)) end
    log('I', TAG, ('frozen water: %d ice slabs (%d in total)'):format(added, count))
  end
  return added
end

function M.setRoad(pts)
  road = pts
  t = M.RECHECK_S
end

function M.update(dt)
  if not road then return end
  t = t + (dt or 0)
  if t < M.RECHECK_S then return end
  t = 0
  pcall(build)
end

function M.clear()
  local n = 0
  for k, o in pairs(slabs) do pcall(function() o:delete() end) slabs[k] = nil n = n + 1 end
  count, road = 0, nil
  if n > 0 then
    pcall(function() be:reloadStaticCollision(false) end)
    log('I', TAG, ('frozen water: %d ice slabs removed'):format(n))
  end
end

function M.count() return count end

return M

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
M.TILE = 40          -- lado de la losa (m): la malla mide 20 m y se escala (27-nov: el río entero con menos objetos)
M.ICE_R = 45         -- distancia al tramo hasta la que se hiela el agua (m)
M.STEP = 8           -- cada cuántos metros del tramo se mira
M.GROUND = 'SNOW'    -- modelo de suelo del hielo
M.TOP = 0.06         -- la cara de arriba, sobre la superficie del agua (m)
M.MAX = 1600         -- tope de losas
-- (27-nov, el usuario: «el río no está congelado del todo; me gustaría que estuviese el río completo») el río que cruza o
-- toca el tramo se hiela entero a lo largo de sus nodos, hasta RIVER_R m del tramo (el mar, solo junto al tramo)
M.RIVER_R = 700
M.RIVER_TOUCH_M = 80 -- un río cuenta si alguno de sus tramos pasa a menos de esto del trazado
-- el camino sobre el hielo marcado a los dos lados (27-nov, el usuario: primero banderines; luego «sustituir los banderines
-- por mallas de seguridad naranjas de 12 m, con ángulo ajustable»): la malla naranja de Utah (10 m, larga en Y) estirada a
-- 12 m y girada con el trazado en cada tramo; un hueco de FLAG_STEP - 12 m entre mallas
M.FLAG_SHAPE = '/art/shapes/race/ut_race_mesh_barricade_.DAE'
M.FLAG_LEN = 12
M.FLAG_STEP, M.FLAG_SIDE = 14, 6.0
M.RECHECK_S = 3
M.LEVEL_R = M.TILE * 1.5   -- losas vecinas (también en diagonal)
M.LEVEL_MAX = 0.5         -- diferencia máxima que se iguala (más: son aguas distintas, p. ej. un río que baja)
M.UNLOADED_Z = -15.9   -- altura que devuelve el terreno de Earth donde aún no ha cargado

local road = nil     -- { {x, y}, ... } en coordenadas del juego
local slabs = {}     -- [key] = obj
local base = {}      -- [key] = altura de la losa sobre su agua (sin igualar)
local count = 0
local t = 0
local matsLoaded = false
local serialF = 0

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
  if not matsLoaded then
    matsLoaded = true
    pcall(loadJsonMaterialsFile, M.MATERIALS)
    -- (27-nov, el usuario: «que deslice un poco menos, que sea controlable») agarre de nieve compacta (SNOW: 0,65/0,40)
    -- en vez de hielo vivo (ICE: 0,40/0,20); también si el material ya estaba cargado de antes
    pcall(function() local m = scenetree.findObject('earthRaid_ice') if m then m:setField('groundType', 0, M.GROUND) end end)
  end
  local ok, o = pcall(function()
    local s = createObject('TSStatic')
    s:setField('shapeName', 0, M.SHAPE)
    s:setField('collisionType', 0, 'Visible Mesh')
    s:setField('decalType', 0, 'Visible Mesh')
    s:setField('canSave', 0, '0')
    s.canSave = false
    s:setPosition(vec3(x, y, z))
    s.scale = vec3(M.TILE / 20, M.TILE / 20, 1)
    s:registerObject(('earthRaid_ice_%s_%d'):format(key, os.time()))
    if scenetree.MissionGroup then scenetree.MissionGroup:addObject(s) end
    return s
  end)
  if not ok or not o then log('W', TAG, 'ice slab: ' .. tostring(o)) return false end
  slabs[key], count = o, count + 1
  base[key] = z
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
  -- el río entero (por sus nodos), si toca el trazado
  local function tryCell(i, j, w)
    local key = i .. '_' .. j
    if slabs[key] or seen[key] then return end
    seen[key] = true
    local cx, cy = (i + 0.5) * T, (j + 0.5) * T
    local surf
    for _, o in ipairs({ { 0, 0 }, { -0.4, -0.4 }, { 0.4, -0.4 }, { 0.4, 0.4 }, { -0.4, 0.4 } }) do
      local x, y = cx + o[1] * T, cy + o[2] * T
      local z = core_terrain.getTerrainHeight(vec3(x, y, 0))
      if z and z <= M.UNLOADED_Z then seen[key] = nil z = nil end
      local s = z and surfaceAt({ w }, x, y, z)
      if s and (not surf or s > surf) then surf = s end
    end
    if surf and addSlab(key, cx, cy, surf + M.TOP) then added = added + 1 end
  end
  local function nearRoad(x, y, r)
    local r2 = r * r
    for k = 1, #road, 3 do local p = road[k] if (p[1] - x) ^ 2 + (p[2] - y) ^ 2 <= r2 then return true end end
    return false
  end
  -- el río de Umeå son bloques de agua (WaterBlock) en mosaico, no un River: los que quedan a menos de RIVER_R del trazado
  -- también se hielan enteros (el mar abierto, un bloque de kilómetros, no)
  for _, w in ipairs(W) do
    if not w.nodes and (w[3] - w[1]) < 1500 and (w[4] - w[2]) < 1500 then
      local near = false
      for k = 1, #road, 3 do
        local p = road[k]
        local qx, qy = math.max(w[1], math.min(w[3], p[1])), math.max(w[2], math.min(w[4], p[2]))
        if (qx - p[1]) ^ 2 + (qy - p[2]) ^ 2 <= M.RIVER_R ^ 2 then near = true break end
      end
      if near then
        for i = math.floor(w[1] / T), math.floor(w[3] / T) do
          for j = math.floor(w[2] / T), math.floor(w[4] / T) do
            if nearRoad((i + 0.5) * T, (j + 0.5) * T, M.RIVER_R) then tryCell(i, j, w) end
          end
        end
      end
    end
  end
  for _, w in ipairs(W) do
    if w.nodes and #w.nodes >= 2 then
      local touch = false
      for k = 1, #w.nodes do
        local nd = w.nodes[k]
        if nearRoad(nd[1], nd[2], M.RIVER_TOUCH_M + nd[4]) then touch = true break end
      end
      if touch then
        for k = 1, #w.nodes - 1 do
          local a, b = w.nodes[k], w.nodes[k + 1]
          local L = math.sqrt((b[1] - a[1]) ^ 2 + (b[2] - a[2]) ^ 2)
          local n = math.max(1, math.ceil(L / M.STEP))
          for q = 0, n do
            local f = q / n
            local x, y = a[1] + (b[1] - a[1]) * f, a[2] + (b[2] - a[2]) * f
            if nearRoad(x, y, M.RIVER_R) then
              local hw = a[4] + (b[4] - a[4]) * f + T * 0.5
              local i0, i1 = math.floor((x - hw) / T), math.floor((x + hw) / T)
              local j0, j1 = math.floor((y - hw) / T), math.floor((y + hw) / T)
              for i = i0, i1 do for j = j0, j1 do tryCell(i, j, w) end end
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
    -- (27-nov, tarde) sin encadenar: cada losa sube como mucho a la más alta de sus vecinas sobre SU altura de agua original
    -- (base). Encadenado, con el río entero, todo el hielo de la bahía acababa a la altura del río de arriba (2,9 m: 2 m
    -- por encima del agua y de los barcos)
    local list = {}
    for key, o in pairs(slabs) do
      local okP, pos = pcall(function() return o:getPosition() end)
      if okP then list[#list + 1] = { o = o, p = pos, base = base[key] or pos.z } end
    end
    for _, a in ipairs(list) do
      a.z = a.base
      for _, b in ipairs(list) do
        if b.base > a.z and b.base - a.base <= M.LEVEL_MAX and (a.p.x - b.p.x) ^ 2 + (a.p.y - b.p.y) ^ 2 <= M.LEVEL_R ^ 2 then a.z = b.base end
      end
    end
    for _, a in ipairs(list) do
      if math.abs(a.z - a.p.z) > 0.001 then pcall(function() a.o:setPosition(vec3(a.p.x, a.p.y, a.z)) end) end
    end
    pcall(function() be:reloadStaticCollision(false) end)
    -- (27-nov, el usuario: «la meta no la he visto») lo que ya estaba puesto sobre el agua (la meta del shakedown cae en el
    -- río) se había colocado en el fondo: se sube a la cara del hielo
    pcall(function()
      local props = require('earthRaid/props')
      local a = rawget(_G, 'beamngEarth_api')
      if not (props.reground and a) then return end
      local moved = 0
      for _, o in pairs(slabs) do
        local okP, pos = pcall(function() return o:getPosition() end)
        if okP and pos then
          local la, lo = a.toGeo(pos.x, pos.y, pos.z)
          if la then moved = moved + (props.reground(la, lo, M.TILE * 0.75, true) or 0) end
        end
      end
      if moved > 0 then log('I', TAG, ('ice: %d objects lifted onto the ice'):format(moved)) end
    end)
    if removed > 0 then log('I', TAG, ('frozen water: %d ice slabs on dry land removed'):format(removed)) end
    log('I', TAG, ('frozen water: %d ice slabs (%d in total)'):format(added, count))
  end
  return added
end

-- banderines a los dos lados del trazado donde va sobre el hielo (cada FLAG_STEP m), a la altura de la losa
local flags, flagDone = {}, {}
local function placeFlags()
  if not road or #road < 2 then return end
  -- las ya puestas siguen a su losa si esta cambió de altura al igualar
  for _, f in ipairs(flags) do
    local z = f.key and slabs[f.key] and M.topAt(f.x, f.y)
    if z and math.abs(z - f.z) > 0.01 then
      pcall(function() local p = f.o:getPosition() f.o:setPosition(vec3(p.x, p.y, z)) end)
      f.z = z
    end
  end
  local acc, n = 0, 0
  for k = 2, #road do
    local a, b = road[k - 1], road[k]
    local dx, dy = b[1] - a[1], b[2] - a[2]
    local L = math.sqrt(dx * dx + dy * dy)
    acc = acc + L
    if L > 0.1 and acc >= M.FLAG_STEP then
      acc = 0
      local key = math.floor(b[1] / 4) .. '_' .. math.floor(b[2] / 4)
      if not flagDone[key] then
        -- la dirección de la malla: la del trazado en los 12 m que cubre (de aquí hacia atrás)
        local k0 = k
        local back = 0
        while k0 > 1 and back < M.FLAG_LEN do
          back = back + math.sqrt((road[k0][1] - road[k0 - 1][1]) ^ 2 + (road[k0][2] - road[k0 - 1][2]) ^ 2)
          k0 = k0 - 1
        end
        local mx, my = b[1] - road[k0][1], b[2] - road[k0][2]
        local ml = math.sqrt(mx * mx + my * my)
        local ux, uy = dx / L, dy / L
        if ml > 1 then ux, uy = mx / ml, my / ml end
        -- el centro de la malla, a mitad de esos 12 m
        local cxm, cym = b[1] - ux * M.FLAG_LEN / 2, b[2] - uy * M.FLAG_LEN / 2
        local ok = true
        local tops = {}
        for _, sd in ipairs({ -1, 1 }) do
          local x, y = cxm - uy * M.FLAG_SIDE * sd, cym + ux * M.FLAG_SIDE * sd
          -- ¿sobre una losa? (rayo contra lo estático, que el terreno no da la altura del hielo)
          local ti, tj = math.floor(x / M.TILE), math.floor(y / M.TILE)
          local slab = slabs[ti .. '_' .. tj]
          if not slab then ok = false break end
          local okP, sp = pcall(function() return slab:getPosition() end)
          if not okP then ok = false break end
          tops[#tops + 1] = { x, y, sp.z, ux, uy }
        end
        if ok then
          flagDone[key] = true
          for _, tp in ipairs(tops) do
            local okF, o = pcall(function()
              local f = createObject('TSStatic')
              f:setField('shapeName', 0, M.FLAG_SHAPE)
              f:setField('collisionType', 0, 'None')
              f:setField('canSave', 0, '0')
              local q = quatFromDir(vec3(tp[4], tp[5], 0), vec3(0, 0, 1))
              local m = QuatF(q.x, q.y, q.z, q.w):getMatrix()
              m:setPosition(vec3(tp[1], tp[2], tp[3]))
              f:setTransform(m)
              f.scale = vec3(1, M.FLAG_LEN / 10, 1)
              serialF = (serialF or 0) + 1
              f:registerObject(('earthRaid_iceflag_%d_%d'):format(serialF, os.time()))
              if scenetree.MissionGroup then scenetree.MissionGroup:addObject(f) end
              return f
            end)
            if okF and o then
              flags[#flags + 1] = { o = o, x = tp[1], y = tp[2], z = tp[3], key = math.floor(tp[1] / M.TILE) .. '_' .. math.floor(tp[2] / M.TILE) }
              n = n + 1
            end
          end
        end
      end
    end
  end
  if n > 0 then log('I', TAG, ('ice: %d safety nets along the way'):format(n)) end
end

-- la cara de arriba del hielo en (x, y), o nil si ahí no hay losa (props.ground: los carteles de meta en el río iban al fondo)
function M.topAt(x, y)
  local o = slabs[math.floor(x / M.TILE) .. '_' .. math.floor(y / M.TILE)]
  if not o then return nil end
  local ok, p = pcall(function() return o:getPosition() end)
  return ok and p and p.z or nil
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
  pcall(placeFlags)
end

function M.clear()
  for _, f in ipairs(flags) do pcall(function() f.o:delete() end) end
  flags, flagDone = {}, {}
  local n = 0
  for k, o in pairs(slabs) do pcall(function() o:delete() end) slabs[k] = nil n = n + 1 end
  base = {}
  count, road = 0, nil
  if n > 0 then
    pcall(function() be:reloadStaticCollision(false) end)
    log('I', TAG, ('frozen water: %d ice slabs removed'):format(n))
  end
end

function M.count() return count end

return M

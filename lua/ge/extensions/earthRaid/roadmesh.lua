-- Raid.Earth: camino de tierra donde el tramo va sin calzada (27-nov, el usuario, Shakedown de Umeå: «los caminos que has
-- hecho en el puente sobresalen mucho; deben ser más naturales y de camino de tierra como la pista de la que viene y a la que
-- sale. Ha de trazarse todo el camino que hay sin calzada; lo que anulamos estaba bastante bien generado: algo así, con un
-- pequeño montículo. Natural, bien alineado con el suelo, sin escalones, y siguiendo la curva de la línea del tramo»).
--
-- Sin tocar el terreno de Earth (lo que se anuló, alpha.TERRAIN_EDIT, porque Earth lo reescribía): una MeshRoad del juego
-- (malla con colisión que sigue nodos) a lo largo del EJE de los caminos generados (pathgen: el que sigue la línea del
-- tramo y las bandas pintadas), con el material de las pistas de tierra de Earth (bne_dirt_gravel). Altura: el terreno
-- más alto en el ancho del camino, suavizado, más un montículo de MOUND m que se va a cero en los extremos (donde enlaza con
-- la pista real o con el tablero de un puente). Debajo, dos bermas más anchas y algo más bajas, para que el borde no sea
-- un escalón vertical sino un talud escalonado que se mete en el suelo. Se salta el agua (hielo) y los puentes.
-- MARK:roadmesh-v1
local M = {}
local TAG = 'earthRaid.roadmesh'

M.ENABLED = true
-- (27-nov, el usuario: «aquí no te he pedido nada; deshaz esta recta. Solo la entrada al puente y la salida, cruzando el
-- campo hacia el camino de destino») solo los huecos que llevan un puente (pathgen: p.bridge)
M.ONLY_BRIDGES = true
M.MATERIAL = 'earthRaid_dirtroad'      -- la textura de las pistas de tierra de Earth (bne_dirt_gravel), pero opaca
M.MATERIALS = '/art/earthRaid/road/main.materials.json'
M.WIDTH = 5.0            -- calzada
M.BERMS = { { w = 7.2, dz = -0.14 } }   -- berma: ancho total y cuánto más baja (se estrecha hasta la calzada en los extremos)
M.MOUND = 0.30           -- el montículo en medio del hueco
M.TAPER_M = 10           -- de 0 al montículo en estos metros desde cada extremo
M.OVERLAP_M = 6          -- se mete en la pista real (o hasta el tablero) estos metros
M.NODE_STEP_M = 3        -- un nodo cada esto (sigue la curva del eje)
M.SMOOTH_M = 7           -- media de ±SMOOTH_M m del terreno
M.MAX_GRADE = 0.14       -- cambio de altura por metro como mucho entre nodos (salvo que el suelo lo obligue)
M.DEPTH = 1.2            -- grosor de la malla hacia abajo
M.MIN_RUN_M = 12

local roads = {}         -- MeshRoad creados
local serial = 0

-- el suelo de verdad: Earth pone parches de terreno (TSStatic patch_*) por encima del TerrainBlock; la altura del
-- TerrainBlock sola dejaba el camino por debajo del suelo que se ve, a manchas
local function th(x, y)
  local z = core_terrain and core_terrain.getTerrainHeight and core_terrain.getTerrainHeight(vec3(x, y, 0))
  if type(z) ~= 'number' or z <= -15.9 then return nil end
  local okP, props = pcall(require, 'earthRaid/props')
  if okP and props.trueGround then
    local g = props.trueGround(x, y, z + 30)
    if type(g) == 'number' and g > z - 0.5 and g < z + 30 then return math.max(z, g) end
  end
  return z
end

local matsLoaded = false
local function makeRoad(nodes, width, dz)
  if not matsLoaded then matsLoaded = true pcall(loadJsonMaterialsFile, M.MATERIALS) end
  local ok, o = pcall(function()
    local r = createObject('MeshRoad')
    r:setField('topMaterial', 0, M.MATERIAL)
    r:setField('bottomMaterial', 0, M.MATERIAL)
    r:setField('sideMaterial', 0, M.MATERIAL)
    r:setField('textureLength', 0, '6')
    r:setField('breakAngle', 0, '3')
    r:setField('canSave', 0, '0')
    serial = serial + 1
    r:registerObject(('earthRaid_dirtroad_%d_%d'):format(serial, os.time()))
    if scenetree.MissionGroup then scenetree.MissionGroup:addObject(r) end
    for i, n in ipairs(nodes) do
      -- en los extremos (puente, pista real) la berma se estrecha hasta el ancho de la calzada y sube a ella
      local k = n.taper or 1
      local w = M.WIDTH + (width - M.WIDTH) * k
      r:insertNode(vec3(n.x, n.y, n.z + dz * k), w, M.DEPTH, vec3(0, 0, 1), i - 1)
    end
    pcall(function() r:regenerate() end)
    return r
  end)
  if ok and o then roads[#roads + 1] = o return true end
  log('W', TAG, 'mesh road: ' .. tostring(o))
  return false
end

-- un tramo seguido de puntos del eje (ya sin puentes ni agua) -> nodos con altura
local function buildRun(run, startOnDeck, endOnDeck)
  -- nodos cada NODE_STEP_M m
  local nodes = {}
  local lastS = -1e9
  for i, p in ipairs(run) do
    if p.s - lastS >= M.NODE_STEP_M or i == #run then
      nodes[#nodes + 1] = { x = p.x, y = p.y, s = p.s, nx = p.nx, ny = p.ny, deck = p.deckZ }
      lastS = p.s
    end
  end
  if #nodes < 3 then return 0 end
  -- el terreno más alto en el ancho (por eso no se mete bajo un bulto) y el del eje
  for _, n in ipairs(nodes) do
    local hi = -1e9
    for _, l in ipairs({ -M.WIDTH / 2, -M.WIDTH / 4, 0, M.WIDTH / 4, M.WIDTH / 2 }) do
      local z = th(n.x + n.nx * l, n.y + n.ny * l)
      if not z then return 0 end
      hi = math.max(hi, z)
    end
    n.hi = hi
    n.c = th(n.x, n.y)
  end
  local s0, s1 = nodes[1].s, nodes[#nodes].s
  for k, n in ipairs(nodes) do
    local sum, c = 0, 0
    for q = 1, #nodes do
      if math.abs(nodes[q].s - n.s) <= M.SMOOTH_M then sum, c = sum + nodes[q].hi, c + 1 end
    end
    local z = math.max(sum / c, n.hi)
    local d = math.min(n.s - s0, s1 - n.s)
    n.taper = math.max(0, math.min(1, d / M.TAPER_M))
    z = z + M.MOUND * n.taper + 0.03
    n.z = z
  end
  -- los extremos que dan a un tablero: a su altura; los que dan al suelo (la pista real), un poco enterrados en el centro,
  -- para que no asome el canto de la malla (se veía un escalón negro al empezar)
  if startOnDeck and nodes[1].deck then nodes[1].z = nodes[1].deck elseif nodes[1].c then nodes[1].z = nodes[1].c - 0.06 end
  if endOnDeck and nodes[#nodes].deck then nodes[#nodes].z = nodes[#nodes].deck elseif nodes[#nodes].c then nodes[#nodes].z = nodes[#nodes].c - 0.06 end
  -- sin cambios bruscos: hacia delante y hacia atrás, sin bajar del suelo
  for pass = 1, 2 do
    local a, b, st = 2, #nodes, 1
    if pass == 2 then a, b, st = #nodes - 1, 1, -1 end
    for k = a, b, st do
      local p, q = nodes[k], nodes[k - st]
      local g = M.MAX_GRADE * math.abs(p.s - q.s)
      if p.z > q.z + g and not (k == #nodes and endOnDeck) then
        -- más alto que lo que permite la pendiente: no se baja del suelo; se sube el anterior (otra pasada lo reparte)
        q.z = math.max(q.z, p.z - g)
      elseif p.z < q.z - g then
        p.z = math.max(p.z, q.z - g, p.hi + 0.02)
      end
    end
  end
  local made = 0
  if makeRoad(nodes, M.WIDTH, 0) then made = made + 1 end
  for _, b in ipairs(M.BERMS) do if makeRoad(nodes, b.w, b.dz) then made = made + 1 end end
  local up = 0
  for _, n in ipairs(nodes) do up = math.max(up, n.z - n.hi) end
  log('I', TAG, ('dirt road %.0f-%.0f m: %d nodes, up to %.2f m over the ground'):format(s0, s1, #nodes, up))
  return made
end

-- Los puntos del eje de un grupo de trozos seguidos (un mismo hueco), en orden y sin repetir; se cortan en puentes y agua
local function buildGroup(group, out)
  local pts, seen = {}, {}
  for _, sec in ipairs(group) do
    for _, p in ipairs(sec.S) do
      if p.s >= sec.from - M.OVERLAP_M and p.s <= sec.to + M.OVERLAP_M then
        local key = math.floor(p.s * 10 + 0.5)
        if not seen[key] then
          seen[key] = true
          pts[#pts + 1] = { s = p.s, x = p.x, y = p.y, nx = p.nx or 0, ny = p.ny or 1, bridge = p.bridge, water = p.water or p.ice,
            deckZ = p.bridge and p.deck or nil }
        end
      end
    end
  end
  table.sort(pts, function(a, b) return a.s < b.s end)
  if M.ONLY_BRIDGES then
    local has = false
    for _, p in ipairs(pts) do if p.bridge then has = true break end end
    if not has then return end
  end
  local before = #roads
  local run, prevBridge = {}, false
  local function flush(nextIsBridge)
    if #run >= 2 and run[#run].s - run[1].s >= M.MIN_RUN_M then
      local ok, err = pcall(buildRun, run, prevBridge, nextIsBridge)
      if not ok then log('W', TAG, 'run: ' .. tostring(err)) end
    end
    run = {}
  end
  for i, p in ipairs(pts) do
    if i > 1 and (p.s - pts[i - 1].s) > 3 then flush(false) prevBridge = false end
    if p.bridge or p.water then
      if #run > 0 then
        -- el último punto del camino toca el tablero (a su altura)
        if p.bridge then run[#run + 1] = { s = p.s, x = p.x, y = p.y, nx = p.nx, ny = p.ny, deckZ = p.deckZ } end
        flush(p.bridge)
      end
      prevBridge = p.bridge and true or false
      -- el primer punto del camino siguiente arranca en el tablero
      run = p.bridge and { { s = p.s, x = p.x, y = p.y, nx = p.nx, ny = p.ny, deckZ = p.deckZ } } or {}
    else
      if #run == 1 and run[1].deckZ and run[1].s < p.s - 3 then run = {} prevBridge = false end
      run[#run + 1] = p
    end
  end
  flush(false)
  for i = before + 1, #roads do out[#out + 1] = roads[i] end
end

-- grupos de trozos seguidos; cada grupo se rehace solo si cambia (un trozo nuevo que lo alarga), no todos a la vez: el
-- camino que el coche pisa no desaparece al construirse el de delante. Los que pathgen ya soltó (S = nil) se quedan.
local groups = {}            -- [clave] = { roads = {...} }
local function rebuild(sections)
  local made = 0
  local cur, list = nil, {}
  for _, sec in ipairs(sections or {}) do
    if sec.built and sec.S then
      if cur and math.abs(cur[#cur].to - sec.from) < 1 then cur[#cur + 1] = sec
      else cur = { sec } list[#list + 1] = cur end
    else cur = nil end
  end
  for _, g in ipairs(list) do
    local key = ('%.0f-%.0f'):format(g[1].from, g[#g].to)
    if not groups[key] then
      -- un grupo que empieza igual que uno ya hecho pero llega más lejos: lo sustituye
      for k, old in pairs(groups) do
        if k:match('^(%-?%d+)%-') == key:match('^(%-?%d+)%-') then
          for _, r in ipairs(old.roads) do pcall(function() r:delete() end) end
          groups[k] = nil
        end
      end
      local out = {}
      buildGroup(g, out)
      groups[key] = { roads = out }
      made = made + #out
    end
  end
  if made > 0 then pcall(function() be:reloadStaticCollision(false) end) end
  return made
end

local acc = 0
function M.update(dt)
  if not M.ENABLED then return end
  acc = acc + (dt or 0)
  if acc < 2 then return end
  acc = 0
  local okP, pg = pcall(require, 'earthRaid/pathgen')
  if not okP or not pg.sections then return end
  local made = rebuild(pg.sections() or {})
  if made > 0 then log('I', TAG, ('dirt roads: %d meshes'):format(made)) end
end

function M.clear()
  for _, r in ipairs(roads) do pcall(function() r:delete() end) end
  local had = #roads > 0
  roads, groups = {}, {}
  if had then pcall(function() be:reloadStaticCollision(false) end) end
end

function M.reset() M.clear() end

function M.count() return #roads end

return M

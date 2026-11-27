-- Raid.Earth: camino de tierra donde el tramo va sin calzada (27-nov, el usuario, Shakedown de Umeå: «los caminos que has
-- hecho en el puente sobresalen mucho; deben ser más naturales y de camino de tierra como la pista de la que viene y a la que
-- sale. Ha de trazarse todo el camino que hay sin calzada; lo que anulamos estaba bastante bien generado: algo así, con un
-- pequeño montículo. Natural, bien alineado con el suelo, sin escalones, y siguiendo la curva de la línea del tramo»).
--
-- 2.ª vuelta (27-nov, noche: «no queda natural, que no se note el parche; un escalón gigante a la salida del puente;
-- integrado con el terreno, rellenando más ancho; el final, como un cruce abierto a la derecha»): en los huecos con puente
-- el TERRENO lo remodela pathgen (explanada, rampas al tablero, taludes anchos: pathgen.EDIT_BRIDGE_GAPS) y aquí va solo la
-- capa de tierra: una cinta fina pegada a la explanada con el material de las pistas de Earth (bne_dirt_gravel, bordes
-- difuminados). Al final, si da a la pista real, se abre hacia la derecha como un cruce.
-- MARK:roadmesh-v1
local M = {}
local TAG = 'earthRaid.roadmesh'

M.ENABLED = true
-- (27-nov, el usuario: «aquí no te he pedido nada; deshaz esta recta. Solo la entrada al puente y la salida, cruzando el
-- campo hacia el camino de destino») solo los huecos que llevan un puente (pathgen: p.bridge)
M.ONLY_BRIDGES = true
M.MATERIAL = 'bne_dirt_gravel'        -- el de las pistas de tierra de Earth (bordes difuminados)
M.MATERIALS = '/art/earthRaid/road/main.materials.json'
M.WIDTH = 7.0            -- ancho de la capa (los bordes van difuminados: el marrón se ve en unos 4 m)
M.TEX_LEN = 40
M.LAYERS = 2
M.LIFT = 0.04            -- la cinta, sobre la explanada
M.FLARE_M, M.FLARE_EXTRA_M = 22, 8   -- cruce al final: se abre hacia la derecha
M.OVERLAP_M = 6          -- se mete en la pista real (o hasta el tablero) estos metros
M.NODE_STEP_M = 3        -- un nodo cada esto (sigue la curva del eje)
M.MIN_RUN_M = 12

local roads = {}         -- capas (DecalRoad) creadas
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

-- un tramo seguido de puntos del eje (ya sin puentes ni agua) -> nodos. (27-nov, 2.ª vuelta, el usuario: «no queda
-- natural; quiero un camino de tierra como los de alrededor, que no se note el parche; integrado con el terreno, sin
-- escalones») El terreno ya lo remodela pathgen en estos huecos (explanada, rampas al puente, taludes anchos): aquí solo
-- la capa de tierra, una cinta fina pegada a la explanada (pathgen p.H) con el material de las pistas de Earth
-- (bne_dirt_gravel, con los bordes difuminados). Al final, si da a la pista real, se abre hacia la derecha como un cruce.
local function buildRun(run, startOnDeck, endOnDeck)
  local nodes = {}
  local lastS = -1e9
  for i, p in ipairs(run) do
    if p.s - lastS >= M.NODE_STEP_M or i == #run then
      nodes[#nodes + 1] = { x = p.x, y = p.y, s = p.s, nx = p.nx, ny = p.ny, z = (p.deckZ or p.H or th(p.x, p.y) or 0) + M.LIFT }
      lastS = p.s
    end
  end
  if #nodes < 3 then return 0 end
  local s1 = nodes[#nodes].s
  -- dos capas iguales: una sola queda más pálida que las pistas de Earth (sobre su terreno ya hay tierra; aquí, nieve)
  for layer = 1, M.LAYERS do
    -- (probado en el juego) el material de Earth como DecalRoad con la textura estirada (TEX_LEN m) se ve como sus pistas:
    -- continuo, marrón en el centro y difuminado a los lados; como malla o con 8-10 m salía a manchas
    local okR, r = pcall(function()
      local o = createObject('DecalRoad')
      o:setField('material', 0, M.MATERIAL)
      -- (la textura aclara cada TEX_LEN m: la segunda capa con otra longitud tapa esos claros)
      o:setField('textureLength', 0, tostring(M.TEX_LEN * (1 - 0.18 * (layer - 1))))
      o:setField('renderPriority', 0, '5')
      o:setField('breakAngle', 0, '3')
      o:setField('canSave', 0, '0')
      serial = serial + 1
      o:registerObject(('earthRaid_dirtroad_%d_%d'):format(serial, os.time()))
      if scenetree.MissionGroup then scenetree.MissionGroup:addObject(o) end
      for i, n in ipairs(nodes) do
        local w, cx, cy, z = M.WIDTH, n.x, n.y, n.z
        -- cruce: los últimos FLARE_M m se abren hacia la derecha (el lado +n del eje) hasta FLARE_EXTRA_M más
        if not endOnDeck and s1 - n.s < M.FLARE_M then
          local f = 1 - (s1 - n.s) / M.FLARE_M
          local extra = M.FLARE_EXTRA_M * f * f
          w = w + extra
          cx, cy = cx + n.nx * extra / 2, cy + n.ny * extra / 2
          local g = th(cx, cy)
          if g then z = math.max(z, g + M.LIFT) end
        end
        o:insertNode(vec3(cx, cy, z), w, i - 1)
      end
      pcall(function() o:regenerate() end)
      return o
    end)
    if not okR or not r then log('W', TAG, 'dirt layer: ' .. tostring(r)) return 0 end
    roads[#roads + 1] = r
  end
  log('I', TAG, ('dirt road %.0f-%.0f m: %d nodes'):format(nodes[1].s, s1, #nodes))
  return 1
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
            deckZ = p.bridge and p.deck or nil, H = p.H }
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
    if sec.built and sec.S and sec.edit then
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
  roads, groups = {}, {}
end

function M.reset() M.clear() end

function M.count() return #roads end

return M

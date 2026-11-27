-- Raid.Earth: tramos con nieve. Petición del usuario, 21-nov: nevada y agarre de nieve en el Rally de Suecia, y probar
-- una textura blanca en el suelo.
--
-- Qué hace (todo en memoria; al terminar el tramo se deja como estaba):
--  1) Nevada: el ajuste "snow" del clima de BeamNG.Earth (copos del propio juego, cielo cubierto, viento y frío).
--  2) Agarre: los materiales de tierra, hierba y barro del terreno pasan al modelo de suelo SNOW del juego.
--  3) Suelo blanco: en esos materiales, la textura de detalle de color pasa a una nieve propia (art/earthRaid/winter)
--     con fuerza máxima, y el terreno se refresca. El asfalto se deja como está.
--  4) Vegetación nevada: los materiales de hojas y matas (con su mapa de opacidad propio) cambian el color por la
--     nieve; la forma de las hojas se conserva. Las copas lejanas (imposters) no se tocan (ver beamngEarth/seasonlook).
--  5) Bancos de nieve a los lados de la carretera del tramo, como los que deja un quitanieves: se elevan las casillas
--     del terreno junto a la calzada (sin objetos nuevos: ni dibujo ni memoria de más), por tandas cerca del coche.
-- Si falta la textura, se hacen solo 1 y 2. Coste: sin objetos nuevos; el refresco del terreno, una vez.
local M = {}
local alpha = require('earthRaid/alpha')
local ice = require('earthRaid/ice')   -- (27-nov) río y mar helados: losas de hielo
local TAG = 'earthRaid.winter'

M.MATERIALS = { 'bngEarthGroundGrass', 'bngEarthGroundLawn', 'bngEarthGroundLoose', 'bngEarthGroundMud', 'beamngEarthDirt', 'bngEarthGroundRock' }
M.TEXTURE = '/art/earthRaid/winter/t_snow_1024_b.png'
M.GROUNDMODEL = 'SNOW'
-- (23-nov, 2.ª) el suelo conducible vuelve a SNOW (con MUD el coche se enterraba hasta media rueda). El MUD, que frena,
-- se guarda para los bancos de nieve: se pintan con el material de barro de Earth (índice 3, bngEarthGroundMud).
-- (23-nov, probado: con el terreno sin repintar el cauce del río y los barros de Earth eran MUD y el coche se quedaba parado; el
-- usuario: «el río, todo hielo»): sin bancos (alpha.TERRAIN_EDIT=false) el barro de Earth es ICE, no MUD
-- (27-nov, el usuario: «los caminos de tierra se comportan como hielo; quiero tierra mojada, como MUD pero no tan exagerado,
-- el barro que deja la nieve») los materiales de camino (tierra suelta, tierra, barro) pasan a GRAVEL_WET (agarre 0,6, sin
-- hundirse); fuera de la calzada la hierba sigue siendo nieve (SNOW). El río ya no depende del fondo: lleva su losa de hielo.
M.GROUNDMODELS = { bngEarthGroundMud = alpha.TERRAIN_EDIT and 'MUD' or 'GRAVEL_WET', bngEarthGroundLoose = 'GRAVEL_WET',
  beamngEarthDirt = 'GRAVEL_WET', bngEarthGroundRock = alpha.TERRAIN_EDIT and 'ICE' or 'GRAVEL_WET' }   -- (23-nov) Rock = la calzada sobre río helado   -- (23-nov, 5.ª, el usuario) los bancos son MUD blanco: ruedas enterradas, frena, levanta barro
M.PLAIN_MAT = 1              -- bngEarthGroundGrass (SNOW): lo que sustituye al barro de Earth cerca de la calzada sin banco
M.BANK_MAT = 4               -- material del terreno con el que se pintan los bancos (nieve sucia con barro)
M.BANK_DETAIL = { 1, 1 }      -- (23-nov, 4.ª) blanco del todo como el suelo: con 0,8 el barro oscuro se veía negro y no parecía nieve
M.DETAIL_STRENGTH = { 1, 1 }     -- cerca, lejos

-- vegetación: materiales con hojas / matas / hierba del juego (los que tengan mapa de opacidad propio)
M.VEG = { 'fir_leaves', 'fir_leaves_02', 'fir_leaves_dead', 'm_fir_leaves_distant', 'm_fir_leaves_distant_02', 'scots_pine',
  'scots_pine_branches', 'Birch_Leaves_01', 'm_birch_leaves_distant', 'oak_leaves_01', 'oak_leaves_02', 'oak_leaves_03',
  'm_oak_leaves_distant', 'beech_leaves', 'm_beech_leaves_distant', 'm_grass_green_short_01', 'm_grass_green_long_01',
  'm_grass_dry_01', 'wca_groundcover', 'generibush_leaves', 'holm_oak_branches', 'cork_oak' }
M.VEG_FACTOR = '0.95 0.97 1.0 1'
M.VEG_CHECK_S = 5                -- las hojas cargan con el primer árbol de su forma: se vuelve a mirar cada tanto

-- bancos de nieve (m): hueco tras la calzada, subida, meseta y bajada; altura
-- Bancos de nieve (22-nov, rediseño): 21-nov el banco de 0,9 m y 37 grados dejaba el coche varado encima (el terreno es
-- sólido; no hay forma de darle física de nieve blanda). Ahora: bajos (0,5 m en recta) y de pendiente suave, más altos por
-- el exterior de las curvas (donde el quitanieves amontona) y más bajos por el interior, y con hueco en los cruces.
M.BANK = { enabled = true, gap = 1.2, rise = 1.8, flat = 0.8, fall = 1.6, h = 0.35, outer = 0.45, wobble = 0.12, window = 300,
  chunk = 24, budgetMs = 3, junctionR = 9, junctionFade = 5, curveWin = 12, trigger = 130, batch = 8, endClear = 20 }

local saved = nil                -- { mats, veg = { [name] = { bcm, bcf } }, preset, seasonUpdate }
local road = nil                 -- { pts = { {x, y} ... }, hw, cum = {..}, done = { [chunk] = true } }
local banks = nil                -- { file = terrainFile, orig = { [key] = { x, y, h0 } }, add = { [key] = m } }
local vegT = 0
local waterList = nil            -- WaterBlocks (río, mar): ahí no se levantan bancos

local function waterBlocks()
  if not waterList then
    waterList = {}
    for _, n in ipairs(scenetree.findClassObjects('WaterBlock') or {}) do
      local w = scenetree.findObject(n)
      if w then
        local p, sc = w:getPosition(), w:getScale()
        if sc.x < 3000 then waterList[#waterList + 1] = { x = p.x, y = p.y, h = sc.x / 2, hy = (sc.y or sc.x) / 2, z = p.z } end
      end
    end
  end
  return waterList
end

-- ¿Casilla (x, y) de altura h0 bajo o junto al agua (río, bahía)? (23-nov: «en ríos congelados no debe haber bancos»)
local function inWater(x, y, h0)
  -- (23-nov) fondo de río/bahía helado (como pathgen.WATER_Z): sin bancos de nieve
  if h0 and h0 < 0.3 then return true end
  for _, b in ipairs(waterBlocks()) do
    if math.abs(x - b.x) <= b.h + 3 and math.abs(y - b.y) <= b.hy + 3 and h0 <= b.z + 0.8 then return true end
  end
  return false
end

-- altura que los bancos suman en una casilla (la lee pathgen para no tomar el banco por terreno original)
function M.bankAdd(x, y)
  if not banks then return 0 end
  return banks.add[math.floor(x + 0.5) * 100003 + math.floor(y + 0.5)] or 0
end

local function terrain() return scenetree and scenetree.findObject('bngEarthTerrain') end

local function refresh(tb)
  if not tb then return end
  local okC, count = pcall(function() return tb:getMaterialCount() end)
  if not okC or not count then return end
  for i = 0, count - 1 do
    local nm = tb:getMaterialName(i)
    if nm and nm ~= '' then pcall(function() tb:updateMaterial(i, nm) end) end
  end
  pcall(function() tb:updateGridMaterials(vec3(-1e6, -1e6, 0), vec3(1e6, 1e6, 0)) end)
end

function M.active() return saved ~= nil end

-- ---- vegetación ------------------------------------------------------------------------------------------------
local function snowVeg()
  if not saved then return end
  saved.veg = saved.veg or {}
  for _, n in ipairs(M.VEG) do
    if not saved.veg[n] then
      local m = scenetree.findObject(n)
      if m and m:getField('version', 0) ~= '1' and (m:getField('opacityMap', 0) or '') ~= '' then
        saved.veg[n] = { bcm = m:getField('baseColorMap', 0), bcf = m:getField('baseColorFactor', 0) }
        m:setField('baseColorMap', 0, M.TEXTURE)
        m:setField('baseColorFactor', 0, M.VEG_FACTOR)
        m:flush()
        m:reload()
      end
    end
  end
end

local function restoreVeg(veg)
  for n, o in pairs(veg or {}) do
    local m = scenetree.findObject(n)
    if m then
      pcall(function()
        m:setField('baseColorMap', 0, o.bcm)
        m:setField('baseColorFactor', 0, o.bcf)
        m:flush()
        m:reload()
      end)
    end
  end
end

-- ---- calzada de tierra mojada (23-nov, el usuario: "la superficie de la calzada de tierra de Earth no me convence: un poco
-- mojada, o con barro de nieve"). Los caminos de Earth son una malla con materiales bne_dirt_*: se oscurecen y bajan de
-- rugosidad (aspecto mojado), con un tono gris de nieve sucia. La hierba y el terreno blanco no cambian.
M.WET_MATS = { 'bne_dirt_gravel', 'bne_dirt_variation_01', 'bne_dirt_variation_02', 'bne_dirt_variation_03', 'bne_dirt_variation_04' }
M.WET_TINT = { 0.62, 0.58, 0.55 }       -- se multiplica por el color propio del material
M.WET_ROUGH = '0.4'
local function wetDirt()
  if not saved then return end
  saved.wet = saved.wet or {}
  for _, n in ipairs(M.WET_MATS) do
    if not saved.wet[n] then
      local m = scenetree.findObject(n)
      if m then
        local bcf, rf = m:getField('baseColorFactor', 0), m:getField('roughnessFactor', 0)
        local r, g, b, a = tostring(bcf):match('([%d%.eE%-]+)%s+([%d%.eE%-]+)%s+([%d%.eE%-]+)%s+([%d%.eE%-]+)')
        if r then
          saved.wet[n] = { bcf = bcf, rf = rf }
          m:setField('baseColorFactor', 0, ('%.4f %.4f %.4f %s'):format(tonumber(r) * M.WET_TINT[1], tonumber(g) * M.WET_TINT[2],
            tonumber(b) * M.WET_TINT[3], a))
          m:setField('roughnessFactor', 0, M.WET_ROUGH)
          m:flush()
          m:reload()
        end
      end
    end
  end
end

local function restoreWet(wet)
  for n, o in pairs(wet or {}) do
    local m = scenetree.findObject(n)
    if m then
      pcall(function()
        m:setField('baseColorFactor', 0, o.bcf)
        m:setField('roughnessFactor', 0, o.rf)
        m:flush()
        m:reload()
      end)
    end
  end
end

-- ---- bancos de nieve ----------------------------------------------------------------------------------------------
local function smooth(t) t = math.max(0, math.min(1, t)) return t * t * (3 - 2 * t) end

-- Pure: altura (m) del banco a d metros del eje de la carretera de semianchura hw, con una pequeña variación por x, y
function M.bankHeight(d, hw, x, y, scale)
  local B = M.BANK
  local a = hw + B.gap
  local b, c = a + B.rise, a + B.rise + B.flat
  local e = c + B.fall
  if d <= a or d >= e then return 0 end
  local top = B.h * (scale or 1) * (1 + B.wobble * (math.sin(x * 0.37 + 0.4) + math.sin(y * 0.53 + 1.3)) * 0.5)
  if d < b then return top * smooth((d - a) / B.rise) end
  if d <= c then return top end
  return top * (1 - smooth((d - c) / B.fall))
end

local function terrainKey(tb) return tostring(tb.terrainFile) end

local function dropBanks()
  banks = nil
  if road then road.done = {} end
end

local function restoreBanks()
  local tb = terrain()
  if banks and tb and banks.file == terrainKey(tb) then
    local x0, y0, x1, y1 = math.huge, math.huge, -math.huge, -math.huge
    for _, o in pairs(banks.orig) do
      pcall(function() tb:setHeightWs(vec3(o.x, o.y, 0), o.h0) end)
      if o.m0 then pcall(function() tb:setMaterialIdxWs(vec3(o.x, o.y, 0), o.m0) end) end
      x0, y0, x1, y1 = math.min(x0, o.x), math.min(y0, o.y), math.max(x1, o.x), math.max(y1, o.y)
    end
    if x0 < x1 then
      pcall(function() tb:updateGrid(vec3(x0 - 2, y0 - 2, 0), vec3(x1 + 2, y1 + 2, 0)) end)
      pcall(function() tb:updateGridMaterials(vec3(x0 - 2, y0 - 2, 0), vec3(x1 + 2, y1 + 2, 0)) end)
    end
  end
  banks = nil
end

-- El eje de la carretera del tramo en coordenadas del juego ({ {x, y} ... }) y su semianchura
function M.setRoad(pts, hw)
  restoreBanks()
  waterList = nil
  pcall(ice.setRoad, pts)
  if not alpha.TERRAIN_EDIT or not M.BANK.enabled or not pts or #pts < 2 then road = nil return end   -- (23-nov, ALPHA) sin bancos
  local cum = { 0 }
  for i = 2, #pts do
    local dx, dy = pts[i][1] - pts[i - 1][1], pts[i][2] - pts[i - 1][2]
    cum[i] = cum[i - 1] + math.sqrt(dx * dx + dy * dy)
  end
  -- giro del eje (rad, + a la izquierda) en una ventana de ±curveWin m: decide qué lado es el exterior
  local W, curv, ia, ib = M.BANK.curveWin, {}, 1, 1
  for i = 1, #pts do
    while ia < i and cum[i] - cum[ia + 1] >= W do ia = ia + 1 end
    if ib < i then ib = i end
    while ib < #pts and cum[ib] - cum[i] < W do ib = ib + 1 end
    local ax, ay, bx, by = pts[i][1] - pts[ia][1], pts[i][2] - pts[ia][2], pts[ib][1] - pts[i][1], pts[ib][2] - pts[i][2]
    curv[i] = (ax * ax + ay * ay > 0.01 and bx * bx + by * by > 0.01) and math.atan2(ax * by - ay * bx, ax * bx + ay * by) or 0
  end
  road = { pts = pts, hw = hw or 3, cum = cum, done = {}, curv = curv }
end

-- Cruces (3 o más calles) junto al eje en el recuadro dado: el banco no los cierra (22-nov: "nunca cortando el camino")
local function junctionsIn(x0, y0, x1, y1)
  local list = {}
  local ok, mp = pcall(map.getMap)
  if not ok or not (mp and mp.nodes) then return list end
  local props = require('earthRaid/props')
  local R = M.BANK.junctionR + M.BANK.junctionFade
  for name, n in pairs(mp.nodes) do
    local px, py = n.pos.x, n.pos.y
    if px > x0 - R and px < x1 + R and py > y0 - R and py < y1 + R then
      local deg = 0
      for _ in pairs(props.neighbors(name)) do deg = deg + 1 end
      if deg >= 3 then list[#list + 1] = { px, py } end
    end
  end
  return list
end

-- Levanta el banco de un trozo del eje (índices i0..i1)
local function buildChunk(tb, i0, i1)
  local okP, pg = pcall(require, 'earthRaid/pathgen')
  if not okP then pg = nil end
  local B, pts, hw, curv = M.BANK, road.pts, road.hw, road.curv
  local from, to = math.max(1, i0 - 1), math.min(#pts, i1 + 1)
  local pad = hw + B.gap + B.rise + B.flat + B.fall
  -- (23-nov, 4.ª) los segmentos se miran también de los trozos vecinos (hasta pad + 4 m de eje a cada lado): una casilla de
  -- la calzada del trozo siguiente (una esquina de calle) quedaba a «distancia de banco» del último segmento de este y se
  -- levantaba, cruzando la calle: eran los badenes a 5-8 m de la salida y a 118 m de ella
  local fromE, toE = from, to
  while fromE > 1 and road.cum[from] - road.cum[fromE] < pad + 4 do fromE = fromE - 1 end
  while toE < #pts and road.cum[toE] - road.cum[to] < pad + 4 do toE = toE + 1 end
  local x0, y0, x1, y1 = math.huge, math.huge, -math.huge, -math.huge
  for i = from, to do
    x0, y0, x1, y1 = math.min(x0, pts[i][1]), math.min(y0, pts[i][2]), math.max(x1, pts[i][1]), math.max(y1, pts[i][2])
  end
  local junc = junctionsIn(x0 - pad, y0 - pad, x1 + pad, y1 + pad)
  local segs = {}      -- tramos de otras calles del grafo (los que no van pegados al eje) con su semianchura + margen
  pcall(function()
    local mp = map.getMap()
    local function axisD(px, py)
      local bd = math.huge
      for i = 1, #pts - 1 do
        local ax, ay, vx, vy = pts[i][1], pts[i][2], pts[i + 1][1] - pts[i][1], pts[i + 1][2] - pts[i][2]
        local l2 = vx * vx + vy * vy
        local u = l2 > 0 and math.max(0, math.min(1, ((px - ax) * vx + (py - ay) * vy) / l2)) or 0
        local ex, ey = px - (ax + vx * u), py - (ay + vy * u)
        bd = math.min(bd, ex * ex + ey * ey)
      end
      return math.sqrt(bd)
    end
    for name, n in pairs(mp.nodes) do
      local px, py = n.pos.x, n.pos.y
      if px > x0 - pad - 30 and px < x1 + pad + 30 and py > y0 - pad - 30 and py < y1 + pad + 30 then
        for nb in pairs(n.links or {}) do
          local m2 = mp.nodes[nb]
          if m2 then
            local own = axisD(px, py) < hw + 6 and axisD(m2.pos.x, m2.pos.y) < hw + 6
            if not own then segs[#segs + 1] = { px, py, m2.pos.x, m2.pos.y, math.max(n.radius or 2.5, m2.radius or 2.5, 2.5) + 1.0 } end
          end
        end
      end
    end
  end)
  for gx = math.floor(x0 - pad), math.ceil(x1 + pad) do
    for gy = math.floor(y0 - pad), math.ceil(y1 + pad) do
      local best, bi, bside, bt = math.huge, fromE, 1, 0
      for i = fromE, toE - 1 do
        local ax, ay, bx, by = pts[i][1], pts[i][2], pts[i + 1][1], pts[i + 1][2]
        local dx, dy = bx - ax, by - ay
        local l2 = dx * dx + dy * dy
        local t = l2 > 0 and math.max(0, math.min(1, ((gx - ax) * dx + (gy - ay) * dy) / l2)) or 0
        local ex, ey = gx - (ax + dx * t), gy - (ay + dy * t)
        local d2 = ex * ex + ey * ey
        if d2 < best then best, bi, bside, bt = d2, i, (dx * ey - dy * ex) >= 0 and 1 or -1, t end
      end
      local d = math.sqrt(best)
      -- (23-nov, el usuario: "los bancos están perpendiculares cortando el paso como resaltos") una casilla cuyo punto más
      -- cercano es el EXTREMO del trozo (que sigue en el trozo vecino) caería sobre la calzada de delante, a distancia
      -- de banco del extremo: se deja al vecino. Solo los extremos reales del eje tienen remate.
      local capped = (bi == fromE and bt == 0 and fromE > 1) or (bi == toE - 1 and bt == 1 and toE < #pts)
      -- (23-nov, el usuario: «en la salida hay un banco perpendicular, de badén»): más allá de los extremos REALES del eje
      -- (salida y final) no hay banco: la calle sigue y un banco ahí cruzaría la calzada
      if (bi == 1 and bt == 0) or (bi == #pts - 1 and bt == 1) then capped = true end
      if d < pad and not capped and pg and pg.hasCell and pg.hasCell(gx, gy) then capped = true end   -- el camino generado no se toca
      -- (23-nov) tampoco en los 20 m de cada extremo del eje (salida/final): ahí la calzada sigue y cualquier banco la cruzaría
      if d < pad and not capped and (road.cum[bi] + (road.cum[bi + 1] - road.cum[bi]) * bt < B.endClear
         or road.cum[#pts] - (road.cum[bi] + (road.cum[bi + 1] - road.cum[bi]) * bt) < B.endClear) then capped = true end
      -- ni encima de otra calle (el asfalto no se levanta nunca) ni cruzándola
      if d < pad and not capped then
        for _, sg in ipairs(segs) do
          local vx, vy = sg[3] - sg[1], sg[4] - sg[2]
          local l2 = vx * vx + vy * vy
          local u = l2 > 0 and math.max(0, math.min(1, ((gx - sg[1]) * vx + (gy - sg[2]) * vy) / l2)) or 0
          local ex, ey = gx - (sg[1] + vx * u), gy - (sg[2] + vy * u)
          if ex * ex + ey * ey < sg[5] * sg[5] then capped = true break end
        end
      end
      if d < pad and not capped then
        -- exterior de la curva más alto, interior más bajo (bside +1 = a la izquierda; curv + = giro a la izquierda)
        local k = math.max(-1, math.min(1, -bside * (curv[bi] or 0) / 0.5))
        local scale = 1 + B.outer * k + (k < 0 and B.outer * 0.4 * k or 0)
        for _, j in ipairs(junc) do
          local jd = math.sqrt((gx - j[1]) ^ 2 + (gy - j[2]) ^ 2)
          if jd < B.junctionR + B.junctionFade then scale = scale * smooth((jd - B.junctionR) / B.junctionFade) end
        end
        local h = scale > 0.02 and M.bankHeight(d, hw, gx, gy, scale) or 0
        if h > 0.03 then
          local h00 = tb:getHeightWs(vec3(gx, gy, 0))
          if inWater(gx, gy, h00) then h = 0 end
        end
        -- (23-nov, el usuario: «hay zonas de superficie mud en la arbolada estrecha; que solo pase con bancos de nieve») el barro
        -- de Earth (el mismo material que los bancos, con groundmodel MUD) cerca de la calzada y SIN banco pasa a césped nevado
        if h <= 0.12 then
          local okM, mi = pcall(function() return tb:getMaterialIdxWs(vec3(gx, gy, 0)) end)
          if okM and mi == M.BANK_MAT and not inWater(gx, gy, tb:getHeightWs(vec3(gx, gy, 0))) then
            local key = gx * 100003 + gy
            local o = banks.orig[key]
            if not o then
              o = { x = gx, y = gy, h0 = tb:getHeightWs(vec3(gx, gy, 0)), m0 = mi }
              banks.orig[key] = o
            end
            pcall(function() tb:setMaterialIdxWs(vec3(gx, gy, 0), M.PLAIN_MAT) end)
          end
        end
        if h > 0.03 then
          local key = gx * 100003 + gy
          local o = banks.orig[key]
          if not o then
            o = { x = gx, y = gy, h0 = tb:getHeightWs(vec3(gx, gy, 0)) }
            local okM, mi = pcall(function() return tb:getMaterialIdxWs(vec3(gx, gy, 0)) end)
            if okM and type(mi) == 'number' and mi ~= 0 then o.m0 = mi else o.asph = true end      -- el asfalto no se pinta ni se levanta
            banks.orig[key] = o
          end
          if o.m0 and h > 0.12 then pcall(function() tb:setMaterialIdxWs(vec3(gx, gy, 0), M.BANK_MAT) end) end
          if not o.asph and h > (banks.add[key] or 0) then
            banks.add[key] = h
            tb:setHeightWs(vec3(gx, gy, 0), o.h0 + h)
          end
        end
      end
    end
  end
  tb:updateGrid(vec3(x0 - pad, y0 - pad, 0), vec3(x1 + pad, y1 + pad, 0))
  pcall(function() tb:updateGridMaterials(vec3(x0 - pad, y0 - pad, 0), vec3(x1 + pad, y1 + pad, 0)) end)
end

local function updateBanks()
  if not road then return end
  local tb, veh = terrain(), be:getPlayerVehicle(0)
  if not (tb and veh) then return end
  local key = terrainKey(tb)
  if banks and banks.file ~= key then dropBanks() end   -- otro bloque de terreno: lo levantado se perdió con él
  if not banks then banks = { file = key, orig = {}, add = {} } end
  local p = veh:getPosition()
  -- (23-nov) un salto lejos (viaje de BeamNG.Earth, recuperar): el terreno de allí se recarga y lo levantado antes se perdió o
  -- nunca llegó a ponerse; se rehace desde cero con el terreno ya cargado
  if road.lastP and (p.x - road.lastP.x) ^ 2 + (p.y - road.lastP.y) ^ 2 > 150 * 150 then road.done = {} end
  road.lastP = { x = p.x, y = p.y }
  local pts, B = road.pts, M.BANK
  local t0 = os.clock()
  -- (23-nov, el usuario: «las rodadas parpadean») cada updateGrid sobre un trozo hace que el juego rehaga los decals (rodadas)
  -- de esa zona: se hace por tandas grandes y poco frecuentes (a ~130 m del primer trozo sin hacer), no un trozo por metro
  local nearest = math.huge
  do
    local ii = 1
    while ii < #pts do
      local jj = ii
      while jj < #pts and road.cum[jj + 1] - road.cum[ii] < B.chunk do jj = jj + 1 end
      if jj == ii then jj = ii + 1 end
      if not road.done[ii] then
        local dx, dy = pts[ii][1] - p.x, pts[ii][2] - p.y
        nearest = math.min(nearest, dx * dx + dy * dy)
      end
      ii = jj
    end
  end
  if nearest > B.trigger * B.trigger then return end
  local built = 0
  -- trozos de ~B.chunk m cuyo inicio está dentro de la ventana alrededor del coche, y aún sin hacer
  local i = 1
  while i < #pts do
    local c0 = i
    local startD = road.cum[c0]
    local j = c0
    while j < #pts and road.cum[j + 1] - startD < B.chunk do j = j + 1 end
    if j == c0 then j = c0 + 1 end
    local id = c0
    if not road.done[id] then
      local dx, dy = pts[c0][1] - p.x, pts[c0][2] - p.y
      if dx * dx + dy * dy < B.window * B.window then
        local ok, err = pcall(buildChunk, tb, c0, j)
        if not ok then log('W', TAG, 'bank: ' .. tostring(err)) end
        road.done[id] = true
        built = built + 1
        if built >= B.batch or (os.clock() - t0) * 1000 > B.budgetMs * 4 then return end
      end
    end
    i = j
  end
end

-- Cada fotograma (barato si no hay nieve): bancos y vegetación que cargó tarde
function M.update(dt)
  if not saved then return end
  pcall(ice.update, dt)
  vegT = vegT + (dt or 0)
  if vegT >= M.VEG_CHECK_S then vegT = 0 snowVeg() end
  updateBanks()
end

function M.enable()
  if saved then return true end
  local tb = terrain()
  if not tb then log('W', TAG, 'no terrain block (bngEarthTerrain): no winter') return false end
  saved = { mats = {}, preset = nil }
  local useTex = FS:fileExists(M.TEXTURE)
  if not useTex then log('W', TAG, 'missing ' .. M.TEXTURE .. ': snow grip and weather only') end
  for _, n in ipairs(M.MATERIALS) do
    local m = scenetree.findObject(n)
    if m then
      local s = m.baseColorDetailStrength
      saved.mats[n] = { tex = m.baseColorDetailTex, sx = s and s.x or 0.25, sy = s and s.y or 0, gm = m.groundmodelName }
      m.groundmodelName = M.GROUNDMODELS[n] or M.GROUNDMODEL
      if useTex then
        m.baseColorDetailTex = M.TEXTURE
        local ds = (n == 'bngEarthGroundMud') and M.BANK_DETAIL or M.DETAIL_STRENGTH
        m.baseColorDetailStrength = Point2F(ds[1], ds[2])
      end
    end
  end
  refresh(tb)
  pcall(M.snowDust, true)
  local w = extensions.beamngEarth_weather
  if w and w.setPreset then
    saved.preset = w.preset and w.preset() or nil
    pcall(w.setPreset, 'snow')
  end
  -- el color de otoño de las hojas (seasonlook) se congela mientras dura la nieve; después vuelve a ir solo
  local sl = extensions.beamngEarth_seasonlook
  if sl and sl.update then saved.seasonUpdate = sl.update sl.update = function() end end
  if useTex then snowVeg() end
  log('I', TAG, 'winter on (' .. (useTex and 'white ground' or 'no texture') .. ')')
  return true
end

-- (27-nov, el usuario: «la nieve del exterior de la calzada está bien; me gustaría que soltase un poco más de polvo de nieve»)
-- el polvo que levantan las ruedas en la nieve es el emisor del juego BNGP_83 (partícula BNG_snow_contact): con nieve, el
-- doble de partículas, algo más grandes, que duran más y caen más despacio; al terminar se deja como estaba
M.DUST = { emitter = 'BNGP_83', particle = 'BNG_snow_contact',
  e = { ejectionPeriodMS = '5', ejectionVelocity = '1.8', velocityVariance = '0.6' },
  p = { sizes = '0.18', lifetimeMS = '2100', gravityCoefficient = '0.45' } }
local dustSaved = nil
function M.snowDust(on)
  local e, p = scenetree.findObject(M.DUST.emitter), scenetree.findObject(M.DUST.particle)
  if not (e and p) then return false end
  if on then
    if dustSaved then return true end
    dustSaved = { e = {}, p = {} }
    for f, v in pairs(M.DUST.e) do dustSaved.e[f] = e:getField(f, 0) e:setField(f, 0, v) end
    for f, v in pairs(M.DUST.p) do dustSaved.p[f] = p:getField(f, 0) p:setField(f, 0, v) end
  else
    if not dustSaved then return true end
    for f, v in pairs(dustSaved.e) do e:setField(f, 0, v) end
    for f, v in pairs(dustSaved.p) do p:setField(f, 0, v) end
    dustSaved = nil
  end
  pcall(function() p:reload() end)
  pcall(function() e:reload() end)
  return true
end

-- (27-nov, el usuario: «Suecia carga sin la nieve y al salir de boxes se activa; la nieve tiene que aparecer mientras carga y
-- desaparecer una vez finaliza el tramo o el rally completo») en un rally de nieve, la nieve se pone al cargar el rally (el
-- parque de asistencia incluido) y se mantiene entre tramos y en los enlaces: hold(true). Los tramos solo quitan lo suyo
-- (hielo del río, bancos); la nieve se va al terminar o cancelar el rally (hold(false) + disable). MARK:winter-hold-v1
local held = false
function M.hold(on) held = on == true end
function M.held() return held end

function M.disable(force)
  pcall(ice.clear)
  if held and not force then
    pcall(restoreBanks)
    road = nil
    return false
  end
  pcall(M.snowDust, false)
  if not saved then return false end
  local s = saved
  saved = nil
  local tb = terrain()
  for n, o in pairs(s.mats) do
    local m = scenetree.findObject(n)
    if m then
      m.groundmodelName = o.gm
      m.baseColorDetailTex = o.tex
      m.baseColorDetailStrength = Point2F(o.sx, o.sy)
    end
  end
  refresh(tb)
  restoreVeg(s.veg)
  restoreWet(s.wet)
  restoreBanks()
  local sl = extensions.beamngEarth_seasonlook
  if sl and s.seasonUpdate then sl.update = s.seasonUpdate end
  local w = extensions.beamngEarth_weather
  if w and w.setPreset then pcall(w.setPreset, s.preset or 'real') end
  log('I', TAG, 'winter off')
  return true
end

function M.toggle() if saved then return M.disable() else return M.enable() end end

-- Llamada por el tramo: snow = true si su superficie es nieve
function M.forStage(isSnow)
  if isSnow then M.enable() elseif not held then M.disable() end
end

return M

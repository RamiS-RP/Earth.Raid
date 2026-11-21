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
local TAG = 'earthRaid.winter'

M.MATERIALS = { 'bngEarthGroundGrass', 'bngEarthGroundLawn', 'bngEarthGroundLoose', 'bngEarthGroundMud', 'beamngEarthDirt' }
M.TEXTURE = '/art/earthRaid/winter/t_snow_1024_b.png'
M.GROUNDMODEL = 'SNOW'
M.DETAIL_STRENGTH = { 1, 1 }     -- cerca, lejos

-- vegetación: materiales con hojas / matas / hierba del juego (los que tengan mapa de opacidad propio)
M.VEG = { 'fir_leaves', 'fir_leaves_02', 'fir_leaves_dead', 'm_fir_leaves_distant', 'm_fir_leaves_distant_02', 'scots_pine',
  'scots_pine_branches', 'Birch_Leaves_01', 'm_birch_leaves_distant', 'oak_leaves_01', 'oak_leaves_02', 'oak_leaves_03',
  'm_oak_leaves_distant', 'beech_leaves', 'm_beech_leaves_distant', 'm_grass_green_short_01', 'm_grass_green_long_01',
  'm_grass_dry_01', 'wca_groundcover', 'generibush_leaves', 'holm_oak_branches', 'cork_oak' }
M.VEG_FACTOR = '0.95 0.97 1.0 1'
M.VEG_CHECK_S = 5                -- las hojas cargan con el primer árbol de su forma: se vuelve a mirar cada tanto

-- bancos de nieve (m): hueco tras la calzada, subida, meseta y bajada; altura
M.BANK = { gap = 1.0, rise = 1.2, flat = 1.2, fall = 2.2, h = 0.9, wobble = 0.15, window = 260, chunk = 24, budgetMs = 3 }

local saved = nil                -- { mats, veg = { [name] = { bcm, bcf } }, preset, seasonUpdate }
local road = nil                 -- { pts = { {x, y} ... }, hw, cum = {..}, done = { [chunk] = true } }
local banks = nil                -- { file = terrainFile, orig = { [key] = { x, y, h0 } }, add = { [key] = m } }
local vegT = 0

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

-- ---- bancos de nieve ----------------------------------------------------------------------------------------------
local function smooth(t) t = math.max(0, math.min(1, t)) return t * t * (3 - 2 * t) end

-- Pure: altura (m) del banco a d metros del eje de la carretera de semianchura hw, con una pequeña variación por x, y
function M.bankHeight(d, hw, x, y)
  local B = M.BANK
  local a = hw + B.gap
  local b, c = a + B.rise, a + B.rise + B.flat
  local e = c + B.fall
  if d <= a or d >= e then return 0 end
  local top = B.h * (1 + B.wobble * (math.sin(x * 0.37 + 0.4) + math.sin(y * 0.53 + 1.3)) * 0.5)
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
      x0, y0, x1, y1 = math.min(x0, o.x), math.min(y0, o.y), math.max(x1, o.x), math.max(y1, o.y)
    end
    if x0 < x1 then pcall(function() tb:updateGrid(vec3(x0 - 2, y0 - 2, 0), vec3(x1 + 2, y1 + 2, 0)) end) end
  end
  banks = nil
end

-- El eje de la carretera del tramo en coordenadas del juego ({ {x, y} ... }) y su semianchura
function M.setRoad(pts, hw)
  restoreBanks()
  if not pts or #pts < 2 then road = nil return end
  local cum = { 0 }
  for i = 2, #pts do
    local dx, dy = pts[i][1] - pts[i - 1][1], pts[i][2] - pts[i - 1][2]
    cum[i] = cum[i - 1] + math.sqrt(dx * dx + dy * dy)
  end
  road = { pts = pts, hw = hw or 3, cum = cum, done = {} }
end

-- Levanta el banco de un trozo del eje (índices i0..i1)
local function buildChunk(tb, i0, i1)
  local B, pts, hw = M.BANK, road.pts, road.hw
  local from, to = math.max(1, i0 - 1), math.min(#pts, i1 + 1)
  local pad = hw + B.gap + B.rise + B.flat + B.fall
  local x0, y0, x1, y1 = math.huge, math.huge, -math.huge, -math.huge
  for i = from, to do
    x0, y0, x1, y1 = math.min(x0, pts[i][1]), math.min(y0, pts[i][2]), math.max(x1, pts[i][1]), math.max(y1, pts[i][2])
  end
  for gx = math.floor(x0 - pad), math.ceil(x1 + pad) do
    for gy = math.floor(y0 - pad), math.ceil(y1 + pad) do
      local best = math.huge
      for i = from, to - 1 do
        local ax, ay, bx, by = pts[i][1], pts[i][2], pts[i + 1][1], pts[i + 1][2]
        local dx, dy = bx - ax, by - ay
        local l2 = dx * dx + dy * dy
        local t = l2 > 0 and math.max(0, math.min(1, ((gx - ax) * dx + (gy - ay) * dy) / l2)) or 0
        local ex, ey = gx - (ax + dx * t), gy - (ay + dy * t)
        local d2 = ex * ex + ey * ey
        if d2 < best then best = d2 end
      end
      local h = M.bankHeight(math.sqrt(best), hw, gx, gy)
      if h > 0.03 then
        local key = gx * 100003 + gy
        local o = banks.orig[key]
        if not o then
          o = { x = gx, y = gy, h0 = tb:getHeightWs(vec3(gx, gy, 0)) }
          banks.orig[key] = o
        end
        if h > (banks.add[key] or 0) then
          banks.add[key] = h
          tb:setHeightWs(vec3(gx, gy, 0), o.h0 + h)
        end
      end
    end
  end
  tb:updateGrid(vec3(x0 - pad, y0 - pad, 0), vec3(x1 + pad, y1 + pad, 0))
end

local function updateBanks()
  if not road then return end
  local tb, veh = terrain(), be:getPlayerVehicle(0)
  if not (tb and veh) then return end
  local key = terrainKey(tb)
  if banks and banks.file ~= key then dropBanks() end   -- otro bloque de terreno: lo levantado se perdió con él
  if not banks then banks = { file = key, orig = {}, add = {} } end
  local p = veh:getPosition()
  local pts, B = road.pts, M.BANK
  local t0 = os.clock()
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
        if (os.clock() - t0) * 1000 > B.budgetMs then return end
      end
    end
    i = j
  end
end

-- Cada fotograma (barato si no hay nieve): bancos y vegetación que cargó tarde
function M.update(dt)
  if not saved then return end
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
      m.groundmodelName = M.GROUNDMODEL
      if useTex then
        m.baseColorDetailTex = M.TEXTURE
        m.baseColorDetailStrength = Point2F(M.DETAIL_STRENGTH[1], M.DETAIL_STRENGTH[2])
      end
    end
  end
  refresh(tb)
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

function M.disable()
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
  if isSnow then M.enable() else M.disable() end
end

return M

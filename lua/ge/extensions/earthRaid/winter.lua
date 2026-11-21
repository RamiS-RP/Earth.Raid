-- Raid.Earth: tramos con nieve. Petición del usuario, 21-nov: nevada y agarre de nieve en el Rally de Suecia, y probar
-- una textura blanca en el suelo.
--
-- Qué hace (todo en memoria; al terminar el tramo se deja como estaba):
--  1) Nevada: el ajuste "snow" del clima de BeamNG.Earth (copos del propio juego, cielo cubierto, viento y frío).
--  2) Agarre: los materiales de tierra, hierba y barro del terreno pasan al modelo de suelo SNOW del juego.
--  3) Suelo blanco: en esos materiales, la textura de detalle de color pasa a una nieve propia (art/earthRaid/winter)
--     con fuerza máxima, y el terreno se refresca. El asfalto se deja como está.
-- Si falta la textura, se hacen solo 1 y 2. Coste: ningún objeto nuevo; el refresco del terreno ocurre una vez.
local M = {}
local TAG = 'earthRaid.winter'

M.MATERIALS = { 'bngEarthGroundGrass', 'bngEarthGroundLawn', 'bngEarthGroundLoose', 'bngEarthGroundMud', 'beamngEarthDirt' }
M.TEXTURE = '/art/earthRaid/winter/t_snow_1024_b.png'
M.GROUNDMODEL = 'SNOW'
M.DETAIL_STRENGTH = { 1, 1 }     -- cerca, lejos

local saved = nil                -- { mats = { [name] = { tex, sx, sy, gm } }, preset = <ajuste de clima previo> }

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

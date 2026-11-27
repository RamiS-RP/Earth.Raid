-- Earth.Raid: tráfico según la zona del mundo (19-nov, el usuario: "si estoy en Europa, más coches de esa zona").
-- El juego elige los coches del tráfico por el país del mapa (info.json del nivel: usa, germany, italy...), y el mapa
-- de BeamNG.Earth no tiene uno: es el mundo entero. Aquí se mira dónde está el jugador (lat, lon y el país que da
-- BeamNG.Earth) y, solo en mapas de BeamNG.Earth, se añade al grupo de tráfico que crea el juego un filtro por país de
-- origen del modelo (el campo Country de cada vehículo: Germany, France, Italy, Japan, United States...).
-- No se toca ningún archivo del juego: se envuelve, en memoria, la función que crea el grupo de tráfico
-- (gameplay_traffic_trafficUtils.createTrafficGroup) y se deshace al descargar el mod. Si algo falla, el grupo del
-- juego tal cual. Con «vehículos de tráfico simples» el juego usa un solo modelo (simple_traffic) sin país: ahí se
-- vuelve a sortear entre sus configuraciones, que llevan el nombre del coche (etk800_eu_base_sedan, covet_base...),
-- con los mismos pesos y prefiriendo en Europa las versiones europeas (_eu_).
-- MARK:regiontraffic-v1
local M = {}
local TAG = 'earthRaid'

-- pesos por país de origen (en minúsculas, como los compara el juego); `other`: modelos sin país (mods)
M.WEIGHTS = {
  europe = { germany = 3, france = 3, italy = 3, japan = 1.2, ['united states'] = 0.25, other = 1.5 },
  northAmerica = { ['united states'] = 4, japan = 1.5, germany = 0.8, italy = 0.25, france = 0.15, other = 0.7 },
  southAmerica = { france = 2, italy = 2, germany = 1.5, japan = 1.5, ['united states'] = 1.2, other = 1 },
  africa = { japan = 2.5, france = 2.5, germany = 1.2, italy = 1, ['united states'] = 0.5, other = 1 },
  asia = { japan = 4, germany = 1, france = 0.5, italy = 0.5, ['united states'] = 0.6, other = 1 },
  oceania = { japan = 3, ['united states'] = 1.5, germany = 1, france = 0.5, italy = 0.5, other = 1 },
}
M.HOME_BOOST = 2.5           -- en el país de origen de un modelo, todavía más de los suyos

-- El continente por coordenadas (cajas amplias: basta para elegir coches). Puro.
function M.continent(lat, lon)
  if not (lat and lon) then return nil end
  if lat >= 27 and lat <= 30 and lon >= -19 and lon <= -13 then return 'europe' end        -- Canarias
  if lat >= 35 and lat <= 72 and lon >= -25 and lon <= 45 then return 'europe' end
  if lat >= -50 and lat <= -10 and lon >= 110 and lon <= 180 then return 'oceania' end
  if lat < 13 and lat >= -57 and lon >= -82 and lon <= -33 then return 'southAmerica' end
  if lat >= 7 and lon >= -170 and lon <= -50 then return 'northAmerica' end
  if lat >= -36 and lat <= 37 and lon >= -19 and lon <= 52 then return 'africa' end
  if lon > 45 and lat > -11 then return 'asia' end
  return nil
end

-- El filtro para (lat, lon, país): tabla de pesos, y el continente. Puro.
function M.weightsFor(lat, lon, country)
  local c = M.continent(lat, lon)
  local base = c and M.WEIGHTS[c]
  if not base then return nil end
  local w = {}
  for k, v in pairs(base) do w[k] = v end
  local home = type(country) == 'string' and country:lower() or nil
  if home == 'usa' or home == 'united states of america' then home = 'united states' end
  if home and w[home] and home ~= 'other' then w[home] = w[home] * M.HOME_BOOST end
  return w, c
end

-- ---- tráfico simple: un solo modelo, el coche va en el nombre de la configuración -----------------------------------
M.SIMPLE_ORIGIN = { ardente = 'france', tograc = 'france' }   -- configuraciones cuyo nombre no es el de un modelo
M.EU_SPEC, M.EU_OUTSIDE, M.NON_EU_IN_EU = 3, 0.1, 0.3
function M.prefixOf(config) return tostring(config or ''):match('^([%a%d]+)_') or tostring(config or '') end

-- Sortea `amount` vehículos de `pool` sin repetir, con peso según el país de origen (originOf(prefijo) -> país en
-- minúsculas o nil) y la versión (_eu_). Puro (math.random aparte).
function M.resample(pool, amount, w, cont, originOf)
  local hasEu = {}
  for _, v in ipairs(pool) do
    local cfg = tostring(v.config or '')
    if cfg:find('_eu_', 1, true) then hasEu[M.prefixOf(cfg)] = true end
  end
  local items = {}
  for _, v in ipairs(pool) do
    local cfg = tostring(v.config or '')
    local pre = M.prefixOf(cfg)
    local f = w[originOf(pre) or 'other'] or w.other or 1
    local eu = cfg:find('_eu_', 1, true) ~= nil
    if cont == 'europe' then f = f * (eu and M.EU_SPEC or (hasEu[pre] and M.NON_EU_IN_EU or 1))
    elseif eu then f = f * M.EU_OUTSIDE end
    items[#items + 1] = { v = v, f = f }
  end
  local out = {}
  for _ = 1, math.min(amount, #items) do
    local tot = 0
    for _, it in ipairs(items) do tot = tot + it.f end
    if tot <= 0 then break end
    local r, acc = math.random() * tot, 0
    for i, it in ipairs(items) do
      acc = acc + it.f
      if r <= acc or i == #items then out[#out + 1] = it.v table.remove(items, i) break end
    end
  end
  return out
end

local function simpleOrigin(prefix)
  if M.SIMPLE_ORIGIN[prefix] then return M.SIMPLE_ORIGIN[prefix] end
  local ok, c = pcall(function()
    local mdl = core_vehicles.getModelList().models[prefix]
    return mdl and mdl.Country and string.lower(mdl.Country) or nil
  end)
  return ok and c or nil
end

local function here()
  local a = rawget(_G, 'beamngEarth_api')
  if not (a and a.inWorld and a.inWorld() and a.pose) then return nil end
  local p = a.pose()
  if not (p and p.lat) then return nil end
  local country
  pcall(function() local pl = a.place and a.place() country = pl and pl.country end)
  return p.lat, p.lon, country
end

local wrapped, original = nil, nil
-- enabled(): función que dice si el ajuste está activo y el mapa es de BeamNG.Earth
function M.install(enabled)
  local U = rawget(_G, 'gameplay_traffic_trafficUtils')
  if not (U and type(U.createTrafficGroup) == 'function') then return false end
  if wrapped and U.createTrafficGroup == wrapped then return true end
  original = U.createTrafficGroup
  wrapped = function(amount, ...)
    local okE, on = pcall(enabled)
    local lat, lon, country
    if okE and on then lat, lon, country = here() end
    local w, cont = M.weightsFor(lat, lon, country)
    local ms = rawget(_G, 'core_multiSpawn')
    if not (w and ms and type(ms.createGroup) == 'function') then return original(amount, ...) end
    -- el grupo lo crea el juego con sus ajustes; solo se le añade el filtro por país mientras lo hace
    local cg = ms.createGroup
    ms.createGroup = function(n, params)
      if type(params) == 'table' then
        params.filters = params.filters or {}
        if params.filters.Country == nil then params.filters.Country = w end
      end
      return cg(n, params)
    end
    local args = { ... }
    local ok, group = pcall(function() return original(amount, unpack(args)) end)
    ms.createGroup = cg
    if ok and type(group) == 'table' and group[1] and group[1].model == 'simple_traffic' then
      -- tráfico simple: de un grupo cuatro veces mayor (la variedad que da el juego), los de la zona
      local okP, pool = pcall(function() return original(amount * 4, unpack(args)) end)
      local res = okP and type(pool) == 'table' and M.resample(pool, amount, w, cont, simpleOrigin) or nil
      if res and #res >= math.min(amount, #group) then group = res end
    end
    if ok and type(group) == 'table' and group[1] then
      log('I', TAG, ('regional traffic: %s%s, %d vehicles'):format(cont, country and (' (' .. tostring(country) .. ')') or '', #group))
      return group
    end
    return original(amount, ...)
  end
  U.createTrafficGroup = wrapped
  return true
end

function M.uninstall()
  local U = rawget(_G, 'gameplay_traffic_trafficUtils')
  if U and wrapped and U.createTrafficGroup == wrapped and original then U.createTrafficGroup = original end
  wrapped, original = nil, nil
end

return M

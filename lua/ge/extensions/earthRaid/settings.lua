-- Raid.Earth: los ajustes del jugador para los tramos (como la pantalla "Ajustes" del rally del juego), guardados en
-- /settings/earthRaid/settings.json, y la lista de copilotos (los voicepacks del juego con audio).
local M = {}

M.FILE = '/settings/earthRaid/settings.json'
M.VOICE_DIR = '/lua/ge/extensions/gameplay/rally/compositors/voicepacks/'
M.DEFAULTS = {
  voicepack = 'ak_2026-04-16',   -- Alex Kihurani, inglés americano
  visualNotes = true,            -- notas de ruta visuales en el centro
  voice = true,                  -- copiloto hablando
  falseStart = true,             -- sanción por salida en falso (10 s)
  recoveryPenalty = true,        -- recuperar el coche en un tramo: +5 s
  closures = true,               -- cintas en las calles que salen del tramo
  ambience = true,               -- público, vallas, carpas y parque de asistencia
  racingLine = true,             -- con el mod Racing Line instalado: su línea de carrera en vez de la azul del GPS
  recModsAuto = true,            -- activar al cargar los mods recomendados que estén descargados
  sounds = false,                -- sonido de ambiente (público, generadores): apagado por defecto
  noTraffic = true,              -- sin tráfico en el tramo (vuelve al terminar)
  regionalTraffic = true,        -- tráfico con más coches de la zona del mundo donde estás (regiontraffic.lua)
  parkCars = true,               -- un par de coches de rally aparcados en los boxes del parque de asistencia
  arrows = true,                 -- flechas antes de las curvas cerradas
  cautions = true,               -- carteles de peligro antes de saltos y crestas
  radiusKm = 50,                 -- "cerca de ti": eventos a menos de esto (catálogo y propuesta al llegar a la zona)
  raceHud = true,                -- (fijo) diseño de apps de rally durante los tramos: ya no es un ajuste del jugador
  hardcore = false,              -- modo hardcore: sin reparar/restablecer, sin líneas, notas en pantalla ni minimapa: solo la voz
  notesLeadS = 4.5,              -- segundos de antelación con que se canta cada nota
  notesSafe = false,             -- notas prudentes: cada curva un grado más cerrada
  performance = 'auto',          -- objetos con física (phys.lua): auto (según la calidad de BeamNG.Earth), low, medium, high
}
M.ENUMS = { performance = { auto = true, low = true, medium = true, high = true } }
M.NUMBERS = { radiusKm = { 5, 20000 }, notesLeadS = { 2, 9 } }

local raw = nil
local eff = nil

-- Los ajustes vigentes. El HUD de rally es siempre el del juego (no es un ajuste: vanilla no lo tiene). El modo hardcore
-- (la voz del copiloto y nada más) apaga por encima las ayudas sin tocar lo guardado.
M.HARDCORE_OFF = { visualNotes = false, racingLine = false, arrows = false, cautions = false }
function M.get()
  if eff then return eff end
  if not raw then
    local d = jsonReadFile(M.FILE)
    raw = {}
    for k, v in pairs(M.DEFAULTS) do raw[k] = v end
    if type(d) == 'table' then for k, v in pairs(d) do if M.DEFAULTS[k] ~= nil then raw[k] = v end end end
    raw.raceHud = true
  end
  eff = {}
  for k, v in pairs(raw) do eff[k] = v end
  if raw.hardcore then for k, v in pairs(M.HARDCORE_OFF) do eff[k] = v end eff.voice = true end
  return eff
end

function M.set(key, value)
  M.get()
  local s = raw
  if M.DEFAULTS[key] == nil or key == 'raceHud' then return false end
  if type(M.DEFAULTS[key]) == 'boolean' then value = value == true end
  if type(M.DEFAULTS[key]) == 'number' then
    value = tonumber(value)
    if not value then return false end
    local r = M.NUMBERS[key]
    if r then value = math.max(r[1], math.min(r[2], value)) end
  end
  if M.ENUMS[key] then
    value = tostring(value)
    if not M.ENUMS[key][value] then return false end
  end
  s[key] = value
  eff = nil
  pcall(jsonWriteFile, M.FILE, s, true)
  return true
end

local NAMES = { enthusiast = 'Entusiasta', casual = 'Casual' }
local DIALECTS = { ['en-US'] = 'Inglés americano', ['en-GB'] = 'Inglés británico', ['es-ES'] = 'Español', ['es-MX'] = 'Español (México)' }
-- el origen de la voz en español: grabada por una persona o generada (TTS), pedido del usuario, 19-nov
local function dialectLabel(dialect, real)
  local d = DIALECTS[dialect] or dialect
  if tostring(dialect):sub(1, 2) == 'es' then d = d .. (real and ' Voz Real' or ' TTS') end
  return d
end

-- copilotos con audio propio: { id, name, style, dialect }
function M.voicepacks()
  local out = {}
  for _, f in ipairs(FS:findFiles(M.VOICE_DIR, 'voicepack.json', 1, true, false)) do
    local dir = f:match('(.*)/voicepack.json')
    if FS:fileExists(dir .. '/metadata.json') then
      local d = jsonReadFile(f) or {}
      local style = tostring(d.styleLabel or ''):match('styles%.(%w+)%.name') or d.styleLabel
      local dialect = tostring(d.dialect or ''):match('dialects%.([%w%-]+)%.name') or d.dialect
      -- cuántas notas trae: un voicepack incompleto (Clover, de broma) se completa con la voz por defecto
      local notes = 0
      for _ in pairs(jsonReadFile(dir .. '/metadata.json') or {}) do notes = notes + 1 end
      -- fuera del selector los de broma (Clover, el gato del 1 de abril: idioma "Feline", 12 maullidos) y los incompletos
      local joke = d.enableAnimalCodrivers ~= nil and not tostring(d.language or ''):find('languages', 1, true)
      if not joke and (notes >= 120 or d.raidEarthPartialOk) then
        -- voz grabada por una persona (Xpectro99) o generada (TTS): lo dice la ficha del paquete
        local real = d.raidEarthReal == true or d.raidEarthNoFallback == true
        out[#out + 1] = { id = dir:match('[^/]+$'), dir = dir, name = d.persona or dir:match('[^/]+$'),
          style = NAMES[style] or style, dialect = dialectLabel(dialect, real), notes = notes, real = real,
          language = tostring(d.language or ''):match('languages%.(%w+)%.name') or d.language }
      end
    end
  end
  table.sort(out, function(a, b) return a.id < b.id end)
  return out
end

function M.voiceDir()
  local id = tostring(M.get().voicepack)
  local dir = M.VOICE_DIR .. id
  local listed = false
  for _, v in ipairs(M.voicepacks()) do if v.id == id then listed = true end end
  if listed and FS:fileExists(dir .. '/metadata.json') then return dir end
  return M.VOICE_DIR .. M.DEFAULTS.voicepack
end

return M

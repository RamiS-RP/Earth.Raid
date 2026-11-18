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
  arrows = true,                 -- flechas antes de las curvas cerradas
  cautions = true,               -- carteles de peligro antes de saltos y crestas
  radiusKm = 50,                 -- "cerca de ti": eventos a menos de esto (catálogo y propuesta al llegar a la zona)
  liaisonKmh = 60,               -- rally completo: media para el tiempo asignado a cada enlace
  raceHud = true,                -- diseño de apps de rally durante los tramos (sin minimapa)
  notesLeadS = 4.5,              -- segundos de antelación con que se canta cada nota
  notesScale = 0.72,             -- tamaño de las notas visuales
  notesOpacity = 0.72,           -- opacidad de las notas visuales
  notesSafe = false,             -- notas prudentes: cada curva un grado más cerrada
}
M.NUMBERS = { radiusKm = { 5, 20000 }, liaisonKmh = { 20, 150 }, notesLeadS = { 2, 9 }, notesScale = { 0.4, 1.3 },
  notesOpacity = { 0.3, 1 } }

local cache = nil

function M.get()
  if cache then return cache end
  local d = jsonReadFile(M.FILE)
  cache = {}
  for k, v in pairs(M.DEFAULTS) do cache[k] = v end
  if type(d) == 'table' then for k, v in pairs(d) do if M.DEFAULTS[k] ~= nil then cache[k] = v end end end
  return cache
end

function M.set(key, value)
  local s = M.get()
  if M.DEFAULTS[key] == nil then return false end
  if type(M.DEFAULTS[key]) == 'boolean' then value = value == true end
  if type(M.DEFAULTS[key]) == 'number' then
    value = tonumber(value)
    if not value then return false end
    local r = M.NUMBERS[key]
    if r then value = math.max(r[1], math.min(r[2], value)) end
  end
  s[key] = value
  pcall(jsonWriteFile, M.FILE, s, true)
  return true
end

local NAMES = { enthusiast = 'Entusiasta', casual = 'Casual' }
local DIALECTS = { ['en-US'] = 'Inglés americano', ['en-GB'] = 'Inglés británico' }

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
        out[#out + 1] = { id = dir:match('[^/]+$'), dir = dir, name = d.persona or dir:match('[^/]+$'),
          style = NAMES[style] or style, dialect = DIALECTS[dialect] or dialect, notes = notes,
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

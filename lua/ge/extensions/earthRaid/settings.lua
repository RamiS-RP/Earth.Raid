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
  noTraffic = true,              -- sin tráfico en el tramo (vuelve al terminar); el de los enlaces es del ajuste nativo
  regionalTraffic = true,        -- tráfico con más coches de la zona del mundo donde estás (regiontraffic.lua)
  parkCars = true,               -- un par de coches de rally aparcados en los boxes del parque de asistencia
  arrows = true,                 -- flechas antes de las curvas cerradas
  cautions = true,               -- carteles de peligro antes de saltos y crestas
  radiusKm = 50,                 -- "cerca de ti": eventos a menos de esto (catálogo y propuesta al llegar a la zona)
  raceHud = true,                -- (fijo) diseño de apps de rally durante los tramos: ya no es un ajuste del jugador
  hardcore = false,              -- modo hardcore: sin reparar/restablecer, sin líneas, notas en pantalla ni minimapa: solo la voz
  notesLeadS = 4.5,              -- segundos de antelación con que se canta cada nota
  notesSafe = false,             -- notas prudentes: cada curva un grado más cerrada
  startHour = -1,                -- (26-nov) hora del rally al empezar: -1 la del juego; 0..23 esa hora (no obligar a correr de noche)
  performance = 'auto',          -- objetos con física (phys.lua): auto (según la calidad de BeamNG.Earth), low, medium, high
}
M.ENUMS = { performance = { auto = true, low = true, medium = true, high = true } }
M.NUMBERS = { radiusKm = { 5, 20000 }, notesLeadS = { 2, 9 }, startHour = { -1, 23 } }

local raw = nil
local eff = nil
local effSig = nil

-- Opciones del menú nativo Ajustes > Jugabilidad > Rally que Raid.Earth respeta (la fuente de verdad es el juego):
-- nuestra clave -> clave nativa. Si el jugador las cambia en el menú del juego, aquí se nota en el siguiente tramo.
M.NATIVE = {
  visualNotes = 'rallyVisualPacenotes',    -- notas visuales
  voice       = 'rallyAudioPacenotes',     -- notas de audio
  notesLeadS  = 'rallyCodriverTiming',     -- intervención del copiloto (segundos de antelación)
  falseStart  = 'rallyEnableFalseStarts',  -- sanción por salida en falso
}
-- tráfico en los ENLACES (en el tramo nunca hay: el juego también lo excluye): lo manda el ajuste nativo
function M.liaisonTraffic()
  local ok, v = pcall(function() return settings.getValue('rallyEnableTraffic') end)
  return not (ok and v == false)
end
local function nget(k)
  local ok, v = pcall(function() return settings.getValue(k) end)
  if ok then return v end
end
local function nativeVoicepack()
  local mru = tostring(nget('rallyCodriverVoicepackMRU') or '')
  for id in mru:gmatch('global:([^,]+)') do return id end   -- el primero es el elegido
end
local function nativeSig()
  local t = {}
  for _, nk in pairs(M.NATIVE) do t[#t + 1] = tostring((nget(nk))) end   -- (24-nov) entre paréntesis: sin valor, tostring() sin argumentos daba error fatal y el catálogo salía vacío
  t[#t + 1] = tostring((nativeVoicepack()))
  table.sort(t)
  return table.concat(t, '|')
end
-- escribe en el menú nativo el valor que el jugador acaba de poner en nuestra app
local function nativeSet(key, value)
  local nk = M.NATIVE[key]
  if nk then
    if key == 'noTraffic' then value = not value end
    pcall(function() settings.setValue(nk, value) end)
  elseif key == 'voicepack' then
    local mru, out = tostring(nget('rallyCodriverVoicepackMRU') or ''), { 'global:' .. tostring(value) }
    for e in mru:gmatch('[^,]+') do if e ~= 'global:' .. tostring(value) then out[#out + 1] = e end end
    pcall(function() settings.setValue('rallyCodriverVoicepackMRU', table.concat(out, ',')) end)
  end
end

-- Los ajustes vigentes. El HUD de rally es siempre el del juego (no es un ajuste: vanilla no lo tiene). El modo hardcore
-- (la voz del copiloto y nada más) apaga por encima las ayudas sin tocar lo guardado.
-- (22-nov, el usuario: "sin GPS es imposible orientarse en hardcore"): las flechas, los carteles de curva/peligro, las vallas
-- y los cortes son objetos físicos del rally real, no ayudas de pantalla: en hardcore se quedan. Solo se quitan las ayudas
-- (notas en pantalla y línea de carrera)
M.HARDCORE_OFF = { visualNotes = false, racingLine = false }
function M.get()
  local sig = nativeSig()
  if eff and sig == effSig then return eff end
  effSig = sig
  if not raw then
    local d = jsonReadFile(M.FILE)
    raw = {}
    for k, v in pairs(M.DEFAULTS) do raw[k] = v end
    if type(d) == 'table' then for k, v in pairs(d) do if M.DEFAULTS[k] ~= nil then raw[k] = v end end end
    raw.raceHud = true
  end
  eff = {}
  for k, v in pairs(raw) do eff[k] = v end
  for k, nk in pairs(M.NATIVE) do
    local v = nget(nk)
    if v ~= nil then
      if k == 'noTraffic' then v = not v end
      if k == 'notesLeadS' then v = math.max(M.NUMBERS.notesLeadS[1], math.min(M.NUMBERS.notesLeadS[2], tonumber(v) or raw[k])) end
      eff[k] = v
    end
  end
  local vp = nativeVoicepack()
  if vp then for _, v in ipairs(M.voicepacks()) do if v.id == vp then eff.voicepack = vp break end end end
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
  nativeSet(key, value)
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

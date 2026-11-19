-- Raid.Earth: la voz del copiloto y los sonidos de sistema con los voicepacks del juego
-- (Engine.Audio.intercomPlayPacenote, como gameplay/rally/audioManager.lua). Una cola sencilla: una nota detrás de otra.
local M = {}
local TAG = 'earthRaid'

M.PACK = '/lua/ge/extensions/gameplay/rally/compositors/voicepacks/rh_2026-06-05'   -- voz en inglés con todas las notas
M.GAP_S = 0.12

local meta = nil
local queue, playing, playUntil = {}, nil, 0
local playback = { filename = nil }

local function loadMeta()
  if meta then return meta end
  meta = jsonReadFile(M.PACK .. '/metadata.json') or {}
  return meta
end

function M.setPack(dir) M.PACK = dir meta = nil end

-- Si el voicepack elegido no tiene una nota (Clover, el gato del juego, solo trae 12), se dice con la voz completa por
-- defecto: el copiloto nunca se queda callado (18-nov)
M.FALLBACK = '/lua/ge/extensions/gameplay/rally/compositors/voicepacks/ak_2026-04-16'
local fbMeta = nil
local function find(pack, m, base)
  local name = 'pacenote_' .. base .. '.ogg'
  if m[name] then return pack .. '/audio/' .. name, m[name].audioLen or 1 end
  -- variantes numeradas: _1, _2...
  for i = 1, 8 do
    local n2 = 'pacenote_' .. base .. '_' .. i .. '.ogg'
    if m[n2] then return pack .. '/audio/' .. n2, m[n2].audioLen or 1 end
  end
  return nil
end

-- Un fichero del voicepack por su nombre base ('hairpin_left', 'system_countdown3_1')
function M.file(base)
  local f, len = find(M.PACK, loadMeta(), base)
  if f then return f, len end
  -- un pack de voz real incompleto (Xpectro99: 52 grabaciones) no se mezcla con otra voz: lo que no tiene, no se dice
  local vp = jsonReadFile(tostring(M.PACK) .. '/voicepack.json') or {}
  if vp.raidEarthNoFallback then return nil end
  if M.PACK ~= M.FALLBACK then
    fbMeta = fbMeta or jsonReadFile(M.FALLBACK .. '/metadata.json') or {}
    return find(M.FALLBACK, fbMeta, base)
  end
  return nil
end

-- Encola una lista de nombres base; front = antes de lo que haya
-- Un aviso de sistema (cuenta atrás, «preparados», «treinta segundos»...) no se repite en menos de SYSTEM_GAP_S: si
-- algo lo pide dos veces seguidas (19-nov: la cuenta atrás se oyó dos veces), la segunda se calla
M.SYSTEM_GAP_S = 4
local lastSystem = {}
function M.say(bases, front)
  local items = {}
  local now = os.clock()
  for _, b in ipairs(bases) do
    local skip = false
    if type(b) == 'string' and b:find('^system_') then
      if lastSystem[b] and now - lastSystem[b] < M.SYSTEM_GAP_S then skip = true else lastSystem[b] = now end
    end
    local f, len
    if not skip then f, len = M.file(b) end
    if skip then f = false end
    if f then items[#items + 1] = { f = f, len = len } elseif f == nil then log('D', TAG, 'audio: no file for ' .. tostring(b)) end
  end
  if front then
    for i = #items, 1, -1 do table.insert(queue, 1, items[i]) end
  else
    for _, it in ipairs(items) do queue[#queue + 1] = it end
  end
end

-- lo que dura una grabación (s), o nil si el voicepack no la tiene
function M.length(base)
  local f, len = M.file(base)
  return f and len or nil
end

function M.clear() queue = {} playing = nil playUntil = 0 end

function M.update(dtReal)
  local now = os.clock()
  if playing and now < playUntil then return end
  playing = nil
  local it = table.remove(queue, 1)
  if not it then return end
  playback.filename = it.f
  local ok, err = pcall(function() return Engine.Audio.intercomPlayPacenote(playback) end)
  if not ok then log('W', TAG, 'audio: ' .. tostring(err)) return end
  playing = it
  playUntil = now + (it.len or 1) + M.GAP_S
end

function M.isIdle() return playing == nil and #queue == 0 end

return M

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

-- Un fichero del voicepack por su nombre base ('hairpin_left', 'system_countdown3_1')
function M.file(base)
  local m = loadMeta()
  local name = 'pacenote_' .. base .. '.ogg'
  if m[name] then return M.PACK .. '/audio/' .. name, m[name].audioLen or 1 end
  -- variantes numeradas: _1, _2...
  for i = 1, 8 do
    local n2 = 'pacenote_' .. base .. '_' .. i .. '.ogg'
    if m[n2] then return M.PACK .. '/audio/' .. n2, m[n2].audioLen or 1 end
  end
  return nil
end

-- Encola una lista de nombres base; front = antes de lo que haya
function M.say(bases, front)
  local items = {}
  for _, b in ipairs(bases) do
    local f, len = M.file(b)
    if f then items[#items + 1] = { f = f, len = len } else log('D', TAG, 'audio: no file for ' .. tostring(b)) end
  end
  if front then
    for i = #items, 1, -1 do table.insert(queue, 1, items[i]) end
  else
    for _, it in ipairs(items) do queue[#queue + 1] = it end
  end
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

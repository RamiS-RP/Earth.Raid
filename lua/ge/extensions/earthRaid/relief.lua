-- Earth.Raid: crestas, saltos y badenes por delante del coche, del relieve del terreno ya cargado por BeamNG.Earth
-- (el terreno solo existe cerca del jugador: se mira unos cientos de metros por delante, en marcha).
local geo = require('earthRaid/geo')
local M = {}

M.STEP_M = 10
M.AHEAD_M = 420
M.BASE_M = 30              -- pendiente antes y después del punto, en esta distancia
M.CREST = -0.07            -- cambio de pendiente (convexo) para una cresta
M.BIG_CREST = -0.11
M.JUMP = -0.15             -- y para un salto
M.DIP = 0.10               -- cóncavo: badén
M.MIN_GAP_M = 60

local function api() return rawget(_G, 'beamngEarth_api') end

local function heightAt(t, along)
  local a = api()
  local x, y = geo.at(t, along)
  local lat, lon = geo.toGeo(t, x, y)
  local gx, gy, gz = a.toGame(lat, lon, 0)
  if not gx then return nil end
  local h = be:getSurfaceHeightBelow(vec3(gx, gy, 9000))
  if type(h) ~= 'number' or h < -1e5 then return nil end
  return h
end

-- relieve entre from y from + AHEAD_M: lista de { at, mod = 'crest' | 'bigCrest' | 'jump' | 'dip', level }
function M.scan(t, from)
  local hs = {}
  local a0 = math.max(0, from)
  local a1 = math.min(t.total, from + M.AHEAD_M)
  for d = a0, a1, M.STEP_M do
    local h = heightAt(t, d)
    if not h then return {} end
    hs[#hs + 1] = { d = d, h = h }
  end
  local k = math.floor(M.BASE_M / M.STEP_M)
  local out, last = {}, -1e9
  for i = k + 1, #hs - k do
    local before = (hs[i].h - hs[i - k].h) / (hs[i].d - hs[i - k].d)
    local after = (hs[i + k].h - hs[i].h) / (hs[i + k].d - hs[i].d)
    local change = after - before
    local mod
    if change <= M.JUMP and before > -0.02 then mod = 'jump'
    elseif change <= M.BIG_CREST then mod = 'bigCrest'
    elseif change <= M.CREST then mod = 'crest'
    elseif change >= M.DIP then mod = 'dip' end
    if mod and hs[i].d - last > M.MIN_GAP_M then
      out[#out + 1] = { at = hs[i].d, mod = mod, change = change }
      last = hs[i].d
    end
  end
  return out
end

return M

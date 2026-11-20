-- Raid.Earth: el tráfico no entra en las zonas del rally (19-nov: coches "locos" invadían el camino a los TC, las
-- salidas y las metas). Cada segundo, los coches del tráfico que estén dentro de una zona (los controles, la salida,
-- la meta y el STOP, y el propio tramo mientras está montado) se reaparecen lejos (respawn del juego); si no se puede,
-- se quitan. Las calles que salen del tramo ya se cortan con cinta (dressing.closures).
local M = {}
local TAG = 'earthRaid.trafficzones'
M.EVERY_S = 1.0
M.POINT_R_M = 130       -- alrededor de un control, la salida, la meta
M.CORRIDOR_R_M = 35     -- a cada lado del eje del tramo montado
M.CORRIDOR_STEP_M = 80
local t0 = 0
local zones = {}        -- { x, y, r2 } en coordenadas del juego

local function api() return rawget(_G, 'beamngEarth_api') end

-- pts: lista de { lat, lon, r } (r en m)
function M.set(list)
  local a = api()
  zones = {}
  if not (a and a.toGame) then return end
  for _, z in ipairs(list or {}) do
    local ok, x, y = pcall(a.toGame, z.lat, z.lon, 0)
    if ok and x then zones[#zones + 1] = { x = x, y = y, r2 = (z.r or M.POINT_R_M) ^ 2 } end
  end
end
function M.clear() zones = {} end
function M.count() return #zones end

function M.update(dt)
  if #zones == 0 then return end
  t0 = t0 + (dt or 0)
  if t0 < M.EVERY_S then return end
  t0 = 0
  local tr = rawget(_G, 'gameplay_traffic')
  if not (tr and tr.getTrafficData) then return end
  local ok, data = pcall(tr.getTrafficData)
  if not ok or type(data) ~= 'table' then return end
  local player = getPlayerVehicle and getPlayerVehicle(0)
  local pid = player and player:getID()
  for id, d in pairs(data) do
    local pos = d and d.pos
    if pos and id ~= pid then
      for i = 1, #zones do
        local z = zones[i]
        local dx, dy = pos.x - z.x, pos.y - z.y
        if dx * dx + dy * dy < z.r2 then
          local okR = tr.respawnVehicle and pcall(tr.respawnVehicle, id)
          if not okR and tr.removeTraffic then pcall(tr.removeTraffic, id) end
          break
        end
      end
    end
  end
end

return M

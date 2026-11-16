-- Raid.Earth: limpia el trazado de un tramo antes de usarlo. Algunos KMZ de organizador están dibujados a mano y la
-- línea va en zigzag a los lados de una carretera recta (Córdoba SS1: 921 m de línea para 560 m de avenida): de ahí
-- salen curvas falsas, flechas y carteles que sobran, y puntos de GPS que caen en otras calles.
-- Regla: un tramo de la línea que nunca se aparta más de CORRIDOR_M de la recta entre sus extremos, pero es al menos
-- WIGGLE veces más largo que esa recta, es ruido: se cambia por la recta. Una curva de verdad se sale del pasillo
-- (o, si es suave, apenas alarga el recorrido), así que no se toca. Puro (sin juego).
local M = {}

M.CORRIDOR_M = 22
M.WIGGLE = 1.3
M.MIN_SPAN_M = 120
M.MAX_SPAN_M = 3000
M.STEP_M = 10              -- la recta que sustituye al zigzag, con un punto cada esto

local sqrt, cos, rad, max, min, floor = math.sqrt, math.cos, math.rad, math.max, math.min, math.floor

-- path {lat, lon}... -> path limpio, y cuántos metros de zigzag se han quitado
function M.path(path)
  local n = #path
  if n < 4 then return path, 0 end
  local lat0 = path[1][1]
  local k = cos(rad(lat0)) * 111195
  local xy, cum = {}, { 0 }
  for i, p in ipairs(path) do
    xy[i] = { (p[2] - path[1][2]) * k, (p[1] - lat0) * 111195 }
    if i > 1 then cum[i] = cum[i - 1] + sqrt((xy[i][1] - xy[i - 1][1]) ^ 2 + (xy[i][2] - xy[i - 1][2]) ^ 2) end
  end
  local function within(i, j)
    local ax, ay, bx, by = xy[i][1], xy[i][2], xy[j][1], xy[j][2]
    local dx, dy = bx - ax, by - ay
    local L = sqrt(dx * dx + dy * dy)
    if L < 1 then return false, 0 end
    for q = i + 1, j - 1 do
      local px, py = xy[q][1] - ax, xy[q][2] - ay
      local t = (px * dx + py * dy) / (L * L)
      if t < -0.05 or t > 1.05 then return false, L end
      if math.abs(px * dy - py * dx) / L > M.CORRIDOR_M then return false, L end
    end
    return true, L
  end
  local out = { path[1] }
  local removed = 0
  local i = 1
  while i < n do
    -- el tramo más largo desde i que es zigzag dentro del pasillo
    local best = nil
    local j = i + 3
    while j <= n and cum[j] - cum[i] <= M.MAX_SPAN_M * M.WIGGLE * 1.5 do
      local ok, L = within(i, j)
      if not ok and L > M.MIN_SPAN_M then break end
      if ok and L >= M.MIN_SPAN_M and L <= M.MAX_SPAN_M and (cum[j] - cum[i]) >= L * M.WIGGLE then best = j end
      j = j + 1
    end
    if best then
      local a, b = path[i], path[best]
      local L = sqrt((xy[best][1] - xy[i][1]) ^ 2 + (xy[best][2] - xy[i][2]) ^ 2)
      local steps = max(1, floor(L / M.STEP_M))
      for s = 1, steps do
        local f = s / steps
        out[#out + 1] = { a[1] + (b[1] - a[1]) * f, a[2] + (b[2] - a[2]) * f }
      end
      removed = removed + (cum[best] - cum[i]) - L
      i = best
    else
      i = i + 1
      out[#out + 1] = path[i]
    end
  end
  return out, removed
end

function M.length(path)
  local L = 0
  for i = 2, #path do
    local k = cos(rad(path[i][1])) * 111195
    L = L + sqrt(((path[i][2] - path[i - 1][2]) * k) ^ 2 + ((path[i][1] - path[i - 1][1]) * 111195) ^ 2)
  end
  return L
end

-- El trazado limpio de un tramo, una vez (se guarda en el propio tramo)
function M.stage(st)
  if not (st and st.path) then return st and st.path end
  if not st._clean then
    local p, removed = M.path(st.path)
    st._clean, st._cleanRemovedM = p, removed
  end
  return st._clean
end

return M

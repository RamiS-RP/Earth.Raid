-- Earth.Raid: notas de copiloto a partir de la geometría del tramo, con la escala y los colores del rally del juego
-- (compositors/styles/english/numbering/one_to_six.lua y enthusiast.lua):
--   grado por diámetro de la curva: 1 < 35 m, 2 < 65, 3 < 116, 4 < 190, 5 < 260, 6 el resto
--   horquilla (HP) y escuadra (SQ) por ángulo; "long" / "extra long" por longitud; "tightens" / "opens" si el radio cambia
--   colores: 1 rojo, 2 naranja, 3 dorado, 4 cian, 5 azul, 6 verde, HP rojo, SQ naranja; modificadores en morado;
--   precauciones en negro con borde amarillo (1) o rojo (2, 3)
-- Además: crestas, saltos y badenes (relieve, stage.lua los añade en marcha), y los peligros del organizador (KMZ).
local geo = require('earthRaid/geo')
local M = {}

M.STEP_M = 8
M.SMOOTH = 1               -- antes 2 (40 m de media): suavizaba las curvas y se cantaban más abiertas
M.WINDOW_M = 24            -- el grado sale del radio mínimo medido en esta ventana (lo más cerrado de la curva)
M.MIN_TURN_DEG = 15
M.DISTANCES = { 30, 40, 50, 60, 70, 80, 90, 100, 150, 200, 250, 300, 350, 400, 450, 500, 550, 600, 650, 700, 750, 800, 850, 900, 950 }
M.KM_WORDS = { [1000] = '1_km', [1250] = '1_point_2_5_km', [1500] = '1_point_5_km', [1750] = '1_point_7_5_km', [2000] = '2_km' }

local NEON = {
  crimson = { '#ff1744', '#c4002f' }, orange = { '#ff8a00', '#c96500' }, gold = { '#ffd600', '#c7a500' },
  cyan = { '#00d5ff', '#008fb3' }, blue = { '#33a6ff', '#005ecb' }, green = { '#00e676', '#00a152' },
  purple = { '#a855f7', '#7e22ce' },
}
local FG = 'var(--bng-off-black)'
local GRADE = {   -- { diámetro máximo, palabra, color }
  { 35, 'one', NEON.crimson }, { 65, 'two', NEON.orange }, { 116, 'three', NEON.gold },
  { 190, 'four', NEON.cyan }, { 260, 'five', NEON.blue }, { 1e9, 'six', NEON.green },
}
M.GRADE_COLORS = { NEON.crimson, NEON.orange, NEON.gold, NEON.cyan, NEON.blue, NEON.green }

local function gradeOf(radius)
  local d = radius * 2
  for i, g in ipairs(GRADE) do if d < g[1] then return i end end
  return 6
end

function M.distWords(m)
  if m < 25 then return nil end
  if m >= 1000 then
    local best, bk = 1e9, nil
    for k, w in pairs(M.KM_WORDS) do if math.abs(k - m) < best then best, bk = math.abs(k - m), w end end
    return m <= 2200 and bk or nil
  end
  local best = M.DISTANCES[1]
  for _, d in ipairs(M.DISTANCES) do if math.abs(d - m) < math.abs(best - m) then best = d end end
  return tostring(best)
end

-- ---- curvas -----------------------------------------------------------------------------------------------------------

-- grado de una curva por su ángulo (deg), longitud (arc) y radio mínimo (radius)
function M.classify(nt)
  local r, deg, len = nt.radius, nt.deg, nt.arc
  nt.roundabout = nil
  if deg > 300 then
    nt.grade, nt.roundabout = 'hairpin', true
  elseif deg >= 140 and r * 2 < 50 then
    nt.grade = 'hairpin'
  elseif deg >= 75 and deg <= 110 and len <= 30 and r * 2 < 40 then
    nt.grade = 'square'
  else
    nt.grade = gradeOf(r)
    -- notas prudentes (ajuste del jugador): un grado más cerrada
    if M.safe and nt.grade > 1 then nt.grade = nt.grade - 1 end
  end
  nt.length = nil
  if type(nt.grade) == 'number' then
    if deg > 180 then nt.length = 'extra_long' elseif deg > 110 then nt.length = 'long' end
  end
  return nt.grade
end

-- Vuelve a medir una curva con la geometría real de la carretera del juego: pts = { {x, y}, ... } cada `step` m desde
-- un poco antes hasta un poco después de la curva. Devuelve true si la nota cambió.
function M.refine(nt, pts, step)
  if #pts < 4 then return false end
  local heads = {}
  for k = 1, #pts - 1 do heads[k] = math.atan2(pts[k + 1][1] - pts[k][1], pts[k + 1][2] - pts[k][2]) end
  local turn, total = {}, 0
  local s = nt.side == 'right' and 1 or -1
  for k = 2, #heads do
    local d = heads[k] - heads[k - 1]
    while d > math.pi do d = d - 2 * math.pi end
    while d < -math.pi do d = d + 2 * math.pi end
    turn[k] = d
    if d * s > 0 then total = total + math.abs(d) end
  end
  local deg = math.deg(total)
  if deg < M.MIN_TURN_DEG * 0.6 then return false end
  local w = math.max(2, math.floor(M.WINDOW_M / step + 0.5))
  local rMin = 1e9
  for k = 2, #heads - w + 1 do
    local acc = 0
    for q = k, k + w - 1 do if turn[q] and turn[q] * s > 0 then acc = acc + math.abs(turn[q]) end end
    if acc > 1e-3 then rMin = math.min(rMin, w * step / acc) end
  end
  if rMin > 1e8 then return false end
  local before = nt.grade
  nt.radius, nt.deg = rMin, math.max(nt.deg, deg * 0.9)
  M.classify(nt)
  nt.refined = true
  return nt.grade ~= before
end

function M.corners(t)
  local n = math.max(2, math.floor(t.total / M.STEP_M))
  local raw = {}
  for i = 0, n do
    local along = math.min(t.total, i * M.STEP_M)
    local x, y = geo.at(t, along)
    raw[#raw + 1] = { x = x, y = y, along = along }
  end
  local pts = {}
  for i = 1, #raw do
    local sx, sy, c = 0, 0, 0
    for j = math.max(1, i - M.SMOOTH), math.min(#raw, i + M.SMOOTH) do sx, sy, c = sx + raw[j].x, sy + raw[j].y, c + 1 end
    pts[i] = { x = sx / c, y = sy / c, along = raw[i].along }
  end
  local heads = {}
  for i = 1, #pts - 1 do heads[i] = math.atan2(pts[i + 1].x - pts[i].x, pts[i + 1].y - pts[i].y) end
  heads[#pts] = heads[#pts - 1]
  local turn = {}
  for i = 2, #heads do
    local d = heads[i] - heads[i - 1]
    while d > math.pi do d = d - 2 * math.pi end
    while d < -math.pi do d = d + 2 * math.pi end
    turn[i] = d
  end
  local notes, i = {}, 2
  while i <= #turn do
    local s = turn[i] and (turn[i] > 0 and 1 or turn[i] < 0 and -1 or 0) or 0
    if s ~= 0 and math.abs(turn[i]) > math.rad(2) then
      local j, total, maxStep, firstHalf, secondHalf = i, 0, 0, 0, 0
      while j <= #turn and turn[j] and (turn[j] * s) > 0 do
        total = total + turn[j]
        maxStep = math.max(maxStep, math.abs(turn[j]))
        j = j + 1
      end
      -- dónde se cierra: radio de la primera y la segunda mitad
      local mid = math.floor((i + j) / 2)
      for k = i, j - 1 do if k < mid then firstHalf = firstHalf + math.abs(turn[k]) else secondHalf = secondHalf + math.abs(turn[k]) end end
      local deg = math.abs(math.deg(total))
      if deg >= M.MIN_TURN_DEG then
        local len = math.max(M.STEP_M, (j - i) * M.STEP_M)
        local side = s > 0 and 'right' or 'left'
        -- radio mínimo: el giro más fuerte en WINDOW_M dentro de la curva (un copiloto canta lo más cerrado)
        local w = math.max(1, math.floor(M.WINDOW_M / M.STEP_M + 0.5))
        local rMin = len / math.abs(total)
        for k = i, j - 1 do
          local acc = 0
          for q = k, math.min(j - 1, k + w - 1) do acc = acc + math.abs(turn[q]) end
          local span = math.min(w, j - k) * M.STEP_M
          if acc > 1e-3 then rMin = math.min(rMin, span / acc) end
        end
        local nt = { kind = 'corner', at = pts[i - 1].along, endAt = pts[math.min(#pts, j)].along, side = side, deg = deg,
          arc = len, radius = rMin }
        M.classify(nt)
        local halfLen = (j - i) / 2
        if halfLen >= 2 and firstHalf > 0 and secondHalf > 0 then
          if secondHalf > firstHalf * 1.6 then nt.shape = 'tightens' elseif firstHalf > secondHalf * 1.6 then nt.shape = 'opens' end
        end
        notes[#notes + 1] = nt
      end
      i = j
    else
      i = i + 1
    end
  end
  return notes
end

-- ---- palabras y visual de cada nota --------------------------------------------------------------------------------------

local function cornerWords(nt)
  local w = {}
  if nt.grade == 'hairpin' then w[1] = 'hairpin_' .. nt.side
  elseif nt.grade == 'square' then w[1] = 'square_' .. nt.side
  else w[1] = GRADE[nt.grade][2] .. '_' .. nt.side end
  if nt.length then w[#w + 1] = nt.length end
  if nt.shape then w[#w + 1] = nt.shape end
  return w
end

local MOD_WORDS = { crest = 'crest', bigCrest = 'big_crest', jump = 'jump', bigJump = 'big_jump', dip = 'dip',
  bumpy = 'bumpy', narrows = 'narrows', overBridge = 'over_bridge', water = 'water', overFinish = 'over_finish' }
local MOD_ICONS = { crest = 'crest', bigCrest = 'crest', jump = 'jumpOverBump', bigJump = 'jumpOverBump', dip = 'pothole',
  bumpy = 'bumps', narrows = 'narrows', overBridge = 'bridge', water = 'water' }
local CAUTION_WORDS = { 'caution', 'double_caution', 'double_caution' }

function M.words(nt)
  if nt.kind == 'corner' then return cornerWords(nt) end
  if nt.kind == 'mod' then return { MOD_WORDS[nt.mod] or nt.mod } end
  if nt.kind == 'caution' then
    local w = { CAUTION_WORDS[math.min(3, nt.level or 1)] }
    if nt.what then w[#w + 1] = nt.what end
    return w
  end
  return {}
end

-- La nota visual tal como la espera la app RallyVisualPacenotes del juego
function M.visual(nt, id, pnId, distM, into)
  local v = { id = id, pnId = pnId, size = 2, isInto = into or nil }
  if nt.kind == 'corner' then
    local col
    if nt.grade == 'hairpin' then v.type, v.turnTypeValue, col = 'turnHp', 'HP', NEON.crimson
    elseif nt.grade == 'square' then v.type, v.turnTypeValue, col = 'turnSq', 'SQ', NEON.orange
    else v.type, v.turnTypeValue, col = 'turn' .. nt.grade, tostring(nt.grade), GRADE[nt.grade][3] end
    v.isLeft = nt.side == 'left'
    v.background = { color = col[1], strokeColor = col[2], opacity = 1 }
    v.colorNoteIcon, v.colorNoteText = FG, FG
    if nt.shape == 'tightens' then v.turnModifier = 'mathGreaterThan' elseif nt.shape == 'opens' then v.turnModifier = 'mathLessThan' end
    if nt.overCrest then v.turnModifier = 'crest' end
    if nt.roundabout then v.additionalNote = { icon = 'circleSlashed', color = '#ffffff', colorBg = '#c4002f' } end
  elseif nt.kind == 'mod' then
    v.type = MOD_ICONS[nt.mod] or 'crest'
    v.isLeft = false
    v.background = { color = NEON.purple[1], strokeColor = NEON.purple[2], opacity = 1 }
    v.colorNoteIcon, v.colorNoteText = FG, FG
  elseif nt.kind == 'caution' then
    local lvl = math.min(3, nt.level or 1)
    v.type = lvl >= 2 and 'doubleCaution' or 'caution'
    v.isLeft = false
    local stroke = lvl == 1 and '#ffff00' or '#ff0000'
    v.background = { color = 'var(--bng-off-black)', strokeColor = stroke, opacity = 1 }
    v.colorNoteIcon, v.colorNoteText = stroke, stroke
  end
  if distM and distM >= 25 then v.distance = tostring(math.floor(distM / 10 + 0.5) * 10) end
  return v
end

-- Texto corto para el HUD propio
function M.short(nt)
  if nt.kind == 'corner' then
    local g = nt.grade == 'hairpin' and 'HP' or nt.grade == 'square' and 'SQ' or tostring(nt.grade)
    return g .. (nt.side == 'left' and ' L' or ' R')
  end
  if nt.kind == 'mod' then return nt.mod end
  return ('!'):rep(nt.level or 1)
end

-- Todas las notas ordenadas (curvas + peligros), con la distancia hasta la siguiente
function M.generate(t, hazards)
  local notes = M.corners(t)
  for _, h in ipairs(hazards or {}) do
    notes[#notes + 1] = { kind = 'caution', at = h.at, endAt = h.at + 10, level = h.level, what = h.what }
  end
  table.sort(notes, function(a, b) return a.at < b.at end)
  M.relink(notes, t.total)
  return notes
end

-- distancias entre notas (se rehace al añadir crestas y saltos en marcha)
function M.relink(notes, total)
  for k, nt in ipairs(notes) do
    local nx = notes[k + 1]
    nt.dist = nx and (nx.at - nt.endAt) or (total - nt.endAt)
    nt.overFinish = not nx and nt.dist < 200
  end
end

return M

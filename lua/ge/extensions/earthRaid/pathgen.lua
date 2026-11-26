-- Raid.Earth: caminos generados donde el tramo pasa por terreno sin camino en BeamNG.Earth.
-- ESTÁNDAR (22-nov, el usuario, Shakedown de Umeå: "donde la carretera está cortada y no se han generado los caminos,
-- trazar un camino igual que los que hay; aplana el terreno por donde pase la calzada; indica los estrechamientos —puentes,
-- salidas de caminos, árboles muy cerca— con barreras redondas"). Vale para todos los tramos y rallies:
--   1. HUECO: un trozo del trazado de al menos MIN_GAP_M sin carretera del grafo del juego pegada y paralela, y sin camino
--      pintado en el terreno (los caminos de Earth son material del terreno: 0 asfalto, 2 tierra suelta, 6 borde).
--   2. CAMINO: se pinta en el terreno con los mismos materiales que los caminos de Earth (2 en el centro, 6 en el borde),
--      HALF_M a cada lado del eje, solapando OVERLAP_M con el camino real en cada extremo.
--   3. EXPLANADA: el terreno bajo el camino se aplana (perfil longitudinal suavizado, sin pendiente lateral) y se funde con
--      el terreno de alrededor en BLEND_M. En un PUENTE (tablero sobre una vaguada) el eje se lleva al centro del tablero y
--      el terreno de las dos entradas se enrasa con él: sin escalón. Una vaguada sin puente se rellena (paso elevado).
--   4. DESPEJE: lo que haya en el camino (árboles, postes, bancos, papeleras: elementos de Forest) a menos de CLEAR_M del eje
--      se quita; al retirar el tramo se repone todo (elementos, alturas y materiales).
--   5. ESTRECHAMIENTOS: un par de bidones redondos, uno a cada lado, marcando la anchura útil, en: los dos extremos del
--      camino generado (salida de un camino a otro), las dos entradas de un puente o paso elevado (con un segundo par antes,
--      en embudo) y donde quedan árboles u objetos a los dos lados a menos de NEAR_M del eje.
-- El terreno, las carreteras y el bosque de Earth solo existen cerca del coche: todo se hace sobre la marcha, por delante,
-- y se comprueba cada segundo (si Earth recarga el terreno, el camino se rehace).
local geo = require('earthRaid/geo')
local props = require('earthRaid/props')
local alpha = require('earthRaid/alpha')
local M = {}
local TAG = 'earthRaid'

M.enabled = true
M.HALF_M = 3.0            -- media anchura del camino generado
M.BLEND_M = 3.0           -- franja en la que la explanada se funde con el terreno
M.STEP_M = 0.7            -- un punto del eje cada esto
M.SCAN_STEP_M = 2         -- clasificación camino / hueco cada esto
M.ROAD_GRAPH_M = 8        -- carretera del grafo a menos de esto (y paralela): hay camino
M.ROAD_NEAR_M = 12
M.MIN_GAP_M = 15
M.JOIN_M = 10             -- dos huecos separados por menos de esto son uno
M.OVERLAP_M = 8
M.AHEAD_M = 420           -- se prepara hasta aquí por delante del coche
M.CLASSIFY_NEAR_M = 330   -- solo se clasifica con el coche a menos de esto (grafo de la zona completo)
M.CLEAR_M = 4.0           -- (22-nov: nada a menos de 1 m del borde del camino) HALF_M + 1
M.NEAR_M = 5.6
M.BENCH_OUT_M = 1.6       -- un banco quitado del paso se recoloca a esto del borde, mirando a la costa, con una papelera al lado
M.END_AFTER_STOP_M = 100  -- el camino generado llega hasta aquí pasado el control STOP
M.SMOOTH_M = 8            -- ventana (a cada lado) del suavizado del perfil
M.DIP_M = 1.5             -- el terreno esto por debajo de las dos orillas: vaguada
M.RAMP_SLOPE = 0.10       -- pendiente máxima de la rampa que une el terreno con el suelo de un puente
M.RAMP_MAX_M = 60
M.LEAD_M = 40
M.BLEND_MAX_M = 8
M.BRIDGE_SHIFT_M = 20     -- y el eje vuelve al trazado en esta
-- (22-nov, el usuario: "la calzada me gustaría verla como las de tierra, para diferenciarla de la nieve"): con nieve el
-- material 2 (tierra suelta) se ve blanco y el 6 (tierra) marrón, así que el camino generado va entero en el 6
-- (22-nov, 2.ª vuelta: el 6 pintado en marcha sale marrón oscuro liso, "como si hubiera desaparecido el suelo", y no se
-- parece a los caminos que enlazan. Los caminos de Earth son el material 2: el generado va entero en el 2, sin borde.)
-- (3.ª vuelta, probado en el juego: los caminos de tierra de Earth NO son material del terreno sino una malla dentro de la
-- tesela con sus materiales `bne_dirt_*`; no se puede añadir otra igual en marcha. Un DecalRoad con esos materiales sale a
-- manchas. Con nieve el 2 pintado se ve blanco y no se distingue. Lo que sí se ve y tiene textura es el 3 (roca/grava, que
-- el módulo de invierno no cubre de nieve): rodada de grava oscura de TRACK_HALF_M a cada lado y arcén del material 2
-- —sin hierba— hasta HALF_M.)
-- 4.ª vuelta (el usuario: "si pudiese ser blanca, con dos rodaduras del paso de ruedas, quedaría genial"): el camino
-- entero en el material 2 (blanco con nieve, sin hierba) y encima un DecalRoad con las dos rodadas (RUT_MATERIAL).
M.MAT_ROAD, M.MAT_EDGE = 2, 2
M.MAT_ICE = 3          -- bngEarthGroundRock: con nieve lleva el groundmodel ICE (winter.lua); calzada sobre agua helada
M.TRACK_HALF_M = 2.2
M.RUT_MATERIAL = 'm_dirt_tiretracks'
M.RUT_WIDTH_M = 3.0
M.RUT_TEXLEN_M = 5
M.CHUNK_M = 120           -- un hueco largo se hace por trozos de esto (el terreno de Earth solo existe cerca del coche)
M.ROAD_MATS = { [0] = true, [2] = true, [6] = true }
M.stats = { sections = 0, cells = 0, removed = 0, barrels = 0, bridges = 0, rebuilt = 0 }

local function api() return rawget(_G, 'beamngEarth_api') end
local function terrain() return scenetree.findObject('bngEarthTerrain') end
local function th(x, y)
  local h = core_terrain and core_terrain.getTerrainHeight and core_terrain.getTerrainHeight(vec3(x, y, 0))
  return type(h) == 'number' and h or nil
end

local T                                -- el tramo en curso
local status, scanK, run = {}, 0, nil  -- clasificación: status[k] (k = along / SCAN_STEP_M), true = hay camino
local offs = {}                        -- distancia con signo a una carretera paralela cercana, por muestra
local sections = {}                    -- { from, to, built, S = puntos, probe, cleared, marked }
local cells = {}                       -- 'x:y' -> { x, y, h0, m0, h1, m1 }: lo cambiado en el terreno
local removed = {}                     -- { forest, data, tr, sc }: lo quitado del bosque
local added = {}                       -- { forest, item }: lo puesto (bancos recolocados, papeleras)
local tick = 0

-- hasta dónde llega el camino: la meta, el control STOP y END_AFTER_STOP_M más (22-nov, el usuario: "la calzada debe
-- terminar unos 100 m delante del último control tras la meta")
local function endAt(t)
  -- (23-nov) tramo posterior fijo: el camino acaba justo donde acaba (en el borde de la calle), sin prolongación
  if t.afterFixed and t.after and t.after.total then return t.total + t.after.total end
  local ok, sa = pcall(function() return require('earthRaid/dressing').stopAt(t) end)
  return t.total + ((ok and tonumber(sa)) or 150) + M.END_AFTER_STOP_M
end
local function gpos(t, s)
  local a = api()
  s = math.max(0, math.min(endAt(t), s))
  if s > t.total then
    -- pasada la meta: por donde el montaje pone el STOP (la carretera de después, o la prolongación recta)
    local ok, la, lo = pcall(function() return require('earthRaid/dressing').lineAt(t, t.total, s - t.total) end)
    if ok and la then
      local gx, gy = a.toGame(la, lo, 0)
      return gx, gy
    end
    return nil
  end
  local x, y = geo.at(t, s)
  local la, lo = geo.toGeo(t, x, y)
  local gx, gy = a.toGame(la, lo, 0)
  return gx, gy
end

local function inBlock(tb, x, y)
  local p = tb:getPosition()
  return x > p.x + 12 and y > p.y + 12 and x < p.x + 1012 and y < p.y + 1012
end

-- ¿hay camino en (x, y) con dirección (dx, dy)? nil = aún no se sabe
local function roadAt(tb, x, y, dx, dy)
  if not inBlock(tb, x, y) then return nil end
  local h = th(x, y)
  if not h then return nil end
  -- (22-nov, 2.ª vuelta: el material del terreno ya NO cuenta como "hay camino". En el puerto el trazado va por un paseo
  -- pintado en el terreno pero sin carretera en el grafo, con bancos, papeleras y árboles encima: hay que tratarlo —
  -- despejar, marcar, guiar—, solo que siguiendo ese paseo: ver bandAt)
  -- una calle asfaltada (material 0, 4 m de ancho o más, a menos de 8 m) sí es camino hecho aunque no esté en el grafo:
  -- ahí no se genera nada (probado: sin esto salía un "hueco" de 0 a 102 m en las calles de la salida)
  local run = 0
  for j = -8, 8 do
    local okM, mi = pcall(function() return tb:getMaterialIdxWs(vec3(x + dy * j, y - dx * j, 0)) end)
    if okM and mi == 0 then
      run = run + 1
      if run >= 4 then return true end
    else run = 0 end
  end
  local n1, n2, d = map.findClosestRoad(vec3(x, y, h))
  local m = map.getMap()
  -- (pasada de prueba: el trazado suavizado corta los cruces y se aleja hasta ~10 m de la carretera sin ir paralelo a ella;
  -- salían "huecos" en la salida y en el primer cruce) una carretera del grafo a menos de ROAD_NEAR_M, en cualquier
  -- dirección, es camino hecho
  if n1 and n2 and d and d <= M.ROAD_NEAR_M and not (d <= M.ROAD_GRAPH_M) then return true end
  if n1 and n2 and d and d <= M.ROAD_GRAPH_M and m.nodes[n1] and m.nodes[n2] then
    local A, B = m.nodes[n1].pos, m.nodes[n2].pos
    local sx, sy = B.x - A.x, B.y - A.y
    local L = math.sqrt(sx * sx + sy * sy)
    if L > 0.1 and math.abs(sx * dx + sy * dy) / L < 0.8 then return true end
    if L > 0.1 then
      -- (también la media anchura de esa carretera y el punto de su eje, para marcar dónde se estrecha)
      local u = math.max(0, math.min(1, ((x - A.x) * sx + (y - A.y) * sy) / (L * L)))
      local r1, r2 = m.nodes[n1].radius or 3, m.nodes[n2].radius or 3
      local off = (A.x + sx * u - x) * dy - (A.y + sy * u - y) * dx
      return true, r1 + (r2 - r1) * u, A.x + sx * u, A.y + sy * u, off
    end
  end
  return false
end

-- salida de un camino ancho a uno estrecho (el radio de la carretera del grafo baja de WIDE_M a NARROW_M o menos): un par
-- de bidones a la anchura del estrecho
M.WIDE_M, M.NARROW_M = 2.6, 2.0
local lastRad, lastNarrow = nil, -1e9
M.NO_MARK_END_M = 120   -- ni un bidón a menos de esto de la salida o de la meta (zona de carteles, sensores y público)
local function narrowing(s, rad, ax, ay, dx, dy, total)
  if lastRad and lastRad >= M.WIDE_M and rad <= M.NARROW_M and s - lastNarrow > 150
    and s > M.NO_MARK_END_M and s < (total or 1e9) - M.NO_MARK_END_M then
    lastNarrow = s
    local a = api()
    for _, sg in ipairs({ 1, -1 }) do
      -- (la calzada que se ve es más ancha que el radio del grafo: 1,5 m por fuera, nunca dentro)
      local x, y = ax + dy * (rad + 1.5) * sg, ay - dx * (rad + 1.5) * sg
      local la, lo = a.toGeo(x, y, th(x, y) or 0)
      if la then
        local it = props.add('barrel', la, lo, dx, dy, 0)
        if it then it.roadOk, it.edgeOk, it.pathgen = true, true, true M.stats.barrels = M.stats.barrels + 1 end
      end
    end
  end
  lastRad = rad
end

local function emit(from, to, joinPrev, joinNext)
  sections[#sections + 1] = { from = from, to = to, joinPrev = joinPrev, joinNext = joinNext }
  M.stats.sections = M.stats.sections + 1
  log('I', TAG, ('pathgen: hueco sin camino %.0f-%.0f m'):format(from, to))
end
local function closeRun(endS)
  if not run then return end
  local from, to = run.from, run.to or endS
  local joined = run.joined
  run = nil
  if to - from >= M.MIN_GAP_M or (joined and to - from > 2) then emit(from, to, joined, false) end
end

-- clasifica en orden, desde la salida, lo que queda cerca del coche
local function classify(t, tb, along, cx, cy)
  local step = M.SCAN_STEP_M
  local total = endAt(t)
  local kMax = math.floor(total / step)
  local n = 0
  while scanK <= kMax and n < 120 do
    local s = scanK * step
    if s > along + M.AHEAD_M + 40 then break end
    local x, y = gpos(t, s)
    if not x then break end
    if (x - cx) ^ 2 + (y - cy) ^ 2 > M.CLASSIFY_NEAR_M ^ 2 then
      -- lejos: si queda por detrás (el coche apareció más adelante), se salta; si queda por delante, se espera
      if s < along - 100 then closeRun(s) scanK = math.floor((along - 60) / step) n = n + 1 goto continue end
      break
    end
    do
      local x2, y2 = gpos(t, s + 2)
      local dx, dy = x2 - x, y2 - y
      local l = math.sqrt(dx * dx + dy * dy)
      if l < 0.01 then dx, dy, l = 1, 0, 1 end
      local r, rad, ax, ay, off = roadAt(tb, x, y, dx / l, dy / l)
      if r == nil then break end

      if r and rad then pcall(narrowing, s, rad, ax, ay, dx / l, dy / l, t.total) end
      status[scanK] = r
      if not r then
        if not run then run = { from = s } end
        run.to, run.road = nil, 0
        -- (22-nov: el hueco del puerto a la meta mide más de 1 km y no se cerraba hasta el final: nunca se hacía) por trozos
        if s - run.from >= M.CHUNK_M then
          emit(run.from, s, run.joined, true)
          run.from, run.joined = s, true
        end
      elseif run then
        run.to = run.to or s
        run.road = (run.road or 0) + step
        if run.road >= M.JOIN_M then closeRun(s) end
      end
      scanK = scanK + 1
      n = n + 1
    end
    ::continue::
  end
  if scanK > kMax then closeRun(total) end
end

-- ---- construcción de un hueco ---------------------------------------------------------------------------------------------

local function lerp(a, b, k) return a + (b - a) * math.max(0, math.min(1, k)) end

local function samples(t, tb, sec)
  -- (22-nov: con solo 8 m de margen, la rampa de un puente cercano al principio del hueco no cabía y dejaba un escalón de
  -- 0,18 m) el perfil se calcula LEAD_M más allá de cada extremo; pintar y despejar, solo en el hueco
  local s0 = math.max(0, sec.from - M.LEAD_M)
  local s1 = math.min(endAt(t), sec.to + M.LEAD_M)
  local S = {}
  local s = s0
  while s <= s1 + 0.01 do
    local x, y = gpos(t, s)
    if not x or not inBlock(tb, x, y) then return nil end
    S[#S + 1] = { s = s, x = x, y = y }
    s = s + M.STEP_M
  end
  if #S < 8 then return nil end
  for i, p in ipairs(S) do
    local q0, q1 = S[math.max(1, i - 2)], S[math.min(#S, i + 2)]
    local dx, dy = q1.x - q0.x, q1.y - q0.y
    local l = math.sqrt(dx * dx + dy * dy)
    if l < 0.01 then dx, dy, l = 1, 0, 1 end
    p.dx, p.dy = dx / l, dy / l
    p.nx, p.ny = p.dy, -p.dx
    -- (23-nov) la altura ORIGINAL si ya se tocó esa casilla: al rehacer un trozo (Earth recarga, verify) el fondo del agua que
    -- la rampa de la orilla levantó no debe contar como tierra
    local rec = cells[math.floor(p.x + 0.5) .. ':' .. math.floor(p.y + 0.5)]
    p.th = (rec and rec.h0 and rec.h0 < M.WATER_Z) and rec.h0 or th(p.x, p.y)
    if not p.th then return nil end
    -- (23-nov, el usuario: "calzada a la altura del suelo del hielo del río; un montículo por encima no") el eje del DEM puede
    -- ir sobre un terraplén 1-2 m por encima de un río helado: si a ±7 m el terreno es fondo de agua y el eje queda
    -- más de 0,8 m por encima, la calzada va a la altura del hielo (el de los lados)
    if not p.th_ice then
      local function orig(x, y)
        local r = cells[math.floor(x + 0.5) .. ':' .. math.floor(y + 0.5)]
        return (r and r.h0) or th(x, y)
      end
      local ha, hb = orig(p.x + p.nx * 7, p.y + p.ny * 7), orig(p.x - p.nx * 7, p.y - p.ny * 7)
      if ha and hb and ha < M.WATER_Z and hb < M.WATER_Z and p.th > math.max(ha, hb) + 0.8 then
        p.th, p.ice = (ha + hb) / 2, true
      end
    end
  end
  return S
end

-- NORMA (22-nov, el usuario: "no se sigue el camino de tierra y se desvía por fuera; no debe pasar nunca si no está
-- indicado"): si junto al trazado (hasta BAND_M a cada lado) hay un camino pintado en el terreno (materiales 0, 2 o 6, de
-- 2 m de ancho o más), el eje va por el centro de ESE camino, no por el trazado. Devuelve el desplazamiento lateral o nil.
M.BAND_M = 10
M.BAND_SLEW = 0.12
local function bandAt(tb, p, ref)
  local runs, cur = {}, nil
  for j = -M.BAND_M, M.BAND_M, 0.5 do
    -- (el material ORIGINAL: lo que ya ha pintado otro trozo no cuenta, o cada trozo vería una banda distinta y los ejes de
    -- dos trozos vecinos no coincidirían — medido en la pasada de prueba: escalón de 1,4 m en la junta de 2495 m)
    local bx, by = p.x + p.nx * j, p.y + p.ny * j
    local rec = cells[math.floor(bx + 0.5) .. ':' .. math.floor(by + 0.5)]
    local okM, mi = true, rec and rec.m0
    if mi == nil then okM, mi = pcall(function() return tb:getMaterialIdxWs(vec3(bx, by, 0)) end) end
    if okM and M.ROAD_MATS[mi] then
      if not cur then cur = { a = j, b = j } runs[#runs + 1] = cur end
      cur.b = j
    else cur = nil end
  end
  local best
  for _, r in ipairs(runs) do
    if r.b - r.a >= 2 then
      -- (una banda muy ancha —una explanada, un aparcamiento—: el punto más cercano al trazado dentro de ella)
      local c = (r.a + r.b) / 2
      if r.b - r.a > 8 then c = math.max(r.a + 3, math.min(r.b - 3, ref or 0)) end
      -- (la banda más cercana a la del punto anterior: sin saltar de un camino a otro)
      if not best or math.abs(c - (ref or 0)) < math.abs(best - (ref or 0)) then best = c end
    end
  end
  return best
end
local function followBand(tb, S)
  local N = #S
  local raw = {}
  local ref = 0
  for i, p in ipairs(S) do
    local c = bandAt(tb, p, ref)
    -- (un salto de más de 3 m respecto al punto anterior es otro camino: se ignora)
    if c and math.abs(c - ref) > 3 and i > 1 and raw[i - 1] then c = nil end
    raw[i] = c
    if c then ref = c end
  end
  -- donde no hay banda, el desplazamiento del último punto con banda se apaga en 15 m (hacia delante y hacia atrás)
  local off = {}
  local function spread(from, to, st)
    local last, dist = nil, 0
    for k = from, to, st do
      if raw[k] then last, dist = raw[k], 0 off[k] = raw[k]
      elseif last then
        dist = dist + M.STEP_M
        local o = dist < 15 and last * (1 - dist / 15) or 0
        if not off[k] or math.abs(o) > math.abs(off[k]) then off[k] = o end
      end
    end
  end
  spread(1, N, 1)
  spread(N, 1, -1)
  -- (probado en el puerto: con el desplazamiento saltando 1-2 m entre puntos seguidos, en una ladera, el eje hacía eses y
  -- dejaba escalones de más de 1 m) el eje no se mueve de lado más de BAND_SLEW por metro avanzado, y se promedia ±6 m
  local slew = M.BAND_SLEW * M.STEP_M
  for k = 1, N do off[k] = off[k] or 0 end
  for k = 2, N do off[k] = math.max(off[k - 1] - slew, math.min(off[k - 1] + slew, off[k])) end
  for k = N - 1, 1, -1 do off[k] = math.max(off[k + 1] - slew, math.min(off[k + 1] + slew, off[k])) end
  local w = math.floor(6 / M.STEP_M)
  for i, p in ipairs(S) do
    local sum, n = 0, 0
    for q = math.max(1, i - w), math.min(N, i + w) do sum, n = sum + (off[q] or 0), n + 1 end
    local o = sum / n
    if math.abs(o) > 0.05 then
      p.x, p.y = p.x + p.nx * o, p.y + p.ny * o
      p.th = th(p.x, p.y) or p.th
      p.band = o
    end
  end
end

-- El tablero de un puente en el corte transversal de `p` (rayos desde `top` hacia abajo): algo sólido `minUp` m o más por
-- encima del terreno y cerca de la cota `near`. Devuelve su centro (c, desplazamiento lateral), la media anchura ÚTIL (hw)
-- y la altura del SUELO (h). (22-nov, el usuario: "en la entrada se ha quedado muy alto y en la salida bajo": el puente es
-- un cajón con muretes; antes se tomaba la media de todo —muretes incluidos— y una sola altura para todo el puente.)
local function deckAt(p, top, minUp, near, aroundC)
  local runs, cur = {}, nil
  for j = -8, 8, 0.25 do
    local px, py = p.x + p.nx * j, p.y + p.ny * j
    local tt = th(px, py)
    local sf = tt and be:getSurfaceHeightBelow(vec3(px, py, top))
    local deck = tt and type(sf) == 'number' and sf - tt > minUp and math.abs(sf - near) < 2.5
    if deck then
      if not cur then cur = { a = j, b = j, hs = {} } runs[#runs + 1] = cur end
      cur.b = j
      cur.hs[#cur.hs + 1] = { j, sf }
    else cur = nil end
  end
  local best
  for _, r in ipairs(runs) do
    if r.b - r.a >= 1.5 then
      local c = (r.a + r.b) / 2
      local ref = aroundC or 0
      if not best or math.abs(c - ref) < math.abs(best.c0 - ref) then best = { c0 = c, r = r } end
    end
  end
  if not best then return nil end
  -- el suelo: lo más bajo de la franja; lo útil: lo que está a su altura (los muretes de los lados quedan fuera)
  local floor = 1e9
  for _, e in ipairs(best.r.hs) do if e[2] < floor then floor = e[2] end end
  local fa, fb
  for _, e in ipairs(best.r.hs) do
    if e[2] <= floor + 0.15 then fa = fa or e[1] fb = e[1] end
  end
  if not fa or fb - fa < 1.2 then fa, fb = best.r.a, best.r.b end
  return { c = (fa + fb) / 2, hw = (fb - fa) / 2, h = floor }
end

-- vaguadas y puentes: en una vaguada se busca el tablero a los lados del eje
local function bridges(S)
  local N = #S
  local w = math.floor(30 / M.STEP_M)
  for i, p in ipairs(S) do
    local mb, mf = -1e9, -1e9
    for k = math.max(1, i - w), i do if S[k].th > mb then mb = S[k].th end end
    for k = i, math.min(N, i + w) do if S[k].th > mf then mf = S[k].th end end
    p.level = math.min(mb, mf)
    p.dip = p.th < p.level - M.DIP_M
  end
  for _, p in ipairs(S) do
    if p.dip then
      local best = deckAt(p, p.level + 2.5, 0.8, p.level)
      if best then p.bridge, p.off, p.bw, p.deck = true, best.c, best.hw, best.h end
    end
  end
  -- un tablero de verdad dura al menos 4 m; lo suelto (un tronco, una roca) no es puente
  local i = 1
  local minN = math.floor(4 / M.STEP_M)
  while i <= N do
    if S[i].bridge then
      local j = i
      while j <= N and S[j].bridge do j = j + 1 end
      if j - i < minN then for k = i, j - 1 do S[k].bridge, S[k].off = nil, nil end end
      i = j
    else i = i + 1 end
  end
  -- el tablero sigue sobre las orillas (ahí el terreno ya no es vaguada): se alarga el puente hacia los dos lados mientras
  -- siga habiendo tablero, para no enterrar ni levantar sus extremos
  local function extend(from, st)
    local last = S[from]
    local k = from + st
    local n = 0
    while k >= 1 and k <= N and n < math.floor(25 / M.STEP_M) and not S[k].bridge do
      local d = deckAt(S[k], last.deck + 1.5, 0.06, last.deck, last.off)
      if not d or math.abs(d.c - last.off) > 1.0 or math.abs(d.h - last.deck) > 0.6 then break end
      S[k].bridge, S[k].off, S[k].bw, S[k].deck, S[k].dip = true, d.c, d.hw, d.h, false
      last = S[k]
      k, n = k + st, n + 1
    end
  end
  i = 1
  while i <= N do
    if S[i].bridge then
      local j = i
      while j <= N and S[j].bridge do j = j + 1 end
      extend(i, -1)
      extend(j - 1, 1)
      while j <= N and S[j].bridge do j = j + 1 end
      i = j
    else i = i + 1 end
  end
  -- por puente: el desplazamiento y la anchura medios (el tablero es recto) y la altura del suelo PUNTO A PUNTO (el tablero
  -- puede ir en pendiente), suavizada 1 m para quitar el ruido de los rayos
  i = 1
  while i <= N do
    if S[i].bridge then
      local j, so, sw = i, 0, 0
      while j <= N and S[j].bridge do so, sw = so + S[j].off, sw + S[j].bw j = j + 1 end
      local n = j - i
      local raw = {}
      for k = i, j - 1 do raw[k] = S[k].deck end
      for k = i, j - 1 do
        local sum, c = 0, 0
        for q = math.max(i, k - 1), math.min(j - 1, k + 1) do sum, c = sum + raw[q], c + 1 end
        S[k].off, S[k].bw, S[k].deck = so / n, sw / n, sum / c
      end
      M.stats.bridges = M.stats.bridges + 1
      i = j
    else i = i + 1 end
  end
  local function spread(from, to, st)
    local last, dist = nil, 0
    for k = from, to, st do
      local p = S[k]
      if p.bridge then last, dist = p, 0
      elseif last then
        dist = dist + M.STEP_M
        if dist < M.BRIDGE_SHIFT_M then
          local o = last.off * (1 - dist / M.BRIDGE_SHIFT_M)
          if math.abs(o) > math.abs(p.off or 0) then p.off = o end
        end
      end
    end
  end
  spread(1, N, 1)
  spread(N, 1, -1)
  for _, p in ipairs(S) do
    if p.off and math.abs(p.off) > 0.01 then
      p.x, p.y = p.x + p.nx * p.off, p.y + p.ny * p.off
      if not p.bridge then p.th = th(p.x, p.y) or p.th end
    end
  end
end

-- perfil longitudinal de la explanada
M.SIDE_BLEND_MAX_M = 10
M.SMOOTH_AFTER_M = 30      -- ventana de suavizado tras la meta (campo abierto)
M.AFTER_END_RAISE_M = 1.4   -- (23-nov) subida final al borde de la calle
M.AFTER_GRADE = 0.12       -- pendiente máxima del camino tras la meta
M.SHORE_SLOPE = 0.06       -- pendiente máxima de la orilla (fondo del agua -> tierra)
M.WATER_Z = 0.3            -- por debajo, fondo de río/bahía: se conduce sobre él tal cual
M.BANK_GAIN = 0.35
M.BANK_MAX = 0.06
M.BANK_SMOOTH_M = 20
-- (23-nov, el usuario, con la foto de los barcos: "el terreno debería quedar un poco más bajo que el nivel del agua que
-- vemos") nivel del mar en un punto: el WaterBlock bngEarthSea_* más cercano (el nivel cambia de una teselas a otra: 0,1..1,5).
M.WATER_BED_M = 0.25       -- el fondo del camino por el agua queda tanto por debajo de la superficie
M.WATER_GRADE = 0.15       -- pendiente máxima de la orilla al fondo del camino por el agua
local seaList
local function seaZ(x, y)
  if not seaList then
    seaList = {}
    for _, n in ipairs(scenetree.findClassObjects('WaterBlock') or {}) do
      local w = scenetree.findObject(n)
      if w and tostring(n):find('^bngEarthSea') then
        local p, sc = w:getPosition(), w:getScale()
        if sc.x < 1000 and math.abs(p.z) < 30 then seaList[#seaList + 1] = { x = p.x, y = p.y, h = sc.x / 2, z = p.z, L = sc.x } end
      end
    end
  end
  local best, bm
  for _, b in ipairs(seaList) do
    local m = math.max(math.abs(x - b.x), math.abs(y - b.y)) - b.h
    if m < 60 and (not best or m < bm - 0.01 or (math.abs(m - bm) <= 0.01 and b.L < best.L)) then best, bm = b, m end
  end
  return best and best.z or nil
end
function M.resetSea() seaList = nil end

local function profile(S, sec)
  local N = #S
  local WZ = seaZ(S[math.floor(N / 2)].x, S[math.floor(N / 2)].y)
  sec.sea = WZ
  -- (23-nov, el usuario, con el río helado: "la calzada a la altura del suelo del hielo, sin montículo") con nieve el agua es
  -- hielo y se conduce sobre el fondo tal cual (el WaterBlock queda ~2 m por encima: calzada justo bajo su superficie = terraplén)
  local frozen = sec.snow == true
  if frozen then WZ = nil end
  local waterTh = WZ and (WZ + 0.05) or M.WATER_Z
  -- (23-nov) agua = la tirada de puntos bajo WATER_Z que toca un extremo del trozo (el río o la bahía por donde va el
  -- tramo); una hondonada suelta en medio es tierra y se rellena como siempre
  do
    local i = 1
    while i <= N and S[i].th < waterTh do S[i].water = true i = i + 1 end
    local j = N
    while j > i and S[j].th < waterTh do S[j].water = true j = j - 1 end
    -- tramos de agua en medio (una ensenada que el camino cruza): tiradas de 3 m o más bajo la superficie
    if WZ or frozen then
      local k = i
      while k <= j do
        if S[k].th < waterTh then
          local e = k
          while e <= j and S[e].th < waterTh do e = e + 1 end
          if (e - k) * M.STEP_M >= 3 then for q = k, e - 1 do S[q].water = true end end
          k = e
        else k = k + 1 end
      end
    end
  end
  for _, p in ipairs(S) do if p.ice and not p.bridge then p.water = true end end
  -- vaguada sin puente: relleno entre las dos orillas
  local i = 1
  while i <= N do
    if S[i].dip and not S[i].bridge then
      local j = i
      while j <= N and S[j].dip and not S[j].bridge do j = j + 1 end
      local h0 = S[math.max(1, i - 1)].bridge and S[math.max(1, i - 1)].deck or S[math.max(1, i - 1)].th
      local h1 = S[math.min(N, j)].bridge and S[math.min(N, j)].deck or S[math.min(N, j)].th
      for k = i, j - 1 do S[k].base, S[k].fill = lerp(h0, h1, (k - i + 1) / (j - i + 1)), true end
      i = j
    else i = i + 1 end
  end
  for _, p in ipairs(S) do p.base = p.base or (p.bridge and p.deck or p.th) end
  -- (23-nov, el usuario: "el camino de salida del río está demasiado bacheado, aplánalo") tras la meta el camino va por
  -- campo abierto: ventana de suavizado mucho mayor
  local afterFinish = T and sec.from >= T.total - 10
  local hasWater = false
  for _, p in ipairs(S) do if p.water then hasWater = true break end end
  local OV = hasWater and 24 or M.OVERLAP_M     -- con agua el enganche con el camino real es más largo (sin escalón)
  local w = math.floor((afterFinish and M.SMOOTH_AFTER_M or M.SMOOTH_M) / M.STEP_M)
  for k, p in ipairs(S) do
    if p.bridge then p.H = p.deck
    elseif p.water then
      -- (23-nov) bajo el agua: el fondo del camino queda WATER_BED_M por debajo de la superficie (sube o baja el terreno
      -- hasta ahí); sin WaterBlock cerca se deja el fondo como está (salvo la rampa de la orilla)
      if WZ then
        p.H = math.min(WZ, seaZ(p.x, p.y) or WZ) - M.WATER_BED_M   -- por punto: cada tesela del mar tiene su cota (0,1–1,5)
        if math.abs(p.H - p.th) > 0.05 then p.ramp = true end
      elseif frozen then
        -- (23-nov) río helado: el fondo de Earth cambia a saltos de una tesela a otra (hasta 0,7 m); la calzada va con la
        -- media de ±SMOOTH_M/2 m de agua (plana, sin escalones ni montículo) y el borde se funde con el fondo
        local sum, n = 0, 0
        for q = math.max(1, k - w), math.min(N, k + w) do
          if S[q].water then sum, n = sum + S[q].th, n + 1 end
        end
        p.H = n > 0 and sum / n or p.th
        if math.abs(p.H - p.th) > 0.05 then p.ramp = true end
      else p.H = p.th end
    else
      local sum, n = 0, 0
      for q = math.max(1, k - w), math.min(N, k + w) do
        if not S[q].water then sum, n = sum + S[q].base, n + 1 end
      end
      p.H = n > 0 and sum / n or p.th
      -- en los solapes con el camino real, de vuelta al terreno que hay
      -- (no en el extremo que sigue en otro trozo del mismo hueco)
      -- (también entre trozos del mismo hueco: cada trozo empieza y acaba LEAD_M dentro del vecino, sobre lo que el vecino
      -- ya dejó llano, y ahí vuelve a la altura que hay: sin escalón en la junta — medido: 0,15 m sin esto)
      if p.s < S[1].s + OV then p.H = lerp(p.th, p.H, (p.s - S[1].s) / OV)
      elseif p.s > S[N].s - OV then p.H = lerp(p.th, p.H, (S[N].s - p.s) / OV) end
    end
  end
  -- Pendiente máxima tras la meta (23-nov, "hay un escalón por el que no permite subir"): el camino que sube de la orilla
  -- a la calle no cambia de altura más de AFTER_GRADE por metro, ni de ida ni de vuelta (la calle va 13 m por encima del mar)
  if afterFinish then
    -- el extremo (borde de la calle) queda en el pie del talud: se sube hasta la altura de la calzada (el talud sube ~1,7 m en 4 m)
    if T.afterFixed and T.after and S[N].s >= T.total + T.after.total - 1 then S[N].H = S[N].th + M.AFTER_END_RAISE_M end
    local g = M.AFTER_GRADE * M.STEP_M
    for k = 2, N do
      local p, q = S[k], S[k - 1]
      if not p.water and not p.bridge then p.H = math.max(q.H - g, math.min(q.H + g, p.H)) end
    end
    for k = N - 1, 1, -1 do
      local p, q = S[k], S[k + 1]
      if not p.water and not p.bridge then p.H = math.max(q.H - g, math.min(q.H + g, p.H)) end
    end
  end
  -- Con agua en el trozo: del fondo del camino a las dos orillas, la altura no cambia más de WATER_GRADE por metro (se
  -- excava el borde de la orilla si hace falta); los extremos (el camino real) y el fondo, fijos.
  if hasWater then
    local g = M.WATER_GRADE * M.STEP_M
    for k = 2, N - 1 do
      local p, q = S[k], S[k - 1]
      if not p.water and not p.bridge then p.H = math.max(q.H - g, math.min(q.H + g, p.H)) end
    end
    for k = N - 1, 2, -1 do
      local p, q = S[k], S[k + 1]
      if not p.water and not p.bridge then p.H = math.max(q.H - g, math.min(q.H + g, p.H)) end
    end
  end
  -- Orilla (23-nov, "hay un escalón por el que no permite subir"): el fondo del agua (una meseta plana) choca con la costa
  -- del relieve de tierra (hasta 3 m de corte). Desde el primer punto de tierra, hacia el agua, el fondo se levanta con una
  -- rampa de SHORE_SLOPE por metro hasta enlazar con el fondo; y hacia tierra la altura no se aleja más de esa pendiente.
  do
    local maxS = M.SHORE_SLOPE * M.STEP_M
    local function shore(kL, dir)         -- kL: primer punto de tierra; dir: sentido hacia el agua (-1 o 1)
      local hL = S[kL].H
      local k, n = kL + dir, 0
      while k >= 1 and k <= N and S[k].water do
        n = n + 1
        local want = hL - maxS * n
        if want > S[k].th + 0.02 then S[k].H, S[k].ramp = want, true else break end
        k = k + dir
      end
    end
    local i = 1
    while i <= N and S[i].water do i = i + 1 end
    if i > 1 and i <= N and not WZ then shore(i, -1) end
    local j = N
    while j >= 1 and S[j].water do j = j - 1 end
    if j < N and j >= 1 and not WZ then shore(j, 1) end
  end
  -- Rampas de entrada y salida de cada puente (22-nov, medido: el tablero empieza 2,6 m por debajo de la orilla y con una
  -- rampa fija de 12 m quedaba una bajada del 30 %): desde el suelo del tablero hacia fuera, el terreno no cambia más de
  -- RAMP_SLOPE por metro; la rampa mide lo que haga falta (desmonte o terraplén) y acaba donde alcanza el perfil normal.
  local maxStep = M.RAMP_SLOPE * M.STEP_M
  local function ramp(e, dir)
    local prev = S[e].deck - 0.03
    local k = e + dir
    local n = 0
    local edge = math.floor(M.OVERLAP_M / M.STEP_M)
    while k > edge and k <= N - edge and not S[k].bridge and n < math.floor(M.RAMP_MAX_M / M.STEP_M) do
      local h = S[k].H
      if math.abs(h - prev) <= maxStep then break end
      h = prev + math.max(-maxStep, math.min(maxStep, h - prev))
      S[k].H, prev = h, h
      k, n = k + dir, n + 1
    end
  end
  for k = 1, N do
    if S[k].bridge then
      if k > 1 and not S[k - 1].bridge then ramp(k, -1) end
      if k < N and not S[k + 1].bridge then ramp(k, 1) end
    end
  end
  -- donde el camino va en desmonte o terraplén, el talud de los lados más tendido (1,5 m de ancho por metro de desnivel)
  for _, p in ipairs(S) do
    p.blend = math.max(M.BLEND_M, math.min(M.BLEND_MAX_M, M.BLEND_M + 1.5 * math.abs(p.H - p.th)))
  end
  -- NORMA (22-nov, el usuario, km 2,7: "hace un desnivel extraño; aplánalo o peráltalo contra el montículo para nivelarlo
  -- poco a poco durante la curva"). A media ladera el camino quedaba como una repisa plana con un corte del 50 % a 3 m
  -- del eje. Ahora, por cada lado, el talud se tiende según el desnivel que tiene que salvar (2 m de ancho por metro,
  -- hasta SIDE_BLEND_MAX_M) y la calzada se peralta hacia la ladera (BANK_GAIN de la pendiente transversal del terreno,
  -- como mucho BANK_MAX), entrando y saliendo poco a poco (media de ±BANK_SMOOTH_M) y a cero en puentes y extremos.
  local off = M.HALF_M + 3
  for _, p in ipairs(S) do
    local hl, hr = th(p.x + p.nx * off, p.y + p.ny * off), th(p.x - p.nx * off, p.y - p.ny * off)
    if hl and hr and not p.bridge and hl > -10 and hr > -10 then
      p.bl = math.max(p.blend, math.min(M.SIDE_BLEND_MAX_M, M.BLEND_M + 2 * math.abs(hl - p.H)))
      p.br = math.max(p.blend, math.min(M.SIDE_BLEND_MAX_M, M.BLEND_M + 2 * math.abs(hr - p.H)))
      p.bank0 = math.max(-M.BANK_MAX, math.min(M.BANK_MAX, M.BANK_GAIN * (hl - hr) / (2 * off)))
    else p.bl, p.br, p.bank0 = p.blend, p.blend, 0 end
  end
  local wb = math.floor(M.BANK_SMOOTH_M / M.STEP_M)
  for k, p in ipairs(S) do
    local sb, sl, sr, n = 0, 0, 0, 0
    for q = math.max(1, k - wb), math.min(N, k + wb) do sb, sl, sr, n = sb + S[q].bank0, sl + S[q].bl, sr + S[q].br, n + 1 end
    local e = math.max(0, math.min(1, math.min(p.s - S[1].s, S[N].s - p.s) / (M.OVERLAP_M + 12)))
    p.bank = p.bridge and 0 or sb / n * e
    p.sbl, p.sbr = sl / n, sr / n
  end
  for _, p in ipairs(S) do p.blend = math.max(p.blend, p.sbl, p.sbr) end
end

local function applyTerrain(tb, S, sec)
  local C = {}
  for _, p in ipairs(S) do
    local reach = M.HALF_M + (p.blend or M.BLEND_M)
    for j = -reach, reach, 0.5 do
      local cx, cy = math.floor(p.x + p.nx * j + 0.5), math.floor(p.y + p.ny * j + 0.5)
      local key = cx .. ':' .. cy
      local aj = math.abs(j)
      local r = C[key]
      if not r or aj < r.j then
        local sg = j >= 0 and 1 or -1
        local bl = (sg > 0 and p.sbl or p.sbr) or p.blend or M.BLEND_M
        -- (peralte: la altura sigue la inclinación hasta el borde de la calzada; el talud parte de la altura del borde)
        C[key] = { x = cx, y = cy, j = aj, H = p.H + (p.bank or 0) * sg * math.min(aj, M.HALF_M), bridge = p.bridge, s = p.s, blend = bl, water = p.water, ramp = p.ramp }
      end
    end
  end
  local n = 0
  local probe = {}
  for key, r in pairs(C) do
    if not r.bridge then
      local cur = th(r.x, r.y)
      if cur then   -- (23-nov) sin lo que sumaron los bancos de nieve: lo original es el terreno sin banco
        local okW, W = pcall(require, 'earthRaid/winter')
        if okW and W.bankAdd then cur = cur - (W.bankAdd(r.x, r.y) or 0) end
      end
      -- (23-nov, probado: el coche se quedó atascado en el río helado) el fondo de agua que no se modifica se pinta igual con el
      -- material del camino: el original (barro, bngEarthGroundMud) pasa a ser MUD profundo con la nieve
      if cur and r.water and not r.ramp and r.s >= sec.from - 2 and r.s <= sec.to + 2 and r.j <= M.HALF_M + 0.5 then
        local okM, mi = pcall(function() return tb:getMaterialIdxWs(vec3(r.x, r.y, 0)) end)
        local want = sec.snow and M.MAT_ICE or sec.mat or M.MAT_ROAD   -- (23-nov, el usuario: sobre el río helado, de HIELO)
        if okM and mi ~= 0 then
          local rec = cells[key]
          if not rec then rec = { x = r.x, y = r.y, h0 = cur, h1 = cur } cells[key] = rec M.stats.cells = M.stats.cells + 1 end
          if rec.m0 == nil then rec.m0 = mi end
          rec.m1 = want
          if mi ~= want then pcall(function() tb:setMaterialIdxWs(vec3(r.x, r.y, 0), want) end) end
          -- testigos para que verify() vuelva a pintar si Earth pisa el material (medido: el 70 % se perdía en el río)
          probe.pw = (probe.pw or 0) + 1
          if r.j < 0.6 and #probe < 6 and probe.pw % 150 == 1 then probe[#probe + 1] = rec end
        end
      end
      if cur and (not r.water or r.ramp) then   -- (23-nov) el fondo del agua (río/bahía) no se modifica, salvo la rampa de la orilla
        local rec = cells[key]
        if not rec then rec = { x = r.x, y = r.y, h0 = cur } cells[key] = rec M.stats.cells = M.stats.cells + 1
        elseif not rec.h1 or math.abs(cur - rec.h1) > 0.05 then rec.h0 = cur end   -- Earth lo recargó: el de ahora es el original
        local wgt = r.j <= M.HALF_M and 1 or math.max(0, (M.HALF_M + r.blend - r.j) / r.blend)
        rec.h1 = rec.h0 * (1 - wgt) + r.H * wgt
        pcall(function() tb:setHeightWs(vec3(r.x, r.y, 0), rec.h1) end)
        -- el camino pintado: solo en el hueco (en los solapes ya hay camino) y nunca encima de asfalto o de otro camino
        if r.s >= sec.from - 2 and r.s <= sec.to + 2 and r.j <= M.HALF_M + 0.5 then
          local okM, mi = pcall(function() return tb:getMaterialIdxWs(vec3(r.x, r.y, 0)) end)
          if okM and mi ~= 0 then
            local want = (r.water and sec.snow) and M.MAT_ICE or sec.mat or M.MAT_ROAD
            rec.m1 = want
            if mi ~= want then
              if rec.m0 == nil then rec.m0 = mi end
              pcall(function() tb:setMaterialIdxWs(vec3(r.x, r.y, 0), want) end)
            end
          end
        end
        n = n + 1
        if r.j < 0.6 and (#probe == 0 or n % 400 == 0) and #probe < 6 then probe[#probe + 1] = rec end
      end
    end
  end
  pcall(function() tb:updateGrid() end)
  pcall(function() tb:updateGridMaterials() end)
  M.regrass()
  sec.probe = probe
  -- las celdas de este trozo, para volver a ponerlas tal cual si Earth las pisa (reapply)
  local list = {}
  for key, r in pairs(C) do if not r.bridge and cells[key] and cells[key].h1 then list[#list + 1] = cells[key] end end
  sec.cells = list
  return n
end

-- Earth ha pisado el trozo: se vuelven a poner solo las celdas que han cambiado, con las alturas y materiales ya calculados.
-- Nada más (22-nov, medido: rehacer el trozo entero en cada fotograma —perfil, bosque, hierba, rodadas, objetos— fueron 692
-- reconstrucciones en una pasada y una caída de FPS seria; esto cuesta 1-4 ms y solo cuando hace falta).
local lastGrass = 0
local function reapply(tb, sec)
  local n = 0
  for _, rec in ipairs(sec.cells or {}) do
    if inBlock(tb, rec.x, rec.y) then
      local cur = th(rec.x, rec.y)
      if cur and math.abs(cur - rec.h1) > 0.03 then
        pcall(function() tb:setHeightWs(vec3(rec.x, rec.y, 0), rec.h1) end)
        n = n + 1
      end
      if rec.m1 then
        local okM, mi = pcall(function() return tb:getMaterialIdxWs(vec3(rec.x, rec.y, 0)) end)
        if okM and mi ~= rec.m1 then
          pcall(function() tb:setMaterialIdxWs(vec3(rec.x, rec.y, 0), rec.m1) end)
          n = n + 1
        end
      end
    end
  end
  if n > 0 then
    pcall(function() tb:updateGrid() end)
    pcall(function() tb:updateGridMaterials() end)
    -- la hierba, como mucho cada 5 s
    if os.clock() - lastGrass > 5 then lastGrass = os.clock() M.regrass() end
  end
  return n
end

-- La hierba (GroundCover) no se entera sola de que el terreno ha cambiado: se queda flotando donde se ha rebajado y sigue
-- saliendo sobre el camino (22-nov, el usuario: "el césped sale volando"). postApply la vuelve a sembrar sobre el terreno
-- y los materiales de ahora.
function M.regrass()
  for _, n in ipairs(scenetree.findClassObjects('GroundCover') or {}) do
    local g = scenetree.findObject(n)
    if g then pcall(function() g:postApply() end) end
  end
end

-- Comprobación de que se puede pasar: el perfil de la superficie por el eje (terreno o tablero), cada 0,5 m. Devuelve el
-- mayor escalón entre dos puntos seguidos (m), dónde, y la mayor pendiente en 3 m (%).
function M.checkSection(sec)
  local S = sec.S
  if not S then return nil end
  local prev, worst, at, slope = nil, 0, nil, 0
  local hs = {}
  for i, p in ipairs(S) do
    local tt = th(p.x, p.y) or p.H
    local sf = be:getSurfaceHeightBelow(vec3(p.x, p.y, (p.bridge and p.deck or tt) + 1.5))
    local h = (type(sf) == 'number' and sf > tt - 0.2 and sf < tt + 8) and sf or tt
    hs[i] = h
    if prev and math.abs(h - prev) > worst then worst, at = math.abs(h - prev), p.s end
    prev = h
  end
  local k = math.floor(3 / M.STEP_M)
  for i = 1, #hs - k do
    local sl = math.abs(hs[i + k] - hs[i]) / (k * M.STEP_M) * 100
    if sl > slope then slope = sl end
  end
  return worst, at, slope
end

local function nearestSample(S, x, y)
  local bi, bd = 1, 1e18
  for i = 1, #S, 2 do
    local d = (S[i].x - x) ^ 2 + (S[i].y - y) ^ 2
    if d < bd then bi, bd = i, d end
  end
  return bi, math.sqrt(bd)
end

-- despeje del bosque; devuelve lo que queda cerca: { i, side, d }
-- hacia dónde queda la costa (o lo más bajo) desde (x, y): dirección unitaria, o nil si alrededor está todo a la misma cota
local function coastDir(x, y)
  local h0 = th(x, y)
  if not h0 then return nil end
  local best, bh
  for k = 0, 15 do
    local ang = k * math.pi / 8
    local dx, dy = math.cos(ang), math.sin(ang)
    local low = 1e9
    for _, r in ipairs({ 15, 30, 50, 80 }) do
      local h = th(x + dx * r, y + dy * r)
      if h and h < low then low = h end
    end
    if not bh or low < bh then best, bh = { dx, dy }, low end
  end
  if best and bh < h0 - 1.0 then return best[1], best[2] end
  return nil
end

-- una matriz con la posición `pos` y girada para que el frente del objeto (su -Y, como las sillas del juego) mire a (dx, dy)
local function facing(pos, dx, dy)
  local function mk(ang)
    local m = MatrixF(true)
    m:setFromEuler(vec3(0, 0, ang))
    m:setPosition(pos)
    return m
  end
  local ang = math.atan2(dx, -dy)
  local m = mk(ang)
  local c = m:getColumn(1)
  -- (el signo del giro de setFromEuler se comprueba: -Y debe quedar hacia (dx, dy))
  if -(c.x * dx + c.y * dy) < 0.9 then m = mk(-ang) end
  return m
end

-- ERROR GRAVE corregido (22-nov): antes se guardaba `it:getTransform()` de un elemento del bosque y luego se quitaba el
-- elemento; esa matriz es una referencia a su memoria, y al reponerlo con ella salían elementos con la posición y el
-- tamaño corruptos (caja infinita): 762 en una mañana, con sombras fuera de sitio y vegetación que no volvía. Ahora se
-- copian los NÚMEROS (posición y ejes) antes de quitar nada, y la matriz se rehace con ellos.
local function copyTr(it)
  local m = it:getTransform()
  local function c(i) local v = m:getColumn(i) return { v.x, v.y, v.z } end
  local p = it:getPosition()
  return { c(0), c(1), c(2), { p.x, p.y, p.z } }
end
local function matrixOf(tr, z)
  local m = MatrixF(true)
  m:setColumn(0, vec3(tr[1][1], tr[1][2], tr[1][3]))
  m:setColumn(1, vec3(tr[2][1], tr[2][2], tr[2][3]))
  m:setColumn(2, vec3(tr[3][1], tr[3][2], tr[3][3]))
  m:setColumn(3, vec3(tr[4][1], tr[4][2], z or tr[4][3]))
  return m
end
local function finite(x) return type(x) == 'number' and x == x and x > -1e6 and x < 1e6 end
local function sane(tr)
  for i = 1, 4 do for k = 1, 3 do if not finite(tr[i][k]) then return false end end end
  return true
end
-- crea un elemento y comprueba que ha quedado bien; si no, lo quita
local function newItem(fdata, data, m, sc)
  local item = fdata:createNewItem(data, m, sc)
  if not item then return nil end
  local okR, r = pcall(function() return item:getRadius() end)
  local okP, p = pcall(function() return item:getPosition() end)
  if not (okR and okP and finite(r) and r < 1e4 and finite(p.x) and finite(p.y) and finite(p.z)) then
    pcall(function() fdata:removeItem(item) end)
    return nil
  end
  return item
end

-- quita del bosque cualquier elemento corrupto (radio infinito, posición imposible); devuelve cuántos
function M.purgeCorrupt()
  local n = 0
  for _, name in ipairs(scenetree.findClassObjects('Forest') or {}) do
    local f = scenetree.findObject(name)
    local ok, items = pcall(function() return f:getData():getItems() end)
    if ok and items then
      for _, it in ipairs(items) do
        local r, p = it:getRadius(), it:getPosition()
        if not finite(r) or r > 1e4 or not finite(p.x) or not finite(p.y) or (math.abs(p.x) < 0.01 and math.abs(p.y) < 0.01) then
          if pcall(function() f:getData():removeItem(it) end) then n = n + 1 end
        end
      end
    end
  end
  return n
end

local binData
local function findBin()
  if binData ~= nil then return binData or nil end
  binData = false
  for _, n in ipairs(scenetree.findClassObjects('ForestItemData') or {}) do
    if tostring(n):lower():find('garbage_bin') then binData = scenetree.findObject(n) break end
  end
  return binData or nil
end

-- NORMA (22-nov, el usuario: "en la calzada no debe haber ningún obstáculo NUNCA JAMÁS"; seguía habiendo árboles en el
-- puerto): el tronco a más de 4 m no basta. Un abeto tiene 4 m de copa y muchos elementos son GRUPOS de árboles (un solo
-- elemento con varios troncos repartidos, `*_group*`): se descuenta de la distancia el 60 % de su radio (hasta 6 m) y se
-- quita todo lo que así invada la calzada.
local function canopy(it)
  local ok, r = pcall(function() return it:getRadius() end)
  if not ok or type(r) ~= 'number' or r ~= r then return 0 end
  -- (el radio es el de la esfera que envuelve al árbol, altura incluida: un roble de 20 m da 10 m de radio con el tronco
  -- bien lejos. Un árbol suelto invade lo que su copa baja: el 30 %, hasta 3 m; un GRUPO reparte troncos por todo el radio)
  local okN, nm = pcall(function() return tostring(it:getData():getName()):lower() end)
  if okN and nm:find('group') then return math.min(8, math.max(0, r) * 0.5) end
  return math.min(3, math.max(0, r) * 0.3)
end

-- Despeje del bosque: lo que está a menos de CLEAR_M del eje se quita (árboles, postes…). NORMA (22-nov, el usuario): los
-- bancos no se pierden: se recolocan a BENCH_OUT_M del borde del camino, en el lado en el que estaban, mirando a la costa
-- (o al camino si no hay costa cerca), con una papelera al lado. Devuelve lo que queda cerca: { i, side, d }
local function clearForest(S, sec, sweep)
  local mid = S[math.floor(#S / 2)]
  local rad = (S[#S].s - S[1].s) / 2 + 20
  if sweep then mid, rad = { x = sweep.x, y = sweep.y, th = sweep.z or 0 }, sweep.r end
  local near, benches = {}, {}
  -- (rendimiento, 22-nov: Earth tiene más de 2000 objetos Forest; buscarlos y preguntarles uno a uno cuesta ~9 ms. En el
  -- barrido se hace UNA vez para todos los caminos cercanos —sweep.src— y lo ya retirado se tacha para no tocarlo dos veces)
  local src = sweep and sweep.src
  if not src then
    src = {}
    for _, name in ipairs(scenetree.findClassObjects('Forest') or {}) do
      local f = scenetree.findObject(name)
      local ok, items = pcall(function() return f:getData():getItemsCircle(vec3(mid.x, mid.y, mid.th), rad) end)
      if ok and items and #items > 0 then src[#src + 1] = { name = name, f = f, items = items } end
    end
    if sweep then sweep.src = src end
  end
  for _, sr in ipairs(src) do
    local name, f, items = sr.name, sr.f, sr.items
    do
      for idx, it in ipairs(items) do
        if it == false then goto nextItem end
        local okP, ip = pcall(function() return it:getPosition() end)
        if okP and ip then
          local i, d = nearestSample(S, ip.x, ip.y)
          local p = S[i]
          local inGap = p.s >= sec.from - M.OVERLAP_M and p.s <= sec.to + M.OVERLAP_M
          local side = ((ip.x - p.x) * p.nx + (ip.y - p.y) * p.ny) >= 0 and 1 or -1
          if not inGap then
            -- fuera del hueco (camino real): no se retira nada, pero lo que quedó flotando donde el perfil se funde con
            -- el camino real (el solape y los LEAD_M de cada extremo: 23-nov, "la vegetación sigue volando en la entrada
            -- del puente") se vuelve a plantar a la altura del terreno de ahora
            if d < M.HALF_M + (p.blend or M.BLEND_M) + 1.5 then
              -- (también en el puente: 23-nov, un arbusto flotaba 0,74 m justo antes del tablero)
              local z = th(ip.x, ip.y)
              local cell = cells[math.floor(ip.x + 0.5) .. ':' .. math.floor(ip.y + 0.5)]
              if z and cell and cell.h0 and cell.h1 and math.abs(ip.z - cell.h0) < 0.6 and math.abs(z - ip.z) > 0.12 then
                pcall(function()
                  local dat = it:getData()
                  local rec = { forest = name, data = dat, tr = copyTr(it), sc = it:getScale() }
                  if not sane(rec.tr) then return end
                  f:getData():removeItem(it)
                  items[idx] = false
                  removed[#removed + 1] = rec
                  local item = newItem(f:getData(), dat, matrixOf(rec.tr, z), rec.sc)
                  if item then added[#added + 1] = { forest = name, item = item } M.stats.replanted = (M.stats.replanted or 0) + 1 end
                end)
              end
            end
          elseif (d < M.CLEAR_M or d - canopy(it) < M.HALF_M) and not p.bridge then
            local okR = pcall(function()
              local dat = it:getData()
              local nm = tostring(dat:getName()):lower()
              local rec = { forest = name, data = dat, tr = copyTr(it), sc = it:getScale() }
              if not sane(rec.tr) then return end
              f:getData():removeItem(it)
              items[idx] = false
              removed[#removed + 1] = rec
              if nm:find('bench') and not sweep then benches[#benches + 1] = { forest = name, f = f, data = dat, sc = rec.sc, i = i, side = side } end
            end)
            if okR then M.stats.removed = M.stats.removed + 1 end
          else
            if d < M.NEAR_M and not p.bridge then near[#near + 1] = { i = i, side = side, d = d } end
            -- NORMA (22-nov, el usuario: "la vegetación donde hemos terraformado está volando, replántala"): lo que queda
            -- en el talud (donde el terreno ha cambiado) se vuelve a plantar a la altura del terreno de ahora
            if d < M.HALF_M + (p.blend or M.BLEND_M) + 1.5 then
              -- (solo lo que estaba PLANTADO en el suelo de antes y cuyo suelo hemos movido: una farola lleva su lámpara a
              -- 7 m de altura como elemento aparte, y eso no se baja al suelo)
              local z = th(ip.x, ip.y)
              local cell = cells[math.floor(ip.x + 0.5) .. ':' .. math.floor(ip.y + 0.5)]
              if z and cell and cell.h0 and math.abs(ip.z - cell.h0) < 0.6 and math.abs(z - ip.z) > 0.12 then
                pcall(function()
                  local dat = it:getData()
                  local rec = { forest = name, data = dat, tr = copyTr(it), sc = it:getScale() }
                  if not sane(rec.tr) then return end
                  f:getData():removeItem(it)
                  items[idx] = false
                  removed[#removed + 1] = rec
                  local item = newItem(f:getData(), dat, matrixOf(rec.tr, z), rec.sc)
                  if item then added[#added + 1] = { forest = name, item = item } M.stats.replanted = (M.stats.replanted or 0) + 1 end
                end)
              end
            end
          end
        end
        ::nextItem::
      end
    end
  end
  local lastI = {}
  for _, b in ipairs(benches) do
    pcall(function()
      local p = S[b.i]
      -- (dos bancos seguidos del mismo lado, al menos a 4 m uno de otro)
      if lastI[b.side] and math.abs(p.s - lastI[b.side]) < 4 then return end
      lastI[b.side] = p.s
      local out = M.HALF_M + M.BENCH_OUT_M
      local x, y = p.x + p.nx * out * b.side, p.y + p.ny * out * b.side
      local z = th(x, y)
      if not z then return end
      local cx, cy = coastDir(x, y)
      if not cx then cx, cy = -p.nx * b.side, -p.ny * b.side end
      local item = newItem(b.f:getData(), b.data, facing(vec3(x, y, z), cx, cy), b.sc)
      if item then added[#added + 1] = { forest = b.forest, item = item } M.stats.benches = (M.stats.benches or 0) + 1 end
      local bd = findBin()
      if bd then
        -- la papelera, a un lado del banco (a lo largo del camino), a la misma distancia del borde
        local bx, by = x + p.dx * 1.4, y + p.dy * 1.4
        local bz = th(bx, by)
        if bz then
          local bi = newItem(b.f:getData(), bd, facing(vec3(bx, by, bz), cx, cy), 1)
          if bi then added[#added + 1] = { forest = b.forest, item = bi } end
        end
      end
    end)
  end
  return near
end

-- Las dos rodadas (DecalRoad) sobre el camino blanco; en los puentes se corta (el dibujo iría al terreno de debajo)
local serial = 0
local function ruts(S, sec)
  for _, r in ipairs(sec.decals or {}) do pcall(function() r:delete() end) end
  sec.decals = {}
  -- (23-nov, el usuario: «algunas rodadas no están conectadas en curvas muy cerradas»): en curva, un nodo cada 1,2 m (con 3 m la
  -- cinta de 3 m de ancho se plegaba) y los extremos de cada trozo se alargan 2 m para que enlacen con el vecino
  for i, p in ipairs(S) do
    local q, r = S[math.max(1, i - 2)], S[math.min(#S, i + 2)]
    local a1, a2 = math.atan2(p.y - q.y, p.x - q.x), math.atan2(r.y - p.y, r.x - p.x)
    local da = math.abs(((a2 - a1 + math.pi) % (2 * math.pi)) - math.pi)
    p.curved = da > 0.17
  end
  local cur, n, lastS = nil, 0, -1e9
  local function close()
    if cur and n < 2 then pcall(function() cur:delete() end) table.remove(sec.decals) end
    cur, n = nil, 0
  end
  for _, p in ipairs(S) do
    if p.bridge or p.s < sec.from - 4 or p.s > sec.to + 4 then close()
    elseif p.s - lastS >= ((p.curved and 1.2) or 3) or not cur then
      if not cur then
        cur = createObject('DecalRoad')
        cur:setField('material', 0, M.RUT_MATERIAL)
        cur:setField('textureLength', 0, tostring(M.RUT_TEXLEN_M))
        cur:setField('renderPriority', 0, '10')
        cur:setField('breakAngle', 0, '3')
        cur.canSave = false
        serial = serial + 1
        cur:registerObject(('earthRaid_ruts_%d_%d'):format(serial, os.time()))
        if scenetree.MissionGroup then scenetree.MissionGroup:addObject(cur) end
        sec.decals[#sec.decals + 1] = cur
      end
      cur:insertNode(vec3(p.x, p.y, th(p.x, p.y) or p.H), M.RUT_WIDTH_M, n)
      n, lastS = n + 1, p.s
    end
  end
  close()
end

-- un par de bidones redondos, uno a cada lado del eje, a `half` m: la anchura útil
local function barrelPair(S, i, half, marks, gap)
  i = math.max(1, math.min(#S, i))
  local p = S[i]
  if T and (p.s < M.NO_MARK_END_M or p.s > T.total - M.NO_MARK_END_M) then return end
  -- sin amontonar: ningún otro par a menos de `gap` m (los dos de un puente, en embudo, sí van seguidos)
  for _, m in ipairs(marks) do if math.abs(m - p.s) < (gap or 18) then return end end
  marks[#marks + 1] = p.s
  local a = api()
  for _, sg in ipairs({ 1, -1 }) do
    local x, y = p.x + p.nx * half * sg, p.y + p.ny * half * sg
    local la, lo = a.toGeo(x, y, th(x, y) or p.th)
    if la then
      local it = props.add('barrel', la, lo, p.dx, p.dy, 0)
      if it then it.roadOk, it.edgeOk, it.pathgen = true, true, true M.stats.barrels = M.stats.barrels + 1 end
    end
  end
end

local function mark(S, sec, near)
  local marks = {}
  local per = 1 / M.STEP_M
  local N = #S
  -- puentes y pasos elevados: par en cada entrada (anchura del tablero) y otro antes, en embudo
  local i = 1
  while i <= N do
    local kind = S[i].bridge and 'b' or (S[i].fill and 'f') or nil
    if kind then
      local j = i
      while j <= N and ((kind == 'b' and S[j].bridge) or (kind == 'f' and S[j].fill and not S[j].bridge)) do j = j + 1 end
      local half = kind == 'b' and math.max(1.6, (S[i].bw or 2) + 0.4) or (M.HALF_M + 0.4)
      -- (un relleno corto —una hondonada de menos de 8 m— no es un paso elevado que haya que marcar)
      if kind == 'f' and (j - i) * M.STEP_M < 8 then i = j goto continue end
      barrelPair(S, i - math.floor(2 * per), half, marks, 6)
      barrelPair(S, i - math.floor(10 * per), math.max(half + 0.9, M.HALF_M + 0.4), marks, 6)
      barrelPair(S, j + math.floor(2 * per), half, marks, 6)
      barrelPair(S, j + math.floor(10 * per), math.max(half + 0.9, M.HALF_M + 0.4), marks, 6)
      i = j
    else i = i + 1 end
    ::continue::
  end
  -- NORMA (22-nov, el usuario: "demasiadas señales innecesarias; solo en estrechamientos o peligros, no cada 100 m, y nunca
  -- en la salida ni dentro de la calzada"): los bidones quedan solo en las entradas de puentes y pasos elevados (aquí) y
  -- donde una carretera ancha pasa a estrecha (narrowing). Ni en los extremos del camino generado ni por árboles cercanos
  -- (ya no quedan: el despeje llega a 1 m del borde).
end

local function build(t, tb, sec)
  local S = samples(t, tb, sec)
  if not S then return false end
  pcall(followBand, tb, S)
  -- NORMA (22-nov, el usuario): lo de la nieve (camino blanco con rodadas) es SOLO para tramos de nieve. En los demás el
  -- camino generado copia el terreno del camino al que enlaza: el material que haya en el eje justo antes y después del
  -- hueco (2 o 6; nunca asfalto), y sin rodadas dibujadas.
  sec.snow = require('earthRaid/winter').active() == true
  if sec.snow then sec.mat = M.MAT_ROAD
  elseif not sec.mat then
    local cnt = {}
    for _, p in ipairs(S) do
      if (p.s < sec.from and p.s > sec.from - 25) or (p.s > sec.to and p.s < sec.to + 25) then
        local okM, mi = pcall(function() return tb:getMaterialIdxWs(vec3(p.x, p.y, 0)) end)
        if okM and (mi == 2 or mi == 6) then cnt[mi] = (cnt[mi] or 0) + 1 end
      end
    end
    sec.mat = ((cnt[6] or 0) > (cnt[2] or 0)) and 6 or 2
  end
  bridges(S)
  profile(S, sec)
  do
    local nw, nr, nb = 0, 0, 0
    for _, p in ipairs(S) do if p.water then nw = nw + 1 end if p.ramp then nr = nr + 1 end if p.bridge then nb = nb + 1 end end
    log('D', TAG, ('pathgen: perfil %.0f-%.0f m: %d puntos, %d agua, %d rampa, %d puente, th %.1f..%.1f'):format(sec.from, sec.to, #S, nw, nr, nb, S[1].th, S[#S].th))
  end
  -- (23-nov, ALPHA: alpha.lua) sin remodelar ni repintar el terreno; el despeje de árboles, las señales y las guías siguen
  local n = 0
  if alpha.TERRAIN_EDIT then n = applyTerrain(tb, S, sec) else sec.probe, sec.cells = {}, {} end
  sec.S, sec.built = S, true
  -- la línea de guía, a la altura del terreno nuevo (22-nov: quedaba a la altura de antes de aplanar)
  local g = package.loaded['earthRaid/guide']
  if g then g.rollAt = nil end
  sec.mid = S[math.floor(#S / 2)]
  -- (el despeje, en cada construcción: si Earth recarga la tesela, los árboles vuelven)
  local okF, near = pcall(clearForest, S, sec)
  if not okF then log('W', TAG, 'pathgen forest: ' .. tostring(near)) near = {} end
  if not sec.marked then
    sec.marked = true
    local okM, err = pcall(mark, S, sec, near)
    if not okM then log('W', TAG, 'pathgen marks: ' .. tostring(err)) end
  end
  if sec.snow and alpha.TERRAIN_EDIT then
    local okR, errR = pcall(ruts, S, sec)
    if not okR then log('W', TAG, 'pathgen ruts: ' .. tostring(errR)) end
  end
  -- NORMA (22-nov, el usuario: "algunos objetos están volando; no puede pasar nunca"): tras cambiar el terreno, TODO lo que
  -- el mod tiene puesto en la zona se vuelve a apoyar en el suelo (también lo que está a la vista)
  pcall(function()
    local a = api()
    local la, lo = a.toGeo(sec.mid.x, sec.mid.y, sec.mid.th)
    if la then props.reground(la, lo, (S[#S].s - S[1].s) / 2 + 60, true) end
  end)
  log('I', TAG, ('pathgen: camino %.0f-%.0f m hecho (%d celdas)'):format(sec.from, sec.to, n))
  return true
end


-- ---- rodadas y charcos a lo largo de TODO el tramo (23-nov, el usuario: "me gusta cómo se ve el terreno generado con las
-- rodaduras; que esté en todas las partes por donde pasa el tramo, simulando que se desgasta de ir rápido, y ayuda a
-- distinguirlo de las otras carreteras de tierra en modo hardcore" + "algún charco para simular el estancamiento de agua y
-- nieve"). Solo tramos de nieve o tierra. Por trozos de TRK_CHUNK_M cerca del coche; se borran los de atrás. Los trozos de
-- camino generado con nieve ya llevan sus rodadas (ruts): ahí no se repiten.
M.TRACKS = true
M.PUDDLES = true
M.PUDDLE_MATERIAL = 'm_mud_water'
M.PUDDLE_DEPTH_M = 0.07   -- profundidad del hoyo del charco en el centro
-- (23-nov, el usuario: "una sombra o textura simple encima que simule una carretera de tierra nevada, un poco blanca y más oscura
-- por las rodaduras", sin tocar el suelo de Earth) capa blanca translúcida bajo las rodadas, solo con superficie de nieve
-- (23-nov) DESACTIVADO: el decal de nieve se veía como capa naranja «NO TEXTURE» y parpadeaba
M.SNOWROAD_MATERIAL, M.SNOWROAD_WIDTH_M = nil, 5.4
M.TRK_CHUNK_M = 80
M.TRK_STEP_M = 3
M.TRK_BEHIND_M, M.TRK_AHEAD_M = 300, 320
local trk = {}                       -- [k] = { objs = { DecalRoad ... } }
local trkSerial = 0

local function trkSurfaceOk()
  local okS, st = pcall(function() return package.loaded['earthRaid/stage'] and package.loaded['earthRaid/stage'].state() end)
  local sf = okS and st and st.surface
  if sf == nil then return false end
  sf = tostring(sf):lower()
  return sf == 'snow' or sf == 'gravel' or sf == 'dirt' or sf == 'mixed'
end

local function trkDecal(mat, texLen, prio, name)
  local d = createObject('DecalRoad')
  d:setField('material', 0, mat)
  d:setField('textureLength', 0, tostring(texLen))
  d:setField('renderPriority', 0, tostring(prio))
  d:setField('breakAngle', 0, '3')
  d.canSave = false
  trkSerial = trkSerial + 1
  d:registerObject(('earthRaid_%s_%d_%d'):format(name, trkSerial, os.time()))
  if scenetree.MissionGroup then scenetree.MissionGroup:addObject(d) end
  return d
end

local function trkClearChunk(k)
  local c = trk[k]
  if c then for _, o in ipairs(c.objs) do pcall(function() o:delete() end) end end
  if c and c.pits and #c.pits > 0 then
    local tb = terrain()
    if tb then
      for _, r in ipairs(c.pits) do
        local cur = th(r.x, r.y)
        if cur and math.abs(cur - r.set) < 0.03 then pcall(function() tb:setHeightWs(vec3(r.x, r.y, 0), r.h0) end) end
      end
      pcall(function() tb:updateGrid() end)
    end
  end
  trk[k] = nil
end

function M.clearTracks()
  for k in pairs(trk) do trkClearChunk(k) end
end

local function inSnowSection(s)
  for _, sec in ipairs(sections) do
    if sec.built and sec.snow and not sec.void and s >= sec.from - 2 and s <= sec.to + 2 then return true end
  end
  return false
end

local function trkBuild(t, k)
  local c0, c1 = k * M.TRK_CHUNK_M, (k + 1) * M.TRK_CHUNK_M + M.TRK_STEP_M
  local P = {}
  for s = c0, math.min(c1, endAt(t)), M.TRK_STEP_M do
    local x, y = gpos(t, s)
    if not x then break end
    local h = th(x, y)
    if not h then return false end            -- el terreno aún no está: se reintenta
    P[#P + 1] = { s = s, x = x, y = y, h = h }
  end
  if #P < 3 then return true end
  -- el eje de la carretera del juego (el del trazado puede ir hasta 2,5 m a un lado): desplazamiento suavizado
  for _, p in ipairs(P) do
    local okR, n1, _, dd, cx, cy = pcall(props.nearestRoad, p.x, p.y, p.h, 8)
    if okR and n1 and dd and cx and dd < 6 then p.ox, p.oy = cx - p.x, cy - p.y else p.ox, p.oy = 0, 0 end
  end
  for i, p in ipairs(P) do
    local sx, sy, n = 0, 0, 0
    for q = math.max(1, i - 3), math.min(#P, i + 3) do sx, sy, n = sx + P[q].ox, sy + P[q].oy, n + 1 end
    p.ax, p.ay = p.x + sx / n, p.y + sy / n
  end
  local c = { objs = {} }
  trk[k] = c
  local cur, n = nil, 0
  local base, nb = nil, 0
  local snowy = tostring((package.loaded['earthRaid/stage'] and package.loaded['earthRaid/stage'].state() or {}).surface or ''):lower() == 'snow'
  local function close()
    if cur and n < 2 then pcall(function() cur:delete() end) table.remove(c.objs) end
    if base and nb < 2 then pcall(function() base:delete() end) table.remove(c.objs, #c.objs) end
    cur, n, base, nb = nil, 0, nil, 0
  end
  for _, p in ipairs(P) do
    if p.h < M.WATER_Z + 0.2 and p.h > -10 and false then close()
    elseif inSnowSection(p.s) then close()
    else
      if not cur then
        if snowy and M.SNOWROAD_MATERIAL then
          base = trkDecal(M.SNOWROAD_MATERIAL, 6, 9, 'snw')
          c.objs[#c.objs + 1] = base
        end
        cur = trkDecal(M.RUT_MATERIAL, M.RUT_TEXLEN_M, 10, 'trk')
        c.objs[#c.objs + 1] = cur
      end
      local z = be:getSurfaceHeightBelow(vec3(p.ax, p.ay, p.h + 4))
      if base then base:insertNode(vec3(p.ax, p.ay, (type(z) == 'number' and z > p.h - 3 and z) or p.h), M.SNOWROAD_WIDTH_M, nb) nb = nb + 1 end
      cur:insertNode(vec3(p.ax, p.ay, (type(z) == 'number' and z > p.h - 3 and z) or p.h), M.RUT_WIDTH_M, n)
      n = n + 1
    end
  end
  close()
  -- charcos: 0-2 por trozo, siempre los mismos en el mismo sitio (semilla = trozo)
  if M.PUDDLES then
    local r = (k * 7919 + 17) % 97
    local count = (r % 3 == 0) and 0 or ((r % 3 == 1) and 1 or 2)
    for j = 1, count do
      local i0 = 3 + ((r * (j + 3) + j * 11) % math.max(1, #P - 8))
      local p, q = P[i0], P[i0 + 2]
      if p and q and not inSnowSection(p.s) and p.h > M.WATER_Z + 0.3 then
        local off = (((r + j * 13) % 5) - 2) * 0.45          -- -0,9 .. 0,9 m a un lado del eje
        local dx, dy = q.ax - p.ax, q.ay - p.ay
        local l = math.sqrt(dx * dx + dy * dy)
        if l > 0.5 then
          local nx, ny = dy / l, -dx / l
          local d = trkDecal(M.PUDDLE_MATERIAL, 4, 12, 'pud')
          c.objs[#c.objs + 1] = d
          local w = 2.0 + ((r + j) % 3) * 0.5
          -- (23-nov, el usuario: «charcos más realistas, con un pequeño orificio con un poco de agua») un hoyo suave en el
          -- terreno (PUDDLE_DEPTH_M en el centro, radio w*0,6, con el borde fundido) y el agua dentro, algo por debajo del borde
          local cx, cy = P[i0 + 1].ax + nx * off, P[i0 + 1].ay + ny * off
          local rim = th(cx, cy)
          local tbp = terrain()
          if rim and tbp and rim > -10 then
            c.pits = c.pits or {}
            local R = w * 0.6
            for gx = math.floor(cx - R), math.ceil(cx + R) do
              for gy = math.floor(cy - R), math.ceil(cy + R) do
                local rr = math.sqrt((gx - cx) ^ 2 + (gy - cy) ^ 2)
                local h0 = th(gx, gy)
                if rr < R and h0 and math.abs(h0 - rim) < 0.4 then
                  local set = h0 - M.PUDDLE_DEPTH_M * (0.5 + 0.5 * math.cos(math.pi * rr / R))
                  pcall(function() tbp:setHeightWs(vec3(gx, gy, 0), set) end)
                  c.pits[#c.pits + 1] = { x = gx, y = gy, h0 = h0, set = set }
                end
              end
            end
            pcall(function() tbp:updateGrid() end)
          end
          for m, pp in ipairs({ P[i0], P[i0 + 1], P[i0 + 2] }) do
            local x, y = pp.ax + nx * off, pp.ay + ny * off
            d:insertNode(vec3(x, y, (rim or pp.h) - M.PUDDLE_DEPTH_M * 0.4), (m == 2) and w or w * 0.7, m - 1)
          end
        end
      end
    end
  end
  return true
end

-- (23-nov, el usuario: «las rodadas desaparecen y parpadean») un decal cuyo nodo queda por debajo del terreno (el terreno se
-- recargó, subió una rampa o un banco) no se dibuja. Cada segundo, los nodos de los decals cercanos se llevan a la altura del
-- terreno de ahora (+1 cm) si se han separado más de 6 cm.
local function fixDecalZ(objs, budget)
  local fixed = 0
  for _, o in ipairs(objs or {}) do
    local okN, cnt = pcall(function() return o:getNodeCount() end)
    if okN and type(cnt) == 'number' then
      for i = 0, cnt - 1 do
        local okP, pos = pcall(function() return o:getNodePosition(i) end)
        if okP and pos then
          local z = th(pos.x, pos.y)
          if z and z > -10 and math.abs(pos.z - (z + 0.01)) > 0.06 then
            pcall(function() o:setNodePosition(i, vec3(pos.x, pos.y, z + 0.01)) end)
            fixed = fixed + 1
            if fixed >= budget then return fixed end
          end
        end
      end
    end
  end
  return fixed
end

function M.trackUpdate(t, along)
  if not alpha.TERRAIN_EDIT then return end   -- (23-nov, ALPHA) rodadas y charcos apagados
  if not (M.TRACKS and t and trkSurfaceOk()) then
    if next(trk) then M.clearTracks() end
    return
  end
  do
    local budget = 60
    local kn = math.floor(along / M.TRK_CHUNK_M)
    for k = kn - 1, kn + 1 do
      local c = trk[k]
      if c and budget > 0 then budget = budget - fixDecalZ(c.objs, budget) end
    end
    for _, sec in ipairs(sections) do
      if budget > 0 and sec.decals and sec.to > along - 60 and sec.from < along + 160 then budget = budget - fixDecalZ(sec.decals, budget) end
    end
  end
  local k0 = math.floor(math.max(0, along - M.TRK_BEHIND_M) / M.TRK_CHUNK_M)
  local k1 = math.floor(math.min(endAt(t), along + M.TRK_AHEAD_M) / M.TRK_CHUNK_M)
  for k in pairs(trk) do if k < k0 or k > k1 then trkClearChunk(k) end end
  for k = math.floor(along / M.TRK_CHUNK_M), k1 do          -- por delante primero; uno por segundo
    if not trk[k] then
      local ok, done = pcall(trkBuild, t, k)
      if not ok then log('W', TAG, 'pathgen tracks: ' .. tostring(done)) trk[k] = { objs = {} } end
      if ok and done == false then return end
      return
    end
  end
  for k = k0, math.floor(along / M.TRK_CHUNK_M) - 1 do
    if not trk[k] then
      local ok, done = pcall(trkBuild, t, k)
      if not ok then trk[k] = { objs = {} } end
      return
    end
  end
end

-- ---- cada segundo ---------------------------------------------------------------------------------------------------------

-- Cada fotograma (22-nov, el usuario: "a veces desaparece el mapeado que hemos generado"): Earth vuelve a mandar su terreno
-- de vez en cuando y pisa el nuestro. Se mira una celda testigo de cada trozo cercano en cada fotograma y, si ya no es la
-- nuestra, el trozo se rehace en ese mismo fotograma (antes se miraba una vez por segundo: se veía desaparecer).
local function verify(t, tb, along)
  local now = os.clock()
  for _, sec in ipairs(sections) do
    if sec.built and sec.probe and (sec.nextCheck or 0) <= now and sec.to > along - 250 and sec.from < along + M.AHEAD_M + 100 then
      for _, rec in ipairs(sec.probe) do
        -- (solo testigos dentro del terreno cargado: fuera, la altura que da el juego no vale)
        if inBlock(tb, rec.x, rec.y) then
          local cur = th(rec.x, rec.y)
          local bad = cur and rec.h1 and math.abs(cur - rec.h1) > 0.08
          if not bad and rec.m1 then
            local okM, mi = pcall(function() return tb:getMaterialIdxWs(vec3(rec.x, rec.y, 0)) end)
            bad = okM and mi ~= rec.m1
          end
          if bad then
            M.stats.rebuilt = M.stats.rebuilt + 1
            local ok, n = pcall(reapply, tb, sec)
            -- si no se ha podido arreglar (0 celdas cambiadas o error), no se insiste en cada fotograma
            sec.fails = (ok and n and n > 0) and 0 or ((sec.fails or 0) + 1)
            sec.nextCheck = now + ((sec.fails or 0) >= 3 and 10 or 0.25)
            return   -- un trozo por fotograma
          end
        end
      end
    end
  end
end

M.GRAPH_STABLE_S = 3
M.BUILD_NEAR_M = 300
local graphN, graphAge = -1, 0
M.SWEEP_S = 2
local sweepT = 0
-- NORMA (22-nov, el usuario: "el tema de árboles en la carretera ... hay que limpiar la calzada a toda costa"): el despeje de
-- arriba solo cubre los caminos que generamos. Esto limpia también las CARRETERAS REALES del grafo delante del coche: todo
-- elemento del bosque cuyo tronco (o la parte de su copa que baja) cae dentro de la calzada (radio del grafo) se quita,
-- y se restaura al limpiar el tramo como lo demás. Una consulta de bosque por pasada; lo que no es árbol (farolas, postes,
-- papeleras) solo si está claramente en mitad de la calzada.
M.ROAD_SWEEP_R = 110
M.ROAD_MARGIN_M = 0.4
function M.roadSweep(cx, cy, cz)
  local n, seen = 0, 0
  local mp = map.getMap()
  for _, name in ipairs(scenetree.findClassObjects('Forest') or {}) do
    local f = scenetree.findObject(name)
    local ok, items = pcall(function() return f:getData():getItemsCircle(vec3(cx, cy, cz or 0), M.ROAD_SWEEP_R) end)
    if ok and items then
      for _, it in ipairs(items) do
        local okP, ip = pcall(function() return it:getPosition() end)
        if okP and ip then
          seen = seen + 1
          local n1, n2, d = map.findClosestRoad(vec3(ip.x, ip.y, ip.z))
          if d and d < 12 then
            local r1 = n1 and mp.nodes[n1] and mp.nodes[n1].radius or 0
            local r2 = n2 and mp.nodes[n2] and mp.nodes[n2].radius or 0
            local hw = math.max(2, math.min(8, math.max(r1, r2)))
            local nm = ''
            pcall(function() nm = tostring(it:getData():getName()):lower() end)
            local tree = not (nm:find('lamp') or nm:find('light') or nm:find('pole') or nm:find('post') or nm:find('sign')
              or nm:find('bin') or nm:find('bench') or nm:find('hydrant'))
            local bad
            -- carretera real: el tronco es lo que se toca (0,5 m de tronco); la copa solo cuenta en los GRUPOS de árboles, que
            -- reparten troncos por todo su radio. Los setos de árboles junto al arcén se quedan
            local reach = nm:find('group') and canopy(it) or 0.5
            if tree then bad = d - reach < hw + M.ROAD_MARGIN_M else bad = d < hw * 0.8 end
            if bad then
              pcall(function()
                local dat = it:getData()
                local rec = { forest = name, data = dat, tr = copyTr(it), sc = it:getScale() }
                if not sane(rec.tr) then return end
                f:getData():removeItem(it)
                removed[#removed + 1] = rec
                n = n + 1
              end)
            end
          end
        end
      end
    end
  end
  M.stats.roadTrees = (M.stats.roadTrees or 0) + n
  return n, seen
end

-- (23-nov, el usuario: «el terreno del río helado es mud»; probado: el coche se quedó parado en 2526 m sobre Mud) Earth vuelve a
-- pintar sus materiales encima del río después de construir el camino y el testigo (altura) no lo ve. Cada 0,4 s se repasan
-- las celdas con material propio (rec.m1) del camino de ±40 m / +120 m alrededor del coche y se repinta lo que no coincide.
local guardT = 0
local function guardMaterials(tb, along, dt)
  guardT = guardT + (dt or 0)
  if guardT < 0.4 then return end
  guardT = 0
  local v = be:getPlayerVehicle(0)
  local cp = v and v:getPosition()
  if not cp then return end
  local fixed = 0
  for _, sec in ipairs(sections) do
    if sec.built and sec.cells and sec.to > along - 60 and sec.from < along + 140 then
      for _, rec in ipairs(sec.cells) do
        if rec.m1 and math.abs(rec.x - cp.x) < 140 and math.abs(rec.y - cp.y) < 140 and inBlock(tb, rec.x, rec.y) then
          local okM, mi = pcall(function() return tb:getMaterialIdxWs(vec3(rec.x, rec.y, 0)) end)
          if okM and mi ~= 0 and mi ~= rec.m1 then
            pcall(function() tb:setMaterialIdxWs(vec3(rec.x, rec.y, 0), rec.m1) end)
            fixed = fixed + 1
          end
        end
      end
    end
  end
  if fixed > 0 then
    M.stats.matFixed = (M.stats.matFixed or 0) + fixed
    pcall(function() tb:updateGridMaterials() end)
  end
end

function M.update(t, along, dt)
  if not M.enabled or not t then return end
  if T == t then
    local tb0 = terrain()
    if tb0 and alpha.TERRAIN_EDIT then pcall(verify, t, tb0, along) pcall(guardMaterials, tb0, along, dt) end
  end
  tick = tick + (dt or 0)
  if tick < 1 then return end
  tick = 0
  if T ~= t then M.clear() T = t end
  local a, tb = api(), terrain()
  local v = be:getPlayerVehicle(0)
  if not (a and a.toGame and tb and v and map and map.findClosestRoad and props.roadIndex()) then return end
  local cp = v:getPosition()
  -- NORMA (22-nov; probado: salía un "camino generado" falso de 0 a 104 m encima de una carretera del grafo, porque al
  -- aparecer el grafo de Earth aún estaba a medio cargar): no se clasifica ni se construye nada hasta que el grafo lleva
  -- GRAPH_STABLE_S segundos sin cambiar, y antes de construir un camino se vuelve a comprobar que sigue sin carretera.
  local nodes = 0
  for _ in pairs(map.getMap().nodes or {}) do nodes = nodes + 1 end
  if nodes ~= graphN then graphN = nodes graphAge = 0 else graphAge = graphAge + 1 end
  if nodes == 0 or graphAge < M.GRAPH_STABLE_S then return end
  classify(t, tb, along, cp.x, cp.y)
  pcall(M.trackUpdate, t, along)
  -- NORMA (22-nov, el usuario: "siguen apareciendo los árboles en el camino del puerto; elimínalos durante el tramo"):
  -- Earth carga el bosque por zonas DESPUÉS de construir el camino, así que el despeje se repite cada SWEEP_S segundos
  -- en los ~150 m de delante del coche mientras dura el tramo (también replanta lo que quede flotando en el talud).
  sweepT = sweepT + 1
  if sweepT >= M.SWEEP_S then
    sweepT = 0
    local x, y = gpos(t, math.min(endAt(t), along + 60))
    if x then
      local okR, nR = pcall(M.roadSweep, x, y, th(x, y))
      if not okR then log('W', TAG, 'pathgen roadSweep: ' .. tostring(nR)) end
      local sw
      for _, s2 in ipairs(sections) do
        if s2.built and s2.S and not s2.void and s2.to > along - 40 and s2.from < along + 160 then
          sw = sw or { x = x, y = y, z = th(x, y), r = 100 }
          local okS, errS = pcall(clearForest, s2.S, s2, sw)
          if not okS then log('W', TAG, 'pathgen sweep: ' .. tostring(errS)) end
        end
      end
    end
  end
  for _, sec in ipairs(sections) do
    if sec.to > along - 150 and sec.from < along + M.BUILD_NEAR_M then
      if not sec.built and not sec.checked then
        sec.checked = true
        local n, on = 0, 0
        for d = sec.from, sec.to, 5 do
          local x, y = gpos(t, d)
          if x then
            n = n + 1
            local _, _, dd = map.findClosestRoad(vec3(x, y, th(x, y) or 0))
            if dd and dd <= M.ROAD_GRAPH_M then on = on + 1 end
          end
        end
        if n > 0 and on / n > 0.7 then
          sec.built, sec.void = true, true
          log('I', TAG, string.format('pathgen: [%d-%d] descartado, ya hay carretera', sec.from, sec.to))
        end
      end
      if not sec.built then
        local ok, done = pcall(build, t, tb, sec)
        if not ok then log('W', TAG, 'pathgen build: ' .. tostring(done)) sec.built = true end
      end
    end
  end
end

-- el eje del camino generado en `along` (posición del juego), para la línea de guía; nil fuera de un camino generado
function M.centerAt(t, along)
  if t ~= T then return nil end
  for _, sec in ipairs(sections) do
    if sec.built and sec.S and along >= sec.S[1].s and along <= sec.S[#sec.S].s then
      local p = sec.S[math.max(1, math.min(#sec.S, math.floor((along - sec.S[1].s) / M.STEP_M + 0.5) + 1))]
      if p and p.H then return vec3(p.x, p.y, p.H) end
    end
  end
  return nil
end

function M.sections() return sections end
-- ¿hay celda del camino generado en esta casilla entera? (los bancos de nieve no la tocan)
function M.hasCell(x, y) return cells[math.floor(x + 0.5) .. ':' .. math.floor(y + 0.5)] ~= nil end

-- al retirar el tramo: el terreno y el bosque, como estaban
function M.clear()
  pcall(M.clearTracks)
  local tb = terrain()
  if tb then
    local any = false
    for _, rec in pairs(cells) do
      local cur = th(rec.x, rec.y)
      if cur and rec.h1 and inBlock(tb, rec.x, rec.y) and math.abs(cur - rec.h1) < 0.06 then
        pcall(function() tb:setHeightWs(vec3(rec.x, rec.y, 0), rec.h0) end)
        if rec.m0 ~= nil then pcall(function() tb:setMaterialIdxWs(vec3(rec.x, rec.y, 0), rec.m0) end) end
        any = true
      end
    end
    if any then
      pcall(function() tb:updateGrid() end)
      pcall(function() tb:updateGridMaterials() end)
      M.regrass()
    end
  end
  for _, sec in ipairs(sections) do
    for _, r in ipairs(sec.decals or {}) do pcall(function() r:delete() end) end
  end
  for _, r in ipairs(added) do
    pcall(function()
      local f = scenetree.findObject(r.forest)
      if f then f:getData():removeItem(r.item) end
    end)
  end
  for _, r in ipairs(removed) do
    pcall(function()
      local f = scenetree.findObject(r.forest)
      if f and type(r.tr) == 'table' and sane(r.tr) then newItem(f:getData(), r.data, matrixOf(r.tr), r.sc) end
    end)
  end
  -- por si acaso: ningún elemento corrupto en el bosque al acabar
  pcall(M.purgeCorrupt)
  T, status, scanK, run, sections, cells, removed, tick = nil, {}, 0, nil, {}, {}, {}, 0
  offs, added = {}, {}
  lastRad, lastNarrow = nil, -1e9
end

return M

-- Raid.Earth: control de calidad automático de los tramos (18-nov, el usuario: "comprueba que todos los tramos
-- cumplan la norma"). Para cada tramo: viaje a la salida con la carga normal, se mide el control horario y la salida;
-- viaje a la meta, se mide la meta y el STOP; se cuentan los objetos que han quedado en la calzada. Mueve el coche del
-- jugador: solo cuando no esté jugando. Resultado en /settings/earthRaid/audit.json y en el log (tag earthRaid.audit).
local M = {}
local TAG = 'earthRaid.audit'

local props = require('earthRaid/props')
local dressing = require('earthRaid/dressing')
local geo = require('earthRaid/geo')
local phys = require('earthRaid/phys')

M.FILE = '/settings/earthRaid/audit.json'
M.LINE_OK_M = 1.6            -- el centro de una línea, a menos de esto del eje de la carretera
M.ALIGN_OK = 0.6             -- 1 - |coseno| entre la línea y la carretera (1 = cruzada del todo)
M.SETTLE_S = 30              -- espera tras un viaje para que carguen carreteras y terreno
M.JOBS_S = 130               -- espera máxima a que se monte la zona (tras soltar los trabajos retenidos)
M.BUILD_S = 12               -- y un momento más para que se creen los objetos
M.LINE_KINDS = { line = true }
M.BOARD_KINDS = { tc = true, start = true, finish = true, stop = true }   -- carteles: junto a la calzada
M.BOARD_OK_M = 3.0           -- un cartel, a menos de esto del borde de la calzada
M.ROAD_OK = { cone = true, coneS = true, line = true, laptop = true, sensor = true, tc = true, start = true, finish = true, stop = true,
  finishEntry = true, tcEntry = true, sndCrowd = true, sndCheer = true, sndGenerator = true, lamp = true }

local A = nil   -- la auditoría en marcha

local function api() return rawget(_G, 'beamngEarth_api') end
local function main() return rawget(_G, 'earthRaid_main') end
local function stage() return require('earthRaid/stage') end

-- posición y dirección (eje Y del objeto) de un objeto
local function objDir(obj)
  local ok, d = pcall(function() return obj:getTransform():getColumn(1) end)
  if ok and d then return d.x, d.y end
  return nil
end

-- la carretera más cercana a (x, y): del grafo del juego o, donde no la hay (pistas de tierra que el mapa no tiene),
-- la virtual del tramo (índice de props): distancia al eje, radio y dirección del segmento
local function roadAt(x, y, z)
  local n1, n2, d = props.nearestRoad(x, y, z, 60)
  local m = map.getMap()
  if n1 and n2 and m.nodes[n1] and m.nodes[n2] then
    local a, b = m.nodes[n1].pos, m.nodes[n2].pos
    -- el radio en el punto (entre el de los dos nodos; junto a un nodo, el suyo si es mayor), como dressing.edgeGuard:
    -- con el del primer nodo, lo que está junto a una calle estrecha que sale de un cruce ancho contaba como en la calzada
    local sx, sy = b.x - a.x, b.y - a.y
    local L2 = sx * sx + sy * sy
    local u = L2 > 0.01 and math.max(0, math.min(1, ((x - a.x) * sx + (y - a.y) * sy) / L2)) or 0
    local r1, r2 = m.nodes[n1].radius or 3, m.nodes[n2].radius or 3
    local r = math.max(r1 + (r2 - r1) * u, u < 0.5 and r1 or r2)
    return d, r, sx, sy, false
  end
  local best = nil
  for _, sg in ipairs(props.roadsAt(x, y) or {}) do
    if sg.virtual then
      local sx, sy = sg.bx - sg.ax, sg.by - sg.ay
      local L2 = sx * sx + sy * sy
      local u = L2 > 0.01 and math.max(0, math.min(1, ((x - sg.ax) * sx + (y - sg.ay) * sy) / L2)) or 0
      local dd = math.sqrt((x - sg.ax - sx * u) ^ 2 + (y - sg.ay - sy * u) ^ 2)
      if not best or dd < best[1] then best = { dd, sg.ra + (sg.rb - sg.ra) * u, sx, sy } end
    end
  end
  if best then return best[1], best[2], best[3], best[4], true end
  return nil
end

-- distancia del centro de un objeto al eje de la carretera más cercana, su radio y la alineación con ella
local function roadRel(obj)
  local q = obj:getPosition()
  local d, r, sx, sy = roadAt(q.x, q.y, q.z)
  if not d then return nil end
  local L = math.sqrt(sx * sx + sy * sy)
  local align = nil
  local ox, oy = objDir(obj)
  if ox and L > 0.1 then
    local ol = math.sqrt(ox * ox + oy * oy)
    if ol > 0.01 then align = math.abs((ox * sx + oy * sy) / (L * ol)) end
  end
  return d, r, align
end

-- lo que hay montado cerca de (x, y): las líneas y lo que está en la calzada
local function measure(cx, cy, radius)
  local lines, onRoad, hidden = {}, {}, 0
  local a = api()
  for _, it in ipairs(props.all()) do
    if it.obj and it.kind then
      local q = it.obj:getPosition()
      if (q.x - cx) ^ 2 + (q.y - cy) ^ 2 < radius * radius then
        -- (un cartel con física cerca del coche tiene el estático oculto: sigue contando, con su posición)
        if it.hidden and not phys.isLive(it) then hidden = hidden + 1
        elseif it.line and it.lat2 then
          -- una línea pintada (DecalRoad de borde a borde): su centro en el eje y cruzada a la carretera
          local mx, my = a.toGame((it.lat + it.lat2) / 2, (it.lon + it.lon2) / 2, 0)
          local ex, ey = a.toGame(it.lat2, it.lon2, 0)
          if mx then
            local _, _, gz = props.ground((it.lat + it.lat2) / 2, (it.lon + it.lon2) / 2)
            local d, r, sx, sy = roadAt(mx, my, gz or q.z)
            local perp = nil
            if d then
              local lx, ly = ex - mx, ey - my
              local L1, L2 = math.sqrt(sx * sx + sy * sy), math.sqrt(lx * lx + ly * ly)
              if L1 > 0.1 and L2 > 0.1 then perp = 1 - math.abs((sx * lx + sy * ly) / (L1 * L2)) end
            end
            lines[#lines + 1] = { kind = 'line', d = d, r = r, align = perp, x = math.floor(mx), y = math.floor(my) }
          end
        else
          local d, r, align = roadRel(it.obj)
          if M.BOARD_KINDS[it.kind] then
            lines[#lines + 1] = { kind = it.kind, d = d, r = r, align = nil, x = math.floor(q.x), y = math.floor(q.y), board = true }
          elseif d and r and d < r and not M.ROAD_OK[it.kind] and not it.closure then
            -- dentro de la línea de borde (el asfalto sigue ~0,6 m más allá del radio del grafo)
            onRoad[#onRoad + 1] = { kind = it.kind, d = d, r = r, x = math.floor(q.x), y = math.floor(q.y) }
          end
        end
      end
    end
  end
  return lines, onRoad, hidden
end

local function lineOk(l)
  if not l.d then return false, 'no road' end
  if l.board then
    if l.d > (l.r or 3) + M.BOARD_OK_M then return false, ('%.1f m from the road edge'):format(l.d - (l.r or 3)) end
    return true
  end
  if l.d > M.LINE_OK_M then return false, ('%.1f m off the axis'):format(l.d) end
  return true
end

local function gazeboNear(cx, cy)
  for _, it in ipairs(props.all()) do
    if it.obj and it.kind == 'gazebo3x3' and not it.hidden then
      local q = it.obj:getPosition()
      if (q.x - cx) ^ 2 + (q.y - cy) ^ 2 < 30 * 30 then return true end
    end
  end
  return false
end

local function save()
  if not A then return end
  pcall(function()
    FS:directoryCreate('/settings/earthRaid')
    jsonWriteFile(M.FILE, { startedAt = A.startedAt, done = A.done, results = A.results }, true)
  end)
end

local function teleport(lat, lon)
  local v = be:getPlayerVehicle(0)
  local x, y, z = props.ground(lat, lon)
  if not (v and x) then return false end
  v:setPositionRotation(x, y, z + 0.6, 0, 0, 0, 1)
  pcall(function() v:queueLuaCommand('obj:requestReset(RESET_PHYSICS)') end)
  return true
end

local function next_()
  A.i = A.i + 1
  A.step, A.t = 'begin', 0
end

local function finishStage(res)
  res.ok = #res.problems == 0
  A.results[#A.results + 1] = res
  log(res.ok and 'I' or 'W', TAG, ('%s / %s: %s'):format(res.event, res.stage, res.ok and 'OK' or table.concat(res.problems, '; ')))
  save()
  pcall(function() main().uiCancelStage() end)
  next_()
end

-- Empieza: list = { { eventId, stageId, reverse }... } o nil (todos los tramos de todos los eventos)
function M.run(list)
  local mn = main()
  if not mn then return false end
  if not list then
    list = {}
    for _, e in ipairs(mn.events and mn.events() or {}) do
      local full = mn.event(e.id)
      for _, s in ipairs(full and full.stages or {}) do list[#list + 1] = { full.id, s.id, false } end
    end
  end
  A = { list = list, i = 1, step = 'begin', t = 0, results = {}, startedAt = os.date('%Y-%m-%d %H:%M') }
  pcall(function() mn.uiCancelStage() end)
  log('I', TAG, ('audit: %d stages'):format(#list))
  return true
end
function M.stop() if A then A.done = true save() end A = nil end
function M.onTeleported() if A then A.teleported = true end end
function M.active() return A ~= nil end
function M.state() return A and { i = A.i, n = #A.list, step = A.step, results = #A.results, pausedS = A.pausedS } or nil end

function M.update(dt)
  if not A then return end
  -- BeamNG.Earth pausa el juego mientras carga el terreno (depende del PC y la conexión): ese tiempo no cuenta y no
  -- se toca nada (19-nov: quitar la pausa dejaba el coche cayendo por el mapa en bucle)
  if simTimeAuthority.getPause() then A.pausedS = (A.pausedS or 0) + (dt or 0) return end
  A.t = A.t + (dt or 0)
  local mn, st = main(), stage()
  local item = A.list[A.i]
  if not item then
    A.done = true
    save()
    log('I', TAG, 'audit finished: ' .. #A.results .. ' stages')
    A = nil
    return
  end
  if A.step == 'begin' then
    A.res = { event = item[1], stage = item[2], problems = {}, cut = 0 }
    local keep = mn.PLAY_TELEPORT_M
    mn.PLAY_TELEPORT_M = 0
    local ok, err = pcall(mn.uiPlay, item[1], item[2], item[3], true)
    mn.PLAY_TELEPORT_M = keep
    if not ok then A.res.problems[#A.res.problems + 1] = 'uiPlay: ' .. tostring(err) finishStage(A.res) return end
    A.step, A.t = 'loading', 0
    A.retries = A.retries or 0
  elseif A.step == 'loading' then
    local L = require('earthRaid/loader')
    if not L.active() and A.t > 2 then
      if not st.state() then
        -- el viaje puede negarse mientras el mapa carga el suelo ("Loading the ground"): otra vez en 15 s, hasta 8 veces
        if A.retries < 8 then
          A.retries = A.retries + 1
          A.step, A.t = 'retryWait', 0
          return
        end
        A.res.problems[#A.res.problems + 1] = 'stage did not start' finishStage(A.res) return
      end
      A.step, A.t = 'startSettle', 0
    elseif A.t > 240 then A.res.problems[#A.res.problems + 1] = 'loading timed out' finishStage(A.res) return end
  elseif A.step == 'retryWait' then
    if A.t < 15 then return end
    local keep = mn.PLAY_TELEPORT_M
    mn.PLAY_TELEPORT_M = 0
    pcall(mn.uiPlay, item[1], item[2], item[3], true)
    mn.PLAY_TELEPORT_M = keep
    A.step, A.t = 'loading', 0
  elseif A.step == 'startSettle' then
    -- primero junto a la salida (lo de allí se recomprueba al acercarse, como al conducir), luego la medida
    if A.t < 6 then return end
    if not A.atLine then
      A.atLine = true
      local S0 = st.state()
      if S0 and S0.line then teleport(S0.line.lat, S0.line.lon) end
      A.t = 0
      return
    end
    if A.t < 8 then return end
    A.atLine = nil
    local S = st.state()
    local t = S.track
    local a = api()
    local tx, ty = a.toGame(S.tcLat, S.tcLon, 0)
    local lines, onRoad = measure(tx, ty, 300)
    A.res.cut = (t.cutStart or 0)
    A.res.startInfo = t.startInfo
    local seen = {}
    local sx, sy = a.toGame(S.line.lat, S.line.lon, 0)
    for _, l in ipairs(lines) do
      local nearStart = sx and (l.x - sx) ^ 2 + (l.y - sy) ^ 2 < 30 * 30
      if l.kind == 'tc' or l.kind == 'start' or (l.kind == 'line' and nearStart) then
        local name = l.kind == 'line' and 'start' or l.kind
        seen[name] = true
        local ok, why = lineOk(l)
        if not ok then A.res.problems[#A.res.problems + 1] = ('%s %s %s at %d,%d'):format(name, l.board and 'board' or 'line', why, l.x, l.y) end
        if not l.board and l.align and l.align < M.ALIGN_OK then A.res.problems[#A.res.problems + 1] = ('%s line misaligned (%.2f)'):format(name, l.align) end
      end
    end
    for _, k in ipairs({ 'tc', 'start' }) do if not seen[k] then A.res.problems[#A.res.problems + 1] = 'no ' .. k end end
    if not gazeboNear(tx, ty) then A.res.problems[#A.res.problems + 1] = 'no gazebo at the time control' end
    if #onRoad > 0 then
      local k = {}
      for i = 1, math.min(6, #onRoad) do k[#k + 1] = ('%s@%d,%d'):format(onRoad[i].kind, onRoad[i].x, onRoad[i].y) end
      A.res.problems[#A.res.problems + 1] = ('%d objects on the road near the start: %s'):format(#onRoad, table.concat(k, ' '))
    end
    A.res.startOnRoad = #onRoad
    A.res.before = t.before and math.floor(t.before.total) or 0
    -- a la meta
    local fx, fy = geo.at(t, math.max(0, t.total - 250))
    local fla, flo = geo.toGeo(t, fx, fy)
    A.finishLL = { fla, flo }
    st.holdJobs(true)
    -- el viaje lo hace BeamNG.Earth (carga el terreno, pausa mientras tanto y deja el coche en el suelo)
    A.teleported, A.tpTries = false, 0
    A.step, A.t = 'finishTp', 0
  elseif A.step == 'finishTp' then
    local a = api()
    if not A.tpSent then
      local ok, err = a.teleport(A.finishLL[1], A.finishLL[2], 'audit')
      if ok then A.tpSent = true A.t = 0
      else
        A.tpTries = A.tpTries + 1
        if A.tpTries > 40 then A.res.problems[#A.res.problems + 1] = 'could not travel to the finish: ' .. tostring(err) finishStage(A.res) return end
        A.t = -3   -- otra vez en 3 s
      end
      return
    end
    if (A.teleported and A.t > 2 and a.ready and a.ready()) or A.t > 180 then
      A.tpSent = nil
      A.step, A.t = 'finishSettle', 0
    end
  elseif A.step == 'finishSettle' then
    if A.t < 8 then return end
    if st.jobsHeld then
      -- la meta se monta cuando el grafo de carreteras está cargado allí (como cuando se llega conduciendo)
      local S0 = st.state()
      if S0 and A.t < 60 then
        local t0 = S0.track
        local fx0, fy0 = geo.at(t0, t0.total)
        local fla0, flo0 = geo.toGeo(t0, fx0, fy0)
        local gx0, gy0, gz0 = props.ground(fla0, flo0)
        local n1 = gx0 and props.nearestRoad(gx0, gy0, gz0, 80)
        if not n1 then return end
      end
      st.holdJobs(false)
    end
    local a = api()
    local pl, po = a.position()
    local left = pl and dressing.pendingJobsNear(pl, po) or 0
    if left > 0 and A.t < M.JOBS_S then return end
    -- la meta puede esperar a las carreteras (finishLater se repite): hasta que haya carteles de meta, o 150 s
    local S1 = st.state()
    if S1 and not A.built then
      local t1 = S1.track
      local fx1, fy1 = geo.at(t1, t1.total)
      local fla1, flo1 = geo.toGeo(t1, fx1, fy1)
      local gx1, gy1 = a.toGame(fla1, flo1, 0)
      local seenF = false
      for _, it in ipairs(props.all()) do
        if it.obj and it.kind == 'finish' and (not it.hidden or phys.isLive(it)) then
          local q = it.obj:getPosition()
          if gx1 and (q.x - gx1) ^ 2 + (q.y - gy1) ^ 2 < 450 * 450 then seenF = true break end
        end
      end
      if not seenF and A.t < M.JOBS_S + 150 then return end
      A.built = A.t
    end
    if not A.built then A.built = A.t end
    if A.t < A.built + M.BUILD_S then return end
    A.built = nil
    local S = st.state()
    if not S then A.res.problems[#A.res.problems + 1] = 'stage lost on the way to the finish' finishStage(A.res) return end
    local t = S.track
    local fx, fy = geo.at(t, t.total)
    local fla, flo = geo.toGeo(t, fx, fy)
    local gx, gy = a.toGame(fla, flo, 0)
    local lines, onRoad = measure(gx, gy, 300)
    local seen = {}
    for _, l in ipairs(lines) do
      local nearFinish = gx and (l.x - gx) ^ 2 + (l.y - gy) ^ 2 < 30 * 30
      if l.kind == 'finish' or l.kind == 'stop' or (l.kind == 'line' and nearFinish) then
        local name = l.kind == 'line' and 'finish' or l.kind
        seen[name] = true
        local ok, why = lineOk(l)
        if not ok then A.res.problems[#A.res.problems + 1] = ('%s %s %s at %d,%d'):format(name, l.board and 'board' or 'line', why, l.x, l.y) end
        if not l.board and l.align and l.align < M.ALIGN_OK then A.res.problems[#A.res.problems + 1] = ('%s line misaligned (%.2f)'):format(name, l.align) end
      end
    end
    for _, k in ipairs({ 'finish', 'stop' }) do if not seen[k] then A.res.problems[#A.res.problems + 1] = 'no ' .. k end end
    if #onRoad > 0 then
      local k = {}
      for i = 1, math.min(6, #onRoad) do k[#k + 1] = ('%s@%d,%d'):format(onRoad[i].kind, onRoad[i].x, onRoad[i].y) end
      A.res.problems[#A.res.problems + 1] = ('%d objects on the road near the finish: %s'):format(#onRoad, table.concat(k, ' '))
    end
    A.res.finishOnRoad = #onRoad
    A.res.after = t.after and math.floor(t.after.total) or 0
    A.res.finishCut = t.finishCut == true
    finishStage(A.res)
  end
end

return M

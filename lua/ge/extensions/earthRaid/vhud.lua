-- Raid.Earth: las apps del rally del propio juego (rallyDashboard, rallyTimecard, rallyCountdown, rallyStageTiming,
-- rallyStageProgress) en vez de un HUD propio (18-nov, el usuario: "que no se note que es un mod externo").
-- Todas leen un solo stream de la UI, 'rallyLoop', que en el juego publica gameplay_rallyLoop. Mientras hay un tramo o
-- un rally de Raid.Earth se publica ese stream con nuestros datos, con el mismo formato que el juego
-- (ui/modules/apps/rallyLoop/mockdata/*.json), desde onGuiUpdate: va después del onUpdate de gameplay_rallyLoop, así
-- que el nuestro es el que llega a la UI ese fotograma.
local M = {}
local startclock = require('earthRaid/startclock')

local wasActive = false
-- el color de las apps (sin uiColors.theme, rallyStageTiming/rallyStageProgress no se ven)
local okC, UiColors = pcall(require, '/lua/ge/extensions/gameplay/rally/loop/uiColors')
local colors = {}

local function clockTime(secs)
  secs = math.floor((secs or 0) % 86400)
  return { time = string.format('%02d:%02d:%02d', math.floor(secs / 3600), math.floor(secs % 3600 / 60), secs % 60), ampm = '' }
end
local function hhmm(secs)
  secs = math.floor((secs or 0) % 86400)
  return { time = string.format('%02d:%02d', math.floor(secs / 3600), math.floor(secs % 3600 / 60)), ampm = '' }
end
local function nowSecs()
  return require('earthRaid/geo').dayClock()
end
local function fmtStage(t)
  if not t then return nil end
  local m = math.floor(t / 60)
  return string.format('%d:%04.1f', m, t - m * 60)
end
local function r1(x) return math.floor((x or 0) * 10 + 0.5) / 10 end   -- 103.4995... se veía tal cual en la hoja
local function speedNow()
  local v = getPlayerVehicle and getPlayerVehicle(0)
  if not v then return 0 end
  local ok, s = pcall(function() return v:getVelocity():length() end)
  return ok and s or 0
end

local function baseSchedule()
  return { label = nil, eventType = nil, ssLabel = nil, eventWallClockStart = nil, eventWallClockEnd = nil, timeDiff = nil,
    timeDiffWithEnd = nil, lateness = nil, penalty = 0, hasPenalty = false, canIncurLatePenalty = false, speedLimit = nil,
    speedLimitDisplay = nil, speedUnit = 'km/h', isSpeeding = false }
end

local function prox(distM, isStart)
  -- (24-nov, autorizado por el usuario) como el juego: en la línea de salida la distancia lleva signo y negativa = pasado
  -- de la línea (la interfaz del juego pone entonces BACK); en el resto de controles no baja de 0
  local d = distM or 0
  if not isStart then d = math.max(0, d) end
  return { isNear = d >= 0 and d < 15, distance = d, distanceToPlane = d, isStopped = speedNow() < 0.5, isFrozen = false,
    usingGroundMarkerDistance = false, isStartLine = isStart or false, isOverLineAllowed = false }
end

-- el tramo en marcha (stage.lua): S
local function fromStage(S, R, api)
  local t = S.track
  local n = S.stageNumber or 1
  local label = tostring(n)
  -- circuito con vueltas: la app del juego dice "STAGE vuelta / vueltas"
  local laps = (S.laps or 1) > 1 and S.laps or nil
  if laps then label = tostring(S.lap or 1) end
  local d = { showStageApps = true, missionName = S.title, showDebugInfo = false }
  d.stageData = { currentSSTime = nil, isActive = false, isComplete = false, label = label, stageHeader = S.title, unit = 'km',
    completion = { distM = 0, distPct = 0, totalDistM = t.total },
    splits = nil }
  -- la barra de progreso del juego (DistanceWidgetSVGRect) espera la lista de parciales con pathnodeType 'split_*' y
  -- distPct, y el ÚLTIMO elemento es la meta, con su etiqueta en km (como en el rally del juego: 1.5 ... 3.7 km)
  do
    local tot = t.total or 0
    local list = {}
    local function km(m) return string.format('%.1f', m / 1000) end
    if S.splitAt and tot > 0 and S.splitAt > 0 and S.splitAt < tot then
      list[#list + 1] = { pathnodeId = 1, pathnodeType = 'split_1', distPct = S.splitAt / tot, splitLabel = km(S.splitAt), time = S.splitTime }
    end
    if tot > 0 then list[#list + 1] = { pathnodeId = 2, pathnodeType = 'finish', distPct = 1, splitLabel = km(tot) } end
    d.stageData.splits = #list > 0 and list or nil
  end
  local sc = baseSchedule()
  sc.totalSSCount = laps or S.stageCount
  d.countdownData = { countdown = nil, state = nil }
  -- (23-nov: la caja de Stage, el reloj LED de la salida y «Saltar reloj» deben leer el MISMO reloj: S.wall, el que
  -- también se le da al LED; antes la caja leía la hora del mapa redondeada y se desfasaba hasta 1 s)
  local now = (R and R.clock) or S.wall or nowSecs()
  local canSkip = false
  local ph = S.phase
  if ph == 'approach' or ph == 'hold' or ph == 'tc' then
    d.activeState = 'vehicleProximity'
    sc.label, sc.eventType, sc.ssLabel = 'TC' .. n, 'tc', 'SS' .. n
    local due = S.tcDue or (math.ceil((now + 30) / 60) * 60)
    S.tcDue = due
    sc.eventWallClockStart, sc.eventWallClockEnd = hhmm(due), hhmm(due + 60)
    sc.canIncurLatePenalty = R ~= nil
    local lim = api and api.speedLimit and api.speedLimit()
    local k = lim and lim.ms and math.floor(lim.ms * 3.6 / 10 + 0.5) * 10 or nil   -- redondo a 10 km/h (56 -> 60)
    if not k or k <= 0 then k = 50 end   -- sin dato del mapa: 50 km/h (la zona del control es siempre tranquila)
    sc.speedLimit, sc.speedLimitDisplay = k, tostring(k)
    sc.isSpeeding = speedNow() * 3.6 > k + 5
    d.vehicleProximity = prox(S.distM, false)
    canSkip = ph == 'tc'
  elseif ph == 'grid' then
    -- circuito: en la parrilla, esperando el semáforo
    d.activeState = 'vehicleProximity'
    sc.label, sc.eventType, sc.ssLabel = 'SS' .. n, 'ss_start', 'SS' .. n
    d.vehicleProximity = prox(0, true)
  elseif ph == 'staging' then
    d.activeState = 'vehicleProximity'
    sc.label, sc.eventType, sc.ssLabel = 'SS' .. n, 'ss_start', 'SS' .. n
    if S.startAt then sc.eventWallClockStart, sc.eventWallClockEnd = hhmm(S.startAt), hhmm(S.startAt) end
    sc.timeDiff = math.max(0, math.ceil(S.stagingLeft or 0))   -- el mismo valor que pinta el reloj de la salida
    d.vehicleProximity = prox(S.distM, true)
    canSkip = S.staged == true
  elseif ph == 'countdown' then
    -- la cuenta atrás va en el reloj LED real de la salida (startclock.lua, con la cámara y el marco): sin el semáforo
    -- 2D del juego (como hace el juego con rallyStartCountdownDisplay = 3d)
    -- como el juego (rallyLoop.getUiStreamData): con la cuenta atrás en el reloj 3D se suprime el panel 2D; con '2d' sí sale
    -- y con 'disabled' no sale ninguno
    local cdMode = startclock.mode()
    if S.circuitMode or cdMode == '2d' or (cdMode == '3d' and not startclock.threeD()) then
      d.activeState = 'countdown'
      d.countdownData = { countdown = math.max(0, math.ceil(S.countdown or 0)), state = 'countdown_running' }
    else
      -- (22-nov, el usuario: "se ve el cuadro de Stage cuando no debe"): el juego (rallyLoop.getUiStreamData) pasa el estado a
      -- 'inactive' en la cuenta atrás con el reloj 3D: la tarjeta STAGED/«Start in» desaparece y en su sitio abre la
      -- ventana de cámara del reloj. Con 'vehicleProximity' la tarjeta seguía debajo de la ventana.
      d.activeState = 'inactive'
    end
    sc.label, sc.eventType, sc.ssLabel = 'SS' .. n, 'ss_start', 'SS' .. n
    d.vehicleProximity = prox(0, true)
  elseif ph == 'running' then
    d.activeState = 'stageActive'
    d.stageData.isActive = true
    d.stageData.currentSSTime = S.time
    d.stageData.completion = { distM = S.along or 0, distPct = t.total > 0 and (S.along or 0) / t.total or 0, totalDistM = t.total }
  else -- done, toStop
    d.activeState = 'vehicleProximity'
    d.stageData.isComplete = true
    d.stageData.currentSSTime = S.time
    d.stageData.completion = { distM = t.total, distPct = 1, totalDistM = t.total }
    sc.label, sc.eventType = S.circuitMode and 'Finish' or 'Stop Control', 'ss_stop'
    d.vehicleProximity = prox(S.distM, false)
  end
  d.scheduleData = sc
  d.rallyClock = { wallClockSecs = now, wallClockTime = clockTime(now), epochTime = os.time(), day = 1,
    totalPenalty = (R and R.total and 0) or (S.penalty or 0), totalTime = r1((R and R.total) or S.time or 0), use24hFormat = true,
    canSkipTimeControls = canSkip, isTimeControlSkipAvailable = canSkip, canSkipCountdown = false, isNgrcMode = false }
  d.penaltyData = { totalPenalty = S.penalty or 0, groups = {} }
  return d
end

-- la hoja de tiempos del rally (rally.lua R.rows): un grupo por control horario y su tramo
local function timecard(R)
  local out, g = {}, 0
  for _, r in ipairs(R.rows or {}) do
    if r.kind == 'tc' then g = g + 1 end
    local e = { label = r.label, group = g, isStageEntry = r.kind == 'ss' }
    if r.kind == 'tc' then
      e.scheduledTime = r.due and hhmm(r.due) or nil
      e.recordedTime = r.actual and hhmm(r.actual) or nil
      e.status = r.status == 'ok' and 'on-time' or r.status
    else
      e.stageTime = fmtStage(r.time)
    end
    out[#out + 1] = e
  end
  return out
end

-- el rally completo en un enlace (rally.lua R) sin tramo en marcha
local function fromRally(R, cur, a)
  local d = { showStageApps = true, missionName = R.ev and R.ev.name, showDebugInfo = false, activeState = 'vehicleProximity' }
  local sc = baseSchedule()
  local nSS = 0
  for _, it in ipairs(R.it and R.it.items or {}) do if it.stage then nSS = nSS + 1 end end
  sc.totalSSCount = nSS
  if cur then
    sc.label = cur.label
    sc.eventType = (cur.final and 'service_in') or 'tc'
    sc.ssLabel = cur.stage and ('SS' .. cur.run) or nil
    sc.eventWallClockStart = hhmm(cur.dueMin * 60)
    sc.eventWallClockEnd = hhmm(cur.dueMin * 60 + 60)
    sc.canIncurLatePenalty = true
    -- el límite del rally del juego: 120 en el enlace, 30 en la asistencia
    local k = cur.limitKmh or 120
    sc.speedLimit, sc.speedLimitDisplay = k, tostring(k)
    sc.isSpeeding = speedNow() * 3.6 > k + 5
    local g = a and a.gps and a.gps()
    local dM, tgt = g and g.remaining, cur.pos
    -- en la asistencia con TC0 a la salida: el control que toca es ese (19-nov: ponía "TC1 10.00km" parado en el TC0)
    if R.phase == 'service' and R.tc0 then
      sc.label, sc.ssLabel, tgt, dM = 'TC0', nil, R.tc0, nil
      sc.eventWallClockStart = hhmm(R.startMin * 60)
      sc.eventWallClockEnd = hhmm(R.startMin * 60 + 60)
    end
    -- sin ruta del GPS (planeando, perdida): la distancia en línea recta, no un "10.00km" fijo
    if not dM and tgt and a and a.pose then
      local okP, p = pcall(a.pose)
      if okP and p and p.lat then
        local k = math.cos(math.rad(p.lat))
        dM = math.sqrt(((tgt[1] - p.lat) * 111195) ^ 2 + ((tgt[2] - p.lon) * 111195 * k) ^ 2)
      end
    end
    d.vehicleProximity = prox(dM or 9999, false)
  end
  d.scheduleData = sc
  d.stageData = { currentSSTime = nil, isActive = false, isComplete = false, label = nil, unit = 'km',
    completion = { distM = 0, distPct = 0, totalDistM = 0 } }
  d.countdownData = { countdown = nil, state = nil }
  local early = R.phase == 'service' or R.early
  d.rallyClock = { wallClockSecs = R.clock, wallClockTime = clockTime(R.clock), epochTime = os.time(), day = 1,
    totalPenalty = 0, totalTime = r1(R.total or 0), use24hFormat = true, canSkipTimeControls = early == true,
    isTimeControlSkipAvailable = early == true, canSkipCountdown = false, isNgrcMode = false }
  local pt = 0
  for _, p in ipairs(R.penalties or {}) do pt = pt + (p.s or 0) end
  d.penaltyData = { totalPenalty = pt, groups = {} }
  d.rallyClock.totalPenalty = pt
  return d
end

-- cada fotograma de la UI (main.onGuiUpdate)
function M.update(stage, rally, api)
  local S = stage.state()
  local R = rally.active() and rally.state() or nil
  local data
  if S and S.track and S.phase ~= 'idle' then
    local ok, d = pcall(fromStage, S, R, api)
    data = ok and d or nil
    if data and R then data.timecardData = timecard(R) end
  elseif R then
    local items = R.it and R.it.items or {}
    local ok, d = pcall(fromRally, R, items[R.idx], api)
    data = ok and d or nil
    if data then data.timecardData = timecard(R) end
  end
  if data then
    data.timecardData = data.timecardData or {}
    -- como el juego: dentro de un rally (bucle) la barra va en verde, un tramo suelto en azul (uiColors del juego)
    if okC then
      local fn = R and UiColors.updateForLoop or UiColors.updateForStage
      if fn then pcall(fn, colors, false) end
    end
    if not colors.theme then colors.theme = R and '#009a1a' or '#1f8fff' end
    data.uiColors = colors
    guihooks.queueStream('rallyLoop', data)
    wasActive = true
  elseif wasActive then
    guihooks.queueStream('rallyLoop', { activeState = 'inactive' })
    wasActive = false
  end
end

-- ¿qué disposición de apps del juego toca? la del tramo (cuenta atrás, tiempos, progreso) o la del rally (panel e
-- instrucciones, hoja de tiempos)
function M.wantsStageLayout(stage)
  local S = stage.state()
  if not S then return false end
  -- Ajustes > Rally > «Mostrar apps de tramo»: si el jugador las apaga, no se cambia al diseño de tramo
  local okA, apps = pcall(function() return settings.getValue('rallyShowStageApps') end)
  if okA and apps == false then return false end
  local ph = S.phase
  return ph == 'staging' or ph == 'countdown' or ph == 'running' or ph == 'done' or ph == 'toStop'
end

return M

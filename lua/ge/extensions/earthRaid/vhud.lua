-- Raid.Earth: las apps del rally del propio juego (rallyDashboard, rallyTimecard, rallyCountdown, rallyStageTiming,
-- rallyStageProgress) en vez de un HUD propio (18-nov, el usuario: "que no se note que es un mod externo").
-- Todas leen un solo stream de la UI, 'rallyLoop', que en el juego publica gameplay_rallyLoop. Mientras hay un tramo o
-- un rally de Raid.Earth se publica ese stream con nuestros datos, con el mismo formato que el juego
-- (ui/modules/apps/rallyLoop/mockdata/*.json), desde onGuiUpdate: va después del onUpdate de gameplay_rallyLoop, así
-- que el nuestro es el que llega a la UI ese fotograma.
local M = {}

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
  local tm = os.date('*t')
  return tm.hour * 3600 + tm.min * 60 + tm.sec
end
local function fmtStage(t)
  if not t then return nil end
  local m = math.floor(t / 60)
  return string.format('%d:%04.1f', m, t - m * 60)
end
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
  local d = math.max(0, distM or 0)
  return { isNear = d < 15, distance = d, distanceToPlane = d, isStopped = speedNow() < 0.5, isFrozen = false,
    usingGroundMarkerDistance = false, isStartLine = isStart or false, isOverLineAllowed = false }
end

-- el tramo en marcha (stage.lua): S
local function fromStage(S, R)
  local t = S.track
  local n = S.stageNumber or 1
  local label = tostring(n)
  local d = { showStageApps = true, missionName = S.title, showDebugInfo = false }
  d.stageData = { currentSSTime = nil, isActive = false, isComplete = false, label = label, stageHeader = S.title, unit = 'km',
    completion = { distM = 0, distPct = 0, totalDistM = t.total },
    splits = S.splitAt and { { pathnodeId = 1, splitLabel = 'Split 1', time = S.splitTime } } or {} }
  local sc = baseSchedule()
  sc.totalSSCount = S.stageCount
  d.countdownData = { countdown = nil, state = nil }
  local now = (R and R.clock) or nowSecs()
  local canSkip = false
  local ph = S.phase
  if ph == 'approach' or ph == 'hold' or ph == 'tc' then
    d.activeState = 'vehicleProximity'
    sc.label, sc.eventType, sc.ssLabel = 'TC' .. n, 'tc', 'SS' .. n
    local due = S.tcDue or (math.ceil((now + 30) / 60) * 60)
    S.tcDue = due
    sc.eventWallClockStart, sc.eventWallClockEnd = hhmm(due), hhmm(due + 60)
    sc.canIncurLatePenalty = R ~= nil
    d.vehicleProximity = prox(S.distM, false)
    canSkip = ph == 'tc'
  elseif ph == 'staging' then
    d.activeState = 'vehicleProximity'
    sc.label, sc.eventType, sc.ssLabel = 'SS' .. n, 'ss_start', 'SS' .. n
    if S.startAt then sc.eventWallClockStart, sc.eventWallClockEnd = hhmm(S.startAt), hhmm(S.startAt) end
    d.vehicleProximity = prox(S.distM, true)
    canSkip = S.staged == true
  elseif ph == 'countdown' then
    d.activeState = 'countdown'
    local c = math.max(0, math.ceil(S.countdown or 0))
    d.countdownData = { countdown = c, state = c > 0 and 'counting' or 'go' }
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
    sc.label, sc.eventType = 'Stop Control', 'ss_stop'
    d.vehicleProximity = prox(S.distM, false)
  end
  d.scheduleData = sc
  d.rallyClock = { wallClockSecs = now, wallClockTime = clockTime(now), epochTime = os.time(), day = 1,
    totalPenalty = (R and R.total and 0) or (S.penalty or 0), totalTime = (R and R.total) or S.time or 0, use24hFormat = true,
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
    local lim = a and a.speedLimit and a.speedLimit()
    if lim and lim.ms then
      local k = math.floor(lim.ms * 3.6 + 0.5)
      sc.speedLimit, sc.speedLimitDisplay = k, tostring(k)
      sc.isSpeeding = speedNow() * 3.6 > k + 5
    end
    local g = a and a.gps and a.gps()
    d.vehicleProximity = prox(g and g.remaining or 9999, false)
  end
  d.scheduleData = sc
  d.stageData = { currentSSTime = nil, isActive = false, isComplete = false, label = nil, unit = 'km',
    completion = { distM = 0, distPct = 0, totalDistM = 0 }, splits = {} }
  d.countdownData = { countdown = nil, state = nil }
  local early = R.phase == 'service' or R.early
  d.rallyClock = { wallClockSecs = R.clock, wallClockTime = clockTime(R.clock), epochTime = os.time(), day = 1,
    totalPenalty = 0, totalTime = R.total or 0, use24hFormat = true, canSkipTimeControls = early == true,
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
    local ok, d = pcall(fromStage, S, R)
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
    if okC and UiColors.updateForStage then pcall(UiColors.updateForStage, colors, false) end
    if not colors.theme then colors.theme = '#1f8fff' end
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
  local ph = S.phase
  return ph == 'staging' or ph == 'countdown' or ph == 'running' or ph == 'done' or ph == 'toStop'
end

return M

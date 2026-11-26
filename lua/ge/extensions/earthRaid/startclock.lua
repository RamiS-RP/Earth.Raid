-- ███ BLOQUEADO (23-nov, orden del usuario): funciona y está aprobado. NO modificar sin su permiso expreso. Ver LOCKED.md ███
-- Raid.Earth: el reloj LED de salida del juego (gameplay_rallyStartClock pinta la pantalla sobre cada semáforo
-- s_rally_start_tree de la escena) alimentado con nuestros datos, y la ventana de cámara con zoom al reloj durante la
-- cuenta atrás, hecha igual que la del juego (RenderViewManagerInstance:updateViewCamera, 20 % del ancho, FOV 25,
-- a 1 m del reloj, desplazada 1/3). La del juego solo funciona dentro de sus misiones: esta es una copia.
local M = {}
local TAG = 'earthRaid'

M.VIEW_NAME = 'earthRaidStartClockView'
M.WIDTH_RATIO = 0.2
M.ASPECT = 400 / 164
M.TOP_RATIO = 0.132         -- como el juego (rallyStartClock): la ventana tapa el panel de la cuenta atrás y deja el HUD limpio
M.FOV = 25
M.DIST_M = 1.0
M.SHIFT = 1 / 3
M.LINGER_S = 1.5
M.MASK = 29

local view, linger, clockObj, linePos, roadFwd = nil, 0, nil, nil, nil
-- NORMA (22-nov, el usuario: "la cámara de vanilla está más a la derecha del camino, apuntando hacia la carretera; el coche
-- se ve pasar antes de que desaparezca; y lleva un pequeño movimiento como la steadycam"). Es lo que hace el juego
-- (gameplay/rallyStartClock + startClocks/rallyStartTree.getView): la cámara va a 1 m del reloj en la diagonal
-- (tangente de la pantalla hacia delante de la carretera + normal hacia la calzada), el reloj descentrado 1/3 de ancho, y
-- el balanceo de core/cameraModes/bobbing con standingBobScale = 1.
local bob, camData = nil, { res = {} }
local function newBob()
  local ok, b = pcall(function() return require('core/cameraModes/bobbing')() end)
  if ok and b then b.walkBobScale = 0 b.standingBobScale = 1 return b end
end
local display, displayT = nil, 0
local stageLabel = nil
local shimmed = false

-- La pantalla LED la crea el juego junto a cada semáforo (rallyStartClockDisplayN): la del nuestro, para apuntar la
-- cámara a ella (el centro de la caja del semáforo queda por debajo y a un lado de la pantalla)
local function findDisplay()
  if not (clockObj and simObjectExists(clockObj)) then return nil end
  local cp = clockObj:getPosition()
  local best, bd = nil, 36
  for _, n in ipairs(scenetree.findClassObjects('TSStatic') or {}) do
    if tostring(n):find('^rallyStartClockDisplay') then
      local o = scenetree.findObject(n)
      if o then
        local p = o:getPosition()
        local d = (p.x - cp.x) ^ 2 + (p.y - cp.y) ^ 2
        if d < bd and math.abs(p.z - cp.z) < 6 then best, bd = o, d end
      end
    end
  end
  return best
end

-- El reloj del juego saca el número de tramo de su gestor de rallies (solo en sus misiones): mientras no haya uno de
-- verdad, uno mínimo que solo da la etiqueta del tramo
function M.setStage(label)
  stageLabel = label
  if label and rawget(_G, 'gameplay_rallyLoop') == nil then
    -- el reloj del juego toma la hora de getWallClockTimeSecs si hay gestor: sin ella no pintaba ni hora ni cuenta
    -- atrás (16-nov)
    local mgr = setmetatable({ currentMissionIndex = 1, getSchedule = function() return { { ssLabel = stageLabel } } end,
      getWallClockTimeSecs = function() return M.wallSecs end },
      { __index = function() return function() end end })
    rawset(_G, 'gameplay_rallyLoop', setmetatable({ getManager = function() return mgr end, __earthRaidShim = true },
      { __index = function() return function() end end }))
    shimmed = true
  end
end
local function unshim()
  local g = rawget(_G, 'gameplay_rallyLoop')
  if shimmed and g and rawget(g, '__earthRaidShim') then rawset(_G, 'gameplay_rallyLoop', nil) end
  shimmed = false
end

local function ext() return rawget(_G, 'gameplay_rallyStartClock') end

function M.ensure()
  if not ext() then pcall(extensions.load, 'gameplay_rallyStartClock') end
  -- que vuelva a buscar semáforos (los nuestros son nuevos)
  local e = ext()
  if e and e.onRallySessionEnd then pcall(e.onRallySessionEnd) end
  return e ~= nil
end

-- Lo que el juego espera de un rally: estado, reloj de pared y cuenta atrás
function M.feed(state, wallSecs, countdownLeft)
  M.wallSecs = wallSecs and (wallSecs % 86400) or nil
  local e = ext()
  if not (e and e.onRallyDataUpdated) then return end
  pcall(e.onRallyDataUpdated, {
    activeState = state,
    rallyClock = { wallClockSecs = wallSecs },
    startClockCountdownData = countdownLeft and { timeUntilLaunch = countdownLeft,
      state = countdownLeft > 0 and 'countdown_running' or 'launched' } or nil,
  })
end

-- el semáforo que se enfoca y el punto de la línea de salida (coordenadas del juego, se recalcula tras un rebase)
function M.setClock(obj) clockObj, display = obj, nil end
function M.setLine(pos, fwd) linePos = pos if fwd then roadFwd = fwd end end

-- como startClocks/rallyStartTree.getView: dirección (horizontal) desde el reloj hasta la cámara
local function viewDir(target)
  if not (roadFwd and clockObj and simObjectExists(clockObj)) then return nil end
  local f = vec3(roadFwd.x, roadFwd.y, 0)
  if f:squaredLength() <= 0.01 then return nil end
  f = f:normalized()
  local right = f:cross(vec3(0, 0, 1))
  local clockIsRight = (target - linePos):dot(right) >= 0
  -- geometría de la carretera, no la orientación del modelo: la cámara detrás del reloj (la cara mira al coche) y del lado de fuera (derecho si
  -- el reloj está a la derecha), mirando al reloj y a la carretera
  local outward = right * (clockIsRight and 1 or -1)
  -- (23-nov) la cara del reloj mira hacia atrás (hacia el coche parado en la línea): la cámara va DETRÁS del reloj y fuera
  local d = outward - f
  if d:squaredLength() < 0.01 then return nil end
  return d:normalized()
end

local function rect()
  local canvas = scenetree.findObject('Canvas')
  if not (canvas and canvas.getWindowClientSizeXY) then return nil end
  local w, h = canvas:getWindowClientSizeXY()
  if not w or not h then return nil end
  local vw = math.floor(w * M.WIDTH_RATIO + 0.5)
  local vh = math.floor(vw / M.ASPECT + 0.5)
  return math.floor((w - vw) * 0.5 + 0.5), math.floor(h * M.TOP_RATIO + 0.5), vw, vh, w, h
end

local function ensureView(x, y, w, h)
  if not RenderViewManagerInstance then return nil end
  if not view then
    view = RenderViewManagerInstance:getOrCreateView(M.VIEW_NAME)
    if not view then return nil end
    view.active = false
    view.luaOwned = true
    view.namedTexTargetColor = M.VIEW_NAME
    view.renderCubemap = false
    view.renderEditorIcons = false
    view.renderEditorGizmo = false
    view.renderShadows = true
    view.usePostEffects = true
    view.objectTypeBlacklistMask = 0
    view.shadowCasterObjectTypeBlacklistMask = 0
    pcall(function() view:maskSet(M.MASK) end)
    if RenderSettings then
      pcall(function()
        local rs = RenderSettings.getGlobals()
        rs.vehicleMirrorsEnabled = false
        view.settingsOverride = rs
        view.settingsOverrideEnabled = true
      end)
    end
  end
  view.resolution = Point2I(w, h)
  view.viewPort = RectI(0, 0, w, h)
  view.compositeRect = RectI(x, y, w, h)
  local main = RenderViewManagerInstance:getView('main')
  if main then view.currentExposure = main.currentExposure end
  return view
end

local function hide()
  if view then view.active = false view.compositeRect = RectI(0, 0, 0, 0) end
  guihooks.trigger('EarthRaidClockView', { show = false })
end

-- Cada fotograma: active = en cuenta atrás; code 'R' | 'A' | 'G' (color del marco, como las luces)
-- Ajustes > Rally > «Cuenta atrás de salida»: '3d' = el reloj LED con su ventana de cámara (y sin el panel 2D, como el juego),
-- '2d' = el panel del HUD, 'disabled' = nada
function M.mode()
  local ok, v = pcall(function() return settings.getValue('rallyStartCountdownDisplay') end)
  return ok and v or '3d'
end
-- ¿se va a ver la cuenta atrás en el reloj 3D? (entonces el panel 2D de la cuenta atrás se suprime)
function M.threeD()
  return M.mode() == '3d' and clockObj ~= nil and simObjectExists(clockObj) and linePos ~= nil
end

function M.update(dtReal, active, code)
  if M.mode() ~= '3d' then if view and view.active then hide() end return end
  if active then linger = M.LINGER_S elseif linger > 0 then linger = linger - dtReal end
  if not (active or linger > 0) or not (clockObj and simObjectExists(clockObj)) or not linePos then
    if view and view.active then hide() end
    return
  end
  local ok, err = pcall(function()
    local x, y, w, h, sw, sh = rect()
    local v = x and ensureView(x, y, w, h)
    if not v then return end
    displayT = displayT - dtReal
    if not (display and simObjectExists(display)) or displayT <= 0 then display, displayT = findDisplay(), 1 end
    local target, shift
    if display then
      target, shift = display:getWorldBox():getCenter(), 0
    else
      local box = clockObj:getWorldBox()
      target, shift = box:getCenter() + vec3(0, 0, (box.maxExtents.z - box.minExtents.z) * 0.25), M.SHIFT
    end
    local dir = viewDir(target)
    if not dir then
      dir = vec3(linePos.x - target.x, linePos.y - target.y, 0)
      if dir:squaredLength() < 0.01 then return end
      dir = dir:normalized()
    end
    local cam = target + dir * M.DIST_M
    M.dbg = { cam = cam, target = target, dir = dir }
    local look = target - cam
    local right = look:cross(vec3(0, 0, 1)):normalized()
    local half = math.tan(math.rad(M.FOV * 0.5)) * M.DIST_M * w / h
    local lookTarget = target - right * half * shift
    local q = quatFromDir(lookTarget - cam, vec3(0, 0, 1))
    bob = bob or newBob()
    if bob then
      camData.res.pos, camData.res.rot = cam, q
      if pcall(bob.update, bob, camData, 0, dtReal) then cam, q = camData.res.pos, camData.res.rot end
    end
    local updated = RenderViewManagerInstance:updateViewCamera(M.VIEW_NAME, cam.x, cam.y, cam.z, q.x, q.y, q.z, q.w,
      M.FOV, 0.1, 200, false, 0)
    v.active = updated and true or false
    guihooks.trigger('EarthRaidClockView', { show = v.active, x = x, y = y, w = w, h = h, sw = sw, sh = sh, code = code })
  end)
  if not ok then log('W', TAG, 'startclock view: ' .. tostring(err)) hide() end
end

function M.clear()
  hide()
  clockObj, linePos, linger, display = nil, nil, 0, nil
  unshim()
  local e = ext()
  if e and e.onRallySessionEnd then pcall(e.onRallySessionEnd) end
end

return M

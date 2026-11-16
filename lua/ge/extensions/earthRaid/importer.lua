-- Raid.Earth: importador de rutas. Convierte un archivo de mapa en un evento con el formato del catálogo.
-- Formatos: KML (Google Earth / My Maps / visores de mapas), KMZ (el KML comprimido; main.lua lo descomprime), GPX
-- (tracks, rutas y waypoints), GeoJSON (LineString, MultiLineString, Point) y OSM XML (vías con nombre).
-- Entiende la forma de nombrar de los organizadores y de los mapas de rallies ("Special Stage - SS 2/5 Valleseco -
-- Artenara", "Liaison Route - ...", "TC Red", "Flying Finish Red", "Stop Control", "Radio blue", "Jump"...) y la de
-- una ruta propia (cada línea es un tramo; "Enlace" / "->" / "Liaison" = enlace; "Asistencia" / "Service" = parque).
-- Puro (sin juego): texto -> datos. M.build(sources, meta) -> evento, entrada del índice | nil, error.
local M = {}

local R = 6371008.8
local rad, sin, cos, asin, sqrt, min, max, floor, abs = math.rad, math.sin, math.cos, math.asin, math.sqrt, math.min,
  math.max, math.floor, math.abs
M.MIN_STEP_M = 3            -- puntos más juntos que esto se descartan
M.MAX_POINTS = 6000
M.SAME_STAGE_M = 60         -- dos tramos con la salida y la meta a menos de esto (y casi igual de largos) son el mismo
M.ATTACH_M = 400            -- un punto suelto se asigna al tramo más cercano si está a menos de esto

local function dist(a, b)
  local a1, a2 = rad(a[1]), rad(b[1])
  local h = sin((a2 - a1) / 2) ^ 2 + cos(a1) * cos(a2) * sin(rad(b[2] - a[2]) / 2) ^ 2
  return 2 * R * asin(min(1, sqrt(h)))
end
M.dist = dist

local function length(p)
  local s = 0
  for i = 2, #p do s = s + dist(p[i - 1], p[i]) end
  return s
end

local function unescape(s)
  s = tostring(s or ''):gsub('<!%[CDATA%[(.-)%]%]>', '%1')
  s = s:gsub('<[^>]+>', ' ')
  s = s:gsub('&amp;', '&'):gsub('&lt;', '<'):gsub('&gt;', '>'):gsub('&quot;', '"'):gsub('&#39;', "'"):gsub('&apos;', "'")
  s = s:gsub('&#(%d+);', function(n) n = tonumber(n) return n and n < 128 and string.char(n) or '' end)
  return (s:gsub('%s+', ' '):gsub('^ ', ''):gsub(' $', ''))
end

local function thin(p)
  if #p < 2 then return p end
  local out = { p[1] }
  for i = 2, #p do
    if i == #p or dist(out[#out], p[i]) >= M.MIN_STEP_M then out[#out + 1] = p[i] end
  end
  if #out > M.MAX_POINTS then
    local o2, step = {}, (#out - 1) / (M.MAX_POINTS - 1)
    for i = 0, M.MAX_POINTS - 1 do o2[#o2 + 1] = out[floor(i * step + 0.5) + 1] end
    out = o2
  end
  for i, q in ipairs(out) do out[i] = { floor(q[1] * 1e6 + 0.5) / 1e6, floor(q[2] * 1e6 + 0.5) / 1e6 } end
  return out
end

-- ---- lectores: cada uno devuelve { name, lines = { { name, cat, path = {{lat, lon}...}, where = {nombres de carpeta} } },
-- points = { { name, cat, pos = {lat, lon}, where } } }

local function kmlCoords(s)
  local out = {}
  for tok in tostring(s or ''):gmatch('%S+') do
    local lon, lat = tok:match('^([%-%d%.eE]+),([%-%d%.eE]+)')
    lon, lat = tonumber(lon), tonumber(lat)
    if lat and lon then out[#out + 1] = { lat, lon } end
  end
  return out
end

function M.readKml(text)
  if type(text) ~= 'string' or not text:find('<kml', 1, true) then return nil, 'not a KML file' end
  local out = { lines = {}, points = {} }
  local stack = {}            -- carpetas abiertas: { name = ... }
  local pos = 1
  local n = #text
  while pos <= n do
    local s = text:find('<', pos, true)
    if not s then break end
    local close, tag = text:match('^<(/?)([%w_:]+)', s)
    if not tag then
      pos = s + 1
    else
      local ltag = tag:gsub('^.*:', '')
      if ltag == 'Placemark' and close == '' then
        local e = text:find('</Placemark>', s, true) or text:find('</[%w_]*:?Placemark>', s)
        local body = text:sub(s, e or n)
        pos = (e or n) + 1
        local where = {}
        for i, f in ipairs(stack) do where[i] = f.name or '' end
        local nm = unescape(body:match('<name>(.-)</name>'))
        local desc = unescape(body:match('<description>(.-)</description>'))
        local any = false
        for coords in body:gmatch('<LineString.->.-<coordinates>(.-)</coordinates>') do
          local p = kmlCoords(coords)
          if #p >= 2 then out.lines[#out.lines + 1] = { name = nm, desc = desc, path = p, where = where } any = true end
        end
        if not any then
          local pt = body:match('<Point.->.-<coordinates>(.-)</coordinates>')
          local c = pt and kmlCoords(pt)[1]
          if not c then
            -- un área (zona de reagrupamiento, parque cerrado): su centro
            local ring = body:match('<Polygon.->.-<coordinates>(.-)</coordinates>')
            local p = ring and kmlCoords(ring) or {}
            if #p > 0 then
              local la, lo = 0, 0
              for _, q in ipairs(p) do la, lo = la + q[1], lo + q[2] end
              c = { la / #p, lo / #p }
            end
          end
          if c then out.points[#out.points + 1] = { name = nm, desc = desc, pos = c, where = where } end
        end
      elseif (ltag == 'Folder' or ltag == 'Document') then
        if close == '' then
          stack[#stack + 1] = {}
        else
          stack[#stack] = nil
        end
        pos = s + 1
      elseif ltag == 'name' and close == '' and stack[#stack] and stack[#stack].name == nil then
        local e = text:find('</name>', s, true)
        local raw = text:sub(s, (e or s) + 6)
        stack[#stack].name = unescape(raw:match('<name>(.-)</name>'))
        if not out.name and #stack <= 2 and stack[#stack].name ~= '' then out.name = stack[#stack].name end
        pos = (e or s) + 1
      else
        pos = s + 1
      end
    end
  end
  return out
end

function M.readGpx(text)
  if type(text) ~= 'string' or not text:find('<gpx', 1, true) then return nil, 'not a GPX file' end
  local out = { lines = {}, points = {}, name = unescape(text:match('<metadata>.-<name>(.-)</name>')) }
  local function pts(body, tag)
    local p = {}
    for attrs in body:gmatch('<' .. tag .. '([^>]*)>') do
      local lat = tonumber(attrs:match('lat%s*=%s*["\']([%-%d%.eE]+)'))
      local lon = tonumber(attrs:match('lon%s*=%s*["\']([%-%d%.eE]+)'))
      if lat and lon then p[#p + 1] = { lat, lon } end
    end
    return p
  end
  for trk in text:gmatch('<trk>(.-)</trk>') do
    local nm = unescape(trk:match('<name>(.-)</name>'))
    for seg in trk:gmatch('<trkseg>(.-)</trkseg>') do
      local p = pts(seg, 'trkpt')
      if #p >= 2 then out.lines[#out.lines + 1] = { name = nm, path = p, where = {} } end
    end
  end
  for rte in text:gmatch('<rte>(.-)</rte>') do
    local p = pts(rte, 'rtept')
    if #p >= 2 then out.lines[#out.lines + 1] = { name = unescape(rte:match('<name>(.-)</name>')), path = p, where = {} } end
  end
  for attrs, body in text:gmatch('<wpt([^>]*)>(.-)</wpt>') do
    local lat = tonumber(attrs:match('lat%s*=%s*["\']([%-%d%.eE]+)'))
    local lon = tonumber(attrs:match('lon%s*=%s*["\']([%-%d%.eE]+)'))
    if lat and lon then out.points[#out.points + 1] = { name = unescape(body:match('<name>(.-)</name>')), pos = { lat, lon }, where = {} } end
  end
  return out
end

-- decode: un decodificador de JSON (en el juego, jsonDecode)
function M.readGeojson(text, decode)
  local ok, d = pcall(decode, text)
  if not ok or type(d) ~= 'table' then return nil, 'not a GeoJSON file' end
  local out = { lines = {}, points = {}, name = d.name }
  local feats = d.features or (d.type == 'Feature' and { d }) or {}
  for _, f in ipairs(feats) do
    local g, pr = f.geometry or {}, f.properties or {}
    local nm = tostring(pr.name or pr.title or pr.ref or '')
    local cat = pr.category or pr.type or pr.kind
    if cat and cat ~= '' then nm = tostring(cat) .. ' - ' .. nm end
    local function ll(c) return { tonumber(c[2]), tonumber(c[1]) } end
    if g.type == 'LineString' then
      local p = {}
      for _, c in ipairs(g.coordinates or {}) do p[#p + 1] = ll(c) end
      out.lines[#out.lines + 1] = { name = nm, path = p, where = {} }
    elseif g.type == 'MultiLineString' then
      for _, line in ipairs(g.coordinates or {}) do
        local p = {}
        for _, c in ipairs(line) do p[#p + 1] = ll(c) end
        out.lines[#out.lines + 1] = { name = nm, path = p, where = {} }
      end
    elseif g.type == 'Point' and g.coordinates then
      out.points[#out.points + 1] = { name = nm, pos = ll(g.coordinates), where = {} }
    end
  end
  return out
end

-- OSM XML: las vías con nombre, unidas por sus extremos (las de una ruta exportada de OpenStreetMap)
function M.readOsm(text)
  if type(text) ~= 'string' or not text:find('<osm', 1, true) then return nil, 'not an OSM file' end
  local nodes = {}
  for attrs in text:gmatch('<node([^>]*)>') do
    local id = attrs:match('id%s*=%s*["\'](%-?%d+)')
    local lat = tonumber(attrs:match('lat%s*=%s*["\']([%-%d%.eE]+)'))
    local lon = tonumber(attrs:match('lon%s*=%s*["\']([%-%d%.eE]+)'))
    if id and lat and lon then nodes[id] = { lat, lon } end
  end
  local out = { lines = {}, points = {} }
  local byName = {}
  for body in text:gmatch('<way[^>]*>(.-)</way>') do
    local refs = {}
    for r in body:gmatch('<nd%s+ref%s*=%s*["\'](%-?%d+)') do refs[#refs + 1] = r end
    local nm = body:match('<tag%s+k%s*=%s*["\']name["\']%s+v%s*=%s*["\']([^"\']*)') or ''
    if #refs >= 2 then
      byName[nm] = byName[nm] or {}
      table.insert(byName[nm], refs)
    end
  end
  for nm, ways in pairs(byName) do
    -- encadenar las vías del mismo nombre por sus extremos
    while #ways > 0 do
      local chain = table.remove(ways, 1)
      local grew = true
      while grew do
        grew = false
        for i = #ways, 1, -1 do
          local w = ways[i]
          if w[1] == chain[#chain] then for k = 2, #w do chain[#chain + 1] = w[k] end table.remove(ways, i) grew = true
          elseif w[#w] == chain[1] then
            local nc = {}
            for k = 1, #w - 1 do nc[#nc + 1] = w[k] end
            for _, r in ipairs(chain) do nc[#nc + 1] = r end
            chain = nc table.remove(ways, i) grew = true
          end
        end
      end
      local p = {}
      for _, r in ipairs(chain) do if nodes[r] then p[#p + 1] = nodes[r] end end
      if #p >= 2 then out.lines[#out.lines + 1] = { name = unescape(nm), path = p, where = {} } end
    end
  end
  return out
end

-- ---- clasificación por nombre ---------------------------------------------------------------------------------------

local function low(s) return tostring(s or ''):lower() end
local function has(s, ...)
  for _, w in ipairs({ ... }) do if s:find(w, 1, true) then return true end end
  return false
end

-- "Special Stage - SS 2/5 Valleseco" -> 'Special Stage', 'SS 2/5 Valleseco'
local function splitCat(name)
  local a, b = tostring(name or ''):match('^(.-)%s+%-%s+(.+)$')
  if a and #a <= 32 then return a, b end
  return '', tostring(name or '')
end

-- línea: 'ss' | 'shakedown' | 'liaison'
function M.lineKind(name, where)
  local n = low(name)
  local ctx = low(table.concat(where or {}, ' / '))
  if has(n, 'liaison', 'enlace', 'link ', 'link:', 'transfer', '->', 'road section', 'warming zone', 'tramo de enlace', 'podium') then
    return 'liaison'
  end
  if has(n, 'shakedown', 'test', 'qualifying', ' qs ') or (has(ctx, 'shakedown') and not has(n, 'special stage', 'ss ')) then
    return 'shakedown'
  end
  return 'ss'
end

-- punto: tipo
function M.pointKind(name)
  local n = low(name)
  if has(n, 'tyre warming', 'twz') then return 'twz' end
  if has(n, 'flying finish', 'finish', 'meta lanzada', 'llegada') then return 'finish' end
  if has(n, 'stop') then return 'stop' end
  if n:match('^start') or has(n, 'salida', ' start') then return 'start' end
  if has(n, 'radio') then return 'radio' end
  if has(n, 'jump', 'salto') then return 'jump' end
  if has(n, 'sand bag', 'chicane', 'chicano') then return 'chicane' end
  if has(n, 'no cut', 'attention', 'atención', 'atencion', 'caution', 'danger', 'peligro') then return 'caution' end
  if has(n, 'service', 'asistencia', 'parque de asistencia') then return 'service' end
  if has(n, 'refuel', 'repostaje', 'gas station', 'petrol') then return 'refuel' end
  if has(n, 'regroup', 'reagrup') then return 'regroup' end
  if has(n, 'parc ferm', 'parque cerrado') then return 'parcFerme' end
  if has(n, 'passage control', 'control de paso') then return 'passageControl' end
  if n:match('^tc') or has(n, 'time control', 'control horario', ' tc ') then return 'tc' end
  if has(n, 'amb', 'first aid', 'crane', 'grúa', 'fire', 'bomberos', 'miv', 'safety car', 'medical', 'médico') then return 'safety' end
  return 'other'
end

-- "SS 2/5 Valleseco Artenara" -> { 2, 5 }, "Valleseco Artenara", superespecial?
function M.runsOf(text)
  local t = tostring(text or '')
  local sss, nums, rest = t:match('^%s*([Ss][Ss][Ss]?)%s*([%d][%d%s/,%-y&]*)(.*)$')
  if not sss then
    nums, rest = t:match('^%s*[Tt][Cc]%s*([%d][%d%s/,%-]*)(.*)$')
    if not nums then nums, rest = t:match('^%s*[Tt]ramo%s*([%d][%d%s/,%-]*)(.*)$') end
    if not nums then nums, rest = t:match('^%s*[Ss]tage%s*([%d][%d%s/,%-]*)(.*)$') end
    if not nums then nums, rest = t:match('^%s*[Pp]%.?[Ee]%.?%s*([%d][%d%s/,%-]*)(.*)$') end
  end
  if not nums then return nil, t, false end
  local runs = {}
  for d in nums:gmatch('%d+') do runs[#runs + 1] = tonumber(d) end
  rest = (rest or ''):gsub('^[%s%-:.–]+', ''):gsub('%s+$', '')
  return runs, rest, sss and #sss == 3
end

local function prettyTitle(s)
  s = tostring(s or ''):gsub('%s+%-%s*', ' – '):gsub('%s*%-%s+', ' – '):gsub('%s+', ' ')
  return (s:gsub('^%s+', ''):gsub('%s+$', ''))
end

-- ---- montaje del evento ------------------------------------------------------------------------------------------------

local function cumulative(path)
  local c = { 0 }
  for i = 2, #path do c[i] = c[i - 1] + dist(path[i - 1], path[i]) end
  return c
end
local function nearestOn(path, cum, pos)
  local bd, bi = math.huge, 1
  for i, p in ipairs(path) do
    local d = dist(p, pos)
    if d < bd then bd, bi = d, i end
  end
  return bd, cum[bi], bi
end
local function reverse(t) local r = {} for i = #t, 1, -1 do r[#r + 1] = t[i] end return r end
local function key(where) return table.concat(where or {}, ' / ') end
local function slug(s)
  s = low(s)
  for _, r in ipairs({ { 'á', 'a' }, { 'à', 'a' }, { 'ä', 'a' }, { 'Á', 'a' }, { 'é', 'e' }, { 'è', 'e' }, { 'ë', 'e' },
    { 'É', 'e' }, { 'í', 'i' }, { 'ì', 'i' }, { 'ï', 'i' }, { 'Í', 'i' }, { 'ó', 'o' }, { 'ò', 'o' }, { 'ö', 'o' },
    { 'Ó', 'o' }, { 'ú', 'u' }, { 'ù', 'u' }, { 'ü', 'u' }, { 'Ú', 'u' }, { 'ñ', 'n' }, { 'Ñ', 'n' }, { 'ç', 'c' } }) do
    s = s:gsub(r[1], r[2])
  end
  return (s:gsub('[^%w]+', '-'):gsub('^%-+', ''):gsub('%-+$', ''))
end
M.slug = slug

-- sources: lista de lecturas (M.readKml...); meta: datos del jugador (name, short, dates, country, city, region,
-- championship, organizer, type, surface, link, logo, description). Devuelve evento, entrada del índice, informe.
function M.build(sources, id, meta)
  meta = meta or {}
  local lines, points, docName = {}, {}, nil
  for _, src in ipairs(sources) do
    docName = docName or src.name
    for _, l in ipairs(src.lines or {}) do lines[#lines + 1] = l end
    for _, p in ipairs(src.points or {}) do points[#points + 1] = p end
  end
  local report = { lines = #lines, points = #points, warnings = {} }
  if #lines == 0 then return nil, 'no lines (tramos) in the file' end

  -- 1. tramos y enlaces
  local stages, liaisons = {}, {}
  local perKey = {}
  for _, l in ipairs(lines) do
    local cat, nm = splitCat(l.name)
    local kind = M.lineKind(l.name, l.where)
    if kind == 'liaison' then
      local path = thin(l.path)
      liaisons[#liaisons + 1] = { name = nm ~= '' and nm or l.name, leg = l.where[#l.where - 1] or l.where[1],
        lengthM = floor(length(l.path) + 0.5), path = path }
    else
      local st = { kind = kind, name = l.name, road = nm, where = l.where, raw = l.path, hazards = {} }
      stages[#stages + 1] = st
      local k = key(l.where)
      perKey[k] = (perKey[k] or 0) + 1
    end
  end
  if #stages == 0 then return nil, 'no special stages in the file (only liaisons)' end

  -- 2. puntos de cada tramo: los de su misma carpeta si en ella solo está ese tramo; si no, al más cercano
  for _, st in ipairs(stages) do st.pts = {} end
  local function nearestStage(pos)
    local best, bd = nil, M.ATTACH_M
    for _, st in ipairs(stages) do
      for _, q in ipairs({ st.raw[1], st.raw[#st.raw] }) do
        local d = dist(q, pos)
        if d < bd then best, bd = st, d end
      end
    end
    return best
  end
  local evPoints = {}
  for _, p in ipairs(points) do
    local kind = M.pointKind(p.name)
    p.kind = kind
    local owner
    local k = key(p.where)
    if perKey[k] == 1 then
      for _, st in ipairs(stages) do if key(st.where) == k then owner = st end end
    end
    if kind == 'service' or kind == 'refuel' or kind == 'regroup' or kind == 'parcFerme' or kind == 'passageControl' then
      local _, nm = splitCat(p.name)
      evPoints[#evPoints + 1] = { kind = kind, name = nm ~= '' and nm or p.name, pos = { p.pos[1], p.pos[2] } }
    else
      owner = owner or nearestStage(p.pos)
      if owner then table.insert(owner.pts, p) end
    end
  end
  -- el parque de asistencia: primero una carpeta que se llama así (su primer punto, el TC de salida del parque), y
  -- delante de cualquier otro punto "Service"
  for _, p in ipairs(points) do
    local k = low(key(p.where))
    if k:find('service park', 1, true) or k:find('parque de asistencia', 1, true) then
      table.insert(evPoints, 1, { kind = 'service', name = (p.where[#p.where] or 'Service Park'), pos = { p.pos[1], p.pos[2] } })
      break
    end
  end

  -- 3. sentido de cada tramo (la meta lanzada o el STOP al final; la salida o el TC al principio), nombre y pasadas
  for i, st in ipairs(stages) do
    local path = st.raw
    local endHint, startHint
    for _, p in ipairs(st.pts) do
      if p.kind == 'finish' or p.kind == 'stop' then endHint = endHint or p.pos end
      if p.kind == 'start' or p.kind == 'tc' then startHint = startHint or p.pos end
    end
    local flip = false
    if endHint then flip = dist(endHint, path[1]) < dist(endHint, path[#path])
    elseif startHint then flip = dist(startHint, path[#path]) < dist(startHint, path[1]) end
    if flip then path = reverse(path) report.warnings[#report.warnings + 1] = (st.road or st.name) .. ': sentido invertido (por su meta)' end
    st.lengthM = floor(length(path) + 0.5)
    st.path = thin(path)
    st.rawPoints = #path
    st.start, st.finish = st.path[1], st.path[#st.path]
    -- nombre y pasadas: de la carpeta del tramo (si es solo suya) o de su propia línea
    local folder = perKey[key(st.where)] == 1 and st.where[#st.where] or nil
    local _, lineName = splitCat(st.name)
    local runsF, restF, superF = M.runsOf(folder)
    local runsL, restL, superL = M.runsOf(lineName)
    local runs = runsF or runsL
    local title = (runsL and restL ~= '' and restL) or (runsF and restF ~= '' and restF) or
      (folder and folder ~= '' and folder) or lineName
    if st.kind == 'shakedown' then
      title = (folder and folder ~= '' and folder) or lineName
      runs = nil
    end
    st.runs = runs or {}
    st.title = prettyTitle(title)
    st.super = (superF or superL) and true or nil
    -- avisos (saltos, chicanes, no cortar) y radios, con su distancia desde la salida
    local cum = cumulative(st.path)
    st.radios = {}
    for _, p in ipairs(st.pts) do
      local d, atM = nearestOn(st.path, cum, p.pos)
      if d < 150 then
        if p.kind == 'jump' or p.kind == 'chicane' or p.kind == 'caution' then
          local dup = false
          for _, h in ipairs(st.hazards) do if h.type == p.kind and abs(h.atM - atM) < 20 then dup = true end end
          if not dup then st.hazards[#st.hazards + 1] = { type = p.kind, pos = { p.pos[1], p.pos[2] }, atM = floor(atM + 0.5) } end
        elseif p.kind == 'radio' then
          st.radios[#st.radios + 1] = floor(atM + 0.5)
        end
      end
    end
    table.sort(st.hazards, function(a, b) return a.atM < b.atM end)
    table.sort(st.radios)
    st.order = i
  end

  -- 4. el mismo tramo dibujado dos veces (una por pasada): uno solo con las dos pasadas
  local merged = {}
  for _, st in ipairs(stages) do
    local into
    for _, m in ipairs(merged) do
      if m.kind == st.kind and dist(m.start, st.start) < M.SAME_STAGE_M and dist(m.finish, st.finish) < M.SAME_STAGE_M
        and abs(m.lengthM - st.lengthM) < max(80, 0.05 * m.lengthM) then into = m end
    end
    if into then
      for _, r in ipairs(st.runs) do
        local dup = false
        for _, q in ipairs(into.runs) do if q == r then dup = true end end
        if not dup then into.runs[#into.runs + 1] = r end
      end
      table.sort(into.runs)
      report.warnings[#report.warnings + 1] = st.title .. ': mismo trazado que ' .. into.title .. ' (pasadas unidas)'
    else
      merged[#merged + 1] = st
    end
  end
  stages = merged

  -- 5. identificadores: ssNN por su primera pasada (o por orden), shakedown / test por su nombre
  local used = {}
  local nextFree = 1
  table.sort(stages, function(a, b)
    local ra, rb = a.runs[1] or (1000 + a.order), b.runs[1] or (1000 + b.order)
    if (a.kind == 'ss') ~= (b.kind == 'ss') then return a.kind ~= 'ss' end
    return ra < rb
  end)
  for _, st in ipairs(stages) do
    if st.kind == 'shakedown' then
      local id0 = slug(st.title)
      if id0 == '' then id0 = 'shakedown' end
      local id1, k = id0, 2
      while used[id1] do id1, k = id0 .. '-' .. k, k + 1 end
      st.id = id1
    else
      if #st.runs == 0 then
        while used[('ss%02d'):format(nextFree)] do nextFree = nextFree + 1 end
        st.runs = { nextFree }
      end
      local id1 = ('ss%02d'):format(st.runs[1])
      local k = 2
      while used[id1] do id1, k = ('ss%02d-%d'):format(st.runs[1], k), k + 1 end
      st.id = id1
    end
    used[st.id] = true
    st.raw, st.pts, st.where, st.order = nil, nil, nil, nil
  end

  -- 6. el evento
  local la1, lo1, la2, lo2 = 90, 180, -90, -180
  local function grow(p) la1, lo1, la2, lo2 = min(la1, p[1]), min(lo1, p[2]), max(la2, p[1]), max(lo2, p[2]) end
  for _, s in ipairs(stages) do for _, p in ipairs(s.path) do grow(p) end end
  for _, l in ipairs(liaisons) do for _, p in ipairs(l.path) do grow(p) end end
  local r6 = function(v) return floor(v * 1e5 + 0.5) / 1e5 end
  local bbox = { r6(la1), r6(lo1), r6(la2), r6(lo2) }
  local centre = { r6((la1 + la2) / 2), r6((lo1 + lo2) / 2) }
  local radius = 0
  for _, q in ipairs({ { la1, lo1 }, { la2, lo2 } }) do radius = max(radius, dist(centre, q)) end
  local name = meta.name and meta.name ~= '' and meta.name or docName or id
  local surface = meta.surface and meta.surface ~= '' and meta.surface or 'asphalt'
  local ssKm, total = 0, 0
  local ssCount = 0
  for _, s in ipairs(stages) do
    s.surface = s.surface or surface
    if s.kind == 'ss' then ssCount = ssCount + 1 ssKm = ssKm + s.lengthM * max(1, #s.runs) end
  end
  for _, l in ipairs(liaisons) do total = total + l.lengthM end
  local year = tostring(name):match('(20%d%d)') or tostring(name):match('(19%d%d)')
  local ev = { format = 1, id = id, name = name, type = meta.type or 'rally', surface = surface,
    dates = meta.dates, country = meta.country, source = meta.source or 'import', link = meta.link,
    bbox = bbox, centre = centre, stages = stages, liaisons = liaisons, points = evPoints }
  local entry = { id = id, name = name, short = meta.short, type = ev.type, surface = surface, dates = meta.dates,
    country = meta.country, city = meta.city, region = meta.region, championship = meta.championship,
    organizer = meta.organizer, description = meta.description, link = meta.link, source = ev.source,
    year = year and tonumber(year) or nil, centre = centre, bbox = bbox, radiusKm = floor(radius / 100 + 0.5) / 10,
    stageCount = ssCount, stageKm = floor(ssKm / 100 + 0.5) / 10, liaisonKm = floor(total / 100 + 0.5) / 10,
    stages = {} }
  for _, s in ipairs(stages) do
    entry.stages[#entry.stages + 1] = { id = s.id, title = s.title, km = floor(s.lengthM / 10 + 0.5) / 100,
      start = s.start, kind = s.kind, runs = s.runs }
  end
  report.stages, report.liaisons, report.eventPoints = #stages, #liaisons, #evPoints
  return ev, entry, report
end

-- Lo que se puede deducir del archivo para rellenar la ficha (el jugador lo corrige en el menú)
function M.guessMeta(ev, entry)
  local g = { name = ev.name, short = nil, type = 'rally', surface = ev.surface }
  local n = low(ev.name)
  if has(n, 'raid', 'dakar', 'baja', 'cross country', 'rally-raid') then g.type = 'raid' end
  if has(n, 'wrc') then g.championship = 'WRC' elseif has(n, 'erc') then g.championship = 'ERC' end
  local short = tostring(ev.name or ''):gsub('%s*20%d%d%s*', ' '):gsub('^%d+%.?%s*', ''):gsub('%s+', ' ')
  g.short = (short:gsub('^%s+', ''):gsub('%s+$', ''))
  g.year = entry and entry.year
  return g
end

return M

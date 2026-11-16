"""Raid.Earth: construye un paquete de eventos (index.json + events/*.json) a partir de los trazados que publican
los organizadores (KMZ, KML o GPX), listados en un sources.json.

    python build_catalog.py sources.json salida/            # descarga (con caché) y convierte todo
    python build_catalog.py sources.json salida/ --only sierra-morena-2026

Cada fuente de sources.json:
    { "id": "sierra-morena-2026", "url": "https://...kmz"  (o "file": "ruta/local.kmz"),
      "name": "43 Rally Sierra Morena 2026", "type": "rally", "surface": "asphalt", "dates": "2026-04-17/2026-04-19",
      "country": "es", "city": "Córdoba", "region": "Andalucía", "championship": "ERC · S-CER",
      "organizer": "...", "source": "KMZ oficial (web del organizador)", "description": "...", "logo": "logo.png" }

Descarga con educación: respeta robots.txt, se identifica, espera entre peticiones y guarda lo descargado en
.cache/ para no repetir. Solo para archivos que el organizador publica para descargar; nada de raspar páginas
que no lo permiten (rally-maps.com, por ejemplo, no ofrece exportación ni condiciones de uso públicas).

Clasificación (por el nombre de la línea o de su carpeta, en español o inglés):
    tramo   SS / TC / PE / tramo / special stage / stage / shakedown / QS
    enlace  enlace / liaison / transfer / road section / "->"
    puntos  salida/start, meta/flying finish, asistencia/service, repostaje/refuel, control de paso/passage
"""
import argparse, hashlib, html, io, json, math, os, re, sys, time, urllib.parse, urllib.request, urllib.robotparser, zipfile
import xml.etree.ElementTree as ET

UA = 'RaidEarthCatalog/0.5 (+https://github.com/; BeamNG.Earth add-on catalogue builder)'
DELAY_S = 2.0
TOL_STAGE_M, TOL_LIAISON_M = 1.0, 3.0

# ---- geometría ---------------------------------------------------------------------------------------------------------

def hav(a, b):
    R = 6371008.8
    la1, la2 = math.radians(a[0]), math.radians(b[0])
    h = math.sin((la2 - la1) / 2) ** 2 + math.cos(la1) * math.cos(la2) * math.sin(math.radians(b[1] - a[1]) / 2) ** 2
    return 2 * R * math.asin(min(1, math.sqrt(h)))

def length(p): return sum(hav(p[i], p[i + 1]) for i in range(len(p) - 1))

def simplify(pts, tol):
    """Douglas-Peucker en metros (plano local)."""
    if len(pts) < 3: return pts
    la0 = math.radians(pts[0][0])
    xy = [((p[1] - pts[0][1]) * 111195 * math.cos(la0), (p[0] - pts[0][0]) * 111195) for p in pts]
    keep = [False] * len(pts); keep[0] = keep[-1] = True
    st = [(0, len(pts) - 1)]
    while st:
        a, b = st.pop()
        ax, ay = xy[a]; bx, by = xy[b]; dx, dy = bx - ax, by - ay; L = math.hypot(dx, dy)
        md, mi = 0, -1
        for i in range(a + 1, b):
            px, py = xy[i]
            d = abs(dx * (ay - py) - (ax - px) * dy) / L if L > 0 else math.hypot(px - ax, py - ay)
            if d > md: md, mi = d, i
        if md > tol: keep[mi] = True; st += [(a, mi), (mi, b)]
    return [p for p, k in zip(pts, keep) if k]

def r6(p): return [round(p[0], 6), round(p[1], 6)]

# ---- descarga -----------------------------------------------------------------------------------------------------------

_robots = {}
def allowed(url):
    u = urllib.parse.urlparse(url)
    base = f'{u.scheme}://{u.netloc}'
    if base not in _robots:
        rp = urllib.robotparser.RobotFileParser(base + '/robots.txt')
        try: rp.read()
        except Exception: rp = None
        _robots[base] = rp
    rp = _robots[base]
    return rp is None or rp.can_fetch(UA, url)

def fetch(url, cache):
    os.makedirs(cache, exist_ok=True)
    path = os.path.join(cache, hashlib.sha1(url.encode()).hexdigest() + os.path.splitext(urllib.parse.urlparse(url).path)[1])
    if os.path.exists(path): return open(path, 'rb').read()
    if not allowed(url): raise RuntimeError('robots.txt no permite ' + url)
    time.sleep(DELAY_S)
    with urllib.request.urlopen(urllib.request.Request(url, headers={'User-Agent': UA}), timeout=60) as r:
        data = r.read()
    open(path, 'wb').write(data)
    return data

# ---- lectura ------------------------------------------------------------------------------------------------------------

STAGE_RE = re.compile(r'\b(ss|tc|pe|tramo|special stage|stage|shakedown|qs|prueba especial|power stage)\b', re.I)
LIAISON_RE = re.compile(r'(enlace|liaison|transfer|road section|->|→)', re.I)

def kml_root(data):
    if data[:2] == b'PK':
        z = zipfile.ZipFile(io.BytesIO(data))
        data = z.read([n for n in z.namelist() if n.lower().endswith('.kml')][0])
    return ET.fromstring(data)

def tag(el): return el.tag.split('}')[-1]
def child(el, name):
    for c in el:
        if tag(c) == name: return c
def text(el, name):
    c = child(el, name)
    return (c.text or '').strip() if c is not None and c.text else ''
def desc_of(el):
    d = text(el, 'description')
    return re.sub(r'[\s\xa0]+', ' ', html.unescape(re.sub(r'<[^>]+>', ' ', d))).strip()
def coords_of(el):
    out = []
    for c in el.iter():
        if tag(c) == 'coordinates':
            for tok in (c.text or '').split():
                p = tok.split(',')
                if len(p) >= 2: out.append((float(p[1]), float(p[0])))
            break
    return out

def walk_kml(root):
    """(nombre, carpetas, descripción, 'line'|'point', coords) de cada Placemark."""
    out = []
    def rec(el, folders):
        for c in el:
            t = tag(c)
            if t in ('Folder', 'Document'):
                rec(c, folders + [text(c, 'name')])
            elif t == 'Placemark':
                kind = 'line' if any(tag(x) == 'LineString' for x in c.iter()) else 'point' if any(tag(x) == 'Point' for x in c.iter()) else None
                if kind: out.append((text(c, 'name'), folders, desc_of(c), kind, coords_of(c)))
    rec(root, [])
    return out

def walk_gpx(root):
    out = []
    for el in root.iter():
        t = tag(el)
        if t in ('trk', 'rte'):
            pts = [(float(p.get('lat')), float(p.get('lon'))) for p in el.iter() if tag(p) in ('trkpt', 'rtept')]
            out.append((text(el, 'name'), [], text(el, 'desc'), 'line', pts))
        elif t == 'wpt':
            out.append((text(el, 'name'), [], text(el, 'desc'), 'point', [(float(el.get('lat')), float(el.get('lon')))]))
    return out

def runs_of(name):
    m = re.search(r'\b(?:ss|tc|pe|tramo|stage)\s*\.?\s*(\d+)(?:\s*[-/]\s*(\d+))?', name, re.I)
    if not m: return []
    return [int(m.group(1))] + ([int(m.group(2))] if m.group(2) else [])

def clean_title(name):
    q = re.search(r'["“]([^"”]+)["”]', name)
    if q: t = q.group(1).strip()
    else: t = re.sub(r'^\s*(?:ss|tc|pe|tramo|stage)\s*\.?\s*\d+(?:\s*[-/]\s*\d+)?\s*[:\-–]?\s*', '', name, flags=re.I)
    t = t.strip(' "\'')
    return t.title() if t.isupper() else (t or name)

def convert(src, data):
    root = kml_root(data) if data[:2] == b'PK' or b'<kml' in data[:2000] else ET.fromstring(data)
    items = walk_gpx(root) if tag(root) == 'gpx' else walk_kml(root)
    stages, liaisons, points = [], [], []
    for name, folders, desc, kind, pts in items:
        ctx = ' / '.join(folders + [name])
        if kind == 'line' and len(pts) >= 2:
            # "A -> B" o una carpeta de enlaces: enlace aunque nombre un tramo ("Service -> Start SS 3")
            if LIAISON_RE.search(name) or any(LIAISON_RE.search(f) for f in folders):
                liaisons.append({'leg': folders[-1] if folders else '', 'name': name, 'lengthM': round(length(pts)),
                                 'path': [r6(p) for p in simplify(pts, TOL_LIAISON_M)]})
            elif STAGE_RE.search(ctx) or src.get('allLines'):
                label = name if STAGE_RE.search(name) or not folders else folders[-1] + ' ' + name
                stages.append({'kind': 'shakedown' if re.search(r'shakedown|\bqs\b', label, re.I) else 'ss', 'name': label,
                               'road': name, 'lengthM': round(length(pts)), 'rawPoints': len(pts),
                               'path': [r6(p) for p in simplify(pts, TOL_STAGE_M)], 'hazards': []})
        elif kind == 'point' and pts:
            low = (name + ' ' + desc).lower()
            k = ('start' if re.match(r'(start|salida)\b', low) and STAGE_RE.search(low) else
                 'finish' if re.search(r'flying finish|meta lanzada', low) else
                 'service' if re.search(r'asistencia|service|parque cerrado|parc', low) else
                 'refuel' if re.search(r'repost|refuel', low) else
                 'passageControl' if re.search(r'paso|passage|reagrup|regroup', low) else None)
            if k: points.append({'kind': k, 'name': name or desc[:60], 'pos': r6(pts[0])})
    # un tramo con dos pasadas puede venir dos veces (misma geometría): se juntan
    merged = []
    for s in stages:
        twin = next((m for m in merged if abs(m['lengthM'] - s['lengthM']) < 30 and hav(m['path'][0], s['path'][0]) < 50), None)
        if twin: twin['runs'] = sorted(set(twin.get('runs', []) + runs_of(s['name'])))
        else: s['runs'] = runs_of(s['name']); merged.append(s)
    n, used = 0, set()
    for s in merged:
        n += 1
        if s['kind'] == 'shakedown': s['id'], s['runs'] = 'shakedown', []
        else: s['id'] = 'ss%02d' % (s['runs'][0] if s['runs'] else n)
        base, k = s['id'], 1
        while s['id'] in used: k += 1; s['id'] = '%s_%d' % (base, k)
        used.add(s['id'])
        s['title'] = src.get('titles', {}).get(s['id']) or clean_title(s['name'])
        s.setdefault('start', s['path'][0]); s.setdefault('finish', s['path'][-1])
        s['surface'] = src.get('surface', 'asphalt')
    # los puntos de salida / meta lanzada del organizador mandan sobre los extremos de la línea
    for s in merged:
        for pt in points:
            if pt['kind'] == 'start' and hav(pt['pos'], s['path'][0]) < 300: s['start'] = pt['pos']
            if pt['kind'] == 'finish' and hav(pt['pos'], s['path'][-1]) < 300: s['finish'] = pt['pos']
    points = [p for p in points if p['kind'] not in ('start', 'finish')]
    return merged, liaisons, points

def write_event(src, stages, liaisons, points, outdir):
    allp = [p for s in stages for p in s['path']] + [p for l in liaisons for p in l['path']]
    lats = [p[0] for p in allp]; lons = [p[1] for p in allp]
    bbox = [round(min(lats), 5), round(min(lons), 5), round(max(lats), 5), round(max(lons), 5)]
    centre = [round((bbox[0] + bbox[2]) / 2, 5), round((bbox[1] + bbox[3]) / 2, 5)]
    radius = max(hav(centre, p) for p in allp)
    meta = {k: src[k] for k in ('name', 'type', 'surface', 'dates', 'country', 'source') if k in src}
    ev = {'format': 1, 'id': src['id'], **meta, 'bbox': bbox, 'centre': centre, 'stages': stages, 'liaisons': liaisons,
          'points': points}
    os.makedirs(os.path.join(outdir, 'events'), exist_ok=True)
    json.dump(ev, open(os.path.join(outdir, 'events', src['id'] + '.json'), 'w', encoding='utf-8'), ensure_ascii=False,
              separators=(',', ':'))
    ss = [s for s in stages if s['kind'] == 'ss']
    entry = {'id': src['id'], 'file': 'events/%s.json' % src['id'], **meta, 'centre': centre, 'bbox': bbox,
             'radiusKm': round(radius / 1000, 1), 'stageCount': len(ss),
             'stageKm': round(sum(s['lengthM'] * max(1, len(s['runs'])) for s in ss) / 1000, 1),
             'stages': [{'id': s['id'], 'title': s['title'], 'km': round(s['lengthM'] / 1000, 2), 'start': s['start'],
                         'surface': s['surface']} for s in stages]}
    for k in ('short', 'city', 'region', 'championship', 'organizer', 'description', 'logo', 'stageKmOfficial', 'totalKmOfficial'):
        if k in src: entry[k] = src[k]
    return entry

def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('sources'); ap.add_argument('outdir'); ap.add_argument('--only'); ap.add_argument('--name', default='pack')
    a = ap.parse_args()
    sources = json.load(open(a.sources, encoding='utf-8'))
    base = os.path.dirname(os.path.abspath(a.sources))
    idx_path = os.path.join(a.outdir, 'index.json')
    idx = json.load(open(idx_path, encoding='utf-8')) if os.path.exists(idx_path) else {'format': 1, 'name': a.name, 'events': []}
    for src in sources.get('events', sources if isinstance(sources, list) else []):
        if a.only and src['id'] != a.only: continue
        try:
            data = open(os.path.join(base, src['file']), 'rb').read() if 'file' in src else fetch(src['url'], os.path.join(base, '.cache'))
            stages, liaisons, points = convert(src, data)
            if not stages: raise RuntimeError('sin tramos en el archivo')
            entry = write_event(src, stages, liaisons, points, a.outdir)
            idx['events'] = [e for e in idx['events'] if e['id'] != src['id']] + [entry]
            print('%-28s %2d tramos %6.1f km  %2d enlaces  %d puntos' % (src['id'], entry['stageCount'], entry['stageKm'],
                  len(liaisons), len(points)))
        except Exception as e:
            print('%-28s ERROR %s' % (src.get('id'), e), file=sys.stderr)
    os.makedirs(a.outdir, exist_ok=True)
    json.dump(idx, open(idx_path, 'w', encoding='utf-8'), ensure_ascii=False, indent=1)

if __name__ == '__main__':
    main()

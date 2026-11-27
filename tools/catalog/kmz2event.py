"""KMZ de organizador -> evento Earth.Raid (JSON en lat/lon) + índice de catálogo."""
import sys, zipfile, re, html, json, math, os
import xml.etree.ElementTree as ET

src, outdir, ev_id = sys.argv[1], sys.argv[2], sys.argv[3]
meta = json.loads(sys.argv[4])
z = zipfile.ZipFile(src)
root = ET.fromstring(z.read([n for n in z.namelist() if n.lower().endswith('.kml')][0]))
NS = root.tag.split('}')[0].strip('{')
def q(t): return '{%s}%s' % (NS, t)
def name(el):
    n = el.find(q('name')); return (n.text or '').strip() if n is not None else ''
def desc(el):
    d = el.find(q('description'))
    if d is None or not d.text: return ''
    return re.sub(r'[\s\xa0]+', ' ', html.unescape(re.sub(r'<[^>]+>', ' ', d.text))).strip()
def coords(el):
    c = el.find('.//' + q('coordinates'))
    out = []
    for tok in (c.text or '').split():
        p = tok.split(',')
        out.append((float(p[1]), float(p[0])))        # lat, lon
    return out
def hav(a, b):
    R = 6371008.8
    la1, la2 = math.radians(a[0]), math.radians(b[0])
    dla, dlo = la2 - la1, math.radians(b[1] - a[1])
    h = math.sin(dla/2)**2 + math.cos(la1)*math.cos(la2)*math.sin(dlo/2)**2
    return 2*R*math.asin(math.sqrt(h))
def length(p): return sum(hav(p[i], p[i+1]) for i in range(len(p)-1))
def simplify(pts, tol):
    # Douglas-Peucker en metros (plano local), iterativo
    if len(pts) < 3: return pts
    la0 = math.radians(pts[0][0])
    xy = [((p[1]-pts[0][1])*111195*math.cos(la0), (p[0]-pts[0][0])*111195) for p in pts]
    keep = [False]*len(pts); keep[0] = keep[-1] = True
    st = [(0, len(pts)-1)]
    while st:
        a, b = st.pop()
        ax, ay = xy[a]; bx, by = xy[b]; dx, dy = bx-ax, by-ay; L = math.hypot(dx, dy)
        md, mi = 0, -1
        for i in range(a+1, b):
            px, py = xy[i]
            d = abs(dx*(ay-py) - (ax-px)*dy)/L if L > 0 else math.hypot(px-ax, py-ay)
            if d > md: md, mi = d, i
        if md > tol: keep[mi] = True; st += [(a, mi), (mi, b)]
    return [p for p, k in zip(pts, keep) if k]
def r6(p): return [round(p[0], 6), round(p[1], 6)]
def folder(parent, nm):
    for f in parent.iter(q('Folder')):
        if name(f) == nm: return f

TOL = 1.0
stages, liaisons, points = [], [], []

def parse_stage(f, kind):
    st = {'kind': kind, 'name': name(f), 'hazards': []}
    for pm in f.findall(q('Placemark')):
        d = desc(pm); up = d.upper()
        if pm.find('.//' + q('LineString')) is not None:
            full = coords(pm)
            st['road'] = name(pm)
            st['lengthM'] = round(length(full))
            st['path'] = [r6(p) for p in simplify(full, TOL)]
            st['rawPoints'] = len(full)
        elif pm.find('.//' + q('Point')) is not None:
            c = coords(pm)[0]
            if 'FLYING FINISH' in up: st['finish'] = r6(c)
            elif up.startswith('START'): st['start'] = r6(c)
            elif 'ATTENTION' in up or 'ATENCI' in up:
                t = 'chicane' if 'CHICANE' in up else 'jump' if 'JUMP' in up else 'variant' if 'VARIANT' in up else 'caution'
                st['hazards'].append({'type': t, 'pos': r6(c)})
            elif 'KMS' in up:
                m = re.search(r'KMS:\s*([\d.,]+)', d)
                if m: st['officialKm'] = float(m.group(1).replace(',', '.'))
    if 'path' in st:
        st.setdefault('start', st['path'][0]); st.setdefault('finish', st['path'][-1])
        stages.append(st)

doc = folder(root, 'XLIII Rallye ERC Sierra Morena 2026') if meta.get('rootFolder') is None else folder(root, meta['rootFolder'])
ss = folder(doc, 'SPECIAL STAGES')
for f in ss.iter(q('Folder')):
    if re.match(r'SS \d', name(f)): parse_stage(f, 'ss')
qs = folder(doc, 'QS SHAKEDOWN')
if qs is not None: parse_stage(qs, 'shakedown')
for i, s in enumerate(stages):
    m = re.match(r'SS (\d+)(?:-(\d+))?\s*"(.+)"', s['name'])
    if m:
        s['runs'] = [int(m.group(1))] + ([int(m.group(2))] if m.group(2) else [])
        s['title'] = m.group(3).title().replace('Vva.De', 'Villanueva de')
        s['id'] = 'ss%02d' % s['runs'][0]
    else:
        s['id'], s['title'], s['runs'] = 'shakedown', 'Los Villares (Shakedown)', []
    # marca cada aviso con su distancia desde la salida
    for h in s['hazards']:
        best, acc, bi = 1e9, 0, 0
        cum = [0]
        for k in range(len(s['path'])-1): cum.append(cum[-1] + hav(s['path'][k], s['path'][k+1]))
        for k, p in enumerate(s['path']):
            d = hav(p, h['pos'])
            if d < best: best, bi = d, k
        h['atM'] = round(cum[bi])

li = folder(doc, 'LIAISONS')
for leg in li.findall(q('Folder')):
    for pm in leg.iter(q('Placemark')):
        if pm.find('.//' + q('LineString')) is not None:
            full = coords(pm)
            liaisons.append({'leg': name(leg), 'name': name(pm), 'lengthM': round(length(full)),
                             'path': [r6(p) for p in simplify(full, 3.0)]})
for fname, kind in (('REFUELING', 'refuel'), ('PASSAGE CONTROLS', 'passageControl')):
    f = folder(doc, fname)
    if f is None: continue
    for pm in f.iter(q('Placemark')):
        d = desc(pm); m = re.match(r'(.+?)\s+GPS:', d)
        points.append({'kind': kind, 'name': (m.group(1) if m else d[:60]).strip(), 'pos': r6(coords(pm)[0])})
if liaisons: points.insert(0, {'kind': 'service', 'name': meta.get('serviceName', 'Service Park'), 'pos': liaisons[0]['path'][0]})

allp = [p for s in stages for p in s['path']] + [p for l in liaisons for p in l['path']]
lats = [p[0] for p in allp]; lons = [p[1] for p in allp]
bbox = [round(min(lats), 5), round(min(lons), 5), round(max(lats), 5), round(max(lons), 5)]
centre = [round((bbox[0]+bbox[2])/2, 5), round((bbox[1]+bbox[3])/2, 5)]
radius = max(hav(centre, p) for p in allp)

event = {'format': 1, 'id': ev_id, **{k: meta[k] for k in ('name', 'type', 'surface', 'dates', 'country', 'source')},
         'bbox': bbox, 'centre': centre, 'stages': stages, 'liaisons': liaisons, 'points': points}
os.makedirs(os.path.join(outdir, 'events'), exist_ok=True)
with open(os.path.join(outdir, 'events', ev_id + '.json'), 'w', encoding='utf-8') as fh:
    json.dump(event, fh, ensure_ascii=False, separators=(',', ':'))

idx_path = os.path.join(outdir, 'index.json')
idx = json.load(open(idx_path, encoding='utf-8')) if os.path.exists(idx_path) else {'format': 1, 'events': []}
idx['events'] = [e for e in idx['events'] if e['id'] != ev_id]
idx['events'].append({'id': ev_id, 'file': 'events/%s.json' % ev_id, 'name': meta['name'], 'type': meta['type'],
    'surface': meta['surface'], 'dates': meta['dates'], 'country': meta['country'], 'centre': centre, 'bbox': bbox,
    'radiusKm': round(radius/1000, 1), 'stageCount': sum(1 for s in stages if s['kind'] == 'ss'),
    'stageKm': round(sum(s['lengthM']*max(1, len(s['runs'])) for s in stages if s['kind'] == 'ss')/1000, 1),
    'stages': [{'id': s['id'], 'title': s['title'], 'km': round(s['lengthM']/1000, 2), 'start': s['start']} for s in stages]})
json.dump(idx, open(idx_path, 'w', encoding='utf-8'), ensure_ascii=False, indent=1)

print('%-10s %-34s %8s %8s %6s %6s %s' % ('id', 'title', 'medido', 'oficial', 'ptsIn', 'ptsOut', 'avisos'))
for s in stages:
    print('%-10s %-34s %8.2f %8s %6d %6d %s' % (s['id'], s['title'], s['lengthM']/1000, s.get('officialKm', '-'),
          s['rawPoints'], len(s['path']), [(h['type'], h['atM']) for h in s['hazards']]))
print('enlaces', len(liaisons), 'km', round(sum(l['lengthM'] for l in liaisons)/1000, 1), '| puntos', [(p['kind'], p['name']) for p in points])
print('bbox', bbox, 'centre', centre, 'radiusKm', round(radius/1000, 1))
print('bytes', os.path.getsize(os.path.join(outdir, 'events', ev_id + '.json')))

import json,math
objs=[json.loads(l) for l in open('_utah_prefab.json',encoding='utf-8') if l.strip().startswith('{')]
def nm(o): return (o.get('shapeName') or o.get('filename') or o.get('name') or '').split('/')[-1]
def P(o): return o['position']
def yaw_rel(o,f):
    r=o.get('rotationMatrix')
    if not r: return None
    yx,yy=r[3],r[4]
    return round(math.degrees(math.atan2(yx*f[1]-yy*f[0], yx*f[0]+yy*f[1]))*-1)
def report(kind, pairname, near_name, R=16):
    S=[o for o in objs if nm(o)==pairname]
    used=set(); frames=[]
    for i,a in enumerate(S):
        if i in used: continue
        best=None
        for j,b in enumerate(S):
            if j==i or j in used: continue
            d=math.dist(P(a)[:2],P(b)[:2])
            if d<12 and (best is None or d<best[0]): best=(d,j)
        if not best: continue
        used|={i,best[1]}; b=S[best[1]]
        mx,my=(P(a)[0]+P(b)[0])/2,(P(a)[1]+P(b)[1])/2
        px,py=P(b)[0]-P(a)[0],P(b)[1]-P(a)[1]; L=math.hypot(px,py)
        f=(-py/L,px/L)
        # sentido: hacia el objeto near_name mas cercano (semaforo en salida, STOP en meta...)
        T=[o for o in objs if nm(o)==near_name]
        t=min(T,key=lambda o:math.dist(P(o)[:2],(mx,my)))
        if (P(t)[0]-mx)*f[0]+(P(t)[1]-my)*f[1]<0: f=(-f[0],-f[1])
        frames.append(((mx,my,(P(a)[2]+P(b)[2])/2),f,round(L,2)))
    for (m,f,L) in frames:
        print('== %s en (%.1f,%.1f) separacion carteles %.2f m'%(kind,m[0],m[1],L))
        rx,ry=f[1],-f[0]; rows=[]
        for o in objs:
            p=o.get('position')
            if not p: continue
            dx,dy=p[0]-m[0],p[1]-m[1]
            if dx*dx+dy*dy>R*R: continue
            rows.append((round(dx*f[0]+dy*f[1],2),round(dx*rx+dy*ry,2),round(p[2]-m[2],2),yaw_rel(o,f),nm(o)))
        for r in sorted(rows): print('  fwd=%6.2f right=%6.2f z=%5.2f yawY=%5s  %s'%r)
import sys
report('SALIDA','s_rally_signboard_start.dae','s_rally_start_tree.dae', float(sys.argv[1]) if len(sys.argv)>1 else 16)

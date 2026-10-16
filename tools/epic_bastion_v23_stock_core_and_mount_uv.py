#!/usr/bin/env python3
"""Restore matching stock-Bastion core UVs and retile visible cannon housings only.
Safe interim visual repair. Do not remove unverified cradle geometry.
"""
import sys,urllib.request,collections,hashlib,copy,math
from pathlib import Path
sys.path.insert(0,'tools')
from build_epic_bastion_model import load,save,walk
F=Path('objects3d/Units/legbastiont3.s3o')
m=load(str(F));ps={p.name:p for p in walk(m.root)}
before={n:(p.verts[:],p.indices[:],p.offset) for n,p in ps.items()}
url='https://raw.githubusercontent.com/beyond-all-reason/Beyond-All-Reason/master/objects3d/Units/legbastion.s3o'
stockfile=Path('/tmp/legbastion_stock_reference.s3o')
stockfile.write_bytes(urllib.request.urlopen(url,timeout=60).read())
stock=load(str(stockfile))
src={p.name:p for p in walk(stock.root)}
base=ps['base']
# Exact 6-float position+normal fingerprint prevents corruption of non-stock added geometry.
def key(v):return tuple(round(x,4) for x in v[:6])
uvs=collections.defaultdict(set)
for p in walk(stock.root):
 if p.name not in {'base','turret','ring','ring2','ring3','ring4'}:continue
 for v in p.verts:uvs[key(v)].add((round(v[6],7),round(v[7],7)))
stats=collections.Counter()
restored=[]
for v in base.verts:
 matches=uvs.get(key(v))
 if matches and len(matches)==1:
  u,w=next(iter(matches));restored.append((*v[:6],u,w))
  stats['exact_stock_matches']+=1
  if abs(v[6]-u)>1e-6 or abs(v[7]-w)>1e-6:stats['restored_wrong_core_uv']+=1
 else:
  restored.append(v);stats['not_safely_mappable']+=1
base.verts=restored
assert stats['exact_stock_matches']>3000,stats
# Remap cannon housings, not the barrel pieces. Housing UVs from the large
# donor span unrelated regions resulting in multicolor rectangular patches.
# Consistent bronze Legion armor bounded to well-isolated I036 atlas plate.
plate=(796,976,1064,1140)
def uv(x,y):
 x0,y0,x1,y1=plate
 x=x0+15+(x1-x0-30)*max(.05,min(.95,x))
 y=y0+12+(y1-y0-24)*max(.05,min(.95,y))
 return x/4096,1-y/4096
for i in (1,2,3):
 p=ps[f'gauss{i}_pitch']
 assert len(p.indices)==384 and len(p.verts)>=250,(i,len(p.indices),len(p.verts))
 vs=list(p.verts);out=[]
 lo=[min(v[k] for v in vs) for k in range(3)]
 hi=[max(v[k] for v in vs) for k in range(3)]
 for j,v in enumerate(vs):
  # local planar projection; all color stays inside coherent, neutral bronze armor.
  # UVs are NOT taken from atlas areas containing team-colored tracks or stripes.
  x=(v[0]-lo[0])/max(1e-6,hi[0]-lo[0])
  y=(v[1]-lo[1])/max(1e-6,hi[1]-lo[1])
  out.append((*v[:6],*uv(x,y)))
 p.verts=out
 stats[f'gauss{i}_housing_recolored_vertices']=len(vs)
for n,p in ps.items():
 ov,oi,off=before[n]
 assert p.indices==oi and p.offset==off and len(p.verts)==len(ov),n
 assert all(a[:6]==b[:6] for a,b in zip(p.verts,ov)),n
 assert (n in {'base','gauss1_pitch','gauss2_pitch','gauss3_pitch'} or p.verts==ov),n
assert stats['restored_wrong_core_uv']>0,stats
print('STOCK_LEGION_UV_RESTORE',dict(stats))
if '--apply' in sys.argv:
 save(m,str(F));print('WROTE',F,'SHA256',hashlib.sha256(F.read_bytes()).hexdigest())
else:print('DRY_RUN: No model changed')

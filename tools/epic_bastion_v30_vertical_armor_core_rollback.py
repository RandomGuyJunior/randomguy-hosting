#!/usr/bin/env python3
"""V30: restore central turretbase/pylon UV from V27 and remap actual tall cannon-support armor.
Leaves horizontal cannon seats, cannon meshes, animated rings, geometry, normals and pivots unchanged.
"""
import sys, math, collections, urllib.request, hashlib
from pathlib import Path
sys.path.insert(0,'tools')
from build_epic_bastion_model import load, save, walk
P=Path('objects3d/Units/legbastiont3.s3o')
m=load(str(P));pieces={p.name:p for p in walk(m.root)}
old={n:(p.verts[:],p.indices[:],p.offset,p.primitive) for n,p in pieces.items()}
base=pieces['base']
tris=[base.indices[i:i+3] for i in range(0,len(base.indices),3)]
# Recover V27 core UV by matching full triangle corner geometry, not broad radial assignment.
sha='537f3d0647970c73069e7b66f1d4373d7e8bd6ac'
url=f'https://raw.githubusercontent.com/RandomGuyJunior/randomguy-hosting/{sha}/objects3d/Units/legbastiont3.s3o'
ref=Path('/tmp/legbastion_v27_core_reference.s3o')
ref.write_bytes(urllib.request.urlopen(url,timeout=60).read())
donor=load(str(ref));db=next(p for p in walk(donor.root) if p.name=='base')
def corner_key(v):return tuple(round(x,4) for x in v[:6])
def face_key(vs):return tuple(sorted(corner_key(v) for v in vs))
lookup=collections.defaultdict(list)
for k in range(0,len(db.indices),3):
 vs=[db.verts[j] for j in db.indices[k:k+3]]
 lookup[face_key(vs)].append({corner_key(v):(v[6],v[7]) for v in vs})
# Build connected face groups using geometric positions (resilient to UV seams).
owners=collections.defaultdict(list)
for fi,ids in enumerate(tris):
 for vi in ids:owners[tuple(round(x,3) for x in base.verts[vi][:3])].append(fi)
parent=list(range(len(tris)))
def find(i):
 while parent[i]!=i:parent[i]=parent[parent[i]];i=parent[i]
 return i
for hits in owners.values():
 first=find(hits[0])
 for x in hits[1:]:
  y=find(x)
  if y!=first:parent[y]=first
groups=collections.defaultdict(list)
for fi in range(len(tris)):groups[find(fi)].append(fi)
byfirst={min(g):g for g in groups.values()}
# These components are the upward armor panels either side of each horizontal cannon mount.
# All twelve groups occur in three symmetric sets and are geographically distinct
# from the horizontal seats (starts 0,120,240) and from the central turretbase.
vertical_starts=(580,608,636,672,736,764,792,828,892,920,948,984)
target=set()
for st in vertical_starts:
 g=byfirst.get(st)
 assert g and len(g) in (28,36),('vertical panel component moved',st,len(g) if g else None)
 vv=[base.verts[vid] for fi in g for vid in tris[fi]]
 yy=[v[1] for v in vv];rr=[math.hypot(v[0],v[2]) for v in vv]
 assert min(yy)<15 and max(yy)>=130,(st,min(yy),max(yy))
 assert min(rr)>19 and max(rr)<51,(st,min(rr),max(rr))
 target.update(g)
assert len(target)==384,len(target)
# This core-only zone follows the central axis and excludes every vertical plate.
# Restore from the last version BEFORE V28's broad central retexturing.
central=set()
for fi,ids in enumerate(tris):
 vs=[base.verts[j] for j in ids]
 cx=sum(v[0] for v in vs)/3;cy=sum(v[1] for v in vs)/3;cz=sum(v[2] for v in vs)/3
 if 90<cy<175 and math.hypot(cx,cz)<14:
  central.add(fi)
assert not target&central
# Pixel-safe I017 bronze bolted plate, I039 dark bronze recess, I031 gray channel.
# The tall supports keep their own metallic texture direction. No color-grid atlas region.
BRONZE=(930,606,1496,732)
BRONZE_EDGE=(1120,1192,1488,1504)
def uv(rect,s,t):
 x0,y0,x1,y1=rect
 s=max(.11,min(.89,s));t=max(.11,min(.89,t))
 return ((x0+(x1-x0)*s)/4096,1-(y0+(y1-y0)*t)/4096)
# Per-face UV seams avoid disturbing shared geometry or adjacent stock components.
outv=list(base.verts);outi=[];restored=0;missed=0
for fi,ids in enumerate(tris):
 if fi not in central and fi not in target:
  outi.extend(ids);continue
 vs=[base.verts[j] for j in ids]
 if fi in central:
  poss=lookup.get(face_key(vs))
  if not poss:
   missed+=1;outi.extend(ids);continue
  values=poss[0]
  if not all(corner_key(v) in values for v in vs):
   missed+=1;outi.extend(ids);continue
  for v in vs:
   u,w=values[corner_key(v)]
   outv.append((*v[:6],u,w));outi.append(len(outv)-1)
  restored+=1
  continue
 # Vertical support plate: axial projection around each radial support.
 # Uses one coherent bronze plate motif per component, not a different atlas color per polygon.
 cx=sum(v[0] for v in vs)/3;cz=sum(v[2] for v in vs)/3
 angle=math.atan2(cz,cx)
 # tangential coordinate with fixed support angular direction
 for v in vs:
  r=math.hypot(v[0],v[2])
  a=math.atan2(v[2],v[0])
  local=math.atan2(math.sin(a-angle),math.cos(a-angle))
  s=.5+local*2.6
  t=(v[1]-8)/138
  # Main bronze armor for wide vertical panels
  u,w=uv(BRONZE,s,t)
  outv.append((*v[:6],u,w));outi.append(len(outv)-1)
assert restored>=50,('too few V27 central faces recovered',restored,missed)
used=sorted(set(outi));order={o:i for i,o in enumerate(used)}
base.verts=[outv[j] for j in used]
base.indices=[order[j] for j in outi]
assert len(base.indices)==len(old['base'][1])
for i,prior_index in enumerate(old['base'][1]):
 assert base.verts[base.indices[i]][:6]==old['base'][0][prior_index][:6],('geometry changed',i)
for n,p in pieces.items():
 v,ind,off,primitive=old[n]
 assert p.offset==off and p.primitive==primitive
 if n!='base':assert p.verts==v and p.indices==ind,n
print('V30_SELECTED_VERTICAL_COMPONENTS',vertical_starts,'triangles',len(target))
print('V30_V27_CORE_UV_RESTORED_FACES',restored,'unmatched_kept_as_is',missed,'central_candidates',len(central))
print('V30_PRESERVED_CANNONS_RINGS_PIVOTS_HORIZONTAL_SEATS and every non-base piece')
if '--apply' in sys.argv:
 save(m,str(P))
 print('V30_MODEL_HASH',hashlib.sha256(P.read_bytes()).hexdigest())
else:print('V30_DRY_RUN_ONLY')

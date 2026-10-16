#!/usr/bin/env python3
"""V23: remove one independently connected OUTER cradle band, restore untouched
Bastion-derived base UVs from pre-V15 by exact geometry match, and unify the
three added mount rings in dark Legion metal. Never edit laser/ring5/cannons.
"""
import sys,urllib.request,collections,math,copy
from pathlib import Path
sys.path.insert(0,'tools')
from build_epic_bastion_model import load,save,walk
PATH=Path('objects3d/Units/legbastiont3.s3o')
m=load(str(PATH))
pieces={p.name:p for p in walk(m.root)}
snapshot={n:(p.verts[:],p.indices[:],p.offset,p.primitive) for n,p in pieces.items()}
base=pieces['base'];origverts=base.verts[:];origindex=base.indices[:]
assert base.primitive==0,base.primitive
# Component selection: shared *positions*, including UV-seam splits.
nt=len(base.indices)//3;dsu=list(range(nt))
def find(x):
 while dsu[x]!=x:dsu[x]=dsu[dsu[x]];x=dsu[x]
 return x
def union(a,b):
 a=find(a);b=find(b)
 if a!=b:dsu[b]=a
seen={}
for face in range(nt):
 for vi in base.indices[3*face:3*face+3]:
  v=base.verts[vi];key=tuple(round(c,3) for c in v[:3])
  union(face,seen.setdefault(key,face))
groups=collections.defaultdict(list)
for i in range(nt):groups[find(i)].append(i)
def limits(faces):
 v=[base.verts[j] for t in faces for j in base.indices[3*t:3*t+3]]
 ys=[x[1] for x in v];rs=[math.hypot(x[0],x[2]) for x in v]
 return (min(ys),max(ys),min(rs),max(rs))
# Outer ring is the standalone 384-triangle annulus ~Y174..177 R35..42.
outer=[fs for fs in groups.values() if len(fs)==384 and
       173.5<limits(fs)[0]<175 and 176<limits(fs)[1]<178 and
       34<limits(fs)[2]<36 and 40<limits(fs)[3]<43]
assert len(outer)==1,[(len(fs),limits(fs)) for fs in outer]
removed=set(outer[0])
base.indices=[vi for i in range(nt) if i not in removed for vi in origindex[3*i:3*i+3]]
print('REMOVED_OUTER_CRADLE_TRIANGLES',len(removed),'bounds',limits(outer[0]))
# Pre-v15 original Bastion-derived mesh is the only reliable geometry-matched UV donor.
pre='681351216bc87bb80ed44433ab769d46a05c4605'
reference=Path('/tmp/v23_old_base.s3o')
reference.write_bytes(urllib.request.urlopen(
 f'https://raw.githubusercontent.com/RandomGuyJunior/randomguy-hosting/{pre}/objects3d/Units/legbastiont3.s3o',timeout=65).read())
donor=next(x for x in walk(load(str(reference)).root) if x.name=='base')
def key(v):return tuple(round(c,4) for c in v[:6])
uvid=collections.defaultdict(set)
for v in donor.verts:uvid[key(v)].add((round(v[6],7),round(v[7],7)))
# Important: use donor UVs only where mapping is unique. Existing seam variants are not guessed.
newverts=[]
matched=changed=ambiguous=0
for v in base.verts:
 opts=uvid.get(key(v))
 if opts and len(opts)==1:
  u,w=next(iter(opts));matched+=1
  if abs(u-v[6])>1e-5 or abs(w-v[7])>1e-5:changed+=1
  newverts.append((*v[:6],u,w))
 else:
  if opts:ambiguous+=1
  newverts.append(v)
assert matched>8000,matched
print('RESTORED_BASTION_BASE_UVS',matched,'actually_changed',changed,'ambiguous',ambiguous)
# 3 identical mount rings each have 96 triangles at ~Y100-114, R52-60.
# Their original UVs were patchwork; use a single flat dark bronze metal
# section from known catalog I018. No alternating random colors.
mounts=[]
for fs in groups.values():
 y0,y1,r0,r1=limits(fs)
 if len(fs)==96 and 99<y0<101 and 113<y1<115 and 51<r0<53 and 59<r1<61:
  mounts.append(fs)
assert len(mounts)==3,[(len(fs),limits(fs)) for fs in mounts]
# Avoid UV change of shared vertices with unrelated faces.
inmount={j for fs in mounts for t in fs for j in origindex[3*t:3*t+3]}
outmount={j for t in range(nt) if not any(t in fs for fs in mounts) for j in origindex[3*t:3*t+3]}
safe=inmount-outmount
assert len(safe)>90,len(safe)
# Use very narrow coherent sample of dark Legion flat armor island I018.
# Position-based deterministic variation keeps colors unified, not striped.
for vi in safe:
 v=newverts[vi]
 u=(1640+((v[0]+70)%13)*1.8)/4096
 w=1-(105+((v[1]-100)%12)*1.1)/4096
 newverts[vi]=(*v[:6],u,w)
base.verts=newverts
print('MOUNT_3_COMPONENTS',len(mounts),'safe_mount_vertices',len(safe))
# Test all non-base pieces byte-semantically unchanged, including ring5 and laser rings.
for n,p in pieces.items():
 oldv,oldi,off,prim=snapshot[n]
 assert p.offset==off and p.primitive==prim
 if n!='base':
  assert p.verts==oldv and p.indices==oldi,n
assert len(base.verts)==len(origverts) and all(a[:6]==b[:6] for a,b in zip(base.verts,origverts))
assert len(origindex)-len(base.indices)==384*3
assert all(j<len(base.verts) for j in base.indices)
# Single combined geometry+UV repair; do not create new S3O unless checks pass.
if '--apply' in sys.argv:
 save(m,str(PATH))
 re=load(str(PATH));rb=next(p for p in walk(re.root) if p.name=='base')
 assert rb.indices==base.indices and len(rb.verts)==len(base.verts)
 print('SAVED_V23',PATH,PATH.stat().st_size)
else:print('V23_DRY_RUN_SUCCESS')

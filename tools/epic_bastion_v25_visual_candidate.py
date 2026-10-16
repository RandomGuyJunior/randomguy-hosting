#!/usr/bin/env python3
"""V25 visual candidate; connected-component edits only. Never overwrites live S3O by default."""
import sys,collections,math,urllib.request,copy
from pathlib import Path
sys.path.insert(0,"tools")
from build_epic_bastion_model import load,save,walk
source=Path("objects3d/Units/legbastiont3.s3o")
dest=Path(sys.argv[1]) if len(sys.argv)>1 else Path("/tmp/epic_v25_candidate.s3o")
m=load(str(source));pmap={p.name:p for p in walk(m.root)}
original={n:(copy.deepcopy(p.verts),p.indices[:],p.offset,p.primitive) for n,p in pmap.items()}
def read_ref(sha):
 f=Path("/tmp/reference_"+sha[:10]+".s3o")
 f.write_bytes(urllib.request.urlopen("https://raw.githubusercontent.com/RandomGuyJunior/randomguy-hosting/"+sha+"/objects3d/Units/legbastiont3.s3o",timeout=60).read())
 return {p.name:p for p in walk(load(str(f)).root)}
v19=read_ref("c472bcc1615bd50f549bb5294fbed5fdcc07add3")
pre=read_ref("681351216bc87bb80ed44433ab769d46a05c4605")
stats=collections.Counter()
# Do not touch cannon geometry. Exact restore of the visually approved V19 cannon mapping.
for name in [f"gauss{i}_{suffix}" for i in (1,2,3) for suffix in ("pitch","barrel")]:
 p=pmap[name];old=v19[name]
 assert len(p.verts)==len(old.verts) and p.indices==old.indices,name
 assert all(all(abs(x-y)<0.0001 for x,y in zip(a[:6],b[:6])) for a,b in zip(p.verts,old.verts)),name
 p.verts=[(*a[:6],*b[6:8]) for a,b in zip(p.verts,old.verts)]
 stats["cannon_restored_vertices"]+=len(p.verts)
# Inherited core: restore exact matching pre-custom geometry textures only.
base=pmap["base"]
source_uv=collections.defaultdict(set)
def geo(v):return tuple(round(q,4) for q in v[:6])
for v in pre["base"].verts:source_uv[geo(v)].add(tuple(round(q,7) for q in v[6:8]))
base.verts=[(*v[:6],*next(iter(source_uv[geo(v)]))) if (v[1]>60 and math.hypot(v[0],v[2])<45 and len(source_uv.get(geo(v),()))==1) else v for v in base.verts]
# Connected components identified by the audited exact current topology.
tri=[base.indices[i:i+3] for i in range(0,len(base.indices),3)]
group_owners=collections.defaultdict(list)
for i,t in enumerate(tri):
 for j in t:group_owners[tuple(round(x,2) for x in base.verts[j][:3])].append(i)
parents=list(range(len(tri)))
def root(i):
 while i!=parents[i]:parents[i]=parents[parents[i]];i=parents[i]
 return i
def union(a,b):
 a=root(a);b=root(b)
 if a!=b:parents[b]=a
for group in group_owners.values():
 for item in group[1:]:union(group[0],item)
groups=collections.defaultdict(list)
for i in range(len(tri)):groups[root(i)].append(i)
by_first={min(faces):faces for faces in groups.values()}
# Exactly audited concentric top cradle collars, not ring5 or energy rings.
remove=set()
for first,count,rlo,rhi in [(360,384,24,31),(744,384,30,34)]:
 faces=by_first.get(first)
 assert faces and len(faces)==count,(first,len(faces) if faces else None)
 vertices=[base.verts[j] for i in faces for j in tri[i]]
 ys=[v[1] for v in vertices];rr=[math.hypot(v[0],v[2]) for v in vertices]
 assert 176<min(ys)<178 and max(ys)<178 and rlo<min(rr) and max(rr)<rhi,first
 remove.update(faces);stats["removed_upper_cradle_collar_triangles"]+=len(faces)
# Visible mount support islands are three 96-face components plus 6 smaller 12-face
# retaining the original full silhouette while replacing their multicolored atlas sampling.
mount_faces={}
for first in (0,120,240,96,108,216,228,336,348):
 faces=by_first.get(first)
 assert faces and len(faces) in (12,96),(first,len(faces) if faces else None)
 vs=[base.verts[j] for i in faces for j in tri[i]]
 assert 98<min(v[1] for v in vs) and max(v[1] for v in vs)<116,first
 for face in faces:mount_faces[face]=first
 stats["mount_support_faces"]+=len(faces)
# Deep dark Legion recessed panel I046, bronze support panel I036, and
# gray machinery I029, with generous interior margins (catalog coordinates).
rect={
 "bronze":(808,988,1050,1128),
 "dark":(1882,1204,2250,1500),
 "gray":(320,990,538,1128)
}
def uv(label,s,t):
 x0,y0,x1,y1=rect[label]
 s=max(.1,min(.9,s));t=max(.1,min(.9,t))
 return ((x0+s*(x1-x0))/4096,1-(y0+t*(y1-y0))/4096)
# For UV seams duplicate vertices ONLY if a vertex belongs to a surface re-UV'ed here.
# This keeps other parts' existing UVs and geometry.
newverts=base.verts[:];outindices=[]
for face,t in enumerate(tri):
 if face in remove:continue
 if face not in mount_faces:
  outindices.extend(t);continue
 group=mount_faces[face]
 v=[base.verts[j] for j in t]
 # Connected mount housing styling: bronze main plate, dark recessed inner side.
 label="bronze" if group in (0,120,240) else "dark"
 # local bounding per radial assembly; avoids one huge whole-atlas texture sweep.
 cx=sum(q[0] for q in v)/3;cz=sum(q[2] for q in v)/3
 ang=math.atan2(cz,cx)
 # use vertical Y and horizontal local tangential axis, so details orient with each arm
 tx=-math.sin(ang);tz=math.cos(ang)
 # one 20-unit motif repeated continuously along supports
 for q in v:
  s=.5+(q[0]*tx+q[2]*tz)/30
  tt=(q[1]-98)/18
  newverts.append((*q[:6],*uv(label,s,tt)))
  outindices.append(len(newverts)-1)
stats["mount_support_faces_reuv"]=len(mount_faces)
used=sorted(set(outindices));lookup={old:i for i,old in enumerate(used)}
base.verts=[newverts[i] for i in used]
base.indices=[lookup[i] for i in outindices]
# Protected pieces: ring5, original animated rings, all cannon geometry and pivots.
for name,p in pmap.items():
 ov,oi,off,prim=original[name]
 assert p.offset==off and p.primitive==prim,name
 if name=="base":continue
 assert len(p.verts)==len(ov) and p.indices==oi,name
 assert all(a[:6]==b[:6] for a,b in zip(p.verts,ov)),name
 if name not in {f"gauss{i}_{s}" for i in (1,2,3) for s in ("pitch","barrel")}:assert p.verts==ov,name
assert len(base.indices)//3==len(tri)-768
print("V25_CANDIDATE_STATS",dict(stats),"base_triangles",len(base.indices)//3)
dest.parent.mkdir(parents=True,exist_ok=True)
save(m,str(dest))
assert len(list(walk(load(str(dest)).root)))==len(pmap)
print("V25_CANDIDATE_FILE",dest,dest.stat().st_size)

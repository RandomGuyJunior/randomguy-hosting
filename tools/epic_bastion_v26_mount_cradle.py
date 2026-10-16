#!/usr/bin/env python3
"""V26: bridge floating central cradle to turretbase and clean multicolor mount islands.
Never touches gauss, fifth/laser ring mesh, scripts, or original pylon UVs.
Dry-run by default; deploy only after validation.
"""
import copy,collections,math,sys
from pathlib import Path
sys.path.insert(0,'tools')
from build_epic_bastion_model import load,save,walk,Piece
path=Path('objects3d/Units/legbastiont3.s3o')
m=load(str(path)); pmap={p.name:p for p in walk(m.root)}
before={n:(copy.deepcopy(p.verts),p.indices[:],p.offset,p.primitive) for n,p in pmap.items()}
assert 'epic_cradle_turretbase_bridge' not in pmap
base=pmap['base']
tri=[base.indices[k:k+3] for k in range(0,len(base.indices),3)]
# Group by shared geometric positions: V25 deliberately has separate vertices at UV seams.
ownership=collections.defaultdict(list)
for i,ids in enumerate(tri):
 for j in ids:ownership[tuple(round(q,2) for q in base.verts[j][:3])].append(i)
parents=list(range(len(tri)))
def root(i):
 while parents[i]!=i:parents[i]=parents[parents[i]];i=parents[i]
 return i
def join(i,j):
 i=root(i);j=root(j)
 if i!=j:parents[j]=i
for group in ownership.values():
 for j in group[1:]:join(group[0],j)
components=collections.defaultdict(list)
for i in range(len(tri)):components[root(i)].append(i)
by_first={min(g):g for g in components.values()}
# Audited on V25: 3 primary cannon cradles and 6 neighboring transition armor pieces.
main=(0,120,240);transitions=(96,108,216,228,336,348)
target={}
for start in main+transitions:
 faces=by_first.get(start)
 assert faces and len(faces)==(96 if start in main else 12),(start,len(faces) if faces else 0)
 samples=[base.verts[j] for fi in faces for j in tri[fi]]
 ys=[q[1] for q in samples]; rs=[math.hypot(q[0],q[2]) for q in samples]
 assert min(ys)>97 and max(ys)<117 and min(rs)>25 and max(rs)<62,(start,min(ys),max(ys),min(rs),max(rs))
 for fi in faces:target[fi]=start
assert len(target)==360,len(target)
# One truly flat Legion-bronze atlas surface, not a multicolored machinery texture.
# Catalog I010 safe rectangle, significant inset avoids neighboring pixels/shader boundaries.
BRONZE=(788,24,1040,252)
# A grayer bolted panel for the visible top arm blocks.
METAL=(304,20,408,108) # I002 flat small top plate
def uv(rect,s,t):
 x0,y0,x1,y1=rect
 s=max(.20,min(.80,s));t=max(.20,min(.80,t))
 return ((x0+(x1-x0)*s)/4096,1-(y0+(y1-y0)*t)/4096)
newverts=list(base.verts); indices=[]
for fi,ids in enumerate(tri):
 if fi not in target:indices.extend(ids);continue
 group=target[fi]
 vs=[base.verts[j] for j in ids]
 # Group-local face projection with bounded UVs. Never crosses atlas islands.
 rr=BRONZE if group in main else METAL
 for v in vs:
  angle=math.atan2(v[2],v[0])
  tx,tz=-math.sin(angle),math.cos(angle)
  s=.5+(v[0]*tx+v[2]*tz)/40
  t=.5+(v[1]-107)/24
  newverts.append((*v[:6],*uv(rr,s,t)))
  indices.append(len(newverts)-1)
# compact to avoid orphan duplicate UV vertices
used=sorted(set(indices));imap={old:k for k,old in enumerate(used)}
base.verts=[newverts[j] for j in used]
base.indices=[imap[j] for j in indices]
assert len(base.indices)==len(before['base'][1])
# Donor UV from the user's approved original turretbase: use a uniform patch from
# actual stock-core cylinder's side, not an invented off-theme material.
# choose a source vertex group in the existing original textured central core.
donor=[v for v in before['base'][0] if 139<v[1]<171 and 8<math.hypot(v[0],v[2])<15]
assert len(donor)>50,('insufficient core donor vertices',len(donor))
# Existing turretbase UVs may span many subtextures; use a known neutral bronze
# interior (I010) for the new geometry, visually compatible with original.
def add_quad(verts,idx,a,b,c,d,rect):
 # Planar UV across a single closed face, with inset margins.
 k=len(verts)
 for pt,st in zip((a,b,c,d),((.26,.26),(.74,.26),(.74,.74),(.26,.74))):
  verts.append((*pt,(0.,1.,0.),*uv(rect,*st)))
 idx.extend((k,k+1,k+2,k,k+2,k+3))
def v3(rad,y,angle,width,side):
 # oriented tangent width around spoke; local Y-up as BAR S3O
 dx,dz=math.cos(angle),math.sin(angle)
 tx,tz=-dz,dx
 return (dx*rad+tx*width*side,y,dz*rad+tz*width*side)
# Three sturdy tapered tapered spokes, fully closed box volumes
# lower end sits on r=21.2-22 collar at y~136.5, upper end is flush
# with the central turretbase at y~166-171, radial ~13.
verts=[];inds=[]
for k in range(3):
 a=2*math.pi*k/3+math.pi/6
 lo=[v3(21.0,135.9,a,3.1,s) for s in (-1,1)]
 hi=[v3(13.6,169.2,a,2.3,s) for s in (-1,1)]
 # rectangular 3D beam cross sections with fore/aft radial thickness
 def ring_pts(rad,y,w,depth):
  return [v3(rad+dr,y,a,w,s) for dr,s in ((-depth/2,-1),(-depth/2,1),(depth/2,1),(depth/2,-1))]
 bottom=ring_pts(21.2,135.9,3.5,4.0)
 top=ring_pts(13.6,169.2,2.5,3.1)
 assert len(bottom)==len(top)==4
 for i in range(4):
  j=(i+1)%4
  add_quad(verts,inds,bottom[i],bottom[j],top[j],top[i],BRONZE)
 add_quad(verts,inds,top[0],top[1],top[2],top[3],METAL)
 add_quad(verts,inds,bottom[3],bottom[2],bottom[1],bottom[0],BRONZE)
assert len(inds)==108 and len(verts)==72
# Component belongs directly to fixed base, not weapon/yaw/pitch pivots.
bridge=Piece('epic_cradle_turretbase_bridge',(0,0,0),verts,inds,0,0,[])
base.children.append(bridge)
# Strict protection of all original moving and already-approved pieces.
for name,p in pmap.items():
 oldv,oldidx,off,prim=before[name]
 assert p.offset==off and p.primitive==prim,name
 if name=='base':
  assert len(p.indices)==len(oldidx)
  # Preserve indexed triangle positions exactly, allowing needed UV vertex splitting
  for at in range(len(oldidx)):
   assert all(abs(p.verts[p.indices[at]][q]-oldv[oldidx[at]][q])<1e-5 for q in range(6)),('base geometry changed',at)
 else:
  assert p.verts==oldv and p.indices==oldidx,name
assert len(list(walk(m.root)))==len(before)+1
print('V26 validated: 360 cannon mounting armor faces re-UV, 3 closed cradle/turretbase connectors (36 faces); protected all moving geometry')
if '--apply' in sys.argv:
 save(m,str(path))
 print('V26 SAVED',path,path.stat().st_size)
else: print('V26 DRY-RUN')

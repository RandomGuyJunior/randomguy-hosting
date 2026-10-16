#!/usr/bin/env python3
"""V29: attach cradle to turretbase, remove multicolored mount texture islands.
Preserves all cannon and spinning ring vertex data and scripts.
"""
import sys,math,copy,collections,hashlib
from pathlib import Path
sys.path.insert(0,'tools')
from build_epic_bastion_model import load,save,walk,Piece
P=Path('objects3d/Units/legbastiont3.s3o')
m=load(str(P)); parts={p.name:p for p in walk(m.root)}
old={n:(copy.deepcopy(p.verts),list(p.indices),p.offset,p.primitive) for n,p in parts.items()}
assert 'epic_turretbase_flat_support_ring' in parts
assert 'epic_cradle_turretbase_bridge' not in parts
assert 'epic_cradle_v29_struts' not in parts
base=parts['base']
# Identify actual connected mesh components by shared coordinates, never by a broad y-only slice.
tri=[base.indices[i:i+3] for i in range(0,len(base.indices),3)]
owners=collections.defaultdict(list)
for fi,indices in enumerate(tri):
 for j in indices:owners[tuple(round(q,3) for q in base.verts[j][:3])].append(fi)
parent=list(range(len(tri)))
def root(i):
 while parent[i]!=i:parent[i]=parent[parent[i]];i=parent[i]
 return i
for hits in owners.values():
 a=root(hits[0])
 for b in hits[1:]:
  b=root(b)
  if a!=b:parent[b]=a
groups=collections.defaultdict(list)
for fi in range(len(tri)):groups[root(fi)].append(fi)
summaries=[]
for group in groups.values():
 vv=[base.verts[k] for fi in group for k in tri[fi]]
 yy=[p[1] for p in vv];rr=[math.hypot(p[0],p[2]) for p in vv]
 summaries.append((min(group),len(group),round(min(yy),1),round(max(yy),1),round(min(rr),1),round(max(rr),1)))
print('BASE_COMPONENTS',sorted(summaries)[:100])
# Cannon underside mounting geometry is from the three groups that were previously audited in V26/V27.
# Texture only these, not cannon barrel/pitch objects and not stock inner pylon.
main_components=[]
for group in groups.values():
 if len(group)<80 or len(group)>160:continue
 vv=[base.verts[k] for fi in group for k in tri[fi]]
 yy=[p[1] for p in vv];rr=[math.hypot(p[0],p[2]) for p in vv]
 if min(yy)>95 and max(yy)<120 and min(rr)>23 and max(rr)<66:
  main_components.append(group)
print('CANNON_MOUNT_GROUPS',[(min(g),len(g)) for g in main_components])
assert len(main_components)==3, 'Expected exactly 3 mounted cannon-support armor components'
target={fi for g in main_components for fi in g}
# Avoid atlas multicolor stripes. Choose original Legion bronze panel I010 and gray panel I001,
# with a large safe inset, using component-local projection (no per-triangle random colors).
BRONZE=(800,36,1028,242)  # verified catalog I010 inner rectangle
DARK=(1574,36,1800,240)   # verified catalog I018
GRAY=(36,36,250,238)      # verified catalog I001
def atlas(rect,s,t):
 x0,y0,x1,y1=rect
 s=max(.18,min(.82,s));t=max(.18,min(.82,t))
 return ((x0+(x1-x0)*s)/4096,1-(y0+(y1-y0)*t)/4096)
newv=list(base.verts);newindices=[]
for fi,ids in enumerate(tri):
 if fi not in target:
  newindices.extend(ids);continue
 face=[base.verts[j] for j in ids]
 cx=sum(v[0] for v in face)/3;cz=sum(v[2] for v in face)/3
 angle=math.atan2(cz,cx)
 tx,tz=-math.sin(angle),math.cos(angle)
 # coherent projections around center of support, same coloring across all 3
 for v in face:
  s=.5+(v[0]*tx+v[2]*tz)/55
  t=.5+(v[1]-108)/38
  newv.append((*v[:6],*atlas(BRONZE,s,t)))
  newindices.append(len(newv)-1)
used=sorted(set(newindices));rename={j:i for i,j in enumerate(used)}
base.verts=[newv[j] for j in used];base.indices=[rename[j] for j in newindices]
print('CANNON_MOUNT_FACES_REPAIRED',len(target))
# Add 3 unobtrusive struts as actual CLOSED prisms, anchored into the central turretbase
# between y≈139 and flat stationary support underside at y≈174.5.
# Keeps open center and all five spinning rings. No bulky circumferential ring added.
V=[];I=[]
def face(a,b,c,d,rect):
 ax,ay,az=(b[k]-a[k] for k in range(3))
 bx,by,bz=(c[k]-a[k] for k in range(3))
 n=(ay*bz-az*by,az*bx-ax*bz,ax*by-ay*bx)
 length=math.sqrt(sum(t*t for t in n));assert length>1e-6
 n=tuple(t/length for t in n)
 start=len(V)
 for point,st in zip((a,b,c,d),((.23,.23),(.77,.23),(.77,.77),(.23,.77))):
  V.append((*point,*n,*atlas(rect,*st)))
 I.extend((start,start+1,start+2,start,start+2,start+3))
def cross_section(angle,r,y,width,radial):
 a=(math.cos(angle),math.sin(angle))
 tang=(-a[1],a[0])
 return [((r+dr)*a[0]+s*width*tang[0],y,(r+dr)*a[1]+s*width*tang[1])
         for dr,s in ((-radial/2,-1),(-radial/2,1),(radial/2,1),(radial/2,-1))]
for i in range(3):
 theta=2*math.pi*i/3+math.pi/6
 # lower section at central static housing, top section underneath stationary support
 lo=cross_section(theta,13.4,140.0,2.5,3.2)
 hi=cross_section(theta,21.0,175.0,3.3,4.0)
 for k in range(4):
  q=(k+1)%4
  face(lo[k],lo[q],hi[q],hi[k],BRONZE if k in (0,2) else DARK)
 face(lo[3],lo[2],lo[1],lo[0],DARK)
 face(hi[0],hi[1],hi[2],hi[3],GRAY)
assert len(I)==108
connector=Piece('epic_cradle_v29_struts',(0.,0.,0.),V,I,0,0,[])
base.children.append(connector)
# Absolute protections on original moving geometry / indices / mounts positions
for name,p in parts.items():
 prev,indices,off,prim=old[name]
 assert p.offset==off and p.primitive==prim,name
 if name=='base':
  assert len(p.indices)==len(indices)
  for k in range(len(indices)):
   assert p.verts[p.indices[k]][:6]==prev[indices[k]][:6],('base geometry changed',k)
 else:
  assert p.verts==prev and p.indices==indices,name
for name in ['ring','ring2','ring3','ring4','ring5']+[f'gauss{i}_{part}' for i in (1,2,3) for part in ('pitch','barrel')]:
 assert name in old and parts[name].verts==old[name][0],name
print('V29_VALIDATED',len(V),len(I),'connector triangles',len(I)//3,'original cannon UV protected')
if '--apply' in sys.argv:
 save(m,str(P))
 check=load(str(P))
 assert 'epic_cradle_v29_struts' in {p.name for p in walk(check.root)}
 print('V29_COMMITTED_MODEL',hashlib.sha256(P.read_bytes()).hexdigest())
else:print('DRY_RUN_ONLY')

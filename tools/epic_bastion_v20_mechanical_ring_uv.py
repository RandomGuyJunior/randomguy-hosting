#!/usr/bin/env python3
"""V20: textured mechanical fifth ring from *isolated* official Legion atlas islands.
Changes UV coordinates of ring5 ONLY. Geometry, pieces, animation and cannons untouched.
"""
import sys,math,collections,hashlib
from pathlib import Path
sys.path.insert(0,"tools")
from build_epic_bastion_model import load,save,walk
path=Path("objects3d/Units/legbastiont3.s3o")
model=load(str(path))
pieces={p.name:p for p in walk(model.root)}
ring=pieces["ring5"]
old={n:(list(p.verts),list(p.indices),p.offset) for n,p in pieces.items()}
# Pixel-safe interiors from legion_usable_texture_islands.json, 4096x4096.
# I029 riveted armor, I031 structural channel, I062 dark grille,
# I063 track, I103 green LED. These are detailed artworks, not plain swatches.
islands={
 "riveted":(300,972,556,1144),
 "structural":(308,1172,444,1536),
 "grille":(2592,792,3312,928),
 "track":(2556,968,3312,1256),
 "green":(428,3232,480,3292),
}
# Each 30-degree sector reuses one complete mechanical surface island.
# Seam continuity is intentional at joints; never use a rectangle with adjacent motifs.
verts=[];indices=[];counts=collections.Counter()
assert len(ring.indices)%3==0
for ix in range(0,len(ring.indices),3):
 tri=[ring.verts[q] for q in ring.indices[ix:ix+3]]
 center=[sum(v[k] for v in tri)/3 for k in range(3)]
 radial=math.hypot(center[0],center[2])
 a=math.atan2(center[2],center[0])
 e1=[tri[1][i]-tri[0][i] for i in range(3)]
 e2=[tri[2][i]-tri[0][i] for i in range(3)]
 normal=(e1[1]*e2[2]-e1[2]*e2[1],e1[2]*e2[0]-e1[0]*e2[2],e1[0]*e2[1]-e1[1]*e2[0])
 ax,ay,az=map(abs,normal)
 # The 72 green-indicator triangles were identified by radius in V19.
 if radial>32.5:
  material="green"
 elif ay>=max(ax,az)*0.95:
  material="riveted"
 elif radial<26.5:
  material="grille"
 elif radial>29.5:
  material="track"
 else:
  material="structural"
 counts[material]+=1
 x0,y0,x1,y1=islands[material]
 # angular projection, local to each 30-degree segment, no per-triangle stretch
 # and no wrapping at a boundary within a triangle.
 angular_span=math.pi/6
 angle_center=(math.floor((a+math.pi)/angular_span)+.5)*angular_span-math.pi
 for v in tri:
  theta=math.atan2(v[2],v[0])
  diff=math.atan2(math.sin(theta-angle_center),math.cos(theta-angle_center))
  t=min(.985,max(.015,diff/angular_span+.5))
  if material=="green":
   # LED island center: whole module bright, without importing surrounding graphics
   x=(x0+x1)/2 + (t-.5)*(x1-x0)*.3
   y=(y0+y1)/2 +(v[1]-center[1])*2
  else:
   x=x0+8+t*(x1-x0-16)
   # Project across ring cross-section while keeping island's panel pattern.
   rr=math.hypot(v[0],v[2])
   y=(y0+y1)/2+(rr-28)*min(14,(y1-y0)/14)+(v[1]-center[1])*4
  x=max(x0+2,min(x1-2,x))
  y=max(y0+2,min(y1-2,y))
  verts.append((*v[:6],x/4096.,1-y/4096.))
  indices.append(len(verts)-1)
ring.verts=verts
ring.indices=indices
assert len(indices)==len(old['ring5'][1])
for name,p in pieces.items():
 if name!='ring5':
  assert p.verts==old[name][0] and p.indices==old[name][1] and p.offset==old[name][2],name
 else:
  assert p.offset==old[name][2]
  assert len(p.verts)==len(old[name][0])
  assert all(v[:6]==w[:6] for v,w in zip(p.verts,old[name][0]))
print("Ring triangles",len(indices)//3,"UV themes",dict(counts))
print("All other S3O pieces remain exactly unchanged.")
if "--apply" in sys.argv:
 save(model,str(path))
 print("Updated model",hashlib.sha256(path.read_bytes()).hexdigest())
else: print("Dry run only")

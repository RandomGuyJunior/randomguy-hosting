#!/usr/bin/env python3
"""Epic Bastion: shorter gauss cannon visuals and a catalog-based fifth-ring UV layout.

Never modifies base, inherited rings, cannon UV values, weapon definitions, or Lua.
Use --apply to persist. Default is dry-run. All textures are from actual
4096x4096 Legion atlas artwork islands catalogued 2026-10-12.
"""
import sys, math, hashlib, collections
from pathlib import Path
sys.path.insert(0,'tools')
from build_epic_bastion_model import load,save,walk,find

PATH=Path('objects3d/Units/legbastiont3.s3o')
model=load(str(PATH))
before=PATH.read_bytes()
allpieces={p.name:p for p in walk(model.root)}
assert allpieces.keys() >= {'base','ring','ring2','ring3','ring4','ring5','gauss1_pitch','gauss2_pitch','gauss3_pitch','gauss1_barrel','gauss2_barrel','gauss3_barrel','gauss1_muzzle','gauss2_muzzle','gauss3_muzzle'}
origin={n:(list(p.verts),tuple(p.offset),list(p.indices)) for n,p in allpieces.items()}

# Atlas pixel rectangles with safe margins: gray flat plate, dark structural
# metal, and green luminous tiny LED. S3O V follows the original atlas UV convention.
ISLANDS={
 'gray': (24,24,264,256),
 'dark': (1560,24,1812,256),
 'led': (428,3224,472,3296),
}
def uv(pixel_x,pixel_y):
 return (pixel_x/4096.,1.-pixel_y/4096.)
# 5th ring has ~33 radius. Assign polished gray with darker structural sides.
# Use spatially coherent per-12th-section UVs instead of stretching the *whole*
# texture patch onto each individual triangle, which was the previous defect.
ring=allpieces['ring5']
newverts=[];newindices=[]
counts=collections.Counter()
indices=ring.indices
assert len(indices)%3==0
for i in range(0,len(indices),3):
 tri=[ring.verts[j] for j in indices[i:i+3]]
 p=[v[:3] for v in tri]
 mx=sum(x[0] for x in p)/3
 my=sum(x[1] for x in p)/3
 mz=sum(x[2] for x in p)/3
 rad=math.hypot(mx,mz)
 a=[math.atan2(v[2],v[0]) for v in tri]
 mid=math.atan2(mz,mx)
 angles=[mid+math.atan2(math.sin(x-mid),math.cos(x-mid)) for x in a]
 # Only outer bolt/indicator modules use illuminated green pixels.
 # Sectors continue smoothly within 30-degree repeating motifs.
 d1=[p[1][k]-p[0][k] for k in range(3)]
 d2=[p[2][k]-p[0][k] for k in range(3)]
 normal=(d1[1]*d2[2]-d1[2]*d2[1],d1[2]*d2[0]-d1[0]*d2[2],d1[0]*d2[1]-d1[1]*d2[0])
 kind='led' if rad>32.5 else ('gray' if abs(normal[1])>max(abs(normal[0]),abs(normal[2])) else 'dark')
 x0,y0,x1,y1=ISLANDS[kind]
 counts[kind]+=1
 for v,angle in zip(tri,angles):
  if kind=='led':
   # Sample only the verified LED interior, not its housing artwork.
   x=(x0+x1)/2+(v[1]-my)*.3
   y=(y0+y1)/2+(math.hypot(v[0],v[2])-rad)*.3
  else:
   # Repeat armor every 30 degrees, with a coherent radius/depth axis.
   # Stay within safe central section and avoid neighbor islands.
   fract=(angle/(math.pi/6.))%1.
   x=x0+16+fract*(x1-x0-32)
   radial=math.hypot(v[0],v[2])
   y=(y0+y1)/2+(radial-28)*5+(v[1])*3
  x=min(x1-3,max(x0+3,x))
  y=min(y1-3,max(y0+3,y))
  u,w=uv(x,y)
  newindices.append(len(newverts))
  newverts.append((*v[:6],u,w))
ring.verts=newverts
ring.indices=newindices

# Scale the *entire visible cannon along local longitudinal +Z* by 0.80
# while leaving yaw and pitch pivot placement / rotation completely intact.
# Barrel, mantlet and muzzle remain proportional, and the muzzle stays exactly
# at the barrel nose instead of firing from an old invisible position.
for i in (1,2,3):
 pitch=allpieces[f'gauss{i}_pitch']
 barrel=allpieces[f'gauss{i}_barrel']
 muzzle=allpieces[f'gauss{i}_muzzle']
 for p in (pitch,barrel):
  p.verts=[(v[0],v[1],v[2]*.8,*v[3:]) for v in p.verts]
 # Muzzle is a locator: its local Z needs the same scale.
 muzzle.offset=(muzzle.offset[0],muzzle.offset[1],muzzle.offset[2]*.8)
 print(f'Cannon {i}: barrel forward tip {max(v[2] for v in origin[barrel.name][0]):.2f} -> {max(v[2] for v in barrel.verts):.2f}; muzzle local Z {origin[muzzle.name][1][2]:.2f} -> {muzzle.offset[2]:.2f}')
 # Require original cannon UV floats to stay bitwise-identical.
 for p in (pitch,barrel):
  assert all(v[6:]==old[6:] for v,old in zip(p.verts,origin[p.name][0]))
 # Asymmetrical geometry is okay but cannon Z bounds reduced by exactly 20%.
 assert abs(max(v[2] for v in barrel.verts)-.8*max(v[2] for v in origin[barrel.name][0]))<1e-5

# Check no piece's geometry, UV, indices or position changed unintentionally.
allowed={'ring5'}
for i in (1,2,3):allowed.update({f'gauss{i}_pitch',f'gauss{i}_barrel',f'gauss{i}_muzzle'})
for n,p in allpieces.items():
 oldverts,oldoff,oldidx=origin[n]
 assert p.indices==oldidx or n=='ring5',f'indices unexpectedly modified: {n}'
 if n not in allowed:
  assert p.verts==oldverts and p.offset==oldoff,f'unexpected modification: {n}'
 else:
  assert p.offset==oldoff or n.endswith('_muzzle'),f'unexpected pivot movement: {n}'
print('Ring faces',sum(counts.values()),'new vertex count',len(ring.verts),'materials',dict(counts))
print('Protected lower base, original 4 rings, armatures, cannon UVs and aiming pivots are unchanged.')
if '--apply' in sys.argv:
 save(model,str(PATH))
 after=PATH.read_bytes()
 print('Saved',len(after),'bytes; SHA256',hashlib.sha256(after).hexdigest())
else:
 print('DRY RUN, no file written')

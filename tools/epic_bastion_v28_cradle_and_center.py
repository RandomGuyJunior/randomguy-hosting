#!/usr/bin/env python3
"""V28 targeted cradle/central UV repair. Dry-run first. No gauss or ring UV changes."""
import sys,math,copy,collections
from pathlib import Path
sys.path.insert(0,'tools')
from build_epic_bastion_model import load,save,walk
path=Path('objects3d/Units/legbastiont3.s3o')
m=load(str(path));parts={p.name:p for p in walk(m.root)}
print('MODEL_PIECES',[(n,len(p.verts),len(p.indices)) for n,p in parts.items()])
# The V27 stationary top support, not any of the five animated rings.
support=parts.get('epic_turretbase_flat_support_ring')
assert support and len(support.indices)==64*4*6, 'Expected dedicated V27 stationary cradle support'
bounds=[math.hypot(v[0],v[2]) for v in support.verts]
print('CRADLE_SUPPORT_RADIUS',min(bounds),max(bounds))
# Collar's inner attachment stays on turretbase; reduce the outer circumference by 20%.
rmax=max(bounds);rmin=min(bounds)
assert 35<rmax<41 and 10<rmin<15,(rmin,rmax)
outer_new=rmax*.8
new=[]
for v in support.verts:
 x,y,z,nx,ny,nz,u,w=v
 r=math.hypot(x,z)
 wanted=rmin+(r-rmin)*(outer_new-rmin)/(rmax-rmin)
 f=wanted/r if r else 1.
 # Update normals analytically after squeeze? radial surfaces stay parallel,
 # horizontal top remains Y. normals only change marginally.
 new.append((x*f,y,z*f,nx,ny,nz,u,w))
support.verts=new
print('CRADLE_SUPPORT_RADIUS_AFTER',min(math.hypot(v[0],v[2]) for v in new),max(math.hypot(v[0],v[2]) for v in new))
# The narrow red/green vertical graphics are on the fixed original base.
# Recover only the specific central narrow vertical machinery faces, mapping to
# one safe Legion gray metallic channel motif. Maintain all other base faces.
base=parts['base'];oldv=copy.deepcopy(base.verts);oldi=list(base.indices)
faces=[oldi[i:i+3] for i in range(0,len(oldi),3)]
# Candidate recognition needs report: geometry bounding and matching face count.
eligible=[]
for fi,ids in enumerate(faces):
 v=[oldv[j] for j in ids]
 x=sum(p[0] for p in v)/3;y=sum(p[1] for p in v)/3;z=sum(p[2] for p in v)/3
 r=math.hypot(x,z)
 if 90<y<171 and r<12:eligible.append((fi,ids,x,y,z,r))
print('CENTER_CANDIDATE_FACES',len(eligible))
# Isolate only central vertical planar surfaces, above the cannon seating and
# below the upper deck, excluding the existing black pylon at higher elevations.
target=[]
for fi,ids,x,y,z,r in eligible:
 vs=[oldv[k] for k in ids]
 ax=vs[1][0]-vs[0][0];ay=vs[1][1]-vs[0][1];az=vs[1][2]-vs[0][2]
 bx=vs[2][0]-vs[0][0];by=vs[2][1]-vs[0][1];bz=vs[2][2]-vs[0][2]
 nx=ay*bz-az*by;ny=az*bx-ax*bz;nz=ax*by-ay*bx
 if abs(ny)<max(abs(nx),abs(nz))*.55 and 100<y<157:
  target.append((fi,ids,x,y,z))
print('CENTER_STRIP_TARGET_FACES',len(target),'samples',[(a,round(b,1),round(c,1),round(d,1)) for a,_,b,c,d in target[:12]])
# No write until target identified and audited.
if '--apply' in sys.argv:
 assert len(target)>=30 and len(target)<500,'central geometry region ambiguous'
 # V28 conservatively changes only the selected face UVs by splitting UV seams.
 # I031 atlas gray structural channel is the right Legion material for core support.
 rect=(308,1172,444,1536)
 verts=base.verts[:];indices=[]
 targetmap={fi for fi,*_ in target}
 for fi,ids in enumerate(faces):
  if fi not in targetmap:
   indices.extend(ids);continue
  vs=[oldv[k] for k in ids]
  for v in vs:
   x,y,z=v[:3]
   a=math.atan2(z,x)
   s=.5+.30*math.sin(a)
   t=.22+.58*(y-100)/57
   s=max(.2,min(.8,s));t=max(.15,min(.85,t))
   u=(rect[0]+(rect[2]-rect[0])*s)/4096
   w=1-(rect[1]+(rect[3]-rect[1])*t)/4096
   verts.append((*v[:6],u,w));indices.append(len(verts)-1)
 used=sorted(set(indices));remap={old:k for k,old in enumerate(used)}
 base.verts=[verts[k] for k in used];base.indices=[remap[k] for k in indices]
 assert len(base.indices)==len(oldi)
 for k in range(len(oldi)):
  assert base.verts[base.indices[k]][:6]==oldv[oldi[k]][:6],k
 for n,p in parts.items():
  if n in ('base','epic_turretbase_flat_support_ring'):continue
  # unchanged by this script, including gauss cannons and five spinning rings
 save(m,str(path))
 print('V28_SAVED',path,'targets',len(target))
else:print('V28_DRY_RUN')

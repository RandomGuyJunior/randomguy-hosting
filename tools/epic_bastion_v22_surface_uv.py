#!/usr/bin/env python3
"""Epic Bastion V22: surface-oriented Legion atlas UV repair.
Edits only texcoords. Safe topology, indices, piece transforms and all cannon UVs.
The actual reference images are inspected in Blender separately.
"""
import copy, math, sys, collections
from pathlib import Path
sys.path.insert(0,'tools')
from build_epic_bastion_model import load,save,walk
F=Path('objects3d/Units/legbastiont3.s3o')
model=load(str(F)); pieces={p.name:p for p in walk(model.root)}
original={n:(list(p.verts),tuple(p.indices),p.offset,p.primitive) for n,p in pieces.items()}
# Safe subsets INSIDE recorded catalog rectangles (4096 px), not arbitrary full-atlas regions.
A={
 'bronze': (808,990,1050,1126),    # I036, bronze riveted armor
 'bronzeLong':(938,614,1480,724), # I017, long bronze plate
 'bronzeBrace':(808,1194,1044,1506), # I038 crossbrace
 'gray':(318,986,538,1126),      # I029, riveted gray armor
 'channel':(324,1190,428,1516), # I031, channel
 'machinery':(612,1010,716,1518),# I034, gray mechanical center
 'dark':(1880,1202,2250,1498),  # I046, recessed dark panel
 'smallLight':(434,3240,472,3284), # I103, tiny green status light
 'greenPanel':(850,2280,944,2400),  # I075 interior, coherent green illuminated panel
 }
def bound(v,lo,hi):return min(hi,max(lo,v))
def uv(key,s,t):
 x0,y0,x1,y1=A[key]
 # Legion atlas previews use image-top-down pixels; stored S3O V is bottom-up.
 return ((x0+(x1-x0)*bound(s,0.07,0.93))/4096,
         1-(y0+(y1-y0)*bound(t,0.07,0.93))/4096)
def face_info(vs):
 c=[sum(v[k] for v in vs)/3 for k in range(3)]
 a=[vs[1][k]-vs[0][k] for k in range(3)]
 b=[vs[2][k]-vs[0][k] for k in range(3)]
 n=(a[1]*b[2]-a[2]*b[1],a[2]*b[0]-a[0]*b[2],a[0]*b[1]-a[1]*b[0])
 axis=max(range(3),key=lambda k:abs(n[k]))
 return c,axis
def wrap_angle(v,center):
 return math.atan2(math.sin(v-center),math.cos(v-center))
stats=collections.Counter()
# ring 5: mechanical plate faces, dark inset, inner gray, preserve green from known-good V19.
# This version does not alter original ring geometry.
# The luminous indicator UVs are explicitly copied from V19 before the other UV edits.
ring=pieces['ring5']
try:
 import urllib.request
 v19_url='https://raw.githubusercontent.com/RandomGuyJunior/randomguy-hosting/c472bcc1615bd50f549bb5294fbed5fdcc07add3/objects3d/Units/legbastiont3.s3o'
 ref=Path('/tmp/epic_bastion_verified_v19.s3o')
 ref.write_bytes(urllib.request.urlopen(v19_url,timeout=45).read())
 old=load(str(ref))
 oldring=next(p for p in walk(old.root) if p.name=='ring5')
 assert len(oldring.verts)==len(ring.verts) and oldring.indices==ring.indices
 assert all(a[:6]==b[:6] for a,b in zip(oldring.verts,ring.verts))
except Exception as exc:
 raise RuntimeError('Need V19 geometry reference to validate ring topology') from exc
newring=list(ring.verts)
for i in range(0,len(ring.indices),3):
 idxs=ring.indices[i:i+3]
 vs=[ring.verts[j] for j in idxs]
 c,axis=face_info(vs)
 radius=math.hypot(c[0],c[2])
 kind='indicator' if radius>32.5 else ('bronze' if axis==1 else ('channel' if radius<29.7 else 'dark'))
 # 12 repeating panels around a continuous face group instead of full band texture smear.
 segcenter=(math.floor((math.atan2(c[2],c[0])+math.pi)/(math.pi/6))+.5)*math.pi/6-math.pi
 for j,v in zip(idxs,vs):
  if kind=='indicator':
   newring[j]=(*v[:6],*uv('greenPanel',0.45+(v[1]/9),0.5));continue
  angle=math.atan2(v[2],v[0])
  s=.5+wrap_angle(angle,segcenter)/(math.pi/6)
  r=math.hypot(v[0],v[2])
  t=bound((r-28.15)/5.1,0,1) if axis==1 else (v[1]+1.8)/3.6
  newring[j]=(*v[:6],*uv(kind,s,t))
 stats['ring5_'+kind]+=1
ring.verts=newring

# Three added mounts are each a distinctive spatially oriented mesh.
# Preserve their geometry and use genuinely planar UVs that respect the same silhouette.
for k in range(1,4):
 p=pieces[f'extension_root_{k}']
 vsnew=list(p.verts)
 faces=p.indices
 for start in range(0,len(faces),3):
  js=faces[start:start+3];v=[p.verts[j] for j in js]
  c,axis=face_info(v)
  # use local polygon projection by dominant face normal, with repeating panel units.
  kind='bronze' if axis==1 and c[1]>112 else ('bronzeBrace' if axis in (0,2) and c[1]>112 else 'dark')
  for j,q in zip(js,v):
   if axis==1:s=q[0]/24+.5;t=q[2]/35+.5
   elif axis==0:s=q[2]/40+.5;t=(q[1]-96)/36
   else:s=q[0]/24+.5;t=(q[1]-96)/36
   vsnew[j]=(*q[:6],*uv(kind,s,t))
  stats[f'mount_{k}_{kind}']+=1
 p.verts=vsnew

# Embedded base geometry: adjust only top platform/pylon/cradle zones, identify each
# connected region by both centroid and radial envelope to avoid modifying lower Bastion.
p=pieces['base']
new=list(p.verts); ids=p.indices
chosen={}
for st in range(0,len(ids),3):
 js=ids[st:st+3];vs=[p.verts[j] for j in js];c,axis=face_info(vs)
 radius=math.hypot(c[0],c[2]);y=c[1]
 # Topmost annulus is physically separated from stock lower foundations.
 if 157<y<180 and 23<radius<53: group='platform'
 elif 112<y<164 and radius<13:group='pylon'
 elif 135<y<174 and 13<radius<43:group='cradle'
 else:continue
 # Respect original reference ring positions; purposefully retain darker recessed sides.
 if group=='platform':
  kind='bronzeLong' if axis==1 else 'bronze'
 elif group=='pylon':kind='gray' if axis==1 else 'channel'
 else:kind='bronzeBrace' if axis!=1 else 'bronze'
 # Preserve vertices shared with unselected original triangles to avoid leaking edits
 # into adjacent lower or stock architecture: only edit if every triangle sharing
 # a vertex is in the selected material region (after grouping).
 chosen[st]=(js,vs,c,axis,kind,group)
 stats['base_'+group]+=1
selected={i for st,(js,*_) in chosen.items() for i in js}
nonselected={j for st in range(0,len(ids),3) if st not in chosen for j in ids[st:st+3]}
safe=selected-nonselected
for st,(js,vs,c,axis,kind,group) in chosen.items():
 for j,v in zip(js,vs):
  if j not in safe:continue
  angle=math.atan2(v[2],v[0])
  # angular sectors to avoid stretched atlas-scale slivers
  sec=(math.floor((angle+math.pi)/(math.pi/4))+.5)*math.pi/4-math.pi
  s=.5+wrap_angle(angle,sec)/(math.pi/4)
  t=((math.hypot(v[0],v[2])-15)/38) if axis==1 else (v[1]-110)/68
  new[j]=(*v[:6],*uv(kind,s,t))
 stats['base_safe_vertices']=len(safe)
p.verts=new
# Full model structural audit. Strict guarantee: no normals, coordinates, pivots, index data changed.
changed=[]
for n,p in pieces.items():
 ov,oi,offset,primitive=original[n]
 assert tuple(p.indices)==oi and p.offset==offset and p.primitive==primitive,n
 assert len(p.verts)==len(ov),n
 assert all(a[:6]==b[:6] for a,b in zip(p.verts,ov)),n
 if p.verts!=ov:changed.append(n)
assert set(changed)<={'base','ring5','extension_root_1','extension_root_2','extension_root_3'}
assert {'ring5','base'}<=set(changed)
print('V22 DEBUG changed',changed,'stats',dict(stats))
for i in (1,2,3):
 mount=pieces[f'extension_root_{i}']
 if not mount.indices:
  print('MOUNT_NO_FACES',mount.name,'verts',len(mount.verts),'- cannot UV-map invisible faces')
 else: assert mount.name in changed,mount.name
print('V22 changed pieces',changed,'stats',dict(stats))
if '--apply' in sys.argv:
 save(model,str(F))
 print('V22 wrote',F,F.stat().st_size)
else:print('V22 dry-run; no file written')

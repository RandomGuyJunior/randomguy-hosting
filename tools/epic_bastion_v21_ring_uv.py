#!/usr/bin/env python3
"""V21 ring5 ONLY: preserve V19 green pixels, improve gray armor with catalog islands.
V19 is the last confirmed neon-green S3O mapping. Do not touch other pieces.
"""
import sys,math,collections,urllib.request,hashlib
from pathlib import Path
sys.path.insert(0,'tools')
from build_epic_bastion_model import load,save,walk
PATH=Path('objects3d/Units/legbastiont3.s3o')
V19='c472bcc1615bd50f549bb5294fbed5fdcc07add3'
b=urllib.request.urlopen('https://raw.githubusercontent.com/RandomGuyJunior/randomguy-hosting/'+V19+'/objects3d/Units/legbastiont3.s3o',timeout=90).read()
ref=Path('/tmp/epic_v19_ring_reference.s3o');ref.write_bytes(b)
old=load(str(ref));new=load(str(PATH))
pieces={p.name:p for p in walk(new.root)}
refpieces={p.name:p for p in walk(old.root)}
ring=pieces['ring5'];oldring=refpieces['ring5']
assert len(ring.verts)==len(oldring.verts)==1968
assert ring.indices==oldring.indices
assert all(a[:6]==b[:6] for a,b in zip(ring.verts,oldring.verts))
snapshot={n:(p.verts[:],p.indices[:],p.offset) for n,p in pieces.items()}
# Catalog island pixel-safe coordinates, not invented rectangles.
# I029 "rectangular_bolted_plate" and I031 "vertical_channel"
# I034 "machinery_center" are isolated Legion motifs.
catalog={
 'I029':(300,972,556,1144),
 'I031':(308,1172,444,1536),
 'I034':(592,980,740,1536),
}
out=[]
counts=collections.Counter()
for face in range(len(ring.indices)//3):
 vs=[ring.verts[ring.indices[3*face+k]] for k in range(3)]
 center=[sum(v[k] for v in vs)/3 for k in range(3)]
 radius=math.hypot(center[0],center[2])
 e=[vs[1][i]-vs[0][i] for i in range(3)]
 f=[vs[2][i]-vs[0][i] for i in range(3)]
 norm=(e[1]*f[2]-e[2]*f[1],e[2]*f[0]-e[0]*f[2],e[0]*f[1]-e[1]*f[0])
 is_led=radius>32.5
 if is_led:
  counts['V19_GREEN_UNCHANGED']+=1
  for k in range(3):out.append(oldring.verts[ring.indices[3*face+k]])
  continue
 # top/bottom: plate details; radial sides: vertical channel or machinery.
 kind='I029' if abs(norm[1])>=max(abs(norm[0]),abs(norm[2])) else ('I031' if radius>28 else 'I034')
 counts[kind]+=1
 x0,y0,x1,y1=catalog[kind]
 mean_angle=math.atan2(center[2],center[0])
 half_segment=math.pi/12
 sector=round(mean_angle/(2*half_segment))*(2*half_segment)
 for vert in vs:
  theta=math.atan2(vert[2],vert[0])
  angle_delta=math.atan2(math.sin(theta-sector),math.cos(theta-sector))
  tangential=max(-1,min(1,angle_delta/half_segment))
  rr=math.hypot(vert[0],vert[2])
  # Clear visual paneling at model scale: project ring angular dimension to
  # x and cross-section dimension to y, without sampling adjacent islands.
  u_pix=(x0+x1)*.5+tangential*(x1-x0)*.42
  v_pix=(y0+y1)*.5+(rr-28)*12+(vert[1]-center[1])*3
  u_pix=max(x0+6,min(x1-6,u_pix))
  v_pix=max(y0+6,min(y1-6,v_pix))
  out.append((*vert[:6],u_pix/4096,1-v_pix/4096))
assert len(out)==len(ring.verts)
ring.verts=out
for name,p in pieces.items():
 original=snapshot[name]
 assert p.indices==original[1] and p.offset==original[2]
 if name!='ring5':assert p.verts==original[0],name
assert all(a[:6]==b[:6] for a,b in zip(ring.verts,snapshot['ring5'][0]))
for face in range(len(ring.indices)//3):
 vs=[ring.verts[ring.indices[3*face+k]] for k in range(3)]
 c=[sum(v[k] for v in vs)/3 for k in range(3)]
 if math.hypot(c[0],c[2])>32.5:
  assert all(ring.verts[ring.indices[3*face+k]][6:]==oldring.verts[ring.indices[3*face+k]][6:] for k in range(3))
print('Ring UV faces',dict(counts),'green from verified V19 identical')
print('Protected geometry and all other pieces unchanged')
if '--apply' in sys.argv:
 save(new,str(PATH));print('Saved',hashlib.sha256(PATH.read_bytes()).hexdigest())
else:print('Dry run')

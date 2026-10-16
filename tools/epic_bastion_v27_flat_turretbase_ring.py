#!/usr/bin/env python3
"""V27: one flat turretbase annulus; remove V26 3 pillars; gray the three rear cannon support plates.
Deliberately preserves the five animated rings, every gauss UV and geometry, and stock pylon.
"""
import sys,copy,math,collections,hashlib
from pathlib import Path
sys.path.insert(0,'tools')
from build_epic_bastion_model import load,save,walk,Piece
P=Path('objects3d/Units/legbastiont3.s3o')
m=load(str(P))
existing={p.name:p for p in walk(m.root)}
original={n:(copy.deepcopy(p.verts),tuple(p.indices),p.offset,p.primitive) for n,p in existing.items()}
assert 'epic_cradle_turretbase_bridge' in existing,'V26 three-arm bridge not found'
bridge=existing['epic_cradle_turretbase_bridge']
assert len(bridge.indices)==108 and len(bridge.verts)==72,'Unexpected bridge: refuse to remove another object'
assert bridge in existing['base'].children,'Bridge not attached to base as expected'
existing['base'].children.remove(bridge)
# Construct a CLOSED annular section (not a central disk, not a fifth/swirling ring).
# The old top bowl was around y=177, with two removed raised collars.
# Replace those raised collars with a single low, wide, flat perimeter.
# Inner radius overlaps the central turretbase's outer edge; outer radius holds the 5-ring envelope.
INNER=11.8; OUTER=37.8; BOTTOM=174.5; TOP=176.7; N=64
# Gray metallic top and bronze side follow original Legion palette; avoid teamcolor and bright atlas patches.
# Safe inset rectangles from documented Legion texture-island catalog:
TOP_ARMOR=(24,24,264,252)      # I001 flat gray
LOWER_ARMOR=(788,24,1040,252) # I010 flat bronze
INNER_EDGE=(1560,24,1812,252) # I018 dark gray
def atlas(rect,u,v):
 x0,y0,x1,y1=rect
 u=max(.12,min(.88,u));v=max(.12,min(.88,v))
 return ((x0+(x1-x0)*u)/4096,1-(y0+(y1-y0)*v)/4096)
verts=[];indices=[]
def quad(p0,p1,p2,p3,rect,uvs=None):
 # Closed top/bottom and side panels have explicit normals and isolated UVs.
 a=(p1[0]-p0[0],p1[1]-p0[1],p1[2]-p0[2])
 b=(p2[0]-p0[0],p2[1]-p0[1],p2[2]-p0[2])
 cross=(a[1]*b[2]-a[2]*b[1],a[2]*b[0]-a[0]*b[2],a[0]*b[1]-a[1]*b[0])
 d=math.sqrt(sum(x*x for x in cross))
 assert d>1e-5
 normal=tuple(x/d for x in cross)
 base=len(verts)
 uvs=uvs or ((.12,.20),(.88,.20),(.88,.80),(.12,.80))
 for pos,st in zip((p0,p1,p2,p3),uvs):
  verts.append((*pos,*normal,*atlas(rect,*st)))
 indices.extend((base,base+1,base+2,base,base+2,base+3))
def xyz(r,a,y):return (r*math.cos(a),y,r*math.sin(a))
# Each panel is physically connected to the next, but UV-seamed: no texture bleed.
for j in range(N):
 a=2*math.pi*j/N;b=2*math.pi*(j+1)/N
 # top normal +Y; bottom -Y. Four edges form a watertight closed annulus.
 quad(xyz(INNER,a,TOP),xyz(INNER,b,TOP),xyz(OUTER,b,TOP),xyz(OUTER,a,TOP),TOP_ARMOR)
 quad(xyz(OUTER,a,BOTTOM),xyz(OUTER,b,BOTTOM),xyz(INNER,b,BOTTOM),xyz(INNER,a,BOTTOM),LOWER_ARMOR)
 quad(xyz(OUTER,a,TOP),xyz(OUTER,b,TOP),xyz(OUTER,b,BOTTOM),xyz(OUTER,a,BOTTOM),LOWER_ARMOR)
 quad(xyz(INNER,b,TOP),xyz(INNER,a,TOP),xyz(INNER,a,BOTTOM),xyz(INNER,b,BOTTOM),INNER_EDGE)
# 64 sectors, all closed: 4 quads each, 2 triangles each.
assert len(indices)==N*4*6
support=Piece('epic_turretbase_flat_support_ring',(0.,0.,0.),verts,indices,0,0,[])
existing['base'].children.append(support)

# Three triangular rear support armor components behind the cannon housings.
# Connected components are detected geometrically; do not recolor the cannons or
# any existing stock Bastion pylon faces. Core faces 0/120/240 known from V25/V26 audit.
base=existing['base']
tri=[base.indices[i:i+3] for i in range(0,len(base.indices),3)]
posowners=collections.defaultdict(list)
for fi,ids in enumerate(tri):
 for vid in ids:posowners[tuple(round(q,2) for q in base.verts[vid][:3])].append(fi)
parent=list(range(len(tri)))
def find(i):
 while parent[i]!=i:parent[i]=parent[parent[i]];i=parent[i]
 return i
def union(i,j):
 a,b=find(i),find(j)
 if a!=b:parent[b]=a
for owners in posowners.values():
 for other in owners[1:]:union(owners[0],other)
groups=collections.defaultdict(list)
for i in range(len(tri)):groups[find(i)].append(i)
byfirst={min(v):v for v in groups.values()}
target=set()
for start in (0,120,240):
 faces=byfirst.get(start)
 assert faces and len(faces)==96,('rear armor geometry moved',start,len(faces) if faces else None)
 positions=[base.verts[k] for fi in faces for k in tri[fi]]
 assert 97<min(v[1] for v in positions) and max(v[1] for v in positions)<117,start
 for fi in faces:target.add(fi)
assert len(target)==288
# Mutate UV only; split target triangle vertices so other nearby plates cannot inherit recoloring.
# I001 gray flat plate, interior crop. Coherent local planar UV based on each radial assembly.
original_vertices=list(base.verts)
newverts=list(base.verts);newidx=[]
for fi,idxs in enumerate(tri):
 if fi not in target:
  newidx.extend(idxs)
  continue
 face=[original_vertices[v] for v in idxs]
 cx=sum(v[0] for v in face)/3
 cz=sum(v[2] for v in face)/3
 angle=math.atan2(cz,cx)
 # Radial/tangential projection onto light-gray stock Legion panel.
 tx,tz=-math.sin(angle),math.cos(angle)
 for v in face:
  tangential=v[0]*tx+v[2]*tz
  s=.5+tangential/36
  t=.5+(v[1]-107)/35
  newverts.append((*v[:6],*atlas(TOP_ARMOR,s,t)))
  newidx.append(len(newverts)-1)
used=sorted(set(newidx));remap={old:i for i,old in enumerate(used)}
base.verts=[newverts[k] for k in used]
base.indices=[remap[k] for k in newidx]
# Before/after indexed worldspace check; all source geometry unchanged.
oldverts,oldidx,off,prim=original['base']
assert len(base.indices)==len(oldidx)
for i in range(len(oldidx)):
 assert base.verts[base.indices[i]][:6]==oldverts[oldidx[i]][:6],('base moved',i)
for name,obj in existing.items():
 if name in ('base','epic_cradle_turretbase_bridge'):continue
 o=original[name]
 assert obj.verts==o[0] and tuple(obj.indices)==o[1] and obj.offset==o[2] and obj.primitive==o[3],name
# Explicit checks for required five rings / all cannon barrels.
assert all(f'ring{i}' in existing for i in (2,3,4,5)) and 'ring' in existing
assert len(list(walk(m.root)))==len(original)  # remove bridge, add support
print('V27 validated: removed 3 added bridge arms; 1 watertight flat support annulus',INNER,OUTER,BOTTOM,TOP)
print('V27 cannon-rear light-gray armor faces',len(target),'all cannon UV / ring geometry and original pylon protected')
if '--apply' in sys.argv:
 save(m,str(P))
 check=load(str(P))
 assert 'epic_turretbase_flat_support_ring' in {q.name for q in walk(check.root)}
 assert 'epic_cradle_turretbase_bridge' not in {q.name for q in walk(check.root)}
 print('V27_SAVED',str(P),hashlib.sha256(P.read_bytes()).hexdigest())
else:print('V27_DRY_RUN')

#!/usr/bin/env python3
"""Epic Bastion Legion atlas: fix S3O vertical UV origin with coherent panel mapping (no geometry/animation changes)."""
import struct,math,sys,collections,hashlib
from pathlib import Path
H=struct.Struct('<12sI5f4I')
P=struct.Struct('<10I3f')
V=struct.Struct('<8f')
source=Path('objects3d/Units/legbastiont3.s3o')
data=source.read_bytes()
h=H.unpack_from(data)
assert h[0].startswith(b'Spring unit')
class Piece:
 def __init__(self,n,off,verts,idx,prim,vtype,children):
  self.name,self.offset,self.verts,self.indices,self.primitive,self.vert_type,self.children=n,off,verts,idx,prim,vtype,children
def read(off):
 a=P.unpack_from(data,off)
 name=data[a[0]:data.index(b'\0',a[0])].decode()
 verts=[V.unpack_from(data,a[4]+j*V.size) for j in range(a[3])]
 idx=list(struct.unpack_from('<'+'I'*a[7],data,a[8])) if a[7] else []
 children=[read(x) for x in struct.unpack_from('<'+'I'*a[1],data,a[2])] if a[1] else []
 return Piece(name,tuple(a[10:]),verts,idx,a[6],a[5],children)
root=read(h[7])
pieces={}
def walk(p):
 pieces[p.name]=p
 for c in p.children:walk(c)
walk(root)
assert len(pieces)==33
# Pixel-verified 2048x2048 atlas locations. All boxes lie wholly inside an actual
# Legion surface; exclude seams, yellow/black hazards, and neighboring panels.
# Verified from the actual official leg_color.dds displayed at 2048 pixels.
# IMPORTANT: preview pixel Y increases DOWN; S3O V increases UP.
# All regions deliberately stay inside flat artwork, away from hazard lines.
PATCHES={
 'cradle_plate':(40,26,103,52),     # neutral gray armor panel
 'cradle_side':(49,83,112,105),     # neutral gray inset plate
 'ring_light_gray':(46,26,115,51), # light gray plating
 'ring_edge_gray':(173,24,220,50), # separate gray trim
 'indicator_green':(130,1552,135,1558), # sampled true green LED pixel
}

def map_faces(mesh,editable,choose):
 vertices=mesh.verts
 indices=mesh.indices
 assert len(indices)%3==0
 new_verts=[]
 new_indices=[]
 old_to_new={}
 used=collections.Counter()
 for face in range(len(indices)//3):
  tri=indices[3*face:3*face+3]
  vs=[vertices[q] for q in tri]
  if not editable(face,tri,vs):
   for idx in tri:
    if idx not in old_to_new:
     old_to_new[idx]=len(new_verts)
     new_verts.append(vertices[idx])
    new_indices.append(old_to_new[idx])
   continue
  p=[v[:3] for v in vs]
  d1=[p[1][i]-p[0][i] for i in range(3)]
  d2=[p[2][i]-p[0][i] for i in range(3)]
  n=(d1[1]*d2[2]-d1[2]*d2[1],d1[2]*d2[0]-d1[0]*d2[2],d1[0]*d2[1]-d1[1]*d2[0])
  mid=[sum(v[i] for v in vs)/3 for i in range(3)]
  patch=choose(mid,n,face)
  used[patch]+=1
  x0,y0,x1,y1=PATCHES[patch]
  axis=max(range(3),key=lambda i:abs(n[i]))
  dims=[i for i in range(3) if i!=axis]
  q=[(v[dims[0]],v[dims[1]]) for v in p]
  # Coherent world-space projection: adjacent triangles on a surface sample
  # the same location instead of each triangle stretching an entire plate.
  # Repeat a clean subsection at panel scale. Atlas occupies 2048x2048 px.
  x0,y0,x1,y1=PATCHES[patch]
  cx=(x0+x1)*.5;cy=(y0+y1)*.5
  # Restrict within safe interior. x/y world units map to a few atlas pixels.
  horizontal=max(1.,(x1-x0)*.34)
  vertical=max(1.,(y1-y0)*.34)
  for vert,xy in zip(vs,q):
   px=cx+((xy[0]*.45+horizontal)%(2*horizontal)-horizontal)
   py=cy+((xy[1]*.38+vertical)%(2*vertical)-vertical)
   u=px/2048
   v=1.0-py/2048   # CRITICAL: flipped vertical atlas origin
   new_indices.append(len(new_verts))
   new_verts.append((*vert[:6],u,v))
 mesh.verts=new_verts
 mesh.indices=new_indices
 return dict(used)
def body_material(c,n,face):
 x,y,z=c
 ax,ay,az=map(abs,n)
 r=math.hypot(x,z)
 if y>170:return 'grey_armour'
 if y>140 and ay>ax+az:return 'dark_armour'
 if y>140 and r<23:return 'machinery_2'
 if y>124 and r<17:return 'machinery'
 if y>124 and r>30:return 'dark_armour_2'
 if y>95 and r>34:return 'dark_armour'
 if y>96 and r<23:return 'metal_strip' if ay<ax+az else 'machinery'
 if y<=96 and r>40:return 'dark_plate'
 if y<=96 and r<=40:return 'dark_armour_2'
 return 'grey_armour'
counts={}
# Preserve the correctly UV-mapped stock lower Bastion and cannon donors.
# Only upper Epic-specific shell/cradle materials are replaced.
counts['base']=map_faces(
 pieces['base'],
 lambda face,tri,vs:(sum(v[1] for v in vs)/3>112 and math.hypot(sum(v[0] for v in vs)/3,sum(v[2] for v in vs)/3)<56),
 lambda c,n,f:'cradle_plate' if abs(n[1])>.48 else 'cradle_side')
def ring_material(c,n,face):
 r=math.hypot(c[0],c[2])
 if r>32.5:return 'indicator_green'
 if abs(n[1])>max(abs(n[0]),abs(n[2])):return 'ring_light_gray'
 return 'ring_edge_gray'
counts['ring5']=map_faces(pieces['ring5'],lambda *args:True,ring_material)

def align(buf):
 while len(buf)%4:buf.append(0)
def strz(buf,value):
 offset=len(buf);buf.extend(value.encode()+b'\0');return offset
def write(buf,p):
 align(buf)
 at=len(buf);buf.extend(b'\0'*P.size)
 name_at=strz(buf,p.name)
 vo=0
 if p.verts:
  align(buf);vo=len(buf)
  for vert in p.verts:buf.extend(V.pack(*vert))
 io=0
 if p.indices:
  align(buf);io=len(buf)
  buf.extend(struct.pack('<'+'I'*len(p.indices),*p.indices))
 children=[write(buf,child) for child in p.children]
 co=0
 if children:
  align(buf);co=len(buf)
  buf.extend(struct.pack('<'+'I'*len(children),*children))
 P.pack_into(buf,at,name_at,len(children),co,len(p.verts),vo,p.vert_type,p.primitive,len(p.indices),io,0,*p.offset)
 return at
out=bytearray(b'\0'*H.size)
ro=write(out,root)
def original_string(offset):return data[offset:data.index(b'\0',offset)].decode()
t1=strz(out,original_string(h[9]))
t2=strz(out,original_string(h[10]))
H.pack_into(out,0,b'Spring unit\0',h[1],h[2],h[3],*h[4:7],ro,0,t1,t2)
source.write_bytes(out)
print('Remapped',counts,'size',len(out),'SHA256',hashlib.sha256(out).hexdigest())

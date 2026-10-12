#!/usr/bin/env python3
"""Remove only V15's three clipped-triangle cannon mount meshes, preserving their pivot pieces and children."""
import struct
from pathlib import Path

path=Path("objects3d/Units/legbastiont3.s3o")
data=path.read_bytes()
H=struct.Struct("<12sI5f4I");P=struct.Struct("<10I3f");V=struct.Struct("<8f")
h=H.unpack_from(data)
assert h[0].startswith(b"Spring unit")
class Piece:
 def __init__(self,n,off,verts,idx,vt,pr,ch):
  self.name,self.offset,self.verts,self.indices,self.vtype,self.primitive,self.children=n,off,verts,idx,vt,pr,ch
def parse(at):
 a=P.unpack_from(data,at);name=data[a[0]:data.index(b"\0",a[0])].decode()
 verts=[V.unpack_from(data,a[4]+j*V.size) for j in range(a[3])]
 idx=list(struct.unpack_from("<"+"I"*a[7],data,a[8])) if a[7] else []
 children=[parse(j) for j in struct.unpack_from("<"+"I"*a[1],data,a[2])] if a[1] else []
 return Piece(name,a[10:],verts,idx,a[5],a[6],children)
root=parse(h[7]);found={}
def walk(p):
 found[p.name]=p
 for c in p.children:walk(c)
walk(root)
assert len(found)==33,(len(found),list(found))
for i in (1,2,3):
 p=found[f"extension_root_{i}"]
 assert len(p.verts)>0 and len(p.indices)>0, f"already removed: {p.name}"
 print(f"Removing visual triangle from {p.name}: {len(p.verts)} vertices, {len(p.indices)//3} faces; preserving {len(p.children)} children")
 p.verts=[];p.indices=[]
def pad(b):
 while len(b)%4:b.append(0)
def string(b,v):
 off=len(b);b.extend(v.encode()+b"\0");return off
def write(b,p):
 pad(b);off=len(b);b.extend(b"\0"*P.size);name=string(b,p.name)
 vo=0
 if p.verts:
  pad(b);vo=len(b)
  for v in p.verts:b.extend(V.pack(*v))
 io=0
 if p.indices:
  pad(b);io=len(b);b.extend(struct.pack("<"+"I"*len(p.indices),*p.indices))
 children=[write(b,c) for c in p.children];co=0
 if children:
  pad(b);co=len(b);b.extend(struct.pack("<"+"I"*len(children),*children))
 P.pack_into(b,off,name,len(children),co,len(p.verts),vo,p.vtype,p.primitive,len(p.indices),io,0,*p.offset)
 return off
b=bytearray(b"\0"*H.size);ro=write(b,root)
def oldstring(off):return data[off:data.index(b"\0",off)].decode()
t1=string(b,oldstring(h[9]));t2=string(b,oldstring(h[10]))
H.pack_into(b,0,b"Spring unit\0",h[1],h[2],h[3],*h[4:7],ro,0,t1,t2)
path.write_bytes(b)
# Verify after serialization
data=b;found={}
walk(parse(H.unpack_from(b)[7]))
assert len(found)==33
assert all(not found[f"extension_root_{i}"].verts for i in (1,2,3))
assert all(found[f"gauss{i}_yaw"].children for i in (1,2,3))
print("SUCCESS: only three mount meshes removed; hierarchy retained",len(b),"bytes")

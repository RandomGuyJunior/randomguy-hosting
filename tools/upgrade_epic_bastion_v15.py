import struct, math, sys, hashlib
from pathlib import Path
src=Path("objects3d/Units/legbastiont3.s3o").read_bytes()
HEADER=struct.Struct("<12sI5f4I"); PIECE=struct.Struct("<10I3f"); VERT=struct.Struct("<8f")
class Piece:
 def __init__(self,name,offset,verts,idx,prim,vtype,children): self.name,self.offset,self.verts,self.indices,self.primitive,self.vert_type,self.children=name,offset,verts,idx,prim,vtype,children
def parse(off):
 a=PIECE.unpack_from(src,off)
 name=src[a[0]:src.index(b"\0",a[0])].decode()
 v=[VERT.unpack_from(src,a[4]+i*VERT.size) for i in range(a[3])]
 idx=list(struct.unpack_from("<"+"I"*a[7],src,a[8])) if a[7] else []
 children=[parse(x) for x in struct.unpack_from("<"+"I"*a[1],src,a[2])] if a[1] else []
 return Piece(name,tuple(a[10:]),v,idx,a[6],a[5],children)
h=HEADER.unpack_from(src);root=parse(h[7]);pieces={}
def visit(p):
 pieces[p.name]=p
 for c in p.children: visit(c)
visit(root)
def rotate_y(x,z,a): return x*math.cos(a)+z*math.sin(a),-x*math.sin(a)+z*math.cos(a)
def rotate_subtree(p,a):
 p.verts=[(*rotate_y(v[0],v[2],a)[:1],v[1],rotate_y(v[0],v[2],a)[1],*rotate_y(v[3],v[5],a)[:1],v[4],rotate_y(v[3],v[5],a)[1],v[6],v[7]) for v in p.verts]
 for c in p.children:
  x,y,z=c.offset;x,z=rotate_y(x,z,a);c.offset=(x,y,z)
  rotate_subtree(c,a)
new_radius=51
for i,angle in [(1,0),(2,math.radians(-120)),(3,math.radians(120))]:
 yaw=pieces[f"gauss{i}_yaw"];old=yaw.offset
 theta=math.atan2(old[0],old[2])
 yaw.offset=(new_radius*math.sin(theta),old[1],new_radius*math.cos(theta))
 rotate_subtree(pieces[f"gauss{i}_pitch"],-theta)
 ext=pieces[f"extension_root_{i}"];ext.verts=[];ext.indices=[]
 poly=[(-19,-16),(19,-16),(24,-10),(5,24),(-5,24),(-24,-10)]
 ux,uz=math.sin(theta),math.cos(theta);cx,cz=ux*44,uz*44
 def pxy(x,z,y):
  xx,zz=rotate_y(x,z,theta);return (cx+xx,y,cz+zz)
 verts=[pxy(x,z,y) for y in (110,123) for x,z in poly]
 def plate_uv(x,y,z): return (.425+.0013*(x-cx),.092+.0010*(z-cz))
 raw=[];face_ids=[]
 def triangle(A,B,C,wanted=None):
  pa,pb,pc=[verts[q] for q in (A,B,C)]
  d1=[pb[k]-pa[k] for k in range(3)];d2=[pc[k]-pa[k] for k in range(3)]
  nn=(d1[1]*d2[2]-d1[2]*d2[1],d1[2]*d2[0]-d1[0]*d2[2],d1[0]*d2[1]-d1[1]*d2[0])
  if wanted is not None and sum(nn[k]*wanted[k] for k in range(3))<0:
   B,C=C,B;pb,pc=pc,pb;nn=tuple(-q for q in nn)
  length=math.sqrt(sum(q*q for q in nn)) or 1;nn=tuple(q/length for q in nn)
  start=len(raw)
  for q in (pa,pb,pc):raw.append((*q,*nn,*plate_uv(*q)))
  face_ids.extend([start,start+1,start+2])
 n=len(poly)
 for j in range(1,n-1):
  triangle(n,n+j+1,n+j,(0,1,0))
  triangle(0,j,j+1,(0,-1,0))
 for j in range(n):
  k=(j+1)%n;triangle(j,k,n+k);triangle(j,n+k,n+j)
 ext.verts=raw;ext.indices=face_ids
base=pieces["base"];fixed=[]
for j,v in enumerate(base.verts):
 x,y,z,nx,ny,nz,u,w=v
 if j<8500:
  u=max(.386,min(.525,u))
  w=.055+(max(.03,min(.43,w))-.03)/.40*.075
 fixed.append((x,y,z,nx,ny,nz,u,w))
base.verts=fixed
p=pieces["ring5"];fixed=[]
for v in p.verts:
 x,y,z,nx,ny,nz,u,w=v
 t=(math.atan2(z,x)/(2*math.pi))%1
 u=.405+t*.105
 w=.070+min(1.0,math.hypot(x,z)/38.0)*.055
 fixed.append((x,y,z,nx,ny,nz,u,w))
p.verts=fixed
def align4(buf):
 while len(buf)%4:buf.append(0)
def string(buf,s):
 i=len(buf);buf.extend(s.encode()+b"\0");return i
def write(buf,p):
 align4(buf);off=len(buf);buf.extend(b"\0"*PIECE.size);nm=string(buf,p.name)
 vo=0
 if p.verts:
  align4(buf);vo=len(buf)
  for v in p.verts:buf.extend(VERT.pack(*v))
 io=0
 if p.indices:
  align4(buf);io=len(buf);buf.extend(struct.pack("<"+"I"*len(p.indices),*p.indices))
 child=[write(buf,c) for c in p.children];co=0
 if child:
  align4(buf);co=len(buf);buf.extend(struct.pack("<"+"I"*len(child),*child))
 PIECE.pack_into(buf,off,nm,len(child),co,len(p.verts),vo,p.vert_type,p.primitive,len(p.indices),io,0,*p.offset)
 return off
buf=bytearray(b"\0"*HEADER.size);ro=write(buf,root);t1=string(buf,"leg_color.dds");t2=string(buf,"leg_shader.dds")
HEADER.pack_into(buf,0,b"Spring unit\0",0,h[2],h[3],h[4],h[5],h[6],ro,0,t1,t2)
out=Path("objects3d/Units/legbastiont3.s3o");out.write_bytes(buf)
digest=hashlib.sha256(buf).hexdigest()
print("V15 generated",len(buf),digest)
assert digest=="073677122cd2daf67b9e8f44d68f5d89694669b75e02f8d79b9cb99b104dce9b", "Generated S3O is NOT the V15 file: refusing to commit"

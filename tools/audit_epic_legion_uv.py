#!/usr/bin/env python3
"""Compare stock Legion Bastion UVs with Epic Bastion; no writes."""
import struct,urllib.request,collections,math
from pathlib import Path
P=struct.Struct('<10I3f');V=struct.Struct('<8f');H=struct.Struct('<12sI5f4I')
def read_model(b):
 header=H.unpack_from(b)
 def part(o):
  a=P.unpack_from(b,o);n=b[a[0]:b.index(b'\0',a[0])].decode()
  vs=[V.unpack_from(b,a[4]+i*V.size) for i in range(a[3])]
  ch=[part(j) for j in struct.unpack_from('<'+'I'*a[1],b,a[2])] if a[1] else []
  return (n,vs,ch)
 root=part(header[7]);data={}
 def walk(x):
  n,v,ch=x;data[n]=v
  for child in ch:walk(child)
 walk(root)
 return data
try:
 stock=urllib.request.urlopen('https://raw.githubusercontent.com/RandomGuyJunior/Beyond-All-Reason/master/objects3d/Units/legbastion.s3o',timeout=45).read()
except Exception:
 stock=urllib.request.urlopen('https://raw.githubusercontent.com/beyond-all-reason/Beyond-All-Reason/master/objects3d/Units/legbastion.s3o',timeout=45).read()
old=read_model(stock);new=read_model(Path('objects3d/Units/legbastiont3.s3o').read_bytes())
print('Original pieces:',list(old))
print('Epic pieces:',list(new))
for name in ('base','turret','ring','ring2','ring3','ring4','ring5','ringanchor'):
 for tag,d in (('stock',old),('epic',new)):
  v=d.get(name,[])
  if not v:continue
  u=[x[6] for x in v];w=[x[7] for x in v]
  coords=collections.Counter((round(x[6],2),round(x[7],2)) for x in v)
  print(name,tag,'verts',len(v),'U',round(min(u),3),round(max(u),3),'V',round(min(w),3),round(max(w),3),'top UV',coords.most_common(7))
print('ORIGINAL STOCK BASE UV SPATIAL SAMPLES')
for v in old.get('base',[])[:25]:print(tuple(round(q,3) for q in v[:3]),tuple(round(q,4) for q in v[6:8]))

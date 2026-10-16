#!/usr/bin/env python3
import sys, math,collections,urllib.request
from pathlib import Path
sys.path.insert(0,'tools')
from build_epic_bastion_model import load,walk
m=load('objects3d/Units/legbastiont3.s3o')
root=next(p for p in walk(m.root) if p.name=='base')
# connected triangles through shared position even if verts have UV seams; quantization
parents=list(range(len(root.indices)//3))
def parent(i):
 while parents[i]!=i:
  parents[i]=parents[parents[i]];i=parents[i]
 return i
def join(a,b):
 a=parent(a);b=parent(b)
 if a!=b:parents[b]=a
ownership={}
for ti in range(len(parents)):
 for j in root.indices[3*ti:3*ti+3]:
  v=root.verts[j]
  key=tuple(round(x,3) for x in v[:3])
  prev=ownership.setdefault(key,ti)
  join(ti,prev)
components=collections.defaultdict(list)
for i in range(len(parents)):components[parent(i)].append(i)
print('BASE_COMPONENT_COUNT',len(components))
for _,ts in sorted(components.items(),key=lambda kv:-len(kv[1]))[:90]:
 vertices=[root.verts[j] for t in ts for j in root.indices[3*t:3*t+3]]
 ys=[v[1] for v in vertices];rs=[math.hypot(v[0],v[2]) for v in vertices]
 print('COMPONENT',len(ts),'Y',round(min(ys),2),round(max(ys),2),'R',round(min(rs),2),round(max(rs),2),'sample',tuple(round(z,2) for z in vertices[0][:3]))
# Compare donor exact geometry matches at vertex level
url='https://raw.githubusercontent.com/beyond-all-reason/Beyond-All-Reason/master/objects3d/Units/legbastion.s3o'
p=Path('/tmp/legbastion_stock.s3o');p.write_bytes(urllib.request.urlopen(url,timeout=50).read());old=load(str(p))
for op in walk(old.root):
 if not op.verts:continue
 print('STOCK_PIECE',op.name,'count',len(op.verts),'Y',round(min(v[1] for v in op.verts),2),round(max(v[1] for v in op.verts),2))
orig_base=next(p for p in walk(old.root) if p.name=='base')
key=lambda v:tuple(round(x,4) for x in v[:6])
donor=collections.defaultdict(set)
for v in orig_base.verts:donor[key(v)].add(tuple(round(x,7) for x in v[6:]))
match=sum(len(donor.get(key(v),()))==1 for v in root.verts)
print('STOCK_EXACT_UV_MATCHES',match,'of',len(root.verts))

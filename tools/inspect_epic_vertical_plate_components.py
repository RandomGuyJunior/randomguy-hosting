#!/usr/bin/env python3
import sys,collections,math
sys.path.insert(0,'tools')
from build_epic_bastion_model import load,walk
m=load('objects3d/Units/legbastiont3.s3o'); p=next(p for p in walk(m.root) if p.name=='base')
tri=[p.indices[i:i+3] for i in range(0,len(p.indices),3)]
owners=collections.defaultdict(list)
for fi,ids in enumerate(tri):
 for idx in ids:
  owners[tuple(round(a,3) for a in p.verts[idx][:3])].append(fi)
parent=list(range(len(tri)))
def f(i):
 while parent[i]!=i:parent[i]=parent[parent[i]];i=parent[i]
 return i
for hits in owners.values():
 a=f(hits[0])
 for b in hits[1:]:
  x=f(b)
  if x!=a:parent[x]=a
groups=collections.defaultdict(list)
for fi in range(len(tri)):groups[f(fi)].append(fi)
print('COMPONENT_COUNT',len(groups),'BASE_TRIS',len(tri),'BASE_VERTS',len(p.verts))
for group in sorted(groups.values(),key=lambda g:min(g)):
 pts=[p.verts[j] for fi in group for j in tri[fi]]
 y=[x[1] for x in pts];r=[math.hypot(x[0],x[2]) for x in pts]
 x=[a[0] for a in pts];z=[a[2] for a in pts]
 u=[a[6] for a in pts];v=[a[7] for a in pts]
 print('COMP start=%d n=%d y=%.2f..%.2f r=%.2f..%.2f x=%.2f..%.2f z=%.2f..%.2f uv=%.3f..%.3f/%.3f..%.3f'%(min(group),len(group),min(y),max(y),min(r),max(r),min(x),max(x),min(z),max(z),min(u),max(u),min(v),max(v)))

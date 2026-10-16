#!/usr/bin/env python3
"""Inspect connected triangle islands in Epic base before destructive cleanup."""
import sys,collections,math
sys.path.insert(0,'tools')
from build_epic_bastion_model import load,walk
m=load('objects3d/Units/legbastiont3.s3o')
for p in walk(m.root):
 if p.name not in ('base','extension_root_1','extension_root_2','extension_root_3','gauss1_pitch','gauss1_barrel'):continue
 print('PIECE',p.name,'verts',len(p.verts),'triangles',len(p.indices)//3)
 if not p.indices:continue
 tris=[p.indices[i:i+3] for i in range(0,len(p.indices),3)]
 # vertex position-based connectivity so disconnected UV seams remain connected
 key=lambda v:tuple(round(x,2) for x in v[:3])
 adj=collections.defaultdict(list)
 for i,t in enumerate(tris):
  for j in t:adj[key(p.verts[j])].append(i)
 parent=list(range(len(tris)))
 def find(i):
  while parent[i]!=i:parent[i]=parent[parent[i]];i=parent[i]
  return i
 def union(a,b):
  a=find(a);b=find(b)
  if a!=b:parent[b]=a
 for group in adj.values():
  if len(group)>1:
   a=group[0]
   for b in group[1:]:union(a,b)
 groups=collections.defaultdict(list)
 for i,t in enumerate(tris):groups[find(i)].append(i)
 for k,g in sorted(groups.items(),key=lambda kv:-len(kv[1]))[:90]:
  v={j for t in g for j in tris[t]}
  coords=[p.verts[j] for j in v]
  mn=[round(min(q[k] for q in coords),2) for k in range(3)]
  mx=[round(max(q[k] for q in coords),2) for k in range(3)]
  center=[round(sum(q[k] for q in coords)/len(coords),2) for k in range(3)]
  radii=[math.hypot(q[0],q[2]) for q in coords]
  print('COMP',p.name,'firstTri',min(g),'faces',len(g),'bbox',mn,mx,'center',center,'radial',round(min(radii),2),round(max(radii),2))

import sys,collections,math
sys.path.insert(0,'tools')
from build_epic_bastion_model import load,walk
m=load('objects3d/Units/legbastiont3.s3o')
for p in walk(m.root):
 if p.name not in ('base','gauss1_pitch','gauss1_barrel','extension_root_1','ring5'):continue
 print('PIECE',p.name,'verts',len(p.verts),'indices',len(p.indices))
 if p.name!='base':continue
 # vertex-index connected components, connected by triangle indices
 parent=list(range(len(p.verts)))
 def find(x):
  while parent[x]!=x:parent[x]=parent[parent[x]];x=parent[x]
  return x
 for k in range(0,len(p.indices),3):
  inds=p.indices[k:k+3]
  if len(inds)==3:
   for q in inds[1:]:parent[find(q)]=find(inds[0])
 d=collections.defaultdict(list)
 for t in range(0,len(p.indices),3):
  tri=p.indices[t:t+3]
  if len(tri)==3:d[find(tri[0])].append(t//3)
 rows=[]
 for ci,fs in d.items():
  vs={i for f in fs for i in p.indices[f*3:f*3+3]}
  coords=[p.verts[i] for i in vs];rs=[math.hypot(v[0],v[2]) for v in coords]
  ys=[v[1] for v in coords]
  rows.append((len(fs),min(ys),max(ys),min(rs),max(rs),sum(rs)/len(rs),ci))
 print('COMPONENTS',len(rows))
 for r in sorted(rows,reverse=True)[:70]:print('COMP',r)

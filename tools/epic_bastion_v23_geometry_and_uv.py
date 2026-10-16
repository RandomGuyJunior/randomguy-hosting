#!/usr/bin/env python3
"""V23: remove audited outer cradle + turretbase protrusions; recover donor UVs.
Never changes game script, cannon geometry or pivots. Explicit dry-run by default.
"""
import sys,math,collections,urllib.request,copy
from pathlib import Path
sys.path.insert(0,'tools')
from build_epic_bastion_model import load,save,walk
PATH=Path('objects3d/Units/legbastiont3.s3o')
model=load(str(PATH))
pieces={p.name:p for p in walk(model.root)}
before={name:(copy.deepcopy(p.verts),p.indices[:],p.offset,p.primitive) for name,p in pieces.items()}
def donor(sha,path):
 dst=Path('/tmp/'+sha[:12]+'.s3o')
 dst.write_bytes(urllib.request.urlopen('https://raw.githubusercontent.com/RandomGuyJunior/randomguy-hosting/'+sha+'/objects3d/Units/legbastiont3.s3o',timeout=70).read())
 return {p.name:p for p in walk(load(str(dst)).root)}
v19=donor('c472bcc1615bd50f549bb5294fbed5fdcc07add3','v19')
pre=donor('681351216bc87bb80ed44433ab769d46a05c4605','pre')
counts=collections.Counter()
# Good cannon texcoords: match normals/positions against V19 when identical.
for name in [f'gauss{i}_{kind}' for i in range(1,4) for kind in ('pitch','barrel')]:
 p=pieces[name];q=v19[name]
 assert len(p.verts)==len(q.verts) and p.indices==q.indices,name
 assert all(all(abs(a-b)<1e-4 for a,b in zip(x[:6],y[:6])) for x,y in zip(p.verts,q.verts)),name
 p.verts=[(*x[:6],*y[6:8]) for x,y in zip(p.verts,q.verts)]
 counts['cannon_UV_restored']+=len(p.verts)
# Restore original earlier geometry-matched, uniquely verified UV mapping on internal base.
p=pieces['base']
uvmap=collections.defaultdict(set)
def key(v):return tuple(round(x,4) for x in v[:6])
for v in pre['base'].verts:
 uvmap[key(v)].add(tuple(round(x,7) for x in v[6:8]))
new=[]
for v in p.verts:
 x,y,z=v[:3];r=math.hypot(x,z)
 # Target upper-center inherited Bastion geometry, not gauss barrels or bottom base.
 if y>=54 and r<48:
  choices=uvmap.get(key(v),set())
  if len(choices)==1:
   new.append((*v[:6],*next(iter(choices))))
   counts['inherited_original_Bastion_UVs']+=1
   continue
 new.append(v)
p.verts=new
# Connected islands are from actual model geometry, not vertex order or broad position.
tris=[p.indices[i:i+3] for i in range(0,len(p.indices),3)]
adj=collections.defaultdict(list)
for i,ids in enumerate(tris):
 for j in ids:adj[tuple(round(a,2) for a in p.verts[j][:3])].append(i)
parent=list(range(len(tris)))
def find(x):
 while parent[x]!=x:
  parent[x]=parent[parent[x]];x=parent[x]
 return x
def union(a,b):
 a=find(a);b=find(b)
 if a!=b:parent[b]=a
for links in adj.values():
 for j in links[1:]:union(links[0],j)
components=collections.defaultdict(list)
for i in range(len(tris)):components[find(i)].append(i)
by_first={min(v):v for v in components.values()}
for first,faces,expected in [(1128,384,'outer_surrounding_cradle_ring'),(4402,50,'upper_turretbase_two_arm_remnants')]:
 comp=by_first.get(first)
 assert comp is not None and len(comp)==faces,(first,len(comp) if comp else None)
 vertices=[p.verts[j] for i in comp for j in tris[i]]
 ys=[v[1] for v in vertices];rs=[math.hypot(v[0],v[2]) for v in vertices]
 if first==1128:assert min(ys)>170 and max(rs)>40 and max(rs)<42
 if first==4402:assert min(ys)>166 and max(ys)<179 and max(rs)<22
 counts['removed_'+expected]=len(comp)
remove_faces={i for key in (1128,4402) for i in by_first[key]}
# Keep original unmodified vertex positions; remove only faces & compact dangling vertices.
surviving=[j for i,t in enumerate(tris) if i not in remove_faces for j in t]
used=sorted(set(surviving))
reverse={old:i for i,old in enumerate(used)}
p.indices=[reverse[j] for j in surviving]
p.verts=[p.verts[j] for j in used]
# Protect the fifth ring and laser rings; do NOT alter any model piece other than base and cannon UV.
for name,piece in pieces.items():
 oldverts,oldidx,off,prim=before[name]
 assert piece.offset==off and piece.primitive==prim
 if name not in {'base',*(f'gauss{i}_{typ}' for i in range(1,4) for typ in ('pitch','barrel'))}:
  assert piece.verts==oldverts and piece.indices==oldidx,name
 elif name!='base':
  assert piece.indices==oldidx and len(piece.verts)==len(oldverts)
  assert all(a[:6]==b[:6] for a,b in zip(piece.verts,oldverts))
assert len(p.indices)==len(before['base'][1])-3*(384+50)
print('V23_VALIDATED',dict(counts),'base_faces',len(before['base'][1])//3,'->',len(p.indices)//3)
if '--apply' in sys.argv:
 save(model,str(PATH))
 print('V23_SAVED',PATH.stat().st_size)
else:print('V23_DRY_RUN')

#!/usr/bin/env python3
"""Recover untouched Epic Bastion UVs from the pre-V15 model by exact geometry matching.
Preserves all current geometry, indices, piece pivots, normals and cannon UVs.
Ambiguous/conflicting source samples remain unchanged rather than guessed.
"""
import sys,urllib.request,collections,math,hashlib,os
from pathlib import Path
sys.path.insert(0,'tools')
from build_epic_bastion_model import load,save,walk
PRE='681351216bc87bb80ed44433ab769d46a05c4605'
url=f'https://raw.githubusercontent.com/RandomGuyJunior/randomguy-hosting/{PRE}/objects3d/Units/legbastiont3.s3o'
out=Path('/tmp/epic_bastion_pre_uv.s3o')
out.write_bytes(urllib.request.urlopen(url,timeout=60).read())
old=load(str(out));new=load('objects3d/Units/legbastiont3.s3o')
src={p.name:p for p in walk(old.root)}
total=collections.Counter();changes=collections.Counter()
for p in walk(new.root):
 if p.name not in ('base','turret','ring5'):continue
 donor=src.get(p.name)
 if not donor:continue
 def key(v):return tuple(round(x,4) for x in v[:6])
 uv_by_key=collections.defaultdict(set)
 for v in donor.verts:
  uv_by_key[key(v)].add((round(v[6],7),round(v[7],7)))
 matches=0;ambiguous=0;changed=0;fixed=[]
 for v in p.verts:
  uvs=uv_by_key.get(key(v))
  if not uvs: fixed.append(v);continue
  if len(uvs)!=1:
   ambiguous+=1;fixed.append(v);continue
  u,w=next(iter(uvs));matches+=1
  if abs(v[6]-u)>1e-5 or abs(v[7]-w)>1e-5:changed+=1
  fixed.append((*v[:6],u,w))
 total[p.name]=len(p.verts);changes[p.name]=changed
 print(p.name,'vertices=',len(p.verts),'exact_unique_matches=',matches,'ambiguous=',ambiguous,'restored_different=',changed)
 p.verts=fixed
 print('unmatched=',len(p.verts)-matches-ambiguous)
assert sum(changes.values())>100, 'No substantial recovery identified; refusing to save'
print('total changed',sum(changes.values()))
if '--apply' in sys.argv:
 path='objects3d/Units/legbastiont3.s3o'
 before=Path(path).read_bytes()
 save(new,path)
 after=Path(path).read_bytes()
 print('WROTE',path,'before',hashlib.sha256(before).hexdigest(),'after',hashlib.sha256(after).hexdigest())
else:print('DRY RUN; no file changed')

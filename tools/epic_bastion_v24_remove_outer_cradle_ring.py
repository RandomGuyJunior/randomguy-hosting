#!/usr/bin/env python3
"""Remove ONLY the outermost original Bastion cradle ring visual, retaining pivots.
Protect extra fifth ring, laser pivot, scripts and the other three original rings.
"""
import sys, math, copy, collections, hashlib
from pathlib import Path
sys.path.insert(0,'tools')
from build_epic_bastion_model import load,save,walk
F=Path('objects3d/Units/legbastiont3.s3o')
m=load(str(F));ps={p.name:p for p in walk(m.root)}
original={n:(p.verts[:],p.indices[:],p.offset) for n,p in ps.items()}
def radius(p):
 return max(math.sqrt(v[0]**2+v[1]**2+v[2]**2) for v in p.verts)
names=('ring','ring2','ring3','ring4')
assert all(ps[n].verts and ps[n].indices for n in names)
radii={n:radius(ps[n]) for n in names}
ranked=sorted(radii,key=radii.get,reverse=True)
print('CRADLE_RING_RADII',radii,'largest',ranked[0])
# Only the outside visual ring can be removed. Preserve empty piece hierarchy so
# animation scripts can still reference the piece name without crashing.
assert ranked[0]=='ring',('Unexpected outermost cradle ring identity',radii)
assert radii['ring']>max(radii[n] for n in names if n!='ring')*1.025,('Ring size difference too small to identify safely',radii)
assert ps['ring5'].verts and ps['beam_yaw'] and ps['beam_pitch'] and ps['beam_muzzle']
ps['ring'].verts=[]
ps['ring'].indices=[]
for n,p in ps.items():
 oldverts,oldidx,off=original[n]
 assert p.offset==off,n
 if n!='ring':
  assert p.verts==oldverts and p.indices==oldidx,n
assert len(ps['ring5'].verts)==len(original['ring5'][0])
print('REMOVED_OUTERMOST_RING_VISUAL',ranked[0],'preserved',names[1:],'fifth ring and beam hierarchy untouched')
if '--apply' in sys.argv:
 save(m,str(F)); print('WROTE',str(F),'SHA256',hashlib.sha256(F.read_bytes()).hexdigest())
else: print('DRY_RUN')

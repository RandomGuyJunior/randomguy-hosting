#!/usr/bin/env python3
"""Reproduce local 2026-10-12 Epic Bastion UV-only test on current repo S3O."""
import math,sys,copy,hashlib
from pathlib import Path
sys.path.insert(0,'tools')
from build_epic_bastion_model import load,save,walk
source=Path('objects3d/Units/legbastiont3.s3o')
model=load(str(source));ps={p.name:p for p in walk(model.root)}
before={n:(copy.deepcopy(p.verts),p.indices[:],p.offset) for n,p in ps.items()}
islands={
'gray_plate':(300,972,556,1144),'gray_channel':(308,1172,444,1536),
'gray_machine':(592,980,740,1536),'gray_vent':(2200,3380,2448,3768),
'bronze_plate':(916,596,1508,744),'bronze_rect':(796,976,1064,1140),
'bronze_cross':(788,1176,1060,1524),'bronze_housing':(2060,2052,3052,2504),
'dark_recess':(1860,1184,2276,1524),'dark_track':(2556,968,3312,1256),
'green_light':(208,2848,300,3096),'green_tiny':(428,3232,480,3292)}
def clamp(q,a,b):return max(a,min(b,q))
def uv(kind,s,t,margin=6):
 x0,y0,x1,y1=islands[kind]
 return ((x0+margin+clamp(s,0,1)*(x1-x0-2*margin))/4096,
         (y0+margin+clamp(t,0,1)*(y1-y0-2*margin))/4096)
def cross(ps):
 e1=[ps[1][k]-ps[0][k] for k in range(3)];e2=[ps[2][k]-ps[0][k] for k in range(3)]
 return (e1[1]*e2[2]-e1[2]*e2[1],e1[2]*e2[0]-e1[0]*e2[2],e1[0]*e2[1]-e1[1]*e2[0])
def tri_map(p,choose):
 verts=[];inds=[]
 assert len(p.indices)%3==0
 for i in range(0,len(p.indices),3):
  tri=[p.verts[j] for j in p.indices[i:i+3]]
  output=choose(tri)
  for v,u,w in output:
   verts.append((*v[:6],u,w));inds.append(len(verts)-1)
 p.verts=verts;p.indices=inds

def ring_mapper(tri):
 c=[sum(v[k] for v in tri)/3 for k in range(3)]
 r=math.hypot(c[0],c[2]);n=cross(tri);norm=max(map(abs,n))+1e-9
 result=[]
 for v in tri:
  theta=(math.atan2(v[2],v[0])+math.pi)/(2*math.pi)
  ry=(math.hypot(v[0],v[2])-28.15)/(33.28-28.15)
  yy=(v[1]+1.8)/3.6
  if r>32.35: u,w=uv('green_tiny',.35+.3*theta,.35+.3*yy,4)
  elif abs(n[1])>.65*norm: u,w=uv('gray_plate',theta,.15+.7*ry,10)
  elif r>30.5: u,w=uv('gray_vent',theta,yy,8)
  elif r<29.1: u,w=uv('gray_machine',theta,yy,8)
  else: u,w=uv('gray_channel',theta,yy,8)
  result.append((v,u,w))
 return result
tri_map(ps['ring5'],ring_mapper)

def mount_mapper(tri):
 c=[sum(v[k] for v in tri)/3 for k in range(3)]
 n=cross(tri);ax,ay,az=map(abs,n)
 result=[]
 for v in tri:
  nx=(v[0]+13.1)/26.1;ny=(v[1]-96.6)/34.3;nz=(v[2]-4)/80
  if ay>=ax and ay>=az:
   kind='bronze_rect' if c[1]>110 else 'dark_recess';s,t=nz,nx
  elif az>=ax and az>=ay:
   kind='bronze_housing' if c[2]>30 else 'dark_recess';s,t=nx,ny
  else:
   kind='bronze_cross' if c[1]>110 else 'dark_recess';s,t=nz,ny
  result.append((v,*uv(kind,s,t,8)))
 return result
for i in (1,2,3):tri_map(ps[f'extension_root_{i}'],mount_mapper)

p=ps['base'];original=p.verts;newverts=p.verts[:];newidx=[];count=0
for start in range(0,len(p.indices),3):
 ids=p.indices[start:start+3];tri=[original[j] for j in ids]
 c=[sum(v[k] for v in tri)/3 for k in range(3)]
 r=math.hypot(c[0],c[2]);n=cross(tri);ax,ay,az=map(abs,n)
 region=None
 if c[1]>108 and r<11.5:region='pylon'
 elif c[1]>147 and 12<r<58:region='topannulus'
 elif 110<c[1]<155 and r<22:region='inner_support'
 if not region:
  newidx.extend(ids);continue
 count+=1
 for v in tri:
  theta=(math.atan2(v[2],v[0])+math.pi)/(2*math.pi)
  rr=clamp((math.hypot(v[0],v[2])-5)/55,0,1)
  yy=clamp((v[1]-100)/80,0,1)
  if region=='pylon':
   kind='gray_plate' if ay>=ax and ay>=az else 'gray_channel'
  elif region=='inner_support':
   kind='gray_plate' if ay>=ax and ay>=az else 'gray_machine'
  else:
   kind='bronze_plate' if ay>=ax and ay>=az else ('dark_recess' if r>28 else 'gray_channel')
  s=theta;t=rr if ay>=ax and ay>=az else yy
  u,w=uv(kind,s,t,8)
  newidx.append(len(newverts));newverts.append((*v[:6],u,w))
p.verts=newverts;p.indices=newidx
assert count>1000,(count,'No base UV faces selected')
for n,piece in ps.items():
 oldverts,oldidx,oldoff=before[n]
 assert piece.offset==oldoff,n
 if n not in {'base','ring5','extension_root_1','extension_root_2','extension_root_3'}:
  assert piece.indices==oldidx and piece.verts==oldverts,n
print('Remapped triangles: base',count,'ring5',len(ps['ring5'].indices)//3,'mounts',*[len(ps[f'extension_root_{i}'].indices)//3 for i in (1,2,3)])
print('All three cannons, their UVs, weapon script and pivots untouched')
if '--apply' in sys.argv:
 save(model,str(source))
 print('MODEL_COMMITTED_FILE_HASH',hashlib.sha256(source.read_bytes()).hexdigest())
else:print('DRY_RUN_SUCCESS')

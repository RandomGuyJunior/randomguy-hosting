"""Prototype ring5 UV edits *inside Blender*. Never touch deployed S3O."""
import bpy, math, json, os
from pathlib import Path
obj=bpy.data.objects.get("ring5")
assert obj is not None and obj.type=="MESH", "Cannot find ring5"
mesh=obj.data
assert len(mesh.polygons)==656, f"Unexpected ring faces: {len(mesh.polygons)}"
uv=mesh.uv_layers.active.data
# Safe island bounds from catalog (image pixels, 4096^2).
# Avoid mixed-content island boxes and atlas borders.
ISLANDS={
 "I029_gray_rivets":(300,972,556,1144),
 "I031_gray_channel":(308,1172,444,1536),
 "I063_machine_track":(2556,968,3312,1256),
 "I075_green_panel":(836,2256,956,2428),
}
def atlas_uv(kind,t,s):
 x0,y0,x1,y1=ISLANDS[kind]
 margin=10
 px=x0+margin+(x1-x0-2*margin)*max(0,min(1,t))
 py=y0+margin+(y1-y0-2*margin)*max(0,min(1,s))
 return (px/4096.0,1-py/4096.0)
counts={}
for poly in mesh.polygons:
 cx,cy,cz=poly.center
 r=math.hypot(cx,cz)
 n=poly.normal
 if r>32.5: kind="I075_green_panel"
 elif abs(n.y)>=max(abs(n.x),abs(n.z))*.85:
  kind="I029_gray_rivets"
 elif r>29.5: kind="I063_machine_track"
 else:kind="I031_gray_channel"
 counts[kind]=counts.get(kind,0)+1
 # UV unwrap every 30-degree ring sector as a bounded, complete machinery motif.
 phase=(math.atan2(cz,cx)+2*math.pi)%(2*math.pi)
 span=math.pi/6.0
 sector=int((phase+1e-6)//span)
 center=(sector+.5)*span
 for i in poly.loop_indices:
  v=mesh.vertices[mesh.loops[i].vertex_index].co
  a=math.atan2(v.z,v.x)
  delta=math.atan2(math.sin(a-center),math.cos(a-center))
  t=max(0,min(1,delta/span+.5))
  radial=(math.hypot(v.x,v.z)-28.15)/5.15
  axial=(v.y+1.8)/3.6
  if kind=="I075_green_panel":
   # Inside the strong green color, avoid the border / light bloom.
   t=.2+.6*t;s=.2+.6*axial
  elif kind=="I029_gray_rivets":s=radial
  elif kind=="I063_machine_track":s=axial
  else:s=axial
  uv[i].uv=atlas_uv(kind,t,s)
mesh.update()
report={"piece":"ring5","faces":len(mesh.polygons),"material_faces":counts,"UV_orientation":"Blender V = 1 - image-pixel Y/4096","island_pixel_rectangles":ISLANDS}
out=Path(os.environ["EPIC_BLEND"]).parent
(out/"epic_bastion_ring5_candidate.json").write_text(json.dumps(report,indent=2))
# Actual UV corner coordinates keyed by quantized imported mesh triangle vertex coordinates.
triangles=[]
for poly in mesh.polygons:
 corners=[]
 for i in poly.loop_indices:
  v=mesh.vertices[mesh.loops[i].vertex_index].co
  ucoord=uv[i].uv
  corners.append({"position":[round(v.x,5),round(v.y,5),round(v.z,5)],"uv":[float(ucoord.x),float(ucoord.y)]})
 triangles.append(corners)
(out/"epic_bastion_ring5_candidate_triangles.json").write_text(json.dumps(triangles))
print("RING5_CANDIDATE_UV_COMPLETE",counts,"triangleCount",len(triangles))

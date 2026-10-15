import bpy, os, json, math, csv
from pathlib import Path
# Called after S3O Kit import, texture relinking and packing.
out=Path(os.environ["EPIC_BLEND"]).parent
bpy.context.scene.render.engine='BLENDER_EEVEE'
bpy.context.scene.render.resolution_x=1280
bpy.context.scene.render.resolution_y=960
bpy.context.scene.render.resolution_percentage=100
bpy.context.scene.render.image_settings.file_format='PNG'
bpy.context.scene.render.film_transparent=False
bpy.context.scene.world.color=(0.09,0.09,0.09)
# Fixed orthographic cameras to make actual face texture problems comparable.
from mathutils import Vector
root=bpy.context.scene
meshes=[o for o in bpy.data.objects if o.type=='MESH']
assert meshes
def bound():
 pts=[]
 for o in meshes:
  for corner in o.bound_box:
   pts.append(o.matrix_world @ Vector(corner))
 return (Vector((sum(p[i] for p in pts)/len(pts) for i in range(3))),
         max((p-Vector((sum(q[i] for q in pts)/len(pts) for i in range(3)))).length for p in pts))
center,radius=bound()
cam_data=bpy.data.cameras.new('UV audit orthographic')
cam=bpy.data.objects.new('UV audit camera',cam_data)
root.collection.objects.link(cam)
root.camera=cam;cam_data.type='ORTHO';cam_data.ortho_scale=radius*2.5
def point_camera(loc):
 cam.location=loc
 direction=center-cam.location
 cam.rotation_euler=direction.to_track_quat('-Z','Y').to_euler()
for label,shift in [('iso',(1.4,-1.7,1.3)),('front',(0,-2.0,0.5)),('top',(0.01,-0.01,2.0))]:
 loc=center+Vector(shift)*radius*1.8
 point_camera(loc)
 root.render.filepath=str(out/f'epic_bastion_uv_audit_{label}.png')
 bpy.ops.render.render(write_still=True)
 print('RENDERED_UV_AUDIT',root.render.filepath,Path(root.render.filepath).stat().st_size)
# Detailed per-region UV report, no geometry or S3O writes.
rows=[]
for o in meshes:
 layer=o.data.uv_layers.active
 if not layer:continue
 for poly in o.data.polygons:
  pos=[o.data.vertices[vi].co for vi in poly.vertices]
  c=sum(pos,Vector())/len(pos)
  uv=[tuple(layer.data[li].uv) for li in poly.loop_indices]
  rows.append((o.name,poly.index,round(c.x,3),round(c.y,3),round(c.z,3),len(poly.vertices),
               ';'.join(f'{u:.6f}:{v:.6f}' for u,v in uv)))
with (out/'epic_bastion_uv_face_audit.csv').open('w',newline='') as f:
 writer=csv.writer(f);writer.writerow(['piece','face','x','y','z','corners','uv_coords']);writer.writerows(rows)
print('FACE_AUDIT_ROWS',len(rows))

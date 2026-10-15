import bpy, sys, os, traceback, json, math
sys.path.insert(0, '/tmp/python_addons')
from pathlib import Path

s3o=Path(os.environ["EPIC_S3O"]).resolve()
texdir=Path(os.environ["EPIC_TEXTURES"]).resolve()
dest=Path(os.environ["EPIC_BLEND"]).resolve()
print("BLENDER_VERSION",bpy.app.version_string)
addon=os.environ.get("EPIC_ADDON_MODULE","s3o_kit")
print("ADDON_MODULE",addon)
import importlib
module=importlib.import_module(addon)
module.register()
print("S3O_IMPORT_OPERATOR_EXISTS",hasattr(bpy.ops.s3o_tools,"import_s3o"))
try:
    result=bpy.ops.s3o_tools.import_s3o(filepath=str(s3o),unit_textures_folder=str(texdir), merge_vertices=False)
    print("S3O_IMPORT_RESULT",result)
except Exception:
    traceback.print_exc()
    raise
objs=list(bpy.data.objects)
meshes=[o for o in objs if o.type=="MESH"]
print("IMPORT_OBJECT_COUNT",len(objs))
print("IMPORT_MESH_COUNT",len(meshes))
print("IMPORT_MESH_NAMES",",".join(o.name for o in meshes[:60]))
print("IMPORT_UV_LAYERS",sum(len(o.data.uv_layers) for o in meshes))
print("IMPORT_MATERIALS",",".join(m.name for m in bpy.data.materials))
assert len(meshes)>=7,"No usable S3O meshes produced"
assert any(o.name.lower().startswith("ring5") for o in meshes),"Fifth ring not imported"
assert any("gauss" in o.name.lower() for o in objs),"Gauss cannon hierarchy missing"
assert any(o.data.uv_layers for o in meshes),"No UVs were imported"
# Repair the addon template's Windows-origin paths before packing materials.
# Preserve the shader and actual image colors; do NOT invent any UV or pixel color.
for im in bpy.data.images:
    short=im.name.lower()
    source = 'leg_color.dds' if short=='leg_color.dds' else ('leg_shader.dds' if short=='leg_shader.dds' else ('leg_normal.dds' if short=='leg_normal.dds' else None))
    if source:
        actual=texdir/source
        if actual.is_file():
            im.filepath=str(actual)
            im.reload()
            im.pack()
            print("RELINKED_IMAGE",im.name,str(actual),im.size[:],bool(im.packed_file))
        elif source!='leg_normal.dds':
            raise FileNotFoundError("Required Legion texture missing: "+str(actual))
for im in bpy.data.images:
    print("TEXTURE_IMAGE", im.name, "path", im.filepath, "packed", bool(im.packed_file))
# Record exact UV coords per polygon for each imported visible mesh.
# This diagnostic is computed from Blender's imported UV layers, not guesses about atlas orientation.
report={"blender":bpy.app.version_string,"meshes":{},"required_textures":{}}
for im in bpy.data.images:
    if im.name.lower() in ('leg_color.dds','leg_shader.dds'):
        report["required_textures"][im.name]={"packed":bool(im.packed_file),"size":list(im.size)}
for obj in meshes:
    mesh=obj.data
    if not mesh.uv_layers:continue
    uv=mesh.uv_layers.active.data
    sample=[]
    bad=0
    min_u=min_v=1e9;max_u=max_v=-1e9
    for face in mesh.polygons:
        coords=[(uv[loop_idx].uv.x,uv[loop_idx].uv.y) for loop_idx in face.loop_indices]
        for u,v in coords:
            min_u=min(min_u,u);max_u=max(max_u,u);min_v=min(min_v,v);max_v=max(max_v,v)
            if not (-.01<=u<=1.01 and -.01<=v<=1.01):bad+=1
        if len(sample)<100:
            sample.append(coords)
    report["meshes"][obj.name]={"faces":len(mesh.polygons),"uv_bounds":[min_u,min_v,max_u,max_v],"out_of_bounds_loops":bad,"sample_polygons":sample}
target=dest.with_suffix(".uv_report.json")
target.parent.mkdir(parents=True,exist_ok=True)
target.write_text(json.dumps(report,indent=2))
print("SAVED_UV_REPORT",target,target.stat().st_size)
assert report["required_textures"].get("leg_color.dds",{}).get("packed"),"Legion color atlas failed to pack"
assert report["required_textures"].get("leg_shader.dds",{}).get("packed"),"Legion shader atlas failed to pack"
try:
    bpy.ops.file.pack_all()
    print("TEXTURES_PACKED", [(im.name, bool(im.packed_file)) for im in bpy.data.images])
except Exception:
    traceback.print_exc()
    raise
dest.parent.mkdir(parents=True,exist_ok=True)
bpy.ops.wm.save_as_mainfile(filepath=str(dest))
print("SAVED_BLEND",dest, dest.stat().st_size)

if os.environ.get("EPIC_RENDER_UV_AUDIT") == "1":
    import runpy
    runpy.run_path("tools/render_epic_bastion_uv_audit.py",run_name="__main__")

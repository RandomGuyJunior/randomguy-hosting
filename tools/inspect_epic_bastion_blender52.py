import bpy, sys, os, traceback
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
for im in bpy.data.images:
    print("TEXTURE_IMAGE", im.name, "path", im.filepath, "packed", bool(im.packed_file))
try:
    bpy.ops.file.pack_all()
    print("TEXTURES_PACKED", [(im.name, bool(im.packed_file)) for im in bpy.data.images])
except Exception:
    traceback.print_exc()
    raise
dest.parent.mkdir(parents=True,exist_ok=True)
bpy.ops.wm.save_as_mainfile(filepath=str(dest))
print("SAVED_BLEND",dest, dest.stat().st_size)

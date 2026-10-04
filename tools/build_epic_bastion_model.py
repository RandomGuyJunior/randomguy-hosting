#!/usr/bin/env python3
import copy
import math
import os
import struct
import sys
import urllib.request

HEADER = struct.Struct("<12sI5f4I")
PIECE = struct.Struct("<10I3f")
VERT = struct.Struct("<8f")

class Piece:
    def __init__(self, name, offset=(0.0,0.0,0.0), verts=None, indices=None, primitive=2, vert_type=0, children=None):
        self.name=name
        self.offset=tuple(offset)
        self.verts=list(verts or [])
        self.indices=list(indices or [])
        self.primitive=primitive
        self.vert_type=vert_type
        self.children=list(children or [])

class Model:
    def __init__(self, radius, height, mid, tex1, tex2, root):
        self.radius=radius
        self.height=height
        self.mid=mid
        self.tex1=tex1
        self.tex2=tex2
        self.root=root

def cstr(data, off):
    if not off:
        return ""
    end=data.find(b"\0", off)
    if end < 0: end=len(data)
    return data[off:end].decode("utf-8","replace")

def parse_piece(data, off, seen=None):
    if seen is None: seen=set()
    if off in seen: raise ValueError(f"cycle at {off}")
    seen.add(off)
    vals=PIECE.unpack_from(data,off)
    name_off,nchild,child_off,nverts,verts_off,vert_type,prim,nidx,idx_off,coll_off,x,y,z=vals
    verts=[VERT.unpack_from(data,verts_off+i*VERT.size) for i in range(nverts)] if nverts else []
    indices=list(struct.unpack_from("<"+"I"*nidx,data,idx_off)) if nidx else []
    children=[]
    if nchild:
        child_ptrs=struct.unpack_from("<"+"I"*nchild,data,child_off)
        children=[parse_piece(data,p,seen) for p in child_ptrs]
    return Piece(cstr(data,name_off),(x,y,z),verts,indices,prim,vert_type,children)

def load(path):
    data=open(path,"rb").read()
    magic,version,radius,height,mx,my,mz,root,coll,t1,t2=HEADER.unpack_from(data,0)
    if not magic.startswith(b"Spring unit"):
        raise ValueError(f"{path}: not S3O")
    return Model(radius,height,(mx,my,mz),cstr(data,t1),cstr(data,t2),parse_piece(data,root))

def align4(buf):
    while len(buf)%4: buf.append(0)

def append_cstr(buf,s):
    off=len(buf)
    buf.extend(s.encode("utf-8")+b"\0")
    return off

def save(model,path):
    buf=bytearray(b"\0"*HEADER.size)

    def write_piece(p):
        align4(buf)
        poff=len(buf)
        buf.extend(b"\0"*PIECE.size)
        name_off=append_cstr(buf,p.name)

        verts_off=0
        if p.verts:
            align4(buf); verts_off=len(buf)
            for v in p.verts: buf.extend(VERT.pack(*v))

        idx_off=0
        if p.indices:
            align4(buf); idx_off=len(buf)
            buf.extend(struct.pack("<"+"I"*len(p.indices),*p.indices))

        child_offsets=[write_piece(c) for c in p.children]
        child_table_off=0
        if child_offsets:
            align4(buf); child_table_off=len(buf)
            buf.extend(struct.pack("<"+"I"*len(child_offsets),*child_offsets))

        PIECE.pack_into(
            buf,poff,
            name_off,len(child_offsets),child_table_off,
            len(p.verts),verts_off,p.vert_type,p.primitive,
            len(p.indices),idx_off,0,
            *p.offset
        )
        return poff

    root_off=write_piece(model.root)
    tex1_off=append_cstr(buf,model.tex1) if model.tex1 else 0
    tex2_off=append_cstr(buf,model.tex2) if model.tex2 else 0
    HEADER.pack_into(
        buf,0,b"Spring unit\0",0,
        float(model.radius),float(model.height),
        float(model.mid[0]),float(model.mid[1]),float(model.mid[2]),
        root_off,0,tex1_off,tex2_off
    )
    with open(path,"wb") as f: f.write(buf)

def walk(p):
    yield p
    for c in p.children:
        yield from walk(c)

def find(root,name):
    for p in walk(root):
        if p.name.lower()==name.lower(): return p
    raise KeyError(name)

def parent_of(root,target):
    for p in walk(root):
        if target in p.children: return p
    return None

def detach(root,name):
    p=find(root,name)
    par=parent_of(root,p)
    if par is None: raise ValueError(f"cannot detach root {name}")
    par.children=[c for c in par.children if c is not p]
    return p

def empty(name,offset=(0,0,0)):
    return Piece(name,offset,[],[],2,0,[])

def clone_mesh(source,name,offset=(0,0,0),scale=1.0,mirror_x=False):
    verts=[]
    for v in source.verts:
        x,y,z,nx,ny,nz,u,w=v
        if mirror_x:
            x=-x; nx=-nx
        verts.append((x*scale,y*scale,z*scale,nx,ny,nz,u,w))
    indices=list(source.indices)
    if mirror_x and source.primitive==0:
        for i in range(0,len(indices)-2,3):
            indices[i+1],indices[i+2]=indices[i+2],indices[i+1]
    return Piece(name,offset,verts,indices,source.primitive,source.vert_type,[])

def transform_mesh(piece, sx=1.0, sy=1.0, sz=1.0, dx=0.0, dy=0.0, dz=0.0):
    verts=[]
    for v in piece.verts:
        x,y,z,nx,ny,nz,u,w=v
        verts.append((x*sx+dx,y*sy+dy,z*sz+dz,nx,ny,nz,u,w))
    piece.verts=verts
    return piece

def rotate_mesh_x(piece, degrees):
    """Bake a local X-axis rotation into mesh vertices and normals."""
    a=math.radians(degrees)
    c=math.cos(a)
    sn=math.sin(a)
    verts=[]
    for v in piece.verts:
        x,y,z,nx,ny,nz,u,w=v
        # Positive X rotation tilts the upper (+Y) part toward +Z (forward).
        ry=y*c-z*sn
        rz=y*sn+z*c
        rny=ny*c-nz*sn
        rnz=ny*sn+nz*c
        verts.append((x,ry,rz,nx,rny,rnz,u,w))
    piece.verts=verts
    return piece

def mesh_axis_bounds(piece, axis):
    """Return min/max local vertex position for x=0, y=1, or z=2."""
    if not piece.verts:
        return 0.0, 0.0
    values=[v[axis] for v in piece.verts]
    return min(values), max(values)

def shorten_positive_z(piece, target_max_z):
    """Shorten only the forward (+Z) extent while keeping the rear anchored."""
    if not piece.verts:
        return piece
    zs=[v[2] for v in piece.verts]
    min_z=min(zs)
    max_z=max(zs)
    if max_z <= target_max_z or max_z <= min_z:
        return piece
    scale=(target_max_z-min_z)/(max_z-min_z)
    verts=[]
    for v in piece.verts:
        x,y,z,nx,ny,nz,u,w=v
        new_z=min_z+(z-min_z)*scale
        verts.append((x,y,new_z,nx,ny,nz,u,w))
    piece.verts=verts
    return piece

def remove_piece(root, name):
    try:
        target=find(root,name)
    except KeyError:
        return
    parent=parent_of(root,target)
    if parent:
        parent.children=[c for c in parent.children if c is not target]

def download(url,path):
    urllib.request.urlretrieve(url,path)

def ensure_donors(tmp):
    sol=os.path.join(tmp,"legeheatraymech.s3o")
    chim=os.path.join(tmp,"legapopupdef.s3o")
    if not os.path.exists(sol):
        download("https://raw.githubusercontent.com/beyond-all-reason/Beyond-All-Reason/master/objects3d/Units/legeheatraymech.s3o",sol)
    if not os.path.exists(chim):
        download("https://raw.githubusercontent.com/beyond-all-reason/Beyond-All-Reason/master/objects3d/Units/legapopupdef.s3o",chim)
    return load(sol),load(chim)

def rebuild(epic,sol,chim):
    root=epic.root
    turret=find(root,"turret")

    # The three original Bastion armatures are the armor plates beneath the
    # radial turret positions. Keep their original shape, but shorten only
    # their forward reach so they terminate at the turret mount instead of
    # passing through the cannon volume.
    for arm_name in ("armature1","armature2","armature3"):
        try:
            shorten_positive_z(find(root,arm_name), 23.0)
        except KeyError:
            pass

    def has(name):
        try:
            find(root,name)
            return True
        except KeyError:
            return False

    # First-time conversion: flatten the original nested ring chain into four
    # siblings under one moving anchor. On later passes, preserve the result.
    if has("ringanchor"):
        ring_anchor=find(root,"ringanchor")
        rings=[find(root,name) for name in ("ring","ring2","ring3","ring4")]
    else:
        ring_names=("ring","ring2","ring3","ring4")
        rings=[find(root,name) for name in ring_names]
        ring_set=set(rings)
        for node in list(walk(root)):
            node.children=[c for c in node.children if c not in ring_set]
        for r in rings:
            r.children=[c for c in r.children if c not in ring_set]
            r.offset=(0.0,0.0,0.0)

        ring_anchor=empty("ringanchor",(0.0,0.0,0.0))
        beam_pitch=empty("beam_pitch",(0.0,0.0,0.0))
        beam_muzzle=empty("beam_muzzle",(0.0,0.0,0.0))
        beam_pitch.children=[beam_muzzle]
        ring_anchor.children=rings+[beam_pitch]
        turret.children.append(ring_anchor)

    # Always enforce the important invariant even on later passes.
    ring_set=set(rings)
    for node in list(walk(root)):
        if node is not ring_anchor:
            node.children=[c for c in node.children if c not in ring_set]
    anchor_nonrings=[c for c in ring_anchor.children if c not in ring_set]
    for r in rings:
        r.children=[c for c in r.children if c not in ring_set]
        r.offset=(0.0,0.0,0.0)
    ring_anchor.children=rings+anchor_nonrings

    # V4: fixed visible head with three identical radial turret extensions.
    # Capture the original lower aiming arm as a donor, then remove all of the
    # old directional head arms (including the two diagonals beside the rings).
    try:
        lower_arm_donor=find(root,"bottomAimingArm")
    except KeyError:
        lower_arm_donor=None

    for old_name in (
        "support_plate_1","support_plate_2","support_plate_3",
        "gaussL_yaw","gaussR_yaw","gaussdeck",
        # Remove the old high two-arm aiming assembly that intersects the rings.
        # topArmsPivot owns leftAimingArm/rightAimingArm, so removing the pivot
        # removes both visible arms while leaving the round turret body intact.
        "topArmsPivot","aiming_arm",
        # Legacy dark toroid/half-circle decorations high beside the ring stack.
        "epic_toroid_l","epic_toroid_r",
        "epic_strut_l","epic_strut_r",
        "epic_pod_l","epic_pod_r"
    ):
        remove_piece(root,old_name)

    # Ring/beam aiming is now isolated on invisible pivots. The visible turret
    # never rotates. The ring assembly rides the invisible yaw pivot.
    if has("beam_yaw"):
        beam_yaw=find(root,"beam_yaw")
    else:
        beam_yaw=empty("beam_yaw",(0.0,0.0,0.0))
        turret.children.append(beam_yaw)

    ring_parent=parent_of(root,ring_anchor)
    if ring_parent is not beam_yaw:
        if ring_parent:
            ring_parent.children=[c for c in ring_parent.children if c is not ring_anchor]
        beam_yaw.children.append(ring_anchor)

    # Clean old V4 extension pieces if this builder is run again.
    for i in range(1,4):
        remove_piece(root,f"extension_root_{i}")

    chim_turret_base=find(chim.root,"turretBaseHeading")
    chim_house=find(chim.root,"riotcannonHousing")
    chim_barrel=find(chim.root,"riotCannon")

    if lower_arm_donor is None:
        # On an already-converted model, reconstruct the donor from the stock
        # Bastion source downloaded alongside the other donor models.
        stock_path=os.path.join("/tmp/epic-bastion-donors","legbastion_stock.s3o")
        if not os.path.exists(stock_path):
            download("https://raw.githubusercontent.com/beyond-all-reason/Beyond-All-Reason/master/objects3d/Units/legbastion.s3o",stock_path)
        stock=load(stock_path)
        lower_arm_donor=find(stock.root,"bottomAimingArm")

    def make_extension(index):
        root_piece=empty(f"extension_root_{index}",(0.0,-10.0,0.0))

        # Preserve the three radial holder assemblies exactly; these are the
        # good-looking arms around the central pivot that should remain.
        arm_a=clone_mesh(lower_arm_donor,f"extension_arm_{index}a",(-7.0,-5.0,7.0),0.92)
        arm_b=clone_mesh(lower_arm_donor,f"extension_arm_{index}b",(7.0,-5.0,7.0),0.92,mirror_x=True)

        # Remove the stretched brace/plate connectors completely. The cannon
        # pedestal now sits deeper in the model instead of being linked to the
        # radial holders by long dark geometry.
        # Keep Chimera's turretBaseHeading geometry untouched. Placement and
        # scale belong to the Epic Bastion assembly, but the donor mesh itself
        # must remain an exact clone with no cuts or reshaping.
        # Raise the cannon assembly 20 units from the previous V10 position.
        # The original Bastion armatures are shortened separately so their
        # tips terminate cleanly below/at the turret rather than clipping it.
        mount=empty(f"extension_mountroot_{index}",(0.0,-66.0,49.0))
        pedestal_scale=1.72
        housing_scale=1.34
        pedestal_y=-5.0
        pitch_y=4.0
        seat_clearance=0.45

        pedestal=clone_mesh(
            chim_turret_base,
            f"extension_pedestal_{index}",
            (0.0,pedestal_y,0.0),
            pedestal_scale
        )
        # Start from the donor's original upright orientation. The cannon's
        # front is +Z; a positive X rotation moves that front edge downward.
        # Tip it 90 degrees to horizontal, then another 15 degrees: +105 total.
        pedestal_forward_down_tilt=105.0
        rotate_mesh_x(pedestal,pedestal_forward_down_tilt)

        # Seat the upright cannon housing just above the now-tilted pedestal.
        # Use the transformed pedestal bounds, not the unrotated donor bounds.
        pedestal_top=max(v[1] for v in pedestal.verts)
        housing_bottom,_=mesh_axis_bounds(chim_house,1)
        seated_y=(
            pedestal_y
            + pedestal_top
            + seat_clearance
            - pitch_y
            - housing_bottom*housing_scale
        )
        yaw=empty(f"gauss{index}_yaw",(0.0,seated_y,0.5))
        pitch=clone_mesh(chim_house,f"gauss{index}_pitch",(0.0,pitch_y,1.0),housing_scale)
        barrel=clone_mesh(chim_barrel,f"gauss{index}_barrel",(0.0,0.0,10.0),1.78)
        muzzle=empty(f"gauss{index}_muzzle",(0.0,0.0,29.0))
        barrel.children=[muzzle]
        pitch.children=[barrel]
        yaw.children=[pitch]
        mount.children=[pedestal,yaw]

        root_piece.children=[arm_a,arm_b,mount]
        return root_piece

    # All three start geometrically forward; the unit script rotates the
    # invisible extension roots to 0 / +120 / -120 degrees.
    for i in range(1,4):
        turret.children.append(make_extension(i))

    # Marker for validation/versioning.
    remove_piece(root,"body_revamp_v3")
    remove_piece(root,"body_revamp_v4")
    remove_piece(root,"body_revamp_v5")
    if not has("body_revamp_v6"):
        root.children.append(empty("body_revamp_v6",(0.0,0.0,0.0)))

    epic.radius=max(epic.radius,182.0)
    epic.height=max(epic.height,236.0)
    epic.mid=(epic.mid[0],108.0,epic.mid[2])
    return epic

def validate(model):
    required=[
        "ringanchor","ring","ring2","ring3","ring4","beam_yaw","beam_pitch","beam_muzzle",
        "extension_root_1","extension_root_2","extension_root_3",
        "gauss1_yaw","gauss1_pitch","gauss1_barrel","gauss1_muzzle",
        "gauss2_yaw","gauss2_pitch","gauss2_barrel","gauss2_muzzle",
        "gauss3_yaw","gauss3_pitch","gauss3_barrel","gauss3_muzzle",
        "extension_mountroot_1","extension_mountroot_2","extension_mountroot_3",
        "extension_pedestal_1","extension_pedestal_2","extension_pedestal_3",
        "extension_arm_1a","extension_arm_1b",
        "extension_arm_2a","extension_arm_2b",
        "extension_arm_3a","extension_arm_3b",
        "body_revamp_v6",
    ]
    names={p.name for p in walk(model.root)}
    missing=[n for n in required if n not in names]
    if missing: raise RuntimeError("missing pieces: "+", ".join(missing))

    forbidden=(
        "topArmsPivot","leftAimingArm","rightAimingArm",
        "epic_toroid_l","epic_toroid_r",
        "epic_strut_l","epic_strut_r","epic_pod_l","epic_pod_r",
        "extension_brace_1","extension_brace_2","extension_brace_3",
        "extension_plate_1l","extension_plate_1r",
        "extension_plate_2l","extension_plate_2r",
        "extension_plate_3l","extension_plate_3r"
    )
    present=[n for n in forbidden if n in names]
    if present:
        raise RuntimeError("obsolete ring-clipping/high toroid pieces remain: "+", ".join(present))
    anchor=find(model.root,"ringanchor")
    ring_names={c.name for c in anchor.children}
    for n in ("ring","ring2","ring3","ring4"):
        if n not in ring_names: raise RuntimeError(f"{n} is not direct child of ringanchor")
    for n in ("ring","ring2","ring3","ring4"):
        if find(model.root,n).offset != (0.0,0.0,0.0):
            raise RuntimeError(f"{n} not centered")
    for n in ("gauss1_yaw","gauss2_yaw","gauss3_yaw"):
        if find(model.root,n).verts:
            raise RuntimeError(f"{n} should be an invisible aiming pivot")
    for i in range(1,4):
        mount=find(model.root,f"extension_mountroot_{i}")
        pedestal=find(model.root,f"extension_pedestal_{i}")
        if mount.offset != (0.0,-66.0,49.0):
            raise RuntimeError(f"extension_mountroot_{i} is not raised 20 units from V10")
        if pedestal.offset != (0.0,-5.0,0.0):
            raise RuntimeError(f"extension_pedestal_{i} is not recessed below the cannon mount")

        yaw=find(model.root,f"gauss{i}_yaw")
        pitch=find(model.root,f"gauss{i}_pitch")
        pedestal_top=max(v[1] for v in pedestal.verts)+pedestal.offset[1]
        housing_bottom=min(v[1] for v in pitch.verts)+pitch.offset[1]+yaw.offset[1]
        gap=housing_bottom-pedestal_top
        if gap < 0.35 or gap > 0.55:
            raise RuntimeError(f"gauss{i} is not seated cleanly on armor plate: gap={gap:.3f}")

        # Confirm the +Z/front edge is lower than the -Z/rear edge after the
        # requested +105-degree front-down rotation.
        front=[v for v in pedestal.verts if v[2] >= max(x[2] for x in pedestal.verts)-1.0]
        rear=[v for v in pedestal.verts if v[2] <= min(x[2] for x in pedestal.verts)+1.0]
        if front and rear:
            front_y=sum(v[1] for v in front)/len(front)
            rear_y=sum(v[1] for v in rear)/len(rear)
            if front_y >= rear_y:
                raise RuntimeError(f"extension_pedestal_{i} is not folded backward past 90 degrees")
    for n in ("armature1","armature2","armature3"):
        arm=find(model.root,n)
        if arm.verts and max(v[2] for v in arm.verts) > 23.01:
            raise RuntimeError(f"{n} still extends into the turret volume")

    # Chimera turretBaseHeading has 306 indices. Preserve that topology
    # exactly; no wing/clearance cutting is allowed on the donor base.
    for n in ("extension_pedestal_1","extension_pedestal_2","extension_pedestal_3"):
        if len(find(model.root,n).indices) != 306:
            raise RuntimeError(f"{n} modified Chimera turret-base topology")

def main():
    src=sys.argv[1] if len(sys.argv)>1 else "objects3d/Units/legbastiont3.s3o"
    out=sys.argv[2] if len(sys.argv)>2 else src
    tmp="/tmp/epic-bastion-donors"
    os.makedirs(tmp,exist_ok=True)
    epic=load(src)
    sol,chim=ensure_donors(tmp)
    rebuilt=rebuild(epic,sol,chim)
    validate(rebuilt)
    save(rebuilt,out)
    # Parse the output again to ensure serialization is valid.
    check=load(out)
    validate(check)
    print(f"wrote {out}: radius={check.radius:.1f} height={check.height:.1f}")
    for name in ("ringanchor","beam_yaw","beam_muzzle","extension_root_1","gauss1_yaw","gauss1_muzzle","extension_root_2","gauss2_yaw","gauss2_muzzle","extension_root_3","gauss3_yaw","gauss3_muzzle"):
        p=find(check.root,name)
        print(name,p.offset,len(p.verts),len(p.indices))

if __name__=="__main__":
    main()

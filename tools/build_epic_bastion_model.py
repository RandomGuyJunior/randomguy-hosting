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

def trim_upper_side_wings(piece, x_limit=7.6, y_threshold=0.25):
    """Remove the two upper left/right overhangs from a triangle mesh.

    The Chimera turretBaseHeading is one mesh, so its upper side wings are not
    separately named pieces. Keep the central/lower pedestal and discard only
    triangles whose centroid lies in the high outer side regions.
    """
    if piece.primitive != 0:
        raise ValueError(f"{piece.name}: expected triangle primitive")
    kept=[]
    removed=0
    for i in range(0,len(piece.indices)-2,3):
        tri=piece.indices[i:i+3]
        pts=[piece.verts[j] for j in tri]
        cx=sum(v[0] for v in pts)/3.0
        cy=sum(v[1] for v in pts)/3.0
        if abs(cx) > x_limit and cy > y_threshold:
            removed += 1
            continue
        kept.extend(tri)
    piece.indices=kept
    piece._trimmed_wing_triangles=removed
    return piece


def trim_armature_wings(piece, x_limit=10.5, y_threshold=2.0):
    """Cut only the upper lateral wings from the Bastion armature mesh."""
    if piece.primitive != 0:
        raise ValueError(f"{piece.name}: expected triangle primitive")
    kept=[]
    removed=0
    for i in range(0,len(piece.indices)-2,3):
        tri=piece.indices[i:i+3]
        pts=[piece.verts[j] for j in tri]
        cx=sum(v[0] for v in pts)/3.0
        cy=sum(v[1] for v in pts)/3.0
        # The unwanted wings are the wide, high side lobes. Preserve the
        # central spine and all lower structural geometry.
        if abs(cx) > x_limit and cy > y_threshold:
            removed += 1
            continue
        kept.extend(tri)
    piece.indices=kept
    piece._trimmed_armature_wing_triangles=removed
    return piece

def circularize_turret_top(piece, x_limit=10.5, y_threshold=-2.5, cap_y=5.2, cap_radius=11.5, segments=24):
    """Remove the turret's two raised side prongs and close it with a round cap."""
    if piece.primitive != 0:
        raise ValueError(f"{piece.name}: expected triangle primitive")

    kept=[]
    removed=0
    # Keep central turret body; discard only high outer prong triangles.
    for i in range(0,len(piece.indices)-2,3):
        tri=piece.indices[i:i+3]
        pts=[piece.verts[j] for j in tri]
        cx=sum(v[0] for v in pts)/3.0
        cy=sum(v[1] for v in pts)/3.0
        if abs(cx) > x_limit and cy > y_threshold:
            removed += 1
            continue
        kept.extend(tri)
    piece.indices=kept

    # Use a nearby existing texture coordinate so the new cap inherits a sane
    # material sample instead of introducing a new texture dependency.
    if piece.verts:
        ref=min(piece.verts, key=lambda v: abs(v[0]) + abs(v[2]) + abs(v[1]-cap_y))
        u0,v0=ref[6],ref[7]
    else:
        u0,v0=0.5,0.5

    center_idx=len(piece.verts)
    piece.verts.append((0.0,cap_y,0.0,0.0,1.0,0.0,u0,v0))
    rim=[]
    for i in range(segments):
        a=(math.pi*2.0*i)/segments
        x=math.cos(a)*cap_radius
        z=math.sin(a)*cap_radius
        rim.append(len(piece.verts))
        piece.verts.append((x,cap_y,z,0.0,1.0,0.0,u0,v0))

    for i in range(segments):
        j=(i+1)%segments
        piece.indices.extend([center_idx,rim[j],rim[i]])

    piece._trimmed_turret_prong_triangles=removed
    piece._added_round_cap_triangles=segments
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

    # User-identified source geometry cleanup: remove the upper lateral wings
    # from all three armatures, and turn the main turret top into a clean round
    # base by cutting its raised side prongs and capping the opening.
    for arm_name in ("armature1","armature2","armature3"):
        trim_armature_wings(find(root,arm_name))
    circularize_turret_top(turret)

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
        pedestal=clone_mesh(chim_turret_base,f"extension_pedestal_{index}",(0.0,-51.0,49.0),1.72)
        # Cut only the donor base's two upper side wings; keep the central
        # triangular pedestal and lower armor intact.
        trim_upper_side_wings(pedestal, x_limit=7.6 * 1.72, y_threshold=0.25 * 1.72)

        # Move the armor plate 5 units deeper without moving the cannon itself:
        # compensate the child aiming pivot upward by the same amount.
        yaw=empty(f"gauss{index}_yaw",(0.0,9.2,0.5))
        pitch=clone_mesh(chim_house,f"gauss{index}_pitch",(0.0,4.0,1.0),1.34)
        barrel=clone_mesh(chim_barrel,f"gauss{index}_barrel",(0.0,0.0,10.0),1.78)
        muzzle=empty(f"gauss{index}_muzzle",(0.0,0.0,29.0))
        barrel.children=[muzzle]
        pitch.children=[barrel]
        yaw.children=[pitch]
        pedestal.children=[yaw]

        root_piece.children=[arm_a,arm_b,pedestal]
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
        "extension_plate_3l","extension_plate_3r",
        "extension_cannon_support_1","extension_cannon_support_2","extension_cannon_support_3",
        "extension_cannon_plate_1","extension_cannon_plate_2","extension_cannon_plate_3"
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
    # The Chimera turretBaseHeading donor has 306 indices before trimming.
    # All three Epic pedestals must have the same reduced topology: enough mesh
    # remains for the central triangular base, but the upper side wings are gone.
    pedestal_counts=[]
    for n in ("extension_pedestal_1","extension_pedestal_2","extension_pedestal_3"):
        count=len(find(model.root,n).indices)
        pedestal_counts.append(count)
        if count >= 306 or count < 180:
            raise RuntimeError(f"{n} unexpected trimmed pedestal topology: {count} indices")
    if len(set(pedestal_counts)) != 1:
        raise RuntimeError("trimmed cannon pedestals are not identical")

    # Validate the serialized result, not transient Python attributes.
    # Stock armatures contain 480 indices. A successful wing cut must reduce
    # that count while leaving substantial central structure.
    for n in ("armature1","armature2","armature3"):
        count=len(find(model.root,n).indices)
        if count >= 480 or count < 240:
            raise RuntimeError(f"{n} unexpected post-trim topology: {count} indices")

    # Stock turret contains 774 indices. We add a 24-segment cap (72 indices),
    # so a successful prong cut must still finish below 846 total indices.
    turret_count=len(find(model.root,"turret").indices)
    if turret_count >= 846 or turret_count < 450:
        raise RuntimeError(f"turret unexpected circularized topology: {turret_count} indices")

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

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


def _interp_vertex(a,b,t):
    vals=[a[i] + (b[i]-a[i])*t for i in range(8)]
    nx,ny,nz=vals[3],vals[4],vals[5]
    mag=math.sqrt(nx*nx+ny*ny+nz*nz)
    if mag > 1e-9:
        vals[3],vals[4],vals[5]=nx/mag,ny/mag,nz/mag
    return tuple(vals)

def cut_armature_at_bend(piece, z_cut=12.0):
    """Cleanly clip the outer bent armature end and close it with a rectangle."""
    if piece.primitive != 0:
        raise ValueError(f"{piece.name}: expected triangle primitive")

    new_verts=[]
    new_indices=[]
    cut_points=[]

    def add_vertex(v):
        idx=len(new_verts)
        new_verts.append(v)
        return idx

    def inside(v):
        return v[2] <= z_cut + 1e-6

    for i in range(0,len(piece.indices)-2,3):
        poly=[piece.verts[piece.indices[i+j]] for j in range(3)]
        out=[]
        for j,a in enumerate(poly):
            b=poly[(j+1)%len(poly)]
            a_in=inside(a)
            b_in=inside(b)
            if a_in:
                out.append(a)
            if a_in != b_in:
                dz=b[2]-a[2]
                t=0.0 if abs(dz)<1e-9 else (z_cut-a[2])/dz
                v=_interp_vertex(a,b,t)
                out.append(v)
                cut_points.append(v)

        if len(out) < 3:
            continue
        base=add_vertex(out[0])
        for j in range(1,len(out)-1):
            i1=add_vertex(out[j])
            i2=add_vertex(out[j+1])
            new_indices.extend([base,i1,i2])

    if len(cut_points) < 2:
        raise RuntimeError(f"{piece.name}: cut plane did not intersect mesh")

    minx=min(v[0] for v in cut_points)
    maxx=max(v[0] for v in cut_points)
    miny=min(v[1] for v in cut_points)
    maxy=max(v[1] for v in cut_points)
    u=sum(v[6] for v in cut_points)/len(cut_points)
    w=sum(v[7] for v in cut_points)/len(cut_points)

    cap=[
        (minx,miny,z_cut,0.0,0.0,1.0,u,w),
        (maxx,miny,z_cut,0.0,0.0,1.0,u,w),
        (maxx,maxy,z_cut,0.0,0.0,1.0,u,w),
        (minx,maxy,z_cut,0.0,0.0,1.0,u,w),
    ]
    c0=add_vertex(cap[0]); c1=add_vertex(cap[1]); c2=add_vertex(cap[2]); c3=add_vertex(cap[3])
    new_indices.extend([c0,c1,c2,c0,c2,c3])

    piece.verts=new_verts
    piece.indices=new_indices
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

    # Preserve the original turret design; enlarge only its visible mesh so the
    # built-in upper arms open farther around the unchanged ring stack.
    transform_mesh(turret, sx=1.18, sy=1.18, sz=1.18)

    # Cleanly remove only the bent outer tips of the three original armatures,
    # then close each cut with one flat rectangular end plate.
    for arm_name in ("armature1","armature2","armature3"):
        cut_armature_at_bend(find(root,arm_name), z_cut=12.0)

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
        pedestal=clone_mesh(chim_turret_base,f"extension_pedestal_{index}",(0.0,-46.0,49.0),1.72)
        yaw=empty(f"gauss{index}_yaw",(0.0,4.2,0.5))
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
    # Chimera turretBaseHeading has 306 indices. Preserve that topology
    # exactly; no wing/clearance cutting is allowed on the donor base.
    for n in ("extension_pedestal_1","extension_pedestal_2","extension_pedestal_3"):
        if len(find(model.root,n).indices) != 306:
            raise RuntimeError(f"{n} modified Chimera turret-base topology")

    for n in ("armature1","armature2","armature3"):
        p=find(model.root,n)
        if any(v[2] > 12.001 for v in p.verts):
            raise RuntimeError(f"{n} still extends beyond clean cut")
        capverts=[v for v in p.verts if abs(v[2]-12.0) < 0.001]
        if len(capverts) < 4:
            raise RuntimeError(f"{n} rectangular cut cap missing")

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

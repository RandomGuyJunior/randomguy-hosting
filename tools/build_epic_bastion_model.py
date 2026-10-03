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

    # V3 body redesign: remove the previous top-mounted donor clutter.
    # The Sol Invictus influence now lives in the lower support architecture.
    for old_name in (
        "epic_strut_l","epic_strut_r","epic_pod_l","epic_pod_r",
        "epic_toroid_l","epic_toroid_r"
    ):
        remove_piece(root, old_name)

    arm1=find(root,"armature1")
    arm2=find(root,"armature2")
    arm3=find(root,"armature3")

    if not has("body_revamp_v3"):
        # Extend the three original Bastion structural arms instead of scaling
        # the entire building. Wider/longer supports expose more of the core.
        for arm in (arm1,arm2,arm3):
            transform_mesh(arm, sx=1.18, sy=1.10, sz=1.34, dy=-3.0, dz=4.0)

        # Make the central piston/core assembly narrower and more vertically
        # separated so the interior machinery and orange energy region read.
        piston1=find(root,"piston1")
        piston2=find(root,"piston2")
        transform_mesh(piston1, sx=0.84, sy=1.12, sz=0.84)
        transform_mesh(piston2, sx=0.80, sy=1.16, sz=0.80)
        piston2.offset=(0.0,48.0,0.0)

        # Sol Invictus-style armored support plating, placed on the lower
        # structural arms rather than cluttering the weapon head.
        sol_lstrut=find(sol.root,"lHeatrayStrut")
        sol_rstrut=find(sol.root,"rHeatrayStrut")
        support1=clone_mesh(sol_lstrut,"support_plate_1",(0.0,22.0,2.0),1.22)
        support2=clone_mesh(sol_lstrut,"support_plate_2",(0.0,22.0,2.0),1.22)
        support3=clone_mesh(sol_rstrut,"support_plate_3",(0.0,22.0,2.0),1.22)
        arm1.children.append(support1)
        arm2.children.append(support2)
        arm3.children.append(support3)

        # Script-only points running vertically through the now-visible core.
        piston1.children.append(empty("coreglow_low",(0.0,8.0,0.0)))
        piston2.children.append(empty("coreglow_mid",(0.0,5.0,0.0)))
        turret.children.append(empty("coreglow_high",(0.0,-26.0,0.0)))

        root.children.append(empty("body_revamp_v3",(0.0,0.0,0.0)))

    # Chimera-derived gauss assemblies. Keep the gun geometry, but mount each
    # cannon directly on one of the two side structural supports.
    chim_base=find(chim.root,"turretPivotBottom")
    chim_house=find(chim.root,"riotcannonHousing")
    chim_barrel=find(chim.root,"riotCannon")

    def make_gauss(side):
        prefix="gauss"+side.upper()
        yaw=clone_mesh(chim_base,prefix+"_yaw",(0.0,44.0,8.0),1.55,mirror_x=(side=="r"))
        pitch=clone_mesh(chim_house,prefix+"_pitch",(0.0,4.0,1.0),1.32,mirror_x=(side=="r"))
        barrel=clone_mesh(chim_barrel,prefix+"_barrel",(0.0,0.0,10.0),1.75,mirror_x=(side=="r"))
        muzzle=empty(prefix+"_muzzle",(0.0,0.0,28.5))
        barrel.children=[muzzle]
        pitch.children=[barrel]
        yaw.children=[pitch]
        return yaw

    gauss_l=find(root,"gaussL_yaw") if has("gaussL_yaw") else make_gauss("l")
    gauss_r=find(root,"gaussR_yaw") if has("gaussR_yaw") else make_gauss("r")

    # Detach previous mount hierarchy, including the obsolete high gauss deck.
    gauss_set={gauss_l,gauss_r}
    for node in list(walk(root)):
        node.children=[c for c in node.children if c not in gauss_set]
    remove_piece(root,"gaussdeck")

    gauss_l.offset=(0.0,44.0,8.0)
    gauss_r.offset=(0.0,44.0,8.0)
    arm2.children.append(gauss_l)
    arm3.children.append(gauss_r)

    epic.radius=max(epic.radius,182.0)
    epic.height=max(epic.height,236.0)
    epic.mid=(epic.mid[0],108.0,epic.mid[2])
    return epic

def validate(model):
    required=[
        "ringanchor","ring","ring2","ring3","ring4","beam_pitch","beam_muzzle",
        "gaussL_yaw","gaussL_pitch","gaussL_barrel","gaussL_muzzle",
        "gaussR_yaw","gaussR_pitch","gaussR_barrel","gaussR_muzzle",
        "support_plate_1","support_plate_2","support_plate_3",
        "coreglow_low","coreglow_mid","coreglow_high","body_revamp_v3",
    ]
    names={p.name for p in walk(model.root)}
    missing=[n for n in required if n not in names]
    if missing: raise RuntimeError("missing pieces: "+", ".join(missing))
    anchor=find(model.root,"ringanchor")
    ring_names={c.name for c in anchor.children}
    for n in ("ring","ring2","ring3","ring4"):
        if n not in ring_names: raise RuntimeError(f"{n} is not direct child of ringanchor")
    for n in ("ring","ring2","ring3","ring4"):
        if find(model.root,n).offset != (0.0,0.0,0.0):
            raise RuntimeError(f"{n} not centered")

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
    for name in ("ringanchor","beam_muzzle","gaussL_yaw","gaussL_muzzle","gaussR_yaw","gaussR_muzzle"):
        p=find(check.root,name)
        print(name,p.offset,len(p.verts),len(p.indices))

if __name__=="__main__":
    main()

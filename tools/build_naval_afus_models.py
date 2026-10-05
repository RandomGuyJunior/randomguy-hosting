#!/usr/bin/env python3
"""Build three naval advanced-fusion S3O models from stock BAR faction assets.

Generated models are deterministic; the build workflow commits the binary outputs.

Temporary workshop for the three committed underwater-AFUS S3Os.

Design:
- faction's real underwater-fusion hull/foundation
- widened to the 6x6 land-AFUS footprint
- one dominant advanced-fusion reactor core
- two smaller auxiliary advanced reactor modules
- faction-native meshes/textures only
- final repository keeps the generated S3Os, not this workshop
"""

import copy
import math
import os
import struct
import urllib.request

HEADER = struct.Struct("<12sI5f4I")
PIECE = struct.Struct("<10I3f")
VERT = struct.Struct("<8f")

UPSTREAM = "https://raw.githubusercontent.com/beyond-all-reason/Beyond-All-Reason/master/objects3d/Units/"
OUTDIR = "objects3d/Units"
TMPDIR = "/tmp/naval-afus-donors"

class Piece:
    def __init__(self, name, offset=(0.0,0.0,0.0), verts=None, indices=None, primitive=2, vert_type=0, children=None):
        self.name = name
        self.offset = tuple(offset)
        self.verts = list(verts or [])
        self.indices = list(indices or [])
        self.primitive = primitive
        self.vert_type = vert_type
        self.children = list(children or [])

class Model:
    def __init__(self, radius, height, mid, tex1, tex2, root):
        self.radius = radius
        self.height = height
        self.mid = tuple(mid)
        self.tex1 = tex1
        self.tex2 = tex2
        self.root = root

def cstr(data, off):
    if not off:
        return ""
    end = data.find(b"\0", off)
    if end < 0:
        end = len(data)
    return data[off:end].decode("utf-8", "replace")

def parse_piece(data, off, seen=None):
    if seen is None:
        seen = set()
    if off in seen:
        raise ValueError(f"cycle at {off}")
    seen.add(off)
    vals = PIECE.unpack_from(data, off)
    name_off,nchild,child_off,nverts,verts_off,vert_type,prim,nidx,idx_off,coll_off,x,y,z = vals
    verts = [VERT.unpack_from(data, verts_off+i*VERT.size) for i in range(nverts)] if nverts else []
    indices = list(struct.unpack_from("<"+"I"*nidx, data, idx_off)) if nidx else []
    children = []
    if nchild:
        child_ptrs = struct.unpack_from("<"+"I"*nchild, data, child_off)
        children = [parse_piece(data, p, seen) for p in child_ptrs]
    return Piece(cstr(data, name_off), (x,y,z), verts, indices, prim, vert_type, children)

def load(path):
    data = open(path, "rb").read()
    magic,version,radius,height,mx,my,mz,root,coll,t1,t2 = HEADER.unpack_from(data, 0)
    if not magic.startswith(b"Spring unit"):
        raise ValueError(f"{path}: not S3O")
    return Model(radius, height, (mx,my,mz), cstr(data,t1), cstr(data,t2), parse_piece(data, root))

def align4(buf):
    while len(buf) % 4:
        buf.append(0)

def append_cstr(buf, s):
    off = len(buf)
    buf.extend(s.encode("utf-8") + b"\0")
    return off

def save(model, path):
    buf = bytearray(b"\0" * HEADER.size)

    def write_piece(p):
        align4(buf)
        poff = len(buf)
        buf.extend(b"\0" * PIECE.size)
        name_off = append_cstr(buf, p.name)

        verts_off = 0
        if p.verts:
            align4(buf)
            verts_off = len(buf)
            for v in p.verts:
                buf.extend(VERT.pack(*v))

        idx_off = 0
        if p.indices:
            align4(buf)
            idx_off = len(buf)
            buf.extend(struct.pack("<"+"I"*len(p.indices), *p.indices))

        child_offsets = [write_piece(c) for c in p.children]
        child_table_off = 0
        if child_offsets:
            align4(buf)
            child_table_off = len(buf)
            buf.extend(struct.pack("<"+"I"*len(child_offsets), *child_offsets))

        PIECE.pack_into(
            buf, poff,
            name_off, len(child_offsets), child_table_off,
            len(p.verts), verts_off, p.vert_type, p.primitive,
            len(p.indices), idx_off, 0,
            *p.offset
        )
        return poff

    root_off = write_piece(model.root)
    tex1_off = append_cstr(buf, model.tex1) if model.tex1 else 0
    tex2_off = append_cstr(buf, model.tex2) if model.tex2 else 0
    HEADER.pack_into(
        buf, 0, b"Spring unit\0", 0,
        float(model.radius), float(model.height),
        float(model.mid[0]), float(model.mid[1]), float(model.mid[2]),
        root_off, 0, tex1_off, tex2_off
    )
    with open(path, "wb") as f:
        f.write(buf)

def walk(p):
    yield p
    for c in p.children:
        yield from walk(c)

def download(name):
    os.makedirs(TMPDIR, exist_ok=True)
    path = os.path.join(TMPDIR, name)
    if not os.path.exists(path):
        urllib.request.urlretrieve(UPSTREAM + name, path)
    return path

def clone_tree(piece, prefix):
    p = Piece(
        prefix + piece.name,
        piece.offset,
        list(piece.verts),
        list(piece.indices),
        piece.primitive,
        piece.vert_type,
        []
    )
    p.children = [clone_tree(c, prefix) for c in piece.children]
    return p

def transform_tree(piece, sx=1.0, sy=1.0, sz=1.0):
    ox,oy,oz = piece.offset
    piece.offset = (ox*sx, oy*sy, oz*sz)
    nv = []
    for v in piece.verts:
        x,y,z,nx,ny,nz,u,w = v
        # Geometry scaling. Normal vectors are retained; this is acceptable for
        # these mild, mostly uniform visual transforms.
        nv.append((x*sx, y*sy, z*sz, nx,ny,nz,u,w))
    piece.verts = nv
    for c in piece.children:
        transform_tree(c, sx, sy, sz)
    return piece

def translate_root(piece, dx=0.0, dy=0.0, dz=0.0):
    ox,oy,oz = piece.offset
    piece.offset = (ox+dx, oy+dy, oz+dz)
    return piece

def bounds(root):
    minx=miny=minz=math.inf
    maxx=maxy=maxz=-math.inf

    def rec(p, px=0.0, py=0.0, pz=0.0):
        nonlocal minx,miny,minz,maxx,maxy,maxz
        ox,oy,oz = p.offset
        gx,gy,gz = px+ox, py+oy, pz+oz
        for v in p.verts:
            x,y,z = v[0]+gx, v[1]+gy, v[2]+gz
            minx,miny,minz = min(minx,x),min(miny,y),min(minz,z)
            maxx,maxy,maxz = max(maxx,x),max(maxy,y),max(maxz,z)
        for c in p.children:
            rec(c,gx,gy,gz)

    rec(root)
    if minx is math.inf:
        return (0,0,0,0,0,0)
    return minx,maxx,miny,maxy,minz,maxz

def recalc_model(model):
    minx,maxx,miny,maxy,minz,maxz = bounds(model.root)
    mx=(minx+maxx)*0.5
    my=(miny+maxy)*0.5
    mz=(minz+maxz)*0.5
    radius=max(
        math.sqrt((x-mx)**2+(y-my)**2+(z-mz)**2)
        for x in (minx,maxx) for y in (miny,maxy) for z in (minz,maxz)
    )
    model.radius=max(1.0,radius)
    model.height=max(1.0,maxy-miny)
    model.mid=(mx,my,mz)
    return (minx,maxx,miny,maxy,minz,maxz)

def texture_pair(model):
    return (model.tex1.lower(), model.tex2.lower())

def build_one(faction, naval_name, afus_name, out_name):
    naval = load(download(naval_name))
    afus = load(download(afus_name))

    if texture_pair(naval) != texture_pair(afus):
        raise RuntimeError(
            f"{faction}: donor texture mismatch: "
            f"{naval_name}={naval.tex1}/{naval.tex2}, "
            f"{afus_name}={afus.tex1}/{afus.tex2}"
        )

    # Underwater hull is the visual foundation. Target roughly a 6x6 build
    # footprint, matching the land advanced fusion instead of the smaller
    # ordinary underwater fusion.
    nb = bounds(naval.root)
    nw=max(1.0,nb[1]-nb[0])
    nd=max(1.0,nb[5]-nb[4])
    target_span = 102.0
    foundation = clone_tree(naval.root, "uw_")
    transform_tree(foundation, target_span / nw, 0.92, target_span / nd)
    fb = bounds(foundation)
    foundation_top = fb[3]

    ab = bounds(afus.root)
    aw=max(1.0,ab[1]-ab[0])
    ad=max(1.0,ab[5]-ab[4])
    module_span=max(aw,ad)

    root = Piece(f"{faction}_underwater_advanced_fusion", (0,0,0), [], [], 2, 0, [foundation])

    # Main AFUS reactor: large and central. Keep its original piece names so
    # the faction's normal land-AFUS COB script can animate it.
    main_core = clone_tree(afus.root, "")
    main_scale = 48.0 / module_span
    transform_tree(main_core, main_scale, main_scale * 0.92, main_scale)
    mb = bounds(main_core)
    translate_root(main_core, 0.0, foundation_top - mb[2] - 2.0, -8.0)
    root.children.append(main_core)

    # Auxiliary reactors make the naval version visibly more advanced/powerful
    # without simply stacking three full AFUS buildings.
    side_scale = 28.0 / module_span
    for idx,x in enumerate((-31.0, 31.0), 1):
        core = clone_tree(afus.root, f"aux{idx}_")
        transform_tree(core, side_scale, side_scale * 0.82, side_scale)
        cb = bounds(core)
        translate_root(core, x, foundation_top - cb[2] - 3.5, 20.0)
        root.children.append(core)

    model = Model(naval.radius, naval.height, naval.mid, naval.tex1, naval.tex2, root)
    recalc_model(model)

    os.makedirs(OUTDIR, exist_ok=True)
    out = os.path.join(OUTDIR, out_name)
    save(model, out)

    check = load(out)
    cb = recalc_model(check)
    spanx=cb[1]-cb[0]
    spanz=cb[5]-cb[4]
    print(
        f"{out_name}: tex={check.tex1}/{check.tex2} "
        f"span=({spanx:.1f} x {spanz:.1f}) height={check.height:.1f} "
        f"radius={check.radius:.1f}"
    )
    if spanx > 122 or spanz > 122:
        raise RuntimeError(f"{out_name}: model footprint grew unexpectedly: {spanx:.1f}x{spanz:.1f}")

def main():
    # Armada / Cortex use their stock underwater fusion as the naval foundation.
    # Legion has no stock underwater fusion, so its standard Legion fusion is
    # widened/flattened into the faction-native naval foundation.
    builds = [
        ("arm", "armuwfus.s3o",          "armafus.s3o", "armuwafus.s3o"),
        ("cor", "coruwfus.s3o",          "corafus.s3o", "coruwafus.s3o"),
        ("leg", "leganavalfusion.s3o",   "legafus.s3o", "leguwafus.s3o"),
    ]
    for args in builds:
        build_one(*args)

if __name__ == "__main__":
    main()

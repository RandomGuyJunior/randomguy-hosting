#!/usr/bin/env python3
import struct, sys

HEADER = struct.Struct("<12sI5f4I")
PIECE = struct.Struct("<10I3f")

def cstr(data, off):
    end = data.find(b"\0", off)
    if end < 0:
        end = len(data)
    return data[off:end].decode("utf-8", "replace")

def walk(data, off, depth=0, seen=None):
    if seen is None:
        seen=set()
    if off in seen:
        print("  "*depth + f"<cycle @{off}>")
        return
    seen.add(off)
    vals=PIECE.unpack_from(data, off)
    name_off,nchild,child_off,nverts,verts_off,vert_type,prim,idx_count,idx_off,coll_off,x,y,z=vals
    name=cstr(data,name_off)
    print("  "*depth + f"{name} off=({x:.2f},{y:.2f},{z:.2f}) verts={nverts} idx={idx_count} prim={prim} piece@{off}")
    if nchild:
        children=struct.unpack_from("<"+"I"*nchild,data,child_off)
        for child in children:
            walk(data,child,depth+1,seen)

def main(path):
    data=open(path,"rb").read()
    magic,version,radius,height,midx,midy,midz,root,collision,t1,t2=HEADER.unpack_from(data,0)
    print(f"FILE {path}")
    print(f"magic={magic!r} version={version} radius={radius:.2f} height={height:.2f} mid=({midx:.2f},{midy:.2f},{midz:.2f}) root={root}")
    print(f"tex1={cstr(data,t1) if t1 else ''} tex2={cstr(data,t2) if t2 else ''}")
    walk(data,root)

if __name__=="__main__":
    main(sys.argv[1])

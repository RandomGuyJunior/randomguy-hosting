"""Blender S3O Kit export sanity check: test-only; never deploys the exported model."""
import bpy,os,struct,json
from pathlib import Path
out=Path(os.environ["EPIC_BLEND"]).parent/'epic_bastion_s3okit_roundtrip_test.s3o'
result=bpy.ops.s3o_tools.export_s3o(filepath=str(out))
assert 'FINISHED' in result,(result,'Exporter failed')
assert out.stat().st_size>1000
print('ROUNDTRIP_EXPORTED',out,out.stat().st_size)
H=struct.Struct('<12sI5f4I');P=struct.Struct('<10I3f');V=struct.Struct('<8f')
def parse(path):
 b=path.read_bytes(); h=H.unpack_from(b)
 assert h[0].startswith(b'Spring unit')
 pieces={}
 def piece(off):
  a=P.unpack_from(b,off); n=b[a[0]:b.index(b'\0',a[0])].decode()
  verts=[V.unpack_from(b,a[4]+j*V.size) for j in range(a[3])]
  indices=list(struct.unpack_from('<'+'I'*a[7],b,a[8])) if a[7] else []
  pieces[n]={'vertex_count':len(verts),'face_index_count':len(indices),
             'offset':a[10:13],'vertices':verts,'indices':indices}
  if a[1]:
   for pos in struct.unpack_from('<'+'I'*a[1],b,a[2]):piece(pos)
 piece(h[7]);return pieces
old=parse(Path(os.environ['EPIC_S3O']))
new=parse(out)
missing=sorted(set(old)-set(new));extra=sorted(set(new)-set(old))
changed=[]
for n in old.keys()&new.keys():
 a,b=old[n],new[n]
 if a['vertex_count']!=b['vertex_count'] or a['face_index_count']!=b['face_index_count'] or any(abs(x-y)>1e-4 for x,y in zip(a['offset'],b['offset'])):
  changed.append((n,(a['vertex_count'],a['face_index_count'],a['offset']),
                        (b['vertex_count'],b['face_index_count'],b['offset'])))
print('ROUNDTRIP_PIECES',len(old),len(new),'MISSING',missing,'EXTRA',extra)
print('ROUNDTRIP_CHANGED_PIECE_STATS',changed[:30], 'total',len(changed))
report={'original_piece_count':len(old),'exported_piece_count':len(new),
        'missing':missing,'extra':extra,'changed_piece_stats':changed}
dest=out.with_suffix('.report.json')
dest.write_text(json.dumps(report,indent=2))
print('ROUNDTRIP_VERIFICATION_REPORT',dest)
# Do not claim export is lossless merely because S3O Kit reports success.
if missing or extra or changed:
 print('ROUNDTRIP_NOT_LOSSLESS: keep original model, modify only verified UV data')
else:
 print('ROUNDTRIP_STRUCTURAL_STATS_MATCH: fuller triangle comparison still required')

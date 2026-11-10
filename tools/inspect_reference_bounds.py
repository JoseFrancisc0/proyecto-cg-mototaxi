from pathlib import Path
ROOT=Path(__file__).resolve().parent.parent
exec((ROOT/'tools/build_regional_neighborhoods.py').read_text(encoding='utf8').split('for region,families in districts.items():')[0],globals())
huayoccari_reference(0,14.8,8.1)
items=[]
for o in bpy.context.scene.objects:
    if o.type!='MESH':continue
    points=[o.matrix_world@Vector(c) for c in o.bound_box]
    items.append((max(p.z for p in points),min(p.z for p in points),o.name,tuple(o.location),tuple(o.scale)))
print('BOUNDS_DIAG',sorted(items,reverse=True)[:12],flush=True)

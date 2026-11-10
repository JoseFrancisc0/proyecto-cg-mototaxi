"""Inspect exported material colours and articulated traffic from GLB source."""
from pathlib import Path
import json,struct
ROOT=Path(__file__).resolve().parent.parent
def glb(path):
    data=path.read_bytes();size=struct.unpack_from('<I',data,12)[0]
    return json.loads(data[20:20+size])
models=json.loads((ROOT/'project/assets/houses/peru/catalog.json').read_text())
painted=0;factors=set();normal_surfaces=0;rough_surfaces=0
for model in models:
    path=ROOT/'project/assets/houses'/model['file'];doc=glb(path)
    for image in doc.get('images',[]):
        if 'uri' in image:assert (path.parent/image['uri']).is_file(),image['uri']
    for accessor in doc.get('accessors',[]):
        if 'bufferView' in accessor:assert 0<=accessor['bufferView']<len(doc['bufferViews'])
    for mat in doc.get('materials',[]):
        normal_surfaces+=int('normalTexture' in mat)
        rough_surfaces+=int('metallicRoughnessTexture' in mat.get('pbrMetallicRoughness',{}))
        if mat['name'].startswith('Pintura '):
            factor=mat.get('pbrMetallicRoughness',{}).get('baseColorFactor',[1,1,1,1])
            assert max(factor[:3])-min(factor[:3])>.015 or min(factor[:3])<.99,(model['file'],mat['name'],factor)
            factors.add(tuple(round(v,3) for v in factor[:3]));painted+=1
for name in ['tico','sedan','coaster','urban_bus']:
    doc=glb(ROOT/'project/assets/traffic'/(name+'.glb'))
    wheels=[n for n in doc['nodes'] if n.get('name') in ['WheelFL','WheelFR','WheelRL','WheelRR']]
    assert len(wheels)==4 and all(n.get('extras',{}).get('wheel_radius',0)>0 for n in wheels)
assert normal_surfaces>=20 and rough_surfaces>=20,(normal_surfaces,rough_surfaces)
print('ASSET_AUDIT',len(models),'models;',painted,'painted surfaces;',len(factors),'paint colours;',normal_surfaces,'normal surfaces;',rough_surfaces,'roughness surfaces; 4 articulated vehicles')

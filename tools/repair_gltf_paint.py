"""Preserve architectural paint in glTF's native baseColorFactor.

Blender's glTF exporter drops the colour input of this image/multiply graph.
Write the supported factor explicitly; retain all geometry and binary offsets.
"""
import ast,json,struct
from pathlib import Path
ROOT=Path(__file__).resolve().parent.parent
tree=ast.parse((ROOT/'tools/regional_facade_components.py').read_text(encoding='utf8'))
PALETTES=next(ast.literal_eval(n.value) for n in tree.body if isinstance(n,ast.Assign) and any(isinstance(t,ast.Name) and t.id=='PALETTES' for t in n.targets))
def repair(path):
    raw=path.read_bytes();length=struct.unpack_from('<I',raw,12)[0]
    doc=json.loads(raw[20:20+length]);changed=0
    for mat in doc.get('materials',[]):
        parts=mat.get('name','').split()
        if len(parts)==3 and parts[0]=='Pintura' and parts[1] in PALETTES and parts[2].isdigit():
            color=PALETTES[parts[1]][int(parts[2])%len(PALETTES[parts[1]])]
            mat.setdefault('pbrMetallicRoughness',{})['baseColorFactor']=[*color,1]
            changed+=1
    if changed:
        payload=json.dumps(doc,separators=(',',':')).encode();payload+=b' '*((-len(payload))%4)
        tail=raw[20+length:]
        path.write_bytes(struct.pack('<III',0x46546c67,2,20+len(payload)+len(tail))+struct.pack('<II',len(payload),0x4e4f534a)+payload+tail)
    return changed
if __name__=='__main__':
    count=sum(repair(p) for p in (ROOT/'project/assets/houses/peru').glob('*.glb'))
    print('GLTF_PAINT_FACTORS',count)

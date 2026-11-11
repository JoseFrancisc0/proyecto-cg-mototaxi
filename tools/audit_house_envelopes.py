"""Inspect exported triangles, not only authoring metadata, for open panels."""
from pathlib import Path
import json,struct,collections,sys
ROOT=Path(__file__).resolve().parent.parent
catalog=json.loads((ROOT/'project/assets/houses/peru/catalog.json').read_text())
report=[]
for item in catalog:
    if len(sys.argv)>1 and item['style'] not in sys.argv[1:]:continue
    path=ROOT/'project/assets/houses'/item['file'];raw=path.read_bytes()
    length=struct.unpack_from('<I',raw,12)[0];doc=json.loads(raw[20:20+length]);binary=raw[28+length:]
    def accessor(index):
        a=doc['accessors'][index];view=doc['bufferViews'][a['bufferView']]
        fmt={5126:'f',5125:'I',5123:'H',5121:'B'}[a['componentType']]
        n={'VEC3':3,'SCALAR':1}[a['type']];size=struct.calcsize('<'+fmt*n)
        offset=view.get('byteOffset',0)+a.get('byteOffset',0);stride=view.get('byteStride',size)
        return [struct.unpack_from('<'+fmt*n,binary,offset+i*stride) for i in range(a['count'])]
    boundaries=0;triangles=0
    for mesh in doc.get('meshes',[]):
        # A closed wall can have different finishes on adjacent faces. glTF
        # splits those faces into material primitives, not physical holes.
        edges=collections.Counter()
        for primitive in mesh['primitives']:
            positions=accessor(primitive['attributes']['POSITION'])
            canonical=[tuple(round(c,5) for c in point) for point in positions]
            indices=[v[0] for v in accessor(primitive['indices'])]
            for i in range(0,len(indices),3):
                p=[canonical[j] for j in indices[i:i+3]]
                if len(set(p))<3:continue
                triangles+=1
                for a,b in [(p[0],p[1]),(p[1],p[2]),(p[2],p[0])]:edges[tuple(sorted((a,b)))]+=1
        boundaries+=sum(n==1 for n in edges.values())
    assert boundaries==0,(item['file'],boundaries)
    assert item.get('entrance') and item.get('foundation_size'),item['file']
    report.append({'file':item['file'],'triangles':triangles,'open_edges':boundaries,'entrance':item['entrance']})
target=ROOT/'output/house_integrity';target.mkdir(exist_ok=True,parents=True)
(target/('mesh_audit_latest.json' if len(sys.argv)>1 else 'mesh_audit.json')).write_text(json.dumps(report,indent=2))
print('HOUSE_ENVELOPE_AUDIT',len(report),'models; no unclosed mesh edges; entrances present')

"""Deduplicate original encoded images across GLBs without changing pixels.

glTF permits external images in GLB containers. Geometry remains in the binary
chunk; a shared content-addressed library avoids embedding the same maps in
every building. Buffer views and accessor references are rebuilt explicitly.
"""
from pathlib import Path
import hashlib,json,struct

def share(path):
    raw=path.read_bytes();json_size=struct.unpack_from('<I',raw,12)[0]
    doc=json.loads(raw[20:20+json_size]);bin_start=20+json_size
    binary=raw[bin_start+8:]
    images=doc.get('images',[])
    embedded={image['bufferView'] for image in images if 'bufferView' in image}
    if not embedded:return 0
    folder=path.parent/'shared_textures';folder.mkdir(exist_ok=True)
    views=doc['bufferViews']
    for image in images:
        if 'bufferView' not in image:continue
        view=views[image.pop('bufferView')];offset=view.get('byteOffset',0)
        encoded=binary[offset:offset+view['byteLength']]
        extension={'image/png':'.png','image/jpeg':'.jpg','image/webp':'.webp'}[image['mimeType']]
        name=hashlib.sha256(encoded).hexdigest()+extension
        target=folder/name
        if not target.exists():target.write_bytes(encoded)
        image['uri']='shared_textures/'+name
    output=bytearray();mapping={};retained=[]
    for index,view in enumerate(views):
        if index in embedded:continue
        assert view.get('buffer',0)==0
        mapping[index]=len(retained);old_offset=view.get('byteOffset',0)
        output.extend(b'\0'*((-len(output))%4));view['byteOffset']=len(output)
        output.extend(binary[old_offset:old_offset+view['byteLength']]);retained.append(view)
    def remap(value):
        if isinstance(value,dict):
            for key,item in value.items():
                if key=='bufferView':value[key]=mapping[item]
                else:remap(item)
        elif isinstance(value,list):
            for item in value:remap(item)
    doc['bufferViews']=retained
    remap(doc)
    doc['buffers'][0]['byteLength']=len(output)
    for view in retained:assert view.get('byteOffset',0)+view['byteLength']<=len(output)
    payload=json.dumps(doc,separators=(',',':')).encode();payload+=b' '*((-len(payload))%4)
    output.extend(b'\0'*((-len(output))%4))
    length=12+8+len(payload)+8+len(output)
    path.write_bytes(struct.pack('<III',0x46546c67,2,length)+struct.pack('<II',len(payload),0x4e4f534a)+payload+struct.pack('<II',len(output),0x004e4942)+output)
    return len(raw)-length

if __name__=='__main__':
    root=Path(__file__).resolve().parent.parent/'project/assets/houses/peru'
    saved=sum(share(path) for path in root.glob('*.glb'))
    shared=sum(path.stat().st_size for path in (root/'shared_textures').iterdir() if path.suffix in ['.png','.jpg','.webp'])
    print('SHARED_TEXTURES',shared,'bytes; removed duplicate embedded bytes:',saved)

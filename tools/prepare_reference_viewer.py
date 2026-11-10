"""Copy unchanged reference photos with their actual formats into the game."""
from pathlib import Path
import json,sys,shutil
ROOT=Path(__file__).resolve().parent.parent
sys.path.insert(0,str(ROOT/'tools/.avatar_runtime'))
from PIL import Image
OUT=ROOT/'project/assets/reference_photos';OUT.mkdir(exist_ok=True)
refs=json.loads((ROOT/'output/comparacion/referencias.json').read_text(encoding='utf8'))
reviews=json.loads((ROOT/'docs/revision_visual.json').read_text(encoding='utf8'))
entries=[]
for ref in refs:
    source=ROOT/'output/comparacion'/ref['photo']
    with Image.open(source) as image:extension={'JPEG':'jpg','PNG':'png','WEBP':'webp'}[image.format]
    target=OUT/(ref['key']+'.'+extension)
    if not target.exists() or target.read_bytes()!=source.read_bytes():shutil.copyfile(source,target)
    entries.append(dict(key=ref['key'],title=ref['title'],photo='res://assets/reference_photos/'+target.name,source=ref['source'],**reviews[ref['key']]))
(OUT/'catalog.json').write_text(json.dumps(entries,ensure_ascii=False,indent=2),encoding='utf8')
sources='# Fotos originales del visor\n\nCopias sin alterar los píxeles, con la extensión correspondiente al formato real de cada descarga. Se muestran junto al entorno 3D como referencia, dentro del alcance y las licencias indicados por el usuario.\n\n'
sources+='\n'.join('- `'+Path(e['photo']).name+'`: '+e['source'] for e in entries)
(OUT/'SOURCE.md').write_text(sources+'\n',encoding='utf8')
print('VIEWER_REFERENCES',len(entries))

from pathlib import Path
import urllib.request,json
ROOT=Path(__file__).resolve().parent.parent;OUT=ROOT/'project/assets/houses/peru/graffiti';OUT.mkdir(exist_ok=True)
entries=[]
for key,asset,suffix,page in [('chrome','08','-1',61),('urban','07','-1',60),('silent','71','',59),('wild','70','',58)]:
    for kind,channel in [('albedo','BaseColor'),('opacity','Opacity')]:
        url=f'https://3dtexel.com/wp-content/uploads/2025/10/T_Graffiti_{asset}_1K_JPEG_{channel}{suffix}.jpg'
        target=OUT/(key+'_'+kind+'.jpg')
        if not target.exists():
            req=urllib.request.Request(url,headers={'User-Agent':'Mozilla/5.0','Referer':f'https://3dtexel.com/product/graffiti-decals-{page}/'})
            target.write_bytes(urllib.request.urlopen(req,timeout=40).read())
    entries.append(dict(id=key,source=f'https://3dtexel.com/product/graffiti-decals-{page}/',author='Lucas Anton Gomez',license='CC0',resolution=1024))
    print('GRAFFITI',key,flush=True)
(OUT/'catalog.json').write_text(json.dumps(entries,indent=2))
(OUT/'SOURCE.md').write_text('# Grafitis con transparencia\n\nCuatro diseños manuales de Lucas Anton Gomez, [3DTexel](https://3dtexel.com/decals/), CC0. Se usan los mapas públicos de color y opacidad a 1K. Fuentes individuales en `catalog.json`. Se aplican como pintura en muros, con máscara de transparencia. No se contrataron generadores ni se utilizaron fotografías de calles como decal.\n',encoding='utf8')

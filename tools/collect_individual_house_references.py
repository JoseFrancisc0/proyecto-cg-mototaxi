"""Individual-building study sources. Keep the original downloaded image bytes."""
from pathlib import Path
from html.parser import HTMLParser
from urllib.parse import urljoin
import urllib.request,json,shutil,sys,io
ROOT=Path(__file__).resolve().parent.parent
OUT=ROOT/'project/assets/house_studies';OUT.mkdir(exist_ok=True)
sys.path.insert(0,str(ROOT/'tools/.avatar_runtime'))
from PIL import Image
user_photos=[
('porton_madera','Vivienda con portón de madera','676ffe3a-82be-4dd3-bef4-c75d10b8c42c'),
('casa_angosta','Casa angosta con balcón','2e19680f-4437-4517-89c5-bb2d8022ef1d'),
('casa_tropical','Vivienda blanca con jardín','bb67f1e8-cfcd-4d64-a6fd-9a05fb27d82f'),
('casa_esquina','Vivienda contemporánea de esquina','79500d69-0796-4a1d-90e1-8aaecf6ace12')]
entries=[]
for v,(key,title,clipboard) in enumerate(user_photos):
    source=Path('C:/Users/USUARIO/AppData/Local/Temp')/('codex-clipboard-'+clipboard+'.png')
    target=OUT/(key+'.png')
    if source.exists():shutil.copyfile(source,target)
    assert target.exists(),source
    entries.append({'id':key,'title':title,'photo':target.name,'source':'Referencia aportada por el usuario; ubicación no verificada','region':'Referencia de diseño','model':'peru/costa_casa_moderna_'+str(v)+'.glb','kind':'user_reference'})

sources=[
('costa_azul','Casa Costa Azul, La Molina','Costa · vivienda contemporánea','https://www.aram.pe/proyectos/casa-costa-azul-la-molina-lima'),
('kinsawasi','Casa Kinsawasi, Pisac','Sierra · vivienda de campo','https://reactivoarq.com/en/kinsawasi'),
('larapa','Casa Larapa, Cusco','Sierra · vivienda urbana','https://reactivoarq.com/en/larapa'),
('zarumilla','Residencial Zarumilla, Cusco','Sierra · edificio residencial','https://reactivoarq.com/en/zarumilla'),
('enaco','Residencial Enaco, Cusco','Sierra · edificio residencial','https://reactivoarq.com/en/enaco'),
('huancaro','Residencial Huancaro, Cusco','Sierra · edificio residencial','https://reactivoarq.com/en/huancaro'),
('chelita','Casa Chelita, Huasao','Sierra · vivienda de campo','https://reactivoarq.com/en/chelita'),
('martha','Casa Martha, Tarapoto','Selva · madera, quincha y palma','https://marianabidart.com/project/casa-martha/'),
('el_rio','Cabaña El Río, Loreto','Selva · vivienda elevada (proyecto)','https://reactivoarq.com/en/cabana-el-rio'),
('azul','Casa Azul, Barranco','Costa · vivienda republicana restaurada','https://www.davidmutal.pe/casaazul'),
('sucre','Casa Sucre, Barranco','Costa · vivienda urbana contemporánea','https://romanbauer.org/portfolio-item/casa-sucre/'),
('tarapoto','Vivienda en Tarapoto','Selva · vivienda unifamiliar (propuesta)','https://www.ark-deko.com/vivienda-tarapoto.html'),
('sumaq','Vivienda rural Sumaq Wasi, Cusco','Sierra · vivienda rural','https://www.gob.pe/institucion/pnvr/noticias/52906-programa-nacional-de-vivienda-rural-y-los-sumaq-wasi-en-cusco'),
('ladera','Vivienda progresiva','Costa · autoconstrucción','https://www.swisscontact.org/es/proyectos/vivienda-progresiva')]

class Images(HTMLParser):
    def __init__(self):super().__init__();self.og=[];self.images=[]
    def handle_starttag(self,tag,attrs):
        a=dict(attrs)
        if tag=='meta' and a.get('property')=='og:image':self.og.append(a.get('content',''))
        if tag=='img':
            value=a.get('data-src') or a.get('src','')
            if value and not any(term in (value+' '+a.get('alt','')).lower() for term in ['logo','avatar','icon','data:','isometr']):self.images.append(value)
def get(url):
    request=urllib.request.Request(url,headers={'User-Agent':'Mozilla/5.0 (architecture reference study)'})
    with urllib.request.urlopen(request,timeout=25) as response:return response.read(),response.headers.get_content_type()

for key,title,region,url in sources:
    entry={'id':key,'title':title,'region':region,'source':url,'kind':'research','status':'Fuente localizada; pendiente de correspondencia con modelo'}
    try:
        page,_=get(url);parser=Images();parser.feed(page.decode('utf8','replace'))
        # Project-specific image paths take priority over a generic site card.
        candidates=parser.images+parser.og
        if 'reactivoarq' not in url and key!='azul':candidates=parser.og+parser.images
        for candidate in dict.fromkeys(candidates):
            image_url=urljoin(url,candidate)
            try:
                data,mime=get(image_url)
                if not mime.startswith('image/') or len(data)<15000:continue
                with Image.open(io.BytesIO(data)) as image:
                    if min(image.size)<400:continue
                extension={'image/jpeg':'.jpg','image/png':'.png','image/webp':'.webp'}.get(mime)
                if not extension:continue
                target=OUT/(key+extension);target.write_bytes(data)
                entry.update(photo=target.name,image_source=image_url);break
            except Exception:continue
        print('REFERENCE',key,entry.get('photo','source only'),flush=True)
    except Exception as error:entry['download_note']=str(error);print('REFERENCE_SOURCE_ONLY',key,flush=True)
    entries.append(entry)
for entry in entries:
    if entry['id']=='ladera':
        entry.pop('photo',None);entry['status']='Estudio de contexto; no se utiliza como referencia de una casa individual'
(OUT/'catalog.json').write_text(json.dumps(entries,ensure_ascii=False,indent=2),encoding='utf8')
print('INDIVIDUAL_REFERENCES',len(entries))

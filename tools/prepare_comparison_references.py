"""Real photographs stay in the review gallery; source information is kept separately."""
from pathlib import Path
import json,urllib.request,urllib.parse,shutil,re,time
ROOT=Path(__file__).resolve().parent.parent;OUT=ROOT/'output/comparacion';OUT.mkdir(parents=True,exist_ok=True);PHOTOS=OUT/'referencias';PHOTOS.mkdir(exist_ok=True)
TEMP=Path('C:/Users/USUARIO/AppData/Local/Temp')
def local(key,name,title):
    source=TEMP/('codex-clipboard-'+name+'.png');target=PHOTOS/(key+'.png')
    if source.exists():shutil.copyfile(source,target)
    return dict(key=key,title=title,photo='referencias/'+target.name,source='Referencia fotográfica aportada por el usuario',license='Referencia del usuario',local=source.exists())
def web(key,title,url,page):
    target=PHOTOS/(key+'.jpg')
    for attempt in range(3):
        try:
            if not target.exists():
                req=urllib.request.Request(url,headers={'User-Agent':'PeruTaxiAcademic/1.0 reference board'})
                target.write_bytes(urllib.request.urlopen(req,timeout=30).read())
            return dict(key=key,title=title,photo='referencias/'+target.name,source=page,license='Solo referencia en galería; no incluida como textura del juego',local=True)
        except Exception as e:
            if attempt==2:return dict(key=key,title=title,photo=url,source=page,license='Referencia web',local=False,error=str(e))
            time.sleep(1)
refs=[]
refs.append(web('0_ladera','Villa María del Triunfo · ladera','https://www.swisscontact.org/_ari/fc433215-eb93-4510-aaa6-bd257a92e940/9c4aeebe671b9fe9682118919b525e8763e143f4/1200/0/og/Peru_ViPro_Lima_Cover_Photo.jpg.webp','https://www.swisscontact.org/es/proyectos/vivienda-progresiva'))
refs.append(local('0_popular','85c0a740-db65-4209-b132-ef9315c6d962','Costa · calle de barrio'))
refs.append(web('0_tradicional','Barranco · casonas contiguas','https://portal.andina.pe/EDPfotografia3/Thumbnail/2019/01/17/000557925W.jpg','https://andina.pe/agencia/galeria.aspx?FotoId=557897&GaleriaId=5385'))
refs.append(web('0_residencial','Miraflores · casas y jardines','https://images.squarespace-cdn.com/content/v1/6305036b20097f4c184ac55e/8894d8ed-2e09-4817-bff6-b53c09c6813a/Jardin%2B1.jpg?format=1000w','https://www.quintamiraflores.com/'))
refs.append(local('0_moderna','9496053c-f9ff-4559-b6ce-3718882930f4','Costa · edificios del malecón'))
refs.append(local('0_rural','4b93fefb-4d22-4f0a-94b3-c20649367387','Costa · autoconstrucción y borde urbano'))
refs.append(web('1_popular','Cusco · periferia urbana','https://upload.wikimedia.org/wikipedia/commons/a/a4/Peru_-_Cusco_070_-_hillside_suburbs_%286967954124%29.jpg','https://commons.wikimedia.org/wiki/File:Peru_-_Cusco_070_-_hillside_suburbs_(6967954124).jpg'))
refs.append(web('1_tradicional','Cusco · San Blas','https://www.peru.travel/Contenido/General/Imagen/es/646/1.1/barrio-san-blas-cusco.jpg','https://www.peru.travel/es/masperu/7-cosas-gratis-que-puedes-hacer-en-la-ciudad-de-cusco'))
refs.append(web('1_residencial','Valle Sagrado · terrazas habitadas','https://images.squarespace-cdn.com/content/v1/53456a2fe4b011260e416f8e/1399474445435-0SUTJF2AQX8B444K3HEL/HY%2B10.jpg?format=1500w','https://www.barclaycrousse.com/huayoccari'))
refs.append(web('1_moderna','Huarán · vivienda contemporánea','https://estudiolocal.pe/wp-content/uploads/2024/02/Huaran-1B.jpg','https://estudiolocal.pe/casa-huaran/'))
refs.append(web('1_rural','Entorno de Cusco · vivienda de adobe','https://library.sweetmarias.com/wp-content/uploads/2020/11/House-outside-Cusco-Peru-Sweet-Marias-12.jpg','https://library.sweetmarias.com/peru-coffee-regions-cuzco-and-quillabamba/'))
refs.append(local('1_ladera','ee67947c-30f8-411e-9fa1-2bd8d773f72d','Sierra · calle de adobe y pendiente'))
refs.append(web('2_popular','Tarapoto · calle popular','https://www.bienesonline.com/peru/photos/casa-en-venta-tarapoto-11507776717.jpg','https://www.bienesonline.pe/fotos-CAV23838-inicio.php'))
refs.append(web('2_tradicional','Iquitos · azulejos y balcones','https://thatbackpacker.com/wp-content/uploads/colonial-architecture-and-pedestrians-walking-by-in-iquitos-peru.jpeg','https://thatbackpacker.com/things-to-do-in-iquitos/'))
refs.append(web('2_residencial','Tarapoto · vivienda con balcón','https://tuyoaunclic.com/upload/inmuebles/300WhatsApp%20Image%202025-05-12%20at%2012.28.02%20PM.jpeg','https://tuyoaunclic.com/inmueble-300'))
refs.append(web('2_moderna','Tarapoto · volúmenes y jardín tropical','https://a0.muscache.com/im/pictures/hosting/Hosting-U3RheVN1cHBseUxpc3Rpbmc6MTI1OTcxNzM2ODI4NTc2NjAwNw%3D%3D/original/a98757e8-c01c-441f-bd11-4949336353b5.jpeg','https://www.airbnb.com.mt/rooms/1259717368285766007'))
refs.append(local('2_rural','1b214c39-cc69-4019-a92b-dce9df4e289a','Amazonía · comunidad rural'))
refs.append(web('2_ribereno','Belén · viviendas ribereñas','https://lamula.pe/media/uploads/t/1cd6ef5e1dff5f698b58b86e02686c30.jpg','https://christianreynoso.lamula.pe/2025/07/08/el-barrio-belen-o-la-venecia-de-iquitos-parte-1/christianreynoso/'))
for key,photo,title in [('tico','5ad6e569-0f2a-48c6-87da-1e75ae31567a','Taxi compacto · referencia Tico'),('sedan','8c7590be-b4b1-4f67-9738-f9137aef127c','Taxi sedán · referencia urbana'),('coaster','5b6c2505-5e1b-462a-92e9-bcdc8566ee2b','Cúster · referencia de Lima'),('urban_bus','fc7096c4-aaa5-4a14-b4ea-b21a4dc0fceb','Bus urbano · referencia de Lima')]:refs.append(local(key,photo,title))
fallbacks={'1_popular':('4387deca-bda4-4e34-bf17-71a4d25b1209','Cusco · centro y laderas'),'1_rural':('ee67947c-30f8-411e-9fa1-2bd8d773f72d','Sierra · adobe y teja')}
for i,ref in enumerate(refs):
    if not ref['local'] and ref['key'] in fallbacks:
        name,title=fallbacks[ref['key']];refs[i]=local(ref['key'],name,title)
    elif not ref['local'] and ref['key']=='2_residencial':
        refs[i]=web(ref['key'],'Tarapoto · viviendas ajardinadas','https://img10.naventcdn.com/avisos/11/01/44/92/16/99/720x532/1493262593.jpg?isFirstImage=true','https://www.adondevivir.com/propiedades/clasificado/vecltepa-residencial-bungalow-144921699.html')
fallbacks={'1_popular':('4387deca-bda4-4e34-bf17-71a4d25b1209','Cusco · centro y laderas'),'1_rural':('ee67947c-30f8-411e-9fa1-2bd8d773f72d','Sierra · adobe y teja')}
for i,ref in enumerate(refs):
    if not ref['local'] and ref['key'] in fallbacks:
        name,title=fallbacks[ref['key']];refs[i]=local(ref['key'],name,title)
    elif not ref['local'] and ref['key']=='2_residencial':
        refs[i]=web(ref['key'],'Tarapoto · viviendas ajardinadas','https://img10.naventcdn.com/avisos/11/01/44/92/16/99/720x532/1493262593.jpg?isFirstImage=true','https://www.adondevivir.com/propiedades/clasificado/vecltepa-residencial-bungalow-144921699.html')
(OUT/'referencias.json').write_text(json.dumps(refs,ensure_ascii=False,indent=2),encoding='utf8')
print('REFERENCE_PHOTOS',len(refs),'local',sum(r['local'] for r in refs),flush=True)
for ref in refs:
    if not ref['local']:print('REMOTE_REFERENCE',ref['key'],ref.get('error','missing local'))

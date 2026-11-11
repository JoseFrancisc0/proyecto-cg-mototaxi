"""Review board: unmodified reference photos beside real Godot captures."""
from pathlib import Path
import json,html,hashlib,re
ROOT=Path(__file__).resolve().parent.parent;OUT=ROOT/'output/comparacion'
refs=json.loads((OUT/'referencias.json').read_text(encoding='utf8'))
catalog=json.loads((ROOT/'project/assets/houses/peru/catalog.json').read_text())
materials=json.loads((ROOT/'project/assets/houses/peru/materials/catalog.json').read_text())
names=['Costa','Sierra','Selva']
reviews=json.loads((ROOT/'docs/revision_visual.json').read_text(encoding='utf8'))
zone_names={'ladera':'Ladera y autoconstrucción','popular':'Barrio popular','tradicional':'Centro tradicional','residencial':'Residencial','moderna':'Contemporáneo','rural':'Rural','ribereno':'Ribereño'}
targets={
'0_ladera':'Lotes escalonados, ladrillo y madera, calamina y accesos por escaleras.',
'0_popular':'Frentes adosados, distintos pisos, muros sin tarrajear y fachadas pintadas.',
'0_tradicional':'Casonas de Barranco: cornisa frontal baja, arcos y fachadas contiguas.',
'0_residencial':'Retiros, cercos bajos, jardines y viviendas de uno o dos pisos.',
'0_moderna':'Volúmenes retranqueados, balcones, ventanales y edificios de apartamentos.',
'0_rural':'Construcción baja, materiales expuestos y cubiertas sencillas.',
'1_popular':'Ladrillo urbano, basamento mineral y cubiertas inclinadas.',
'1_tradicional':'Cal, carpintería azul, balcones, piedra en la base y teja.',
'1_residencial':'Piedra, porches, madera y cubiertas de teja en un entorno de valle.',
'1_moderna':'Piedra, ventanales amplios y techos inclinados; referencia contemporánea de Huarán.',
'1_rural':'Adobe, ventanas pequeñas y tejados bajos con aleros.',
'1_ladera':'Volúmenes compactos escalonados y acceso peatonal en pendiente.',
'2_popular':'Color, contraventanas, ventilación y aleros de calamina.',
'2_tradicional':'Iquitos: frentes altos, azulejos, balcones y galería ventilada.',
'2_residencial':'Porches sombreados, jardines y cerramientos ventilados.',
'2_moderna':'Ventanales protegidos, madera y cubierta tropical con gran alero.',
'2_rural':'Madera, palma y galerías abiertas; casas separadas del suelo.',
'2_ribereno':'Pilotes, escaleras, balcones y techos de calamina en distintas alturas.',
'tico':'Proporciones de un compacto tipo Tico, silueta recta, taxi y llantas de acero.',
'sedan':'Capó, cabina y maletera separados, ventanillas y ruedas con medidas propias.',
'coaster':'Cúster de Lima: cabina inclinada, interior, espejos y franjas de transporte.',
'urban_bus':'Bus urbano: ventanas modulares, livery, ruta, interior y ruedas sin fotografías pegadas.'}
cards=[]
for ref in refs:
    key=ref['key'];region=int(key[0]) if key[0].isdigit() else 3
    title=(names[region]+' · '+zone_names[key.split('_',1)[1]]) if region<3 else ref['title']
    count=sum(1 for m in catalog if int(m['region'])==region and key.split('_',1)[1] in m['zones']) if region<3 else 1
    source=ref['source'];credit=f'<a href="{html.escape(source)}" target="_blank" rel="noreferrer">Fuente de la fotografía ↗</a>' if source.startswith('https://') else html.escape(source)
    review=reviews[key]
    assessment=f'<div class="assessment {"rework" if review["status"]=="Por mal camino" else "partial"}"><b>{html.escape(review["status"])}</b><p>{html.escape(review["note"])}</p></div>'
    views=''
    if region==3:
        views=f'<div class="angles"><a href="juego/{key}_opposite.png">Ver el otro lateral</a> · <a href="juego/{key}_rear.png">Ver desde atrás</a></div>'
    cards.append(f'''<article data-region="{region}" id="{key}"><header><span>{names[region] if region<3 else 'Vehículos'}</span><h2>{html.escape(title)}</h2><small>{count} variantes del juego</small></header>
    <div class="pair" onclick="enlarge(this)"><figure><img loading="lazy" src="{html.escape(ref['photo'])}" alt="Foto real: {html.escape(ref['title'])}"><figcaption>FOTO REAL · {html.escape(ref['title'])}</figcaption></figure><figure><img loading="lazy" src="juego/{key}.png" alt="Captura del juego: {html.escape(title)}"><figcaption>VERSIÓN DEL JUEGO</figcaption></figure></div>
    {assessment}<p>{html.escape(targets[key])}</p>{views}<footer>{credit}</footer></article>''')
map_cards=[]
for key,title in [('rio_altura','Río y calzada a distinta altura'),('cruce_unificado','Cruce sobre una superficie compartida'),('mapa_region_0','Costa en el mapa generado'),('mapa_region_1','Sierra en el mapa generado'),('mapa_region_2','Selva en el mapa generado')]:
    map_cards.append(f'<article data-region="4"><header><span>Partida real</span><h2>{title}</h2></header><div class="single" onclick="enlarge(this)"><img loading="lazy" src="juego/{key}.png" alt="{title}"></div><p>Generación completa: 512 × 512 celdas, erosión activada, semilla 67. Esta captura corresponde al mapa, no al catálogo de muestra.</p></article>')
texture_sections=[];model_sections=[]
for key,title in [('vigas','Puente de vigas'),('arco','Puente de arco'),('celosia','Puente de celosía'),('atirantado','Puente atirantado')]:
    map_cards.append(f'<article data-region="4"><header><span>Muestra estructural</span><h2>{title}</h2></header><div class="single" onclick="enlarge(this)"><img loading="lazy" src="juego/puente_{key}.png" alt="{title}"></div><p>Construido por PeruBridges sobre un cauce de muestra. Permite revisar la estructura; no es una captura del mapa de partida ni una réplica aprobada de un puente real.</p></article>')
for region,name in enumerate(names):
    label=['costa','sierra','selva'][region]
    tiles=''.join(f'<a href="{html.escape(m["source"])}" target="_blank"><img loading="lazy" src="../../project/assets/houses/peru/materials/{m["file"]}" alt="{m["id"]}"><small>{m["id"].replace("_"," ")}</small></a>' for m in materials if m['region']==label)
    texture_sections.append(f'<details data-region="{region}"><summary>{name} · 20 superficies fotográficas distintas</summary><div class="textures">{tiles}</div><p>Poly Haven · CC0. Los autores, dimensiones físicas y enlaces originales se conservan en el catálogo de materiales.</p></details>')
    tiles=''.join(f'<a href="../peru_house_{i:02d}.png" target="_blank"><img loading="lazy" src="../peru_house_{i:02d}.png" alt="Modelo {i+1}"><small>{zone_names.get(m["zones"][0],m["zones"][0])} · {m["file"].split("_")[-1].split(".")[0]}</small></a>' for i,m in enumerate(catalog) if m['region']==region)
    count=sum(m['region']==region for m in catalog)
    model_sections.append(f'<details data-region="{region}"><summary>{name} · {count} viviendas individuales</summary><div class="textures">{tiles}</div></details>')
document='''<!doctype html><html lang="es"><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><title>Perú Taxi · comparación con referencias reales</title>
<style>*{box-sizing:border-box}body{margin:0;background:#111820;color:#e8e9df;font:16px/1.5 system-ui,sans-serif}main{max-width:1540px;margin:auto;padding:32px 28px 70px}.eyebrow{letter-spacing:.15em;color:#e2b75c;font-size:13px}h1{font-size:clamp(28px,4vw,48px);line-height:1.1;margin:12px 0 16px}.intro{max-width:980px;color:#bac3c9}.stats{display:flex;gap:26px;margin:24px 0}.stats b{display:block;font-size:28px;color:#e2b75c}.stats span{font-size:13px;color:#bac3c9}nav{position:sticky;top:0;background:#111820ed;backdrop-filter:blur(8px);z-index:2;padding:14px 0;display:flex;gap:8px;flex-wrap:wrap}button{font:inherit;color:inherit;background:#26313b;border:1px solid #52606a;border-radius:24px;padding:8px 19px;cursor:pointer}button.active,button:hover{background:#e2b75c;color:#111820;border-color:#e2b75c}.grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(min(100%,590px),1fr));gap:22px;margin:14px 0 32px}article{background:#1b2630;border:1px solid #3a4650;border-radius:10px;overflow:hidden}article header{padding:16px 20px}header span{font-size:12px;text-transform:uppercase;letter-spacing:.12em;color:#e2b75c}h2{font-size:21px;line-height:1.3;margin:5px 0}small{color:#b5bec4}figure{margin:0;min-width:0;background:#0d1319}.pair{display:grid;grid-template-columns:1fr 1fr;gap:2px;cursor:zoom-in}.pair img{display:block;width:100%;height:230px;object-fit:contain}.single{cursor:zoom-in}.single img{width:100%;display:block}figcaption{font-size:10px;letter-spacing:.05em;padding:9px 12px;color:#d0d3ca;background:#0d1319;min-height:43px}article p,article footer{padding:0 20px;font-size:14px;color:#bac3c9}article footer{padding-bottom:18px;font-size:12px}a{color:#e2b75c}details{background:#1b2630;border:1px solid #3a4650;border-radius:8px;padding:16px;margin:12px 0}summary{cursor:pointer;font-size:20px}.textures{display:grid;grid-template-columns:repeat(auto-fill,minmax(150px,1fr));gap:12px;margin-top:20px}.textures a{display:block;font-size:12px;text-decoration:none}.textures img{width:100%;aspect-ratio:1;object-fit:contain;background:#0d1319}.textures small{display:block}dialog{width:96vw;max-width:1700px;background:#111820;color:white;border:1px solid #59626a;border-radius:10px;padding:18px}dialog::backdrop{background:#000c}dialog .pair img{height:70vh}dialog .single img{max-height:75vh;object-fit:contain}dialog button{float:right;margin-bottom:10px}dialog .pair,dialog .single{clear:both}[hidden]{display:none!important}.note{padding:16px 20px;border-left:3px solid #e2b75c;background:#1b2630;color:#bac3c9;font-size:14px}.legend{font-size:13px;color:#a7b0b6;margin-bottom:22px}@media(max-width:650px){main{padding:22px 12px}.pair img{height:170px}dialog .pair{grid-template-columns:1fr}dialog .pair img{height:34vh}.stats{gap:16px}.stats b{font-size:23px}}</style>
<main><div class="eyebrow">PERÚ TAXI · REVISIÓN VISUAL</div><h1>De la referencia real<br>a la versión del juego.</h1><p class="intro">Comparaciones lado a lado de barrios y vehículos. Las fotografías se mantienen como referencia; las imágenes de la derecha son capturas de Godot usando los recursos integrados en el proyecto.</p><div class="stats"><div><b>18</b><span>familias de barrios</span></div><div><b>72</b><span>viviendas · 24 por región</span></div><div><b>60</b><span>texturas fotográficas</span></div><div><b>4</b><span>vehículos reconstruidos</span></div></div><nav><button class="active" onclick="filter('all',this)">Todo</button><button onclick="filter('0',this)">Costa</button><button onclick="filter('1',this)">Sierra</button><button onclick="filter('2',this)">Selva</button><button onclick="filter('3',this)">Autos y buses</button><button onclick="filter('4',this)">Mapa, río y cruces</button></nav><p class="legend">Pulsa una comparación para ampliarla. Las vistas de barrios son escenas de muestra para comparar los modelos; la sección del mapa muestra la generación real de una partida.</p><div class="grid">'''+''.join(cards+map_cards)+'''</div><div class="note">La referencia guía la silueta, los materiales, los techos y la densidad. Los recursos siguen siendo una interpretación modular para el juego: las fotografías permiten comprobar las diferencias de detalle, iluminación y distribución que todavía existen; no se presentan como réplicas fotogramétricas exactas.</div><h2>Biblioteca de materiales</h2>'''+''.join(texture_sections)+'''<h2>Viviendas individuales</h2>'''+''.join(model_sections)+'''<p class="legend">Fuentes de las fotos junto a cada comparación. Los archivos originales y atribuciones de los materiales están documentados en el proyecto.</p></main><dialog id="zoom"><button onclick="this.parentElement.close()">Cerrar ×</button><div id="zoomBody"></div></dialog><script>function filter(region,button){document.querySelectorAll('[data-region]').forEach(e=>e.hidden=region!=='all'&&e.dataset.region!==region);document.querySelectorAll('nav button').forEach(b=>b.classList.remove('active'));button.classList.add('active')}function enlarge(element){let clone=element.cloneNode(true);clone.removeAttribute('onclick');clone.querySelectorAll('img').forEach(i=>i.loading='eager');document.getElementById('zoomBody').replaceChildren(clone);document.getElementById('zoom').showModal()}document.getElementById('zoom').addEventListener('click',e=>{if(e.target.id==='zoom')e.target.close()});</script></html>'''
document=re.sub(r'<div class="stats">.*?</div></div><nav>', '<div class="note"><strong>Meta: parecido casi idéntico.</strong> Ninguna comparación se marca como aprobada en esta revisión. «Avance parcial» identifica mejoras concretas; «Por mal camino» exige rehacer el conjunto.</div><nav>',document,flags=re.S)
document=document.replace('</style>','.assessment{margin:14px 18px;padding:12px;border-left:4px solid #dda649;background:#2e2b25}.assessment p{padding:0;margin:6px 0 0;font-size:13px}.assessment.rework{border-color:#e36c61;background:#35282a}.angles{padding:0 20px 14px;font-size:13px}</style>')
document=document.replace('<nav>','<p><a style="color:#e9bd70" href="../house_integrity/index.html">Nueva revisión: cada casa por separado, referencia individual y cinco ángulos →</a></p><nav>',1)
(OUT/'index.html').write_text(document,encoding='utf8')
unique={hashlib.sha256((ROOT/'project/assets/houses/peru/materials'/m['file']).read_bytes()).hexdigest() for m in materials}
assert len(catalog)==76 and len(materials)==60 and len(unique)==60
for region,expected in enumerate([28,24,24]):assert sum(m['region']==region for m in catalog)==expected
for ref in refs:
    assert (OUT/ref['photo']).is_file(),ref['key']
from html.parser import HTMLParser
class ImageAudit(HTMLParser):
    def handle_starttag(self, tag, attrs):
        if tag != 'img': return
        source = dict(attrs).get('src', '')
        assert source and (OUT/source).is_file(), f'Missing gallery image: {source}'
ImageAudit().feed(document)
print('COMPARISON_GALLERY',len(cards),'references,',len(map_cards),'map views;',len(catalog),'models, 60 unique photographic materials')

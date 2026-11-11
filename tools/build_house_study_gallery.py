"""Review individual houses and all exposed elevations, without neighbourhood-photo substitutes."""
from pathlib import Path
import json,html
ROOT=Path(__file__).resolve().parent.parent;OUT=ROOT/'output/house_integrity';OUT.mkdir(exist_ok=True)
models=json.loads((ROOT/'project/assets/houses/peru/catalog.json').read_text(encoding='utf8'))
sources=json.loads((ROOT/'project/assets/house_studies/catalog.json').read_text(encoding='utf8'))
known={s['id']:s for s in sources}
prior={s['key']:s for s in json.loads((ROOT/'project/assets/reference_photos/catalog.json').read_text(encoding='utf8'))}
esc=html.escape
cards=[]
for model in models:
    key=Path(model['file']).stem;variant=int(key[-1]);style=model['style'];ref={};photo=''
    if style=='casa_moderna':ref=known[['porton_madera','casa_angosta','casa_tropical','casa_esquina'][variant]]
    elif style=='andina_actual':ref=known[['kinsawasi','larapa','zarumilla','enaco'][variant]]
    elif style=='barranco':ref=known['sucre']
    if ref.get('photo'):photo='../../project/assets/house_studies/'+ref['photo']
    old_key={'jardin':'0_residencial','valle_sagrado':'1_residencial','san_blas':'1_tradicional','tropical_actual':'2_moderna','iquitos':'2_tradicional'}.get(style)
    if not ref and old_key:
        ref=prior[old_key];photo='../../project/'+ref['photo'].removeprefix('res://')
    graffiti=bool(model.get('graffiti_wall',False))
    if graffiti:
        photo='../../project/assets/houses/peru/'+model['graffiti_source']
        ref={'title':'Referencia del acabado de pared, no de la casa completa','source':'Textura de pared y grafiti aportada por el usuario'}
    status='Avance parcial' if style in ['casa_moderna','andina_actual'] else 'Por mal camino respecto a esta referencia' if style=='barranco' else 'Parecido pendiente de revisar' if photo else 'Falta referencia individual'
    if graffiti:status='Acabado de pared aplicado · referencia individual de la casa pendiente'
    images=''
    for view,title in [('frente','Frente'),('izquierda','Costado izquierdo'),('derecha','Costado derecho'),('atras','Parte trasera'),('arriba','Desde arriba')]:
        path=OUT/(key+'_'+view+'.png');assert path.exists(),path
        images+=f'<figure><img loading="lazy" src="{path.name}" alt="{title}"><figcaption>{title}</figcaption></figure>'
    ref_html=f'<img loading="lazy" src="{esc(photo)}" alt="Referencia individual"><p>{esc(ref.get("title","Referencia"))}</p>' if photo else '<p class="missing">Falta asignar una referencia individual apropiada. No se utiliza una foto general de barrio para aparentar parecido.</p>'
    if photo:assert (OUT/photo).is_file(),photo
    source=ref.get('source','')
    attribution=f'<a href="{esc(source)}" target="_blank" rel="noopener">Fuente de la referencia</a>' if source.startswith('http') else esc(source)
    preview=('derecha' if int(model.get('graffiti_side',1))>0 else 'frente' if int(model.get('graffiti_side',1))==0 else 'izquierda') if graffiti else 'frente'
    badge=' · con grafiti' if graffiti else ''
    cards.append(f'<article data-region="{model["region"]}" data-graffiti="{int(graffiti)}"><h2>{esc(key.replace("_"," "))}{badge}</h2><p class="status">{status}</p><div class="pair"><section>{ref_html}<p>{attribution}</p></section><section><img loading="lazy" src="{key}_{preview}.png" alt="Modelo del juego"><p>Modelo del juego · los mismos recursos del mapa</p></section></div><details><summary>Revisar los cinco ángulos</summary><div class="angles">{images}</div></details></article>')
research=''
for source in sources:
    if source['kind']!='research':continue
    photo=source.get('photo','')
    image=f'<img loading="lazy" src="../../project/assets/house_studies/{esc(photo)}" alt="{esc(source["title"])}">' if photo else ''
    research+=f'<article>{image}<h3>{esc(source["title"])}</h3><p>{esc(source["region"])}</p><p>{esc(source.get("status","Pendiente"))}</p><a href="{esc(source["source"])}">Fuente original</a></article>'
document='''<!doctype html><html lang="es"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Casas · revisión individual</title><style>
*{box-sizing:border-box}body{background:#131c24;color:#e5e9e9;font:16px/1.5 system-ui;margin:0}main{max-width:1500px;margin:auto;padding:30px}h1{margin-bottom:5px}p{color:#b8c4cc}.status{color:#e9bd70}nav{position:sticky;top:0;background:#131c24ee;padding:15px 0;display:flex;gap:10px;z-index:1}button,summary{font:inherit;cursor:pointer;color:inherit;background:#263745;border:1px solid #536675;border-radius:6px;padding:10px 16px}a{color:#e9bd70}.grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(min(100%,620px),1fr));gap:22px}article{background:#1e2b35;border:1px solid #394b59;border-radius:9px;padding:18px;overflow:hidden}h2{font-size:21px}.pair{display:grid;grid-template-columns:1fr 1fr;gap:12px}.pair section{min-width:0}img{max-width:100%;width:100%;height:290px;object-fit:contain;background:#17212a}.angles{display:grid;grid-template-columns:repeat(2,1fr);gap:10px;margin-top:15px}figure{margin:0}.angles img{height:300px}figcaption{text-align:center;color:#b8c4cc}details{margin-top:12px}.missing{padding:25px;border:1px dashed #73808a}.research{margin-top:25px;display:grid;grid-template-columns:repeat(auto-fit,minmax(280px,1fr));gap:18px}.research img{height:250px}[hidden]{display:none!important}@media(max-width:650px){main{padding:14px}.pair,.angles{grid-template-columns:1fr}}
</style><main><h1>Casas: referencia individual y revisión de todos los lados</h1><p>El objetivo es comprobar proporciones, ventanas, puertas, balcones y cubiertas. El parecido todavía no se declara aprobado. Las imágenes de proyecto se conservan sin modificaciones; algunas referencias son renders arquitectónicos.</p><p>En el juego: <strong>menú → Revisar casas</strong>, con giro, zoom y botones para cada vista.</p><nav><button onclick="filter('all')">Todas</button><button onclick="filter('0')">Costa</button><button onclick="filter('1')">Sierra</button><button onclick="filter('2')">Selva</button></nav><div class="grid">'''+''.join(cards)+'''</div><h2>Fuentes adicionales para reconstruir los tipos pendientes</h2><p>Encontrar una fuente no significa que su edificio ya esté reproducido. Las referencias sin correspondencia se mantienen como investigación.</p><div class="research">'''+research+'''</div></main><script>function filter(region){document.querySelectorAll('[data-region]').forEach(card=>card.hidden=region!=='all'&&card.dataset.region!==region)}</script></html>'''
document=document.replace('</nav>','<button onclick="graffitiOnly()">Con grafiti</button></nav>',1)
document=document.replace('</script>','function graffitiOnly(){document.querySelectorAll("[data-region]").forEach(card=>card.hidden=card.dataset.graffiti!=="1")}</script>',1)
assert 'Ã' not in document and 'Â' not in document,'Incorrect text decoding in house gallery'
(OUT/'index.html').write_text(document,encoding='utf8')
print('HOUSE_STUDY_GALLERY',len(cards),'houses; 5 exported views each; original reference sources retained')

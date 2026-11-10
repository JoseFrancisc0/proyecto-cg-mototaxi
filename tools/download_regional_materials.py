"""Download original CC0 photographic surfaces; keep source URLs and authors."""
import json,urllib.request,time,sys
from pathlib import Path
from concurrent.futures import ThreadPoolExecutor
ROOT=Path(__file__).resolve().parent.parent
sys.path.insert(0,str(ROOT/'tools/.avatar_runtime'))
from PIL import Image
OUT=ROOT/'project/assets/houses/peru/materials';OUT.mkdir(parents=True,exist_ok=True)
REGIONS={
'costa':['red_brick_03','red_bricks_02','red_bricks_04','red_brick_plaster_patch_02','plaster_brick_01','rough_plaster_brick','painted_plaster_wall','yellow_plaster','blue_plaster_wall','white_plaster_02','concrete_wall_001','concrete_wall_004','concrete_layers','painted_metal_shutter','rusty_metal_sheet','plywood','rectangular_facade_tiles','marble_tiles','brushed_concrete','wooden_garage_door'],
'sierra':['clay_plaster','patterned_clay_plaster','plastered_stone_wall','old_stone_wall','stone_wall','rustic_stone_wall','stone_block_wall','sandstone_blocks_04','white_plaster_rough_01','white_rough_plaster','clay_roof_tiles','clay_roof_tiles_02','clay_roof_tiles_03','ceramic_roof_01','wood_shutter','wooden_gate','wood_peeling_paint_weathered','brown_brick_02','worn_brick_wall','grey_plaster'],
'selva':['wood_plank_wall','wood_planks_grey','wooden_rough_planks','rough_wood','dark_wooden_planks','reed_roof_03','reed_roof_04','thatch_roof_angled','box_profile_metal_sheet','rusty_painted_metal','blue_plaster_weathered','yellow_plaster_02','red_plaster_weathered','painted_concrete','painted_concrete_02','blue_floor_tiles_01','patterned_brick_wall','whitewashed_brick','worn_mossy_plasterwall','wooden_panels']}
metadata=json.loads((ROOT/'tmp/polyhaven_textures.json').read_text())
def get(url):
    for attempt in range(3):
        try:
            with urllib.request.urlopen(urllib.request.Request(url,headers={'User-Agent':'PeruTaxiAcademic/1.0 (offline game material preparation)'}),timeout=45) as r:return r.read()
        except Exception:
            if attempt==2:raise
            time.sleep(2)
def download(job):
    region,index,key=job;folder=OUT/region;folder.mkdir(exist_ok=True)
    target=folder/(key+'.jpg');files=json.loads(get('https://api.polyhaven.com/files/'+key))
    channel=files.get('Diffuse') or files.get('Color') or files.get('diff') or files.get('color')
    size=channel.get('1k') or channel.get('2k') or next(iter(channel.values()))
    file=size.get('jpg') or size.get('png') or next(iter(size.values()))
    if not target.exists():
        target.write_bytes(get(file['url']))
        with Image.open(target) as im:im.convert('RGB').resize((512,512),Image.Resampling.LANCZOS).save(target,quality=90)
    entry={'region':region,'index':index,'id':key,'file':str(target.relative_to(OUT)).replace('\\','/'),'source':'https://polyhaven.com/a/'+key,'download':file['url'],'license':'CC0','authors':metadata[key]['authors'],'dimensions_cm':metadata[key].get('dimensions',[200,200])}
    print('MATERIAL',region,index,key,flush=True);return entry
jobs=[(r,i,k) for r,keys in REGIONS.items() for i,k in enumerate(keys)]
with ThreadPoolExecutor(max_workers=4) as pool:entries=list(pool.map(download,jobs))
(OUT/'catalog.json').write_text(json.dumps(entries,indent=2),encoding='utf8')
(OUT/'SOURCE.md').write_text('# Materiales fotográficos regionales\n\n60 superficies originales de [Poly Haven](https://polyhaven.com), 20 por región. CC0. Autores, páginas de origen y enlaces de descarga en `catalog.json`. Copias de juego reducidas a 512 px; no son simples cambios de color de un mismo material.\n',encoding='utf8')

"""Original CC0 normal and packed roughness/metallic maps from Poly Haven."""
from pathlib import Path
import json,urllib.request,time
from concurrent.futures import ThreadPoolExecutor
ROOT=Path(__file__).resolve().parent.parent
OUT=ROOT/'project/assets/houses/peru/materials'
materials=json.loads((OUT/'catalog.json').read_text())
SELECTED=set('red_brick_03 red_bricks_02 red_bricks_04 white_plaster_02 concrete_wall_001 rusty_metal_sheet white_plaster_rough_01 clay_plaster rustic_stone_wall old_stone_wall clay_roof_tiles clay_roof_tiles_02 clay_roof_tiles_03 ceramic_roof_01 wood_plank_wall dark_wooden_planks box_profile_metal_sheet rusty_painted_metal whitewashed_brick painted_metal_shutter'.split())
def get(url):
    for attempt in range(3):
        try:
            request=urllib.request.Request(url,headers={'User-Agent':'PeruTaxiAcademic/1.0 (local PBR asset preparation)'})
            with urllib.request.urlopen(request,timeout=45) as response:return response.read()
        except Exception:
            if attempt==2:raise
            time.sleep(1)
def download(entry):
    key=entry['id'];folder=OUT/entry['region'];files=json.loads(get('https://api.polyhaven.com/files/'+key))
    result={'id':key,'region':entry['region'],'source':entry['source'],'license':'CC0'}
    for channel,field in [('nor_gl','normal'),('arm','arm')]:
        data=files.get(channel)
        if not data:continue
        size=data.get('1k') or data.get('2k')
        item=size.get('png') or size.get('jpg') or next(iter(size.values()))
        extension=Path(item['url']).suffix
        target=folder/(key+'_'+field+extension)
        if not target.exists():target.write_bytes(get(item['url']))
        result[field]=str(target.relative_to(OUT)).replace('\\','/');result[field+'_source']=item['url']
    print('PBR_MAPS',key,flush=True)
    return result
with ThreadPoolExecutor(max_workers=4) as pool:entries=list(pool.map(download,[m for m in materials if m['id'] in SELECTED]))
(OUT/'pbr_catalog.json').write_text(json.dumps(entries,indent=2),encoding='utf8')
print('PBR_READY',len(entries),flush=True)

"""Local Hunyuan3D 2mini neural geometry for the Peruvian traffic fleet."""
import sys,os,json
from pathlib import Path
ROOT=Path(__file__).resolve().parent.parent
sys.path[:0]=[str(ROOT/'tools/.reconstruction_runtime'),str(ROOT/'tools/.avatar_runtime'),str(ROOT/'tools/.worldgen/Hunyuan3D-2-main')]
os.environ['HF_HOME']=str(ROOT/'tools/.worldgen/hf_cache')
import numpy as np,torch,cv2
from PIL import Image
folder=ROOT/'project/assets/traffic';folder.mkdir(parents=True,exist_ok=True)
cache=ROOT/'tools/.worldgen/generated';cache.mkdir(parents=True,exist_ok=True)
image=Image.open(folder/'reference_atlas.png').convert('RGBA');w,h=image.size
keys=['tico','sedan','coaster','urban_bus']
for index,key in enumerate(keys):
    tile=image.crop(((index%2)*w//2,(index//2)*h//2,(index%2+1)*w//2,(index//2+1)*h//2))
    data=np.array(tile);mask=(data[:,:,3]>120).astype('uint8');count,labels,stats,_=cv2.connectedComponentsWithStats(mask)
    if count>1:
        label=1+np.argmax(stats[1:,cv2.CC_STAT_AREA]);mask=(labels==label).astype('uint8');mask=cv2.dilate(mask,np.ones((3,3),np.uint8));data[:,:,3]*=mask
    tile=Image.fromarray(data);box=tile.getbbox();tile=tile.crop(box)
    side=max(tile.size);canvas=Image.new('RGBA',(side+48,side+48));canvas.paste(tile,((canvas.width-tile.width)//2,(canvas.height-tile.height)//2));canvas.save(folder/(key+'_reference.png'))
from hy3dgen.shapegen import Hunyuan3DDiTFlowMatchingPipeline
torch.set_num_threads(6)
model=ROOT/'tools/.worldgen/models/hunyuan3d-dit-v2-mini-turbo'
pipe=Hunyuan3DDiTFlowMatchingPipeline.from_single_file(str(model/'model.fp16.safetensors'),str(model/'config.yaml'),device='cuda',dtype=torch.float16,use_safetensors=True)
for index,key in enumerate(keys):
    if (cache/(key+'_raw.glb')).exists():continue
    print('GENERATING',key,flush=True)
    mesh=pipe(image=Image.open(folder/(key+'_reference.png')),num_inference_steps=8,octree_resolution=384,num_chunks=6000,mc_algo='mc',generator=torch.Generator().manual_seed(120+index))[0]
    mesh.export(cache/(key+'_raw.glb'));np.savez_compressed(cache/(key+'_surface.npz'),vertices=mesh.vertices,faces=mesh.faces)
    print('READY',key,len(mesh.faces),flush=True);torch.cuda.empty_cache()

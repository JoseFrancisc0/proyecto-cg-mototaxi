"""Real image-conditioned clothed-human reconstruction using official PIFuHD weights locally."""
import sys,os,json,hashlib,traceback
from pathlib import Path
ROOT=Path(__file__).resolve().parent.parent
sys.path[:0]=[str(ROOT/'tools/.reconstruction_runtime'),str(ROOT/'tools/.avatar_runtime'),str(ROOT/'tools/.pifuhd/pifuhd-main')]
if os.name!='nt':os.environ['PYTORCH_CUDA_ALLOC_CONF']='expandable_segments:True'
import numpy as np
import torch
from PIL import Image,ImageOps
from lib.model import HGPIFuNetwNML,HGPIFuMRNet
from lib.mesh_util import reconstruction
photo=Path(sys.argv[1]).resolve();folder=Path(sys.argv[2]).resolve();folder.mkdir(parents=True,exist_ok=True)
resolution=int(sys.argv[3]) if len(sys.argv)>3 else 256
def status(stage,progress,**kwargs):
    print(stage,flush=True)
    tmp=folder/'status.tmp';tmp.write_text(json.dumps(dict(stage=stage,progress=progress,**kwargs)),encoding='utf8');tmp.replace(folder/'status.json')
try:
    status('Cargando reconstrucción humana PIFuHD',.06)
    torch.set_num_threads(6)
    device=torch.device('cuda' if torch.cuda.is_available() else 'cpu')
    # The pickle checkpoint is downloaded only from Facebook's official published URL.
    checkpoint_path=ROOT/'tools/.pifuhd/pifuhd.pt'
    with checkpoint_path.open('rb') as stream:
        if hashlib.file_digest(stream,'sha256').hexdigest()!='891637c65f122c7efe212ebba7ae4581f86d75c92fdd5894096fe32f562175e9':
            raise RuntimeError('Los pesos no coinciden con la versión oficial comprobada. Vuelve a descargarlos.')
    checkpoint=torch.load(checkpoint_path,map_location='cpu',weights_only=False)
    netG=HGPIFuNetwNML(checkpoint['opt_netG'],'orthogonal')
    model=HGPIFuMRNet(checkpoint['opt'],netG,'orthogonal')
    model.load_state_dict(checkpoint['model_state_dict']);del checkpoint
    model.eval().to(device)
    image=ImageOps.exif_transpose(Image.open(photo)).convert('RGB')
    width,height=image.size
    # Square crop with sufficient space around a full person, preserving perspective/aspect.
    side=max(width,height);left=(width-side)//2;top=(height-side)//2
    square=Image.new('RGB',(side,side),(128,128,128));square.paste(image,(-left,-top))
    square.save(folder/'projection.png')
    image.save(folder/'source.png')
    (folder/'projection.json').write_text(json.dumps(dict(side=side,left=left,top=top,width=width,height=height)),encoding='utf8')
    def tensor(size):
        array=np.asarray(square.resize((size,size),Image.Resampling.LANCZOS)).astype('float32')/127.5-1
        return torch.from_numpy(array.transpose(2,0,1).copy())[None].to(device)
    calibration=torch.eye(4,device=device)[None];calibration[:,1,1]=-1
    status('Estimando volumen y pliegues de la ropa',.24)
    with torch.no_grad():
        model.filter_global(tensor(512))
        model.filter_local(tensor(1024)[:,None])
        for name in ['nmlF','nmlB']:
            normal=getattr(netG,name,None)
            if normal is not None:
                normal=((normal[0].cpu().numpy().transpose(1,2,0)+1)*127.5).clip(0,255).astype('uint8');Image.fromarray(normal).save(folder/(name+'.png'))
        status('Extrayendo la superficie 3D de la persona',.5)
        result=reconstruction(model,device,calibration,resolution,np.array([-1,-1,-1]),np.array([1,1,1]),use_octree=True,num_samples=10000)
    if isinstance(result,int):raise RuntimeError('La reconstrucción no produjo una superficie válida.')
    vertices,faces,normals,values=result
    np.savez_compressed(folder/'surface.npz',vertices=vertices,faces=faces)
    with (folder/'surface.obj').open('w',encoding='utf8') as stream:
        for x,y,z in vertices:stream.write(f'v {x:.7f} {y:.7f} {z:.7f}\n')
        for a,b,c in faces:stream.write(f'f {a+1} {b+1} {c+1}\n')
    status('Superficie reconstruida; pendiente de textura y articulación',.72,vertices=len(vertices),triangles=len(faces))
    print('SURFACE_READY',vertices.shape,faces.shape,'peakVRAM',torch.cuda.max_memory_allocated()/1024**3 if device.type=='cuda' else 0,flush=True)
except Exception as error:
    status('No se pudo reconstruir el personaje',0,error=str(error),done=True);traceback.print_exc();sys.exit(1)

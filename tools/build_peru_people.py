"""Prepare six fictional regional pedestrians using the locally installed human reconstruction."""
import sys,os,subprocess,shutil
from pathlib import Path
ROOT=Path(__file__).resolve().parent.parent
sys.path.insert(0,str(ROOT/'tools/.avatar_runtime'))
from PIL import Image
sources={
'coast':'exec-60a32cfe-a37b-40a0-9385-08acfca97917.png',
'highlands':'exec-88adf0fa-252a-4752-8021-425e9adfd665.png',
'amazon':'exec-26670a3c-e00d-4378-ac1f-80cfad21e0c9.png'}
generated=Path('C:/Users/USUARIO/.codex/generated_images/01a198a8-bfa7-73e1-ada0-51d2f3451066')
output=ROOT/'project/assets/people';output.mkdir(parents=True,exist_ok=True)
blender='D:/Program Files/Blender Foundation/Blender 5.2/blender.exe'
env=os.environ.copy();env['PERU_NPC_FACE_BUDGET']='24000';env['PERU_NPC_TEXTURE_SIZE']='2048'
for region,file in sources.items():
    for side in range(2):
        key=region+('_man' if side==0 else '_woman')
        if (output/(key+'.glb')).exists():continue
        photo=output/(key+'_reference.png')
        if not photo.exists():
            image=Image.open(generated/file)
            image.crop((side*image.width//2,0,(side+1)*image.width//2,image.height)).save(photo)
        work=ROOT/'tmp/peru_people'/key;work.mkdir(parents=True,exist_ok=True)
        print('PERSON',key,flush=True)
        for script,args in [('analyze_driver_photo.py',[photo,work]),('reconstruct_clothed_driver.py',[photo,work,'384']),('prepare_driver_texture.py',[work,work])]:
            subprocess.run([sys.executable,str(ROOT/'tools'/script),*map(str,args)],check=True,env=env)
        subprocess.run([blender,'--background','--python-exit-code','1','--python',str(ROOT/'tools/build_reconstructed_driver.py'),'--',str(work)],check=True,env=env)
        shutil.copyfile(work/'driver.glb',output/(key+'.glb'))
        print('PERSON_READY',key,flush=True)

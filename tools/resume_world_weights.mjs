import fs from 'node:fs/promises';import {createWriteStream} from 'node:fs';import {Readable} from 'node:stream';import {pipeline} from 'node:stream/promises';
const base=new URL('./.worldgen/models/',import.meta.url);
const files=[['hunyuan3d-dit-v2-mini-turbo/model.fp16.safetensors',3822584202],['hunyuan3d-vae-v2-mini-turbo/model.fp16.safetensors',407410402]];
for(const [file,size] of files){
 const out=new URL(file,base);await fs.mkdir(new URL('./',out),{recursive:true});let start=0;try{start=(await fs.stat(out)).size;}catch{}
 const block=64*1024*1024;
 while(start<size){const end=Math.min(size-1,start+block-1);let success=false;
  for(let retry=0;retry<4;retry++){try{
   const response=await fetch('https://huggingface.co/tencent/Hunyuan3D-2mini/resolve/main/'+file+'?download=true&range_start='+start,{headers:{Range:`bytes=${start}-${end}`}});
   if(response.status!==206)throw new Error('Range status '+response.status);
   const bytes=Buffer.from(await response.arrayBuffer());if(bytes.length!==end-start+1)throw new Error('Partial block');
   const handle=await fs.open(out,start===0?'w':'a');await handle.write(bytes);await handle.close();start=end+1;success=true;console.log(file,Math.round(start/size*100)+'%');break;
  }catch(e){console.log('retry',retry,String(e));}}
  if(!success)throw new Error('Could not resume '+file);
 }
}
for(const file of ['hunyuan3d-vae-v2-mini-turbo/config.yaml','LICENSE.txt']){
 const out=new URL(file,base);await fs.mkdir(new URL('./',out),{recursive:true});const r=await fetch('https://huggingface.co/tencent/Hunyuan3D-2mini/resolve/main/'+file);if(r.ok)await fs.writeFile(out,Buffer.from(await r.arrayBuffer()));
}

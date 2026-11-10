import fs from 'node:fs/promises';import {createWriteStream} from 'node:fs';import {Readable} from 'node:stream';import {pipeline} from 'node:stream/promises';
const dir=new URL('./.worldgen/models/',import.meta.url);await fs.mkdir(dir,{recursive:true});
for(const file of ['hunyuan3d-dit-v2-mini-turbo/config.yaml','hunyuan3d-dit-v2-mini-turbo/model.fp16.safetensors','hunyuan3d-vae-v2-mini-turbo/config.yaml','hunyuan3d-vae-v2-mini-turbo/model.fp16.safetensors','LICENSE.txt']){
 const output=new URL(file,dir);await fs.mkdir(new URL('./',output),{recursive:true});try{const s=await fs.stat(output);if(s.size>1000000)continue;}catch{}
 const r=await fetch('https://huggingface.co/tencent/Hunyuan3D-2mini/resolve/main/'+file);if(!r.ok)throw new Error(`${file}: ${r.status}`);
 await pipeline(Readable.fromWeb(r.body),createWriteStream(output));console.log('Downloaded',file);
}

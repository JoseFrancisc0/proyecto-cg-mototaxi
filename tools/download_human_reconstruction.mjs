import fs from 'node:fs/promises';
import {Readable} from 'node:stream';
import {pipeline} from 'node:stream/promises';
import {createWriteStream} from 'node:fs';
import {createReadStream} from 'node:fs';
import {createHash} from 'node:crypto';
const root=new URL('./.pifuhd/',import.meta.url);await fs.mkdir(root,{recursive:true});
async function download(url,file){try{const stat=await fs.stat(file);if(stat.size>1000000){console.log('Already downloaded',String(file));return;}}catch{}const response=await fetch(url);if(!response.ok)throw new Error(`${response.status}: ${url}`);await pipeline(Readable.fromWeb(response.body),createWriteStream(file));console.log('Downloaded',String(file));}
await download('https://codeload.github.com/facebookresearch/pifuhd/zip/refs/heads/main',new URL('source.zip',root));
await download('https://dl.fbaipublicfiles.com/pifuhd/checkpoints/pifuhd.pt',new URL('pifuhd.pt',root));
const hash=createHash('sha256');for await(const chunk of createReadStream(new URL('pifuhd.pt',root)))hash.update(chunk);
if(hash.digest('hex')!=='891637c65f122c7efe212ebba7ae4581f86d75c92fdd5894096fe32f562175e9')throw new Error('El modelo descargado no coincide con la versión comprobada. No se ejecutará.');

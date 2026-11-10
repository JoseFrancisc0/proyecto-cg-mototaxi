/** Official PIFuHD: photo -> continuous clothed mesh -> baked PBR atlas -> articulated GLB. */
import {spawn} from 'node:child_process';
import fs from 'node:fs/promises';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
const [photoArg,folderArg]=process.argv.slice(2);
const photo=photoArg?path.resolve(photoArg):'',folder=folderArg?path.resolve(folderArg):'';
const tools=path.dirname(fileURLToPath(import.meta.url));
if(!photo||!folder)throw new Error('Se necesita una foto y una carpeta de salida.');
await fs.mkdir(folder,{recursive:true});
async function exists(file){try{await fs.access(file);return true;}catch{return false;}}
async function locate(candidates){for(const file of candidates.filter(Boolean))if(await exists(file))return file;return null;}
async function run(exe,args){await new Promise((resolve,reject)=>{const child=spawn(exe,args,{windowsHide:true});let log='';child.stdout.on('data',b=>log=(log+b).slice(-4000));child.stderr.on('data',b=>log=(log+b).slice(-4000));child.on('error',reject);child.on('close',code=>code===0?resolve():reject(new Error(log.slice(-800)||'El proceso local no pudo terminar.')));});}
try{
 const blender=await locate([process.env.DRIVER_BLENDER,'D:/Program Files/Blender Foundation/Blender 5.2/blender.exe','C:/Program Files/Blender Foundation/Blender 5.2/blender.exe']);
 if(!blender)throw new Error('No se encontró Blender. Configura DRIVER_BLENDER o importa un GLB.');
 const base=path.dirname(blender);const python=await locate([process.env.DRIVER_PYTHON,...(await fs.readdir(base)).filter(v=>/^\d+\.\d+$/.test(v)).map(v=>path.join(base,v,'python/bin/python.exe'))]);
 if(!python)throw new Error('No se encontró Python de Blender. Configura DRIVER_PYTHON.');
 if(!await exists(path.join(tools,'.avatar_runtime/mediapipe')))throw new Error('Falta instalar el generador local gratuito. Consulta tools/DRIVER_SETUP.md.');
 const stat=await fs.stat(photo);if(stat.size>12*1024*1024)throw new Error('La foto supera 12 MB.');
 await run(python,[path.join(tools,'analyze_driver_photo.py'),photo,folder]);
 const analysis=JSON.parse(await fs.readFile(path.join(folder,'analysis.json'),'utf8'));
 const fullBody=analysis.body?.length===33&&[27,28].every(i=>analysis.body[i][3]>.5&&analysis.body[i][1]>.1&&analysis.body[i][1]<.98);
 if(!fullBody)throw new Error('Para reconstruir fielmente cuerpo y ropa, esta versión necesita una foto de cuerpo entero. Se conserva tu referencia; no se reemplazará tu conductor por un cuerpo inventado.');
 if(!await exists(path.join(tools,'.pifuhd/pifuhd.pt'))||!await exists(path.join(tools,'.reconstruction_runtime/torch')))throw new Error('Falta instalar PIFuHD gratuito. Consulta tools/DRIVER_SETUP.md.');
 await run(python,[path.join(tools,'reconstruct_clothed_driver.py'),photo,folder,'512']);
 await run(python,[path.join(tools,'prepare_driver_texture.py'),folder,folder]);
 await run(blender,['--background','--python-exit-code','1','--python',path.join(tools,'build_reconstructed_driver.py'),'--',folder]);
 if(!await exists(path.join(folder,'driver.glb')))throw new Error('Blender terminó sin exportar el personaje.');
 const skin=JSON.parse(await fs.readFile(path.join(folder,'skin_quality.json'),'utf8'));
 if(!skin.automatic_weights)throw new Error('La malla se reconstruyó, pero no se pudo articular con suficiente confianza. Se conserva el resultado para revisarlo; el conductor actual no se reemplaza.');
 const model=path.join(folder,'driver.glb');
 await fs.writeFile(path.join(folder,'profile.json'),JSON.stringify({version:3,method:'pifuhd-clothed-reconstruction',credits:0,source:photo,model}));
 await fs.writeFile(path.join(folder,'status.json'),JSON.stringify({stage:'Reconstrucción lista para revisar',progress:1,model,done:true}));
}catch(e){
 await fs.writeFile(path.join(folder,'generation.log'),String(e.stack||e));
 let message=e.message;try{const previous=JSON.parse(await fs.readFile(path.join(folder,'status.json'),'utf8'));if(previous.error)message=previous.error;}catch{}
 await fs.writeFile(path.join(folder,'status.json'),JSON.stringify({stage:'No se pudo completar el personaje local',progress:0,error:message,done:true}));process.exitCode=1;
}

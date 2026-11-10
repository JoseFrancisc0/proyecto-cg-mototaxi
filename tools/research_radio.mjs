import fs from 'node:fs/promises';
await fs.mkdir('tmp/radio_sources',{recursive:true});
for(const [name,url] of [['nuevaq','https://www.radionuevaq.pe/qa-crp/radioenvivo/on-demand/'],['radiomar','https://www.radiomar.pe/qa-crp/radioenvivo/on-demand/'],['inolvidable','https://www.oigo.com/lainolvidable/radioenvivo/']]){
 try{const r=await fetch(url,{signal:AbortSignal.timeout(10000)});const html=await r.text();await fs.writeFile(`tmp/radio_sources/${name}.html`,html);console.log(name,r.status,html.match(/https?:[^\s"'<>]*(?:mp3|mdstrm|live-audio|stream|icecast)[^\s"'<>]*/gi)?.slice(0,15));}catch(e){console.log(name,String(e));}
}

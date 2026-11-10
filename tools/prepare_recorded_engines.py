"""Build lighter engine loops from the six CC0 field recordings; preserve original downloads."""
from pathlib import Path
import subprocess,wave,struct,array,math,json
ROOT=Path(__file__).resolve().parents[1]
BANK=ROOT/'project/audio/engines'
FFMPEG='D:/USUARIO/Downloads/ffmpeg-8.1.1-essentials_build/ffmpeg-8.1.1-essentials_build/bin/ffmpeg.exe'
RATE=22050
sources=json.loads((BANK/'recorded/sources.json').read_text())
for source in sources:
 key=source['vehicle']
 raw=subprocess.check_output([FFMPEG,'-v','error','-i',str(ROOT/source['file']),'-af','highpass=f=150,lowpass=f=4600','-f','s16le','-ac','1','-ar',str(RATE),'-'])
 data=array.array('h');data.frombytes(raw)
 window=RATE*4
 candidates=[]
 for start in range(RATE, max(RATE+1,len(data)-window-RATE), RATE//2):
  piece=data[start:start+window]
  if len(piece)<window: continue
  energy=[]
  for t in range(0,window,RATE//5):
   chunk=piece[t:t+RATE//5];energy.append(math.sqrt(sum(x*x for x in chunk)/len(chunk)))
  mean=sum(energy)/len(energy)
  variation=sum((x-mean)**2 for x in energy)/len(energy)/(mean*mean+1)
  if mean>150:candidates.append((variation,mean,start))
 if not candidates:raise RuntimeError('Recording is too short or silent: '+key)
 stable=sorted(candidates)[:max(3,len(candidates)//3)]
 idle=min(stable,key=lambda x:x[1]);loaded=max(stable,key=lambda x:x[1])
 for kind,item in [('idle',idle),('load',loaded)]:
  piece=[float(v) for v in data[item[2]:item[2]+window]]
  # DC removal and RMS normalization at a restrained level; true crossfade at loop wrap.
  dc=sum(piece)/len(piece);piece=[v-dc for v in piece]
  rms=math.sqrt(sum(x*x for x in piece)/len(piece));gain=min(4500/max(rms,1),22000/max(max(abs(x) for x in piece),1))
  piece=[v*gain for v in piece]
  fade=round(RATE*.025)
  for i in range(fade):
   a=i/(fade-1);piece[-fade+i]=piece[-fade+i]*(1-a)+piece[i]*a
  with wave.open(str(BANK/(key+'_'+kind+'.wav')),'wb') as out:
   out.setparams((1,2,RATE,0,'NONE','not compressed'));out.writeframes(b''.join(struct.pack('<h',round(v)) for v in piece))
 source['segments_seconds']={'idle':idle[2]/RATE,'load':loaded[2]/RATE}
 print(key,source['segments_seconds'],flush=True)
(BANK/'recorded/sources.json').write_text(json.dumps(sources,indent=2))
(BANK/'recorded/README.md').write_text('# Recorded engine sources\n\nSix independent field recordings, all CC0-1.0 verified on the original source pages. Original public high-quality MP3 previews are preserved here. Derived game loops are mono 22.05 kHz, high-pass filtered at 150 Hz, low-pass at 4.6 kHz, level-matched, with a 25 ms loop crossfade.\n\n'+'\n'.join(f"- **{s['vehicle']}**: {s['title']} — {s['author']}. [Original]({s['source']}). CC0-1.0." for s in sources)+'\n',encoding='utf-8')

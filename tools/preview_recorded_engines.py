"""Audition the actual runtime WAV bank, never replace it with synthesized engine audio."""
from pathlib import Path
import wave,array,math
ROOT=Path(__file__).resolve().parent.parent
RATE=22050
KEYS=['neon_thunder','faketaxi_drift','neon_shadow','silver_guardian','midnight_camper','dusty']
RANGES=[.72,.94,.62,.84,.64,.58]
def read(path):
    with wave.open(str(path),'rb') as f:
        values=array.array('h');values.frombytes(f.readframes(f.getnframes()));return values
def save(path,values):
    with wave.open(str(path),'wb') as f:
        f.setparams((1,2,RATE,0,'NONE','not compressed'));f.writeframes(array.array('h',[int(max(-32767,min(32767,v))) for v in values]).tobytes())
out=ROOT/'output';out.mkdir(exist_ok=True);combined=[]
for index,key in enumerate(KEYS):
    bank={kind:read(ROOT/f'project/audio/engines/{key}_{kind}.wav') for kind in ['idle','load','turbo','release']}
    demo=[];cursor=0
    for i in range(6*RATE):
        t=i/RATE;rpm=min(1,max(0,(t-.8)/2.3));cursor+=.85+rpm*RANGES[index]
        mix=min(1,max(0,(t-.8)/.35)) if t<5 else 0
        sample=bank['idle'][int(cursor)%len(bank['idle'])]*math.sqrt(1-mix)*.18+bank['load'][int(cursor)%len(bank['load'])]*math.sqrt(mix)*.24
        if 3.5<t<5:sample+=bank['turbo'][int((t-3.5)*RATE)%len(bank['turbo'])]*.1
        if t>=5:
            j=int((t-5)*RATE)
            if j<len(bank['release']):sample+=bank['release'][j]*.063
        demo.append(sample*max(0,min(1,t/.03,(6-t)/.08)))
    save(out/f'{key}_sound_preview.wav',demo);combined.extend(demo+[0]*int(.4*RATE))
save(out/'vehicle_sound_comparison.wav',combined)

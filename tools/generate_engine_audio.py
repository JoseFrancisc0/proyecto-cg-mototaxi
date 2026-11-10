"""Original engine/turbo sound bank with six contrasting synthesis styles.
No external recordings. Run Python 3 to rebuild all WAV assets and comparisons.
"""
from pathlib import Path
import math,random,struct,wave
RATE=22050
KEYS=['neon_thunder','faketaxi_drift','neon_shadow','silver_guardian','midnight_camper','dusty']

def synth(key,kind):
 index=KEYS.index(key);turbo=kind=='turbo';release=kind=='release';loaded=kind=='load'
 seconds=.8 if release else (2 if turbo else 4)
 rng=random.Random(4821+index*19);samples=[];low=0;slow=0;last=0
 for i in range(round(seconds*RATE)):
  t=i/RATE;n=rng.uniform(-1,1);low+=.12*(n-low);slow+=.015*(n-slow)
  high=n-low
  if turbo or release:
   # Each turbo has its own spectrum, rhythm and release, not just a pitch change.
   if index==0:
    phase=math.tau*(820*t+.045*math.sin(math.tau*3*t))
    signal=.38*math.sin(phase+2*math.sin(phase*.5))+.12*math.sin(math.tau*1640*t)+high*.035
   elif index==1:
    flutter=(.25+.75*max(0,math.sin(math.tau*(19 if turbo else 27)*t)))
    signal=high*.65*flutter+.18*math.sin(math.tau*560*t)
   elif index==2:
    signal=low*.9+slow*2.6+.18*math.sin(math.tau*155*t)*(1+.2*math.sin(math.tau*8*t))
   elif index==3:
    signal=.32*math.sin(math.tau*430*t)+.2*math.sin(math.tau*860*t)+.1*math.sin(math.tau*1290*t)+high*.04
   elif index==4:
    signal=low*.65+high*.09+.08*math.sin(math.tau*240*t)
   else:
    tick=max(0,math.sin(math.tau*11*t))**18
    signal=low*.6+high*.25+.42*tick*math.sin(math.tau*1700*t)+.25*math.sin(math.tau*81*t)
   if release:
    # Racy flutter, electric chirp, truck air dump, belt whine, soft sigh, rusty rattle.
    envelope=(1-t/seconds)**(1.3 if index in (1,2,5) else 2.5)
    signal*=envelope*min(1,t/.012)
  else:
   gain=1.0 if loaded else .55
   if index==0:
    # High-tech electric drive: smooth FM harmonics, no piston pulse train.
    f=105;ph=math.tau*f*t
    signal=(.30*math.sin(ph+(.95 if loaded else .22)*math.sin(ph*2))+(.16 if loaded else .04)*math.sin(ph*4)+.045*math.sin(ph*9)+low*.04)*gain
   elif index==1:
    # Open two-stroke racing exhaust: sharp combustion, rasp and intake hiss.
    ph=(57*t+.012*math.sin(math.tau*6*t))%1
    impulse=math.exp(-ph*(17 if loaded else 25))*math.sin(ph*math.tau*(6 if loaded else 3))
    signal=math.tanh((impulse*.9+.2*math.sin(math.tau*114*t)+high*.11)*2.8)*gain
   elif index==2:
    # Truck-like diesel: low chug, uneven double beat and dense bass.
    ph=(19*t)%1;p=math.exp(-ph*9)*math.sin(ph*math.tau*2)
    q=math.exp(-((ph+.37)%1)*13)*math.sin(((ph+.37)%1)*math.tau*2)
    signal=(p*.85+q*(.6 if loaded else .2)+.23*math.sin(math.tau*38*t)+slow*.5)*gain
   elif index==3:
    # V-twin: two distinct firing pulses and a resonant mechanical overtone.
    ph=(23*t)%1
    p=math.exp(-ph*18)*math.sin(ph*math.tau*3)
    q=(ph+.59)%1
    signal=(p+.8*math.exp(-q*18)*math.sin(q*math.tau*3)+(.18 if loaded else .04)*math.sin(math.tau*184*t)+low*.07)*gain
   elif index==4:
    # Muffled touring engine: rounded low-frequency rhythm and very little hiss.
    ph=math.tau*29*t
    signal=(.30*math.sin(ph)+(.18 if loaded else .06)*math.sin(ph*2+.4)+.055*math.sin(ph*3)+slow*.12)*gain
   else:
    # Worn single-cylinder: audible gaps, coarse exhaust and loose-metal clatter.
    cycle=14*t+.05*math.sin(math.tau*3*t);ph=cycle%1
    miss=.08 if int(cycle)%11 in (2,3,8) else 1
    bang=math.exp(-ph*14)*math.sin(ph*math.tau*4)*miss
    rattle=max(0,math.sin(math.tau*9*t))**20
    signal=(bang*1.8+.2*math.sin(math.tau*28*t)*miss+high*(.16 if loaded else .04)*(.3+math.exp(-ph*10))+.32*rattle*math.sin(math.tau*1350*t))*gain
   signal=math.tanh(signal*(2.2 if index==5 else 1.5))
  samples.append(signal)
 if not release:
  fade=int(.025*RATE)
  for i in range(fade):
   a=i/(fade-1);samples[-fade+i]=samples[-fade+i]*(1-a)+samples[i]*a
 peak=max(abs(v) for v in samples) or 1
 return [v/peak*.72 for v in samples]

def save(path,samples):
 with wave.open(str(path),'wb') as wav:
  wav.setparams((1,2,RATE,0,'NONE','not compressed'))
  wav.writeframes(b''.join(struct.pack('<h',round(max(-1,min(1,v))*32767)) for v in samples))

if __name__=='__main__':
 root=Path(__file__).resolve().parents[1];folder=root/'project/audio/engines';folder.mkdir(parents=True,exist_ok=True)
 comparison=[]
 for key in KEYS:
  bank={kind:synth(key,kind) for kind in ('idle','load','turbo','release')}
  # Recorded CC0 engines are the production bank; preserve them when regenerating effects.
  for kind,signal in bank.items():
   if kind in ('turbo','release') or '--synthetic-engines' in __import__('sys').argv:
    save(folder/(key+'_'+kind+'.wav'),signal)
  # Identical audition sequence per bike: idle, acceleration, turbo, release.
  demo=[];cursor=0
  for i in range(RATE*6):
   t=i/RATE;pitch=.85+min(1,max(0,(t-.8)/2.3))*1.7;cursor+=pitch
   source=bank['idle'] if t<.8 else bank['load'];engine=source[int(cursor)%len(source)]*.40
   boost=bank['turbo'][int((t-3.5)*RATE)%len(bank['turbo'])]*.24 if 3.5<t<5 else 0
   dump=bank['release'][min(len(bank['release'])-1,int((t-5)*RATE))]*.3 if t>=5 else 0
   demo.append((engine+boost+dump)*min(1,t/.03,(6-t)/.08))
  out=root/'output';out.mkdir(exist_ok=True);save(out/(key+'_sound_preview.wav'),demo)
  comparison.extend(demo+[0.0]*int(.4*RATE));print(key,flush=True)
 save(root/'output/vehicle_sound_comparison.wav',comparison)

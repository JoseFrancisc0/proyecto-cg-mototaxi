"""Original short instrumental radio beds, horn and environmental noise (no third-party samples)."""
from pathlib import Path
import math,wave,struct,random
root=Path(__file__).resolve().parents[1]/'project/audio/world';root.mkdir(parents=True,exist_ok=True)
rate=22050
rng=random.Random(817)
def write(name,duration,callback):
 signal=[callback(i/rate,i) for i in range(round(rate*duration))];peak=max(abs(v) for v in signal) or 1
 with wave.open(str(root/name),'wb') as out:
  out.setparams((1,2,rate,0,'NONE','not compressed'));out.writeframes(b''.join(struct.pack('<h',round(v/peak*21000)) for v in signal))
def instrumental(style):
 notes=[220,261.63,293.66,329.63,392,440,392,329.63] if style==0 else [261.63,329.63,392,440,392,329.63,293.66,261.63]
 def sample(t,i):
  beat=t*(2.0 if style==0 else 2.5);phase=beat%1;bar=int(beat)
  frequency=notes[(bar//2)%len(notes)]
  pluck=math.sin(math.tau*frequency*t)*math.exp(-phase*(4 if style==0 else 7))*.23
  upper=math.sin(math.tau*frequency*2*t)*math.exp(-phase*6)*.08
  kick=math.sin(math.tau*(48*t+(.15*math.exp(-phase*25))))*math.exp(-phase*25)*(.20 if bar%2==0 else .07)
  shaker=rng.uniform(-1,1)*max(0,math.sin(math.tau*beat*4))**12*.035
  bass=math.sin(math.tau*frequency*.25*t)*math.exp(-phase*3)*.15
  return (pluck+upper+kick+shaker+bass)*min(1,t/.03,(16-t)/.03)
 return sample
write('sierra_instrumental.wav',16,instrumental(0));write('barrio_instrumental.wav',16,instrumental(1))
write('horn.wav',.55,lambda t,i:(math.sin(math.tau*420*t)+.4*math.sin(math.tau*630*t))*min(1,t/.02,(.55-t)/.04))
write('rural.wav',12,lambda t,i:rng.uniform(-1,1)*.05+max(0,math.sin(math.tau*.5*t))**35*math.sin(math.tau*(2300*t+20*math.sin(math.tau*7*t)))*.06)

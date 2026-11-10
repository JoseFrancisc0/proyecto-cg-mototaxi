from pathlib import Path
import subprocess,concurrent.futures,struct,math
root=Path(__file__).resolve().parent.parent
decoder=next((root/'tools/.radio_runtime/imageio_ffmpeg/binaries').glob('ffmpeg*.exe'))
signals={'Nueva Q':'6839e1f153fcf56d988d5943','Radiomar':'6839e261d2efddf5bfbc2d3d','La Inolvidable':'6839e24cf4eacd81ada4e6b4'}
def probe(pair):
    name,key=pair;url=f'https://mdstrm.com/audio/{key}/live.m3u8?property=aiir'
    r=subprocess.run([str(decoder),'-hide_banner','-loglevel','error','-i',url,'-t','2','-f','s16le','-ar','44100','-ac','2','pipe:1'],capture_output=True,timeout=40)
    samples=struct.unpack('<%dh'%(len(r.stdout)//2),r.stdout) if r.stdout else []
    rms=math.sqrt(sum(x*x for x in samples)/max(1,len(samples)))/32768
    return name,r.returncode,len(r.stdout),round(rms,4),r.stderr.decode(errors='replace')[:250]
with concurrent.futures.ThreadPoolExecutor(max_workers=3) as pool:
    for result in pool.map(probe,signals.items()):print(result,flush=True)

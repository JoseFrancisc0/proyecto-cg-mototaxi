"""Install the free streaming decoder for a new project checkout."""
from pathlib import Path
import subprocess,sys
root=Path(__file__).resolve().parent.parent
subprocess.run([sys.executable,'-m','pip','install','--disable-pip-version-check','--no-deps','--target',str(root/'tools/.radio_runtime'),'imageio-ffmpeg==0.8.1'],check=True)
print('Radio decoder installed in tools/.radio_runtime; no music is bundled or downloaded.')

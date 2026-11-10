"""Extend foreground colour outside the silhouette to prevent grey projection seams."""
import sys,json
from pathlib import Path
ROOT=Path(__file__).resolve().parent.parent
sys.path[:0]=[str(ROOT/'tools/.reconstruction_runtime'),str(ROOT/'tools/.avatar_runtime')]
import numpy as np
from PIL import Image
from scipy.ndimage import distance_transform_edt,binary_closing
folder=Path(sys.argv[1]);analysis=Path(sys.argv[2])
image=Image.open(folder/'source.png').convert('RGB');rgb=np.asarray(image)
labels=np.asarray(Image.open(analysis/'segmentation.png').resize(image.size,Image.Resampling.NEAREST))
foreground=binary_closing(labels>0,iterations=2)
_,indices=distance_transform_edt(~foreground,return_indices=True)
extended=rgb.copy();extended[~foreground]=rgb[tuple(indices[:,~foreground])]
prepared=Image.fromarray(extended)
meta=json.loads((folder/'projection.json').read_text())
square=Image.new('RGB',(meta['side'],meta['side']),(12,13,14));square.paste(prepared,(-meta['left'],-meta['top']));square.save(folder/'texture_projection.png')

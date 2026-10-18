"""Static numerical preview of actual C++ terrain/roads, without editing scenes."""
import json
from pathlib import Path
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np
from matplotlib.patches import Patch
root = Path(__file__).resolve().parents[1]
cases = json.loads((root / "output/s11_cgb/samples.json").read_text(encoding="utf-8"))
palette = np.array([[0.65, 0.56, 0.36], [0.45, 0.38, 0.28], [0.20, 0.45, 0.15]])
fig = plt.figure(figsize=(15, 16), facecolor="#f6f5f1")
for i, case in enumerate(cases):
    side = case["side"]
    axis = np.linspace(-384, 384, side)
    x, z = np.meshgrid(axis, axis)
    h = np.array(case["heights"]).reshape(side, side)
    colors = np.array(case["weights"]).reshape(side, side, 3) @ palette
    top = fig.add_subplot(4, 2, i * 2 + 1)
    top.imshow(colors, extent=(-384,384,-384,384), origin="lower")
    for path in case["roads"]:
        points = np.array(path)
        top.plot(points[:,0],points[:,2],color="#573927",lw=1.5)
    top.set_title(f"Semilla {case['seed']} | regiones y {len(case['roads'])} caminos",fontsize=13)
    top.set_aspect("equal"); top.set_xticks([]); top.set_yticks([])
    ax = fig.add_subplot(4, 2, i * 2 + 2, projection="3d", facecolor="#f6f5f1")
    ax.plot_surface(x, z, h, facecolors=colors, rstride=2, cstride=2, linewidth=0, antialiased=False, shade=True)
    for path in case["roads"]:
        points = np.array(path)
        ax.plot(points[:,0],points[:,2],points[:,1]+0.8,color="#573927",lw=1.5)
    ax.set_zlim(-20,70); ax.set_box_aspect((768,768,270)); ax.view_init(elev=30,azim=-55)
    ax.set_xticks([]); ax.set_yticks([]); ax.set_zticks([0,35,70]); ax.tick_params(labelsize=8)
    ax.set_title("Mismo T0, sin erosion",fontsize=12)
fig.suptitle("Regiones irregulares y caminos del generador original",fontsize=20,y=0.985)
fig.legend(handles=[Patch(facecolor=palette[i],label=name) for i,name in enumerate(["Costa","Sierra","Selva"])]+[Patch(facecolor="#573927",label="Caminos A*")],loc="lower center",ncol=4,bbox_to_anchor=(0.5,0.025),frameon=False)
fig.text(0.5,0.012,"Muestras numericas reales de C++. Altura exagerada x3. No se modifico la malla guardada.",ha="center",fontsize=10)
fig.subplots_adjust(left=0.04,right=0.97,bottom=0.065,top=0.95,hspace=0.24,wspace=0.02)
fig.savefig(root / "output/s11_cgb/regiones_irregulares_caminos.png",dpi=110)
plt.close(fig)
